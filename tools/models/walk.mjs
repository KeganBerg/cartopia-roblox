// Touch-ups for buildings seen at a player's eye height. The web game only shows its buildings from
// its high town camera, where nobody sees a prop half sunk into a wall or the bare back of a shop;
// in Roblox players walk right up to them. Runs on each building's converted parts (studs, as
// build.mjs writes them: [kind, x, y, z, qx, qy, qz, qw, sx, sy, sz, look, mesh?]).
//
// 1. Props standing on the ground that are sunk deep into a wall (the garage's tyre stack sat
//    inside its side wall, so only three black slivers showed) move out to the nearest free spot.
// 2. Big bare walls get a few windows, in the stretches no other piece covers.

// A wall: an upright block at least this tall (studs), this wide and deep, standing on the ground.
const WALL_HIGH = 10
const WALL_WIDE = 8
// A prop: a piece no longer than this, whose bottom is this close to the ground.
const PROP = 8
const GROUND = 2.5
// Props sunk at least this far into a wall (studs, and this share of their own size) move out.
const SUNK = 1
const SUNK_SHARE = 0.3
// Gap left between a moved prop and the wall.
const GAP = 0.2
// Windows: size (studs), the most a face takes, the least room round each, and how bare a face
// must be (share of its area other pieces cover) to get them.
const WIN_W = 4.4
const WIN_H = 5.2
const WIN_MAX = 4
const WIN_ROOM = 2.2
const BARE = 0.25
// Faces narrower than this get no windows.
const FACE_MIN = 12

const EPS = 1e-3

// A part's unit axes (columns of its rotation).
function axesOf(p) {
  const [qx, qy, qz, qw] = p.slice(4, 8)
  return [
    [1 - 2 * (qy * qy + qz * qz), 2 * (qx * qy + qz * qw), 2 * (qx * qz - qy * qw)],
    [2 * (qx * qy - qz * qw), 1 - 2 * (qx * qx + qz * qz), 2 * (qy * qz + qx * qw)],
    [2 * (qx * qz + qy * qw), 2 * (qy * qz - qx * qw), 1 - 2 * (qx * qx + qy * qy)],
  ]
}
const dot = (a, b) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2]

// A part's extent along each of the frame's axes: [lo, hi] for each, round its middle.
function extent(p, frame) {
  const ax = axesOf(p)
  const c = [p[1], p[2], p[3]]
  return frame.map((f) => {
    const mid = dot(c, f)
    let half = 0
    for (let i = 0; i < 3; i++) half += Math.abs(dot(ax[i], f)) * p[8 + i] / 2
    return [mid - half, mid + half]
  })
}

// Walls: upright blocks turned only about the vertical, with their own level frame.
function wallsOf(parts, looks) {
  const walls = []
  for (const p of parts) {
    if (p[0] !== 'b') continue
    const look = looks[p[11] - 1]
    if (look.transparency > 0.05 || look.material === 'Glass' || look.material === 'Neon') continue
    const [qx, qy, qz, qw] = p.slice(4, 8)
    if (Math.abs(qx) > EPS || Math.abs(qz) > EPS) continue
    if (p[9] < WALL_HIGH || p[8] < WALL_WIDE || p[10] < WALL_WIDE) continue
    if (p[2] - p[9] / 2 > GROUND) continue
    const t = 2 * Math.atan2(qy, qw)
    const frame = [[Math.cos(t), 0, -Math.sin(t)], [0, 1, 0], [Math.sin(t), 0, Math.cos(t)]]
    walls.push({ p, frame, box: extent(p, frame) })
  }
  return walls
}

const overlaps = (a, b, pad = 0) => a.every(([lo, hi], k) => lo < b[k][1] - pad && hi > b[k][0] + pad)

// The ground the building stands on: its lot, from every piece lying low.
function lotOf(parts) {
  const lot = [[Infinity, -Infinity], [Infinity, -Infinity]]
  const world = [[1, 0, 0], [0, 1, 0], [0, 0, 1]]
  for (const p of parts) {
    const e = extent(p, world)
    if (e[1][0] > GROUND) continue
    lot[0] = [Math.min(lot[0][0], e[0][0]), Math.max(lot[0][1], e[0][1])]
    lot[1] = [Math.min(lot[1][0], e[2][0]), Math.max(lot[1][1], e[2][1])]
  }
  return lot
}

// The union of several extents.
const union = (list) => list[0].map((_, k) => [Math.min(...list.map((e) => e[k][0])), Math.max(...list.map((e) => e[k][1]))])

function moveProps(parts, walls, size) {
  // On its own tiles, or failing that the ground its pieces cover.
  const lot = size ? [[-size[0] / 2, size[0] / 2], [-size[1] / 2, size[1] / 2]] : lotOf(parts)
  const world = [[1, 0, 0], [0, 1, 0], [0, 0, 1]]
  const isWall = new Set(walls.map((w) => w.p))
  // Props, with the ones stacked on the same spot (a pile of tyres) moving together.
  const stacks = new Map()
  for (const p of parts) {
    if (isWall.has(p) || Math.max(p[8], p[9], p[10]) > PROP) continue
    const k = `${Math.round(p[1] * 10)},${Math.round(p[3] * 10)}`
    if (!stacks.has(k)) stacks.set(k, [])
    stacks.get(k).push(p)
  }
  let moved = 0
  for (const stack of stacks.values()) {
    const mine = new Set(stack)
    const solid = (o) => o[9] > 1 && !isWall.has(o) && !mine.has(o)
    for (const w of walls) {
      const e = union(stack.map((p) => extent(p, w.frame)))
      if (e[1][0] > GROUND || !overlaps(e, w.box)) continue
      // How far it is sunk, and the moves that bring it out, along the wall's level axes.
      const tries = []
      for (const k of [0, 2]) {
        const out = [w.box[k][1] - e[k][0], e[k][1] - w.box[k][0]]
        const sunk = Math.min(...out)
        if (sunk < SUNK || sunk < SUNK_SHARE * (e[k][1] - e[k][0])) {
          tries.length = 0
          break
        }
        tries.push({ k, d: out[0] + GAP }, { k, d: -(out[1] + GAP) })
      }
      // Whole inside the wall (hidden) or barely touching it: leave it.
      if (!tries.length || e.every(([lo, hi], k) => k === 1 || (lo >= w.box[k][0] && hi <= w.box[k][1]))) continue
      tries.sort((a, b) => Math.abs(a.d) - Math.abs(b.d))
      // Further along each way out too, in half studs, past anything already standing there.
      const ways = tries.flatMap((t) => Array.from({ length: 41 }, (_, i) => ({ k: t.k, d: t.d + Math.sign(t.d) * i * 0.5 })))
      for (const t of ways) {
        const shift = w.frame[t.k].map((x) => x * t.d)
        const qs = stack.map((p) => {
          const q = [...p]
          for (let i = 0; i < 3; i++) q[1 + i] += shift[i]
          return q
        })
        const at = union(qs.map((q) => extent(q, world)))
        if (at[0][0] < lot[0][0] - EPS || at[0][1] > lot[0][1] + EPS || at[2][0] < lot[1][0] - EPS || at[2][1] > lot[1][1] + EPS) continue
        // Not into a wall or another solid piece.
        if (parts.some((o) => solid(o) && overlaps(extent(o, world), at, 0.05))) continue
        if (walls.some((o) => qs.some((q) => overlaps(o.box, extent(q, o.frame), 0.05)))) continue
        stack.forEach((p, j) => {
          for (let i = 0; i < 3; i++) p[1 + i] = qs[j][1 + i]
        })
        moved += stack.length
        break
      }
      break
    }
  }
  return moved
}

// Free stretches of [lo, hi] once the taken intervals are cut out.
function freeSpans(lo, hi, taken) {
  const spans = []
  let at = lo
  for (const [a, b] of [...taken].sort((x, y) => x[0] - y[0])) {
    if (a > at) spans.push([at, Math.min(a, hi)])
    at = Math.max(at, b)
  }
  if (at < hi) spans.push([at, hi])
  return spans.filter(([a, b]) => b > a)
}

function addWindows(parts, walls, frameLook, glassLook) {
  const added = []
  const others = parts.slice()
  for (const w of walls) {
    const [bx, by, bz] = w.box
    const height = by[1] - Math.max(by[0], 0)
    for (const [k, side] of [[0, 1], [0, -1], [2, 1], [2, -1]]) {
      const across = k === 0 ? 2 : 0
      const span = w.box[across]
      if (span[1] - span[0] < FACE_MIN) continue
      const plane = side > 0 ? w.box[k][1] : w.box[k][0]
      const rows = height >= 28 ? 2 : 1
      const ys = rows === 2 ? [height * 0.3, height * 0.68] : [Math.min(height * 0.5, 8.5)]
      const base = Math.max(by[0], 0)
      // What lies against this face (within a stud and a half of it) or in front of it.
      const taken = []
      let covered = 0
      for (const o of others) {
        if (o === w.p) continue
        const e = extent(o, w.frame)
        const near = side > 0 ? e[k][1] > plane - 0.3 && e[k][0] < plane + 1.5 : e[k][0] < plane + 0.3 && e[k][1] > plane - 1.5
        if (!near) continue
        const a = Math.max(e[across][0], span[0]), b = Math.min(e[across][1], span[1])
        const y0 = Math.max(e[1][0], by[0]), y1 = Math.min(e[1][1], by[1])
        if (b <= a || y1 <= y0) continue
        covered += (b - a) * (y1 - y0)
        // Anything at window height keeps the windows clear of it.
        if (ys.some((y) => e[1][1] > base + y - WIN_H / 2 - 1 && e[1][0] < base + y + WIN_H / 2 + 1)) taken.push([a - 1, b + 1])
      }
      if (covered > BARE * (span[1] - span[0]) * height) continue
      let n = 0
      for (const [a, b] of freeSpans(span[0] + WIN_ROOM, span[1] - WIN_ROOM, taken)) {
        const fit = Math.min(WIN_MAX - n, Math.floor((b - a + WIN_ROOM) / (WIN_W + WIN_ROOM * 1.6)))
        if (fit < 1) continue
        const step = (b - a) / fit
        for (let i = 0; i < fit; i++) {
          const u = a + step * (i + 0.5)
          for (const y of ys) {
            const at = (depth) => {
              const pos = [0, 0, 0]
              const local = []
              local[k] = plane + side * depth
              local[1] = base + y
              local[across] = u
              for (let c = 0; c < 3; c++) pos[c] = w.frame[0][c] * local[0] + w.frame[1][c] * local[1] + w.frame[2][c] * local[2]
              return pos
            }
            // The face's own frame: the window's thin side points out of the wall.
            const size = (wide, high, thick) => (k === 0 ? [thick, high, wide] : [wide, high, thick])
            const q = w.p.slice(4, 8)
            parts.push(['b', ...at(0.12), ...q, ...size(WIN_W + 0.8, WIN_H + 0.8, 0.24), frameLook])
            parts.push(['b', ...at(0.18), ...q, ...size(WIN_W, WIN_H, 0.24), glassLook])
            added.push(2)
          }
        }
        n += fit
      }
    }
  }
  return added.length
}

// lot: the building's footprint in studs, [width, depth], round the origin (when the export gave it).
export function polishBuilding(parts, lot, looks, frameLook, glassLook) {
  const walls = wallsOf(parts, looks)
  if (!walls.length) return { moved: 0, windows: 0 }
  const moved = moveProps(parts, walls, lot)
  const windows = addWindows(parts, walls, frameLook, glassLook)
  return { moved, windows }
}
