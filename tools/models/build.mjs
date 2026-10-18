// Turns the web game's 3D models into Roblox parts.
//
//   node tools/models/build.mjs <web repo>            render the web game's models, then convert
//   node tools/models/build.mjs --json <export.json>  convert an earlier render
//
// 1. export.test.tsx renders every building and car with the web game's own code and lists each
//    mesh it drew: shape, place, size and look.
// 2. Shapes Roblox has built in become plain parts: boxes, round cylinders, discs, flat panels and
//    balls. Everything else (car bodies, cones, rings, lathed shapes) becomes a mesh, simplified a
//    little where it is much denser than Roblox needs, and saved as .glb files that upload.mjs
//    uploads to Roblox.
// 3. Writes src/shared/Models/Catalog.luau (every model's parts) and src/shared/Models/Meshes.luau
//    (each mesh's size and the Roblox asset it lives in, from tools/models/assets.json).
//
// One web unit is SCALE studs: a car is about 12 studs long, a tile 20.

import { execFileSync } from 'node:child_process'
import { createHash } from 'node:crypto'
import { copyFileSync, existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { MeshoptSimplifier } from 'meshoptimizer'

const HERE = dirname(fileURLToPath(import.meta.url))
const ROOT = resolve(HERE, '../..')
const OUT_DIR = join(ROOT, 'src/shared/Models')
const GLB_DIR = join(ROOT, 'build/meshes')
const TEX_DIR = join(ROOT, 'build/textures')
const ASSETS = join(HERE, 'assets.json')

export const SCALE = 10
// Thinnest a part may be (studs). Flat panels and discs get this thickness.
const THIN = 0.05
// Countryside meshes are merged per MERGE_CHUNK studs of ground, up to MERGE_TRIS triangles each
// (Roblox takes up to 20,000 a mesh).
const MERGE_CHUNK = 700
const MERGE_TRIS = 10000
// Countryside colours are rounded to steps of this much (of 255) so near shades merge.
const MERGE_SHADE = 14
// A mesh pack (one uploaded model) holds up to this many triangles.
const PACK_TRIS = 60000
// Meshes denser than this many triangles are simplified, keeping the shape within ERROR of its size.
const DENSE = 400
const KEEP = 0.4
const ERROR = 0.004

// ---------------------------------------------------------------------------------------------
// Rendering

function render(web) {
  const test = join(web, 'src/__rbx_export__.test.tsx')
  const out = join(ROOT, 'build/models.json')
  mkdirSync(dirname(out), { recursive: true })
  copyFileSync(join(HERE, 'export.test.tsx'), test)
  try {
    execFileSync('npx', ['vitest', 'run', 'src/__rbx_export__.test.tsx'], {
      cwd: web,
      stdio: 'inherit',
      env: { ...process.env, RBX_MODELS_OUT: out },
    })
  } finally {
    rmSync(test, { force: true })
  }
  return out
}

// ---------------------------------------------------------------------------------------------
// Small vector helpers on three.js column-major matrices

const col = (e, i) => [e[i * 4], e[i * 4 + 1], e[i * 4 + 2]]
const len = (v) => Math.hypot(v[0], v[1], v[2])
const dot = (a, b) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
const scale = (v, k) => [v[0] * k, v[1] * k, v[2] * k]
const neg = (v) => [-v[0], -v[1], -v[2]]
const near = (a, b, tol = 0.02) => Math.abs(a - b) <= tol * Math.max(Math.abs(a), Math.abs(b), 1e-6)
const apply = (e, p) => [
  e[0] * p[0] + e[4] * p[1] + e[8] * p[2] + e[12],
  e[1] * p[0] + e[5] * p[1] + e[9] * p[2] + e[13],
  e[2] * p[0] + e[6] * p[1] + e[10] * p[2] + e[14],
]

// Splits a transform into position, unit axes (columns) and per-axis scale. Null when the axes
// are skewed or mirrored, which Roblox parts can't show (those meshes get their transform baked in).
function decompose(e) {
  const c = [col(e, 0), col(e, 1), col(e, 2)]
  const s = c.map(len)
  if (s.some((x) => x < 1e-9)) return null
  const u = c.map((v, i) => scale(v, 1 / s[i]))
  if (Math.abs(dot(u[0], u[1])) > 1e-3 || Math.abs(dot(u[0], u[2])) > 1e-3 || Math.abs(dot(u[1], u[2])) > 1e-3) return null
  const cr = [u[0][1] * u[1][2] - u[0][2] * u[1][1], u[0][2] * u[1][0] - u[0][0] * u[1][2], u[0][0] * u[1][1] - u[0][1] * u[1][0]]
  return { p: [e[12], e[13], e[14]], axes: u, s, mirrored: dot(cr, u[2]) < 0 }
}

// Unit axes (columns) to a quaternion [x, y, z, w], for CFrame.new(x, y, z, qx, qy, qz, qw).
function quat([X, Y, Z]) {
  const m00 = X[0], m01 = Y[0], m02 = Z[0]
  const m10 = X[1], m11 = Y[1], m12 = Z[1]
  const m20 = X[2], m21 = Y[2], m22 = Z[2]
  const tr = m00 + m11 + m22
  let q
  if (tr > 0) {
    const s = Math.sqrt(tr + 1) * 2
    q = [(m21 - m12) / s, (m02 - m20) / s, (m10 - m01) / s, s / 4]
  } else if (m00 > m11 && m00 > m22) {
    const s = Math.sqrt(1 + m00 - m11 - m22) * 2
    q = [s / 4, (m01 + m10) / s, (m02 + m20) / s, (m21 - m12) / s]
  } else if (m11 > m22) {
    const s = Math.sqrt(1 + m11 - m00 - m22) * 2
    q = [(m01 + m10) / s, s / 4, (m12 + m21) / s, (m02 - m20) / s]
  } else {
    const s = Math.sqrt(1 + m22 - m00 - m11) * 2
    q = [(m02 + m20) / s, (m12 + m21) / s, s / 4, (m10 - m01) / s]
  }
  const n = Math.hypot(...q)
  return q.map((x) => x / n)
}

// ---------------------------------------------------------------------------------------------
// Looks: colour, see-through, material and glow

// Base colours of the web game's painted ground textures (textures.ts), drawn in Roblox with the
// matching material so paving and asphalt keep some of their grain.
const TEXTURED = { '#eadfc8': 'Pavement', '#9ba1a8': 'Asphalt' }

function lookKey(look, paint) {
  const c = look.c
  const transparency = Math.round((1 - look.o) * 100) / 100
  // Lit glow (emissive or unlit bright colours on signs and lamps) shows as Neon.
  let material = 'SmoothPlastic'
  if (look.e && look.e !== '#000000') material = 'Neon'
  else if (transparency > 0.05 && (look.rough ?? 1) < 0.35) material = 'Glass'
  // (The baked vertex-colour material the web game uses for kit pieces and plants reports metalness
  // 1 with roughness 1; that's not metal.)
  else if ((look.met ?? 0) > 0.6 && (look.rough ?? 1) < 0.8) material = 'Metal'
  else if (TEXTURED[c]) material = TEXTURED[c]
  const color = material === 'Neon' && look.e ? look.e : c
  return { color, transparency, material, text: look.text ?? null, paint: !!paint }
}

// ---------------------------------------------------------------------------------------------
// Meshes

// The triangles of a geometry (or of one of its material groups), as positions, normals and
// indices, split by vertex colour when it has them (each colour becomes its own mesh).
function trianglesOf(geo, group) {
  const g = group === undefined ? null : geo.groups?.[group]
  const start = g ? g.start : 0
  const end = g ? Math.min(geo.idx.length, g.start + g.count) : geo.idx.length
  const byColor = new Map()
  for (let i = start; i + 2 < end; i += 3) {
    const tri = [geo.idx[i], geo.idx[i + 1], geo.idx[i + 2]]
    let key = ''
    if (geo.col) {
      const v = tri[0] * 3
      key = '#' + [geo.col[v], geo.col[v + 1], geo.col[v + 2]].map((x) => Math.round(Math.max(0, Math.min(1, x)) * 255).toString(16).padStart(2, '0')).join('')
    }
    if (!byColor.has(key)) byColor.set(key, [])
    byColor.get(key).push(...tri)
  }
  return [...byColor].map(([color, idx]) => ({ color: color || null, idx }))
}

// Welds vertices that share a position and normal, drops unused ones, and simplifies dense
// meshes. Returns positions, normals and indices.
function cleanMesh(pos, nrm, idx) {
  const map = new Map()
  const P = []
  const N = []
  const I = []
  const q = (x) => Math.round(x * 1e4)
  for (const v of idx) {
    const px = pos[v * 3], py = pos[v * 3 + 1], pz = pos[v * 3 + 2]
    const nx = nrm ? nrm[v * 3] : 0, ny = nrm ? nrm[v * 3 + 1] : 0, nz = nrm ? nrm[v * 3 + 2] : 0
    const k = `${q(px)},${q(py)},${q(pz)},${Math.round(nx * 100)},${Math.round(ny * 100)},${Math.round(nz * 100)}`
    let id = map.get(k)
    if (id === undefined) {
      id = P.length / 3
      map.set(k, id)
      P.push(px, py, pz)
      N.push(nx, ny, nz)
    }
    I.push(id)
  }
  // Drop triangles that collapsed to a line.
  const tris = []
  for (let i = 0; i < I.length; i += 3) if (I[i] !== I[i + 1] && I[i + 1] !== I[i + 2] && I[i] !== I[i + 2]) tris.push(I[i], I[i + 1], I[i + 2])
  let out = tris
  if (tris.length / 3 > DENSE) {
    const [simple] = MeshoptSimplifier.simplify(new Uint32Array(tris), new Float32Array(P), 3, Math.max(DENSE * 3, Math.floor((tris.length * KEEP) / 3) * 3), ERROR, [])
    out = Array.from(simple)
  }
  // Compact to the vertices still used.
  const remap = new Map()
  const P2 = [], N2 = [], I2 = []
  for (const v of out) {
    let id = remap.get(v)
    if (id === undefined) {
      id = P2.length / 3
      remap.set(v, id)
      P2.push(P[v * 3], P[v * 3 + 1], P[v * 3 + 2])
      N2.push(N[v * 3], N[v * 3 + 1], N[v * 3 + 2])
    }
    I2.push(id)
  }
  // Normals: keep the web game's, or work them out when the geometry had none.
  if (!nrm) {
    N2.fill(0)
    for (let i = 0; i < I2.length; i += 3) {
      const [a, b, c] = [I2[i], I2[i + 1], I2[i + 2]].map((x) => P2.slice(x * 3, x * 3 + 3))
      const u = [b[0] - a[0], b[1] - a[1], b[2] - a[2]], w = [c[0] - a[0], c[1] - a[1], c[2] - a[2]]
      const n = [u[1] * w[2] - u[2] * w[1], u[2] * w[0] - u[0] * w[2], u[0] * w[1] - u[1] * w[0]]
      for (const x of [I2[i], I2[i + 1], I2[i + 2]]) for (let k = 0; k < 3; k++) N2[x * 3 + k] += n[k]
    }
    for (let i = 0; i < N2.length; i += 3) {
      const l = Math.hypot(N2[i], N2[i + 1], N2[i + 2]) || 1
      N2[i] /= l; N2[i + 1] /= l; N2[i + 2] /= l
    }
  }
  return { pos: P2, nrm: N2, idx: I2 }
}

function bounds(pos) {
  const lo = [Infinity, Infinity, Infinity], hi = [-Infinity, -Infinity, -Infinity]
  for (let i = 0; i < pos.length; i += 3) for (let k = 0; k < 3; k++) {
    lo[k] = Math.min(lo[k], pos[i + k])
    hi[k] = Math.max(hi[k], pos[i + k])
  }
  return { lo, hi, c: lo.map((l, k) => (l + hi[k]) / 2), s: lo.map((l, k) => hi[k] - l) }
}

// A minimal binary glTF: one mesh per node, named by the mesh's key, centred on the origin.
export function glb(meshes) {
  const chunks = []
  let offset = 0
  const views = [], accessors = [], gltfMeshes = [], nodes = []
  const push = (buf, target) => {
    const pad = (4 - (buf.byteLength % 4)) % 4
    views.push({ buffer: 0, byteOffset: offset, byteLength: buf.byteLength, target })
    chunks.push(Buffer.from(buf.buffer, buf.byteOffset, buf.byteLength), Buffer.alloc(pad))
    offset += buf.byteLength + pad
    return views.length - 1
  }
  for (const m of meshes) {
    const P = new Float32Array(m.pos), N = new Float32Array(m.nrm), I = new Uint32Array(m.idx)
    const b = bounds(m.pos)
    const pv = push(P, 34962), nv = push(N, 34962), iv = push(I, 34963)
    accessors.push({ bufferView: pv, componentType: 5126, count: P.length / 3, type: 'VEC3', min: b.lo, max: b.hi })
    accessors.push({ bufferView: nv, componentType: 5126, count: N.length / 3, type: 'VEC3' })
    accessors.push({ bufferView: iv, componentType: 5125, count: I.length, type: 'SCALAR' })
    const a = accessors.length - 3
    gltfMeshes.push({ name: m.key, primitives: [{ attributes: { POSITION: a, NORMAL: a + 1 }, indices: a + 2, material: 0 }] })
    nodes.push({ name: m.key, mesh: gltfMeshes.length - 1 })
  }
  const bin = Buffer.concat(chunks)
  const json = {
    asset: { version: '2.0', generator: 'cartopia-roblox tools/models' },
    scene: 0,
    scenes: [{ nodes: nodes.map((_, i) => i) }],
    nodes,
    meshes: gltfMeshes,
    materials: [{ name: 'White', pbrMetallicRoughness: { baseColorFactor: [1, 1, 1, 1], metallicFactor: 0, roughnessFactor: 1 } }],
    accessors,
    bufferViews: views,
    buffers: [{ byteLength: bin.length }],
  }
  let js = Buffer.from(JSON.stringify(json))
  js = Buffer.concat([js, Buffer.alloc((4 - (js.length % 4)) % 4, 0x20)])
  const header = Buffer.alloc(12)
  header.writeUInt32LE(0x46546c67, 0)
  header.writeUInt32LE(2, 4)
  header.writeUInt32LE(12 + 8 + js.length + 8 + bin.length, 8)
  const jh = Buffer.alloc(8)
  jh.writeUInt32LE(js.length, 0)
  jh.writeUInt32LE(0x4e4f534a, 4)
  const bh = Buffer.alloc(8)
  bh.writeUInt32LE(bin.length, 0)
  bh.writeUInt32LE(0x004e4942, 4)
  return Buffer.concat([header, jh, js, bh, bin])
}

// ---------------------------------------------------------------------------------------------
// Converting

// Whether a geometry's vertices are still the shape its parameters describe. The web game often
// clones a BoxGeometry or SphereGeometry and bakes a move or scale into its vertices (PropKit,
// merged parts); the clone keeps its type and parameters, so trust those only when the vertices agree.
const pristineCache = new WeakMap()
function pristine(geo) {
  if (pristineCache.has(geo)) return pristineCache.get(geo)
  const P = geo.params
  const want = {
    BoxGeometry: () => [P.width, P.height, P.depth],
    PlaneGeometry: () => [P.width, P.height, 0],
    CylinderGeometry: () => [2 * Math.max(P.radiusTop, P.radiusBottom), P.height, 2 * Math.max(P.radiusTop, P.radiusBottom)],
    CircleGeometry: () => [2 * P.radius, 2 * P.radius, 0],
    SphereGeometry: () => [2 * P.radius, 2 * P.radius, 2 * P.radius],
  }[geo.type]?.()
  let ok = false
  if (want && geo.pos.length) {
    const b = bounds(geo.pos)
    const big = Math.max(...want)
    // Round shapes with an odd number of sides fall a little short of their radius one way.
    const slack = geo.type === 'BoxGeometry' || geo.type === 'PlaneGeometry' ? 2e-3 : 0.04
    ok = b.c.every((c) => Math.abs(c) < 0.02 * big + 1e-4) && b.s.every((x, k) => Math.abs(x - want[k]) <= slack * big + 1e-4)
  }
  pristineCache.set(geo, ok)
  return ok
}

export function convert(data) {
  const { geos, models } = data
  const looks = []
  const lookIds = new Map()
  const lookId = (look, paint) => {
    const l = lookKey(look, paint)
    const k = JSON.stringify(l)
    if (!lookIds.has(k)) {
      lookIds.set(k, looks.length + 1)
      looks.push(l)
    }
    return lookIds.get(k)
  }
  // Meshes by key, the model that first used each, and a cache of cleaned geometry.
  const meshes = new Map()
  const cleaned = new Map()
  const stats = { parts: 0, meshes: 0, tris: 0 }

  const meshKey = (m) => createHash('sha1').update(new Float32Array(m.pos)).update(new Uint32Array(m.idx)).digest('hex').slice(0, 16)

  const out = {}
  const loose = new Map()
  const scenery = new Set()
  for (const model of models) {
    if (model.kind === 'scenery') scenery.add(model.id)
    // Countryside meshes are only uploaded merged (mergeScenery), so their pieces aren't kept.
    const keep = model.kind === 'scenery' ? (m) => ((m.key ??= meshKey(m)), loose.set(m.key, m), m.key) : remember
    const name = model.kind === 'building' ? `${model.id}@${model.level ?? 1}` : model.id
    const paint = new Set(model.paint ?? [])
    const parts = []
    model.pieces.forEach((piece, i) => {
      const geo = geos[piece.g]
      const T = decompose(piece.m)
      const P = geo.params
      const look = lookId(piece.look, paint.has(i))
      const add = (kind, p, axes, size, extra) => {
        const q = quat(axes)
        parts.push([kind, ...p.map((x) => x * SCALE), ...q, ...size.map((x) => Math.max(THIN, x * SCALE)), look, ...(extra ? [extra] : [])])
        stats.parts++
      }
      if (T && !T.mirrored && piece.group === undefined && pristine(geo)) {
        const [X, Y, Z] = T.axes
        const [sx, sy, sz] = T.s
        const full = (start, length) => (start ?? 0) === 0 && near(length ?? Math.PI * 2, Math.PI * 2, 1e-3)
        if (geo.type === 'BoxGeometry') return add('b', T.p, T.axes, [P.width * sx, P.height * sy, P.depth * sz])
        if (geo.type === 'PlaneGeometry') return add('b', T.p, T.axes, [P.width * sx, P.height * sy, 0])
        if (geo.type === 'CylinderGeometry' && near(P.radiusTop, P.radiusBottom) && !P.openEnded && P.radialSegments >= 12 && full(P.thetaStart, P.thetaLength) && near(sx, sz))
          return add('c', T.p, [Y, neg(X), Z], [P.height * sy, 2 * P.radiusTop * sx, 2 * P.radiusTop * sz])
        if (geo.type === 'CircleGeometry' && P.segments >= 12 && full(P.thetaStart, P.thetaLength) && near(sx, sy))
          return add('c', T.p, [Z, Y, neg(X)], [0, 2 * P.radius * sy, 2 * P.radius * sx])
        if (geo.type === 'SphereGeometry' && P.widthSegments >= 8 && full(P.phiStart, P.phiLength) && near(P.thetaStart ?? 0, 0, 1e-3) && near(P.thetaLength ?? Math.PI, Math.PI, 1e-3)) {
          const d = [2 * P.radius * sx, 2 * P.radius * sy, 2 * P.radius * sz]
          return add(near(sx, sy) && near(sy, sz) ? 's' : 'e', T.p, T.axes, d)
        }
      }
      // Anything else is a mesh. Cleaned geometry is shared by every piece that draws it.
      for (const sub of trianglesOf(geo, piece.group)) {
        const subLook = sub.color ? lookId({ ...piece.look, c: mul(piece.look.c, sub.color) }, paint.has(i)) : look
        const ck = `${piece.g}/${piece.group ?? 0}/${sub.color}`
        let m = cleaned.get(ck)
        if (!m) {
          m = cleanMesh(geo.pos, geo.nrm, sub.idx)
          if (m.idx.length) {
            const b = bounds(m.pos)
            // Centre it: a MeshPart's position is the middle of its mesh.
            for (let v = 0; v < m.pos.length; v += 3) for (let k = 0; k < 3; k++) m.pos[v + k] -= b.c[k]
            m.center = b.c
            m.size = b.s
          }
          cleaned.set(ck, m)
        }
        if (!m.idx.length) continue
        if (T && !T.mirrored) {
          const key = keep(m, model.id)
          add('m', apply(piece.m, m.center), T.axes, m.size.map((x, k) => x * T.s[k]), key)
        } else {
          // Skewed or mirrored: bake the transform into the vertices.
          const pos = []
          for (let v = 0; v < m.pos.length; v += 3) pos.push(...apply(piece.m, [m.pos[v] + m.center[0], m.pos[v + 1] + m.center[1], m.pos[v + 2] + m.center[2]]))
          const b = bounds(pos)
          for (let v = 0; v < pos.length; v += 3) for (let k = 0; k < 3; k++) pos[v + k] -= b.c[k]
          const flip = T?.mirrored
          const idx = flip ? m.idx.map((_, j, a) => a[j - (j % 3) + [0, 2, 1][j % 3]]) : m.idx
          const baked = cleanMesh(pos, null, idx)
          baked.size = b.s
          const key = keep(baked, model.id)
          add('m', b.c, [[1, 0, 0], [0, 1, 0], [0, 0, 1]], b.s, key)
        }
        // Look for vertex-coloured meshes: the last part takes the sub-mesh's colour.
        if (sub.color) parts[parts.length - 1][11] = subLook
      }
    })
    out[name] = scenery.has(model.id) ? mergeScenery(parts, model.id) : parts
  }

  // The countryside is thousands of small meshes (trees, tufts, crops). Drawn one part each it
  // would cost the frame rate, so its meshes are baked together: one mesh per patch of ground and
  // look, up to MERGE_TRIS triangles each. Blocks and other plain parts stay as they are.
  function mergeScenery(parts, owner) {
    const out = []
    const groups = new Map()
    for (const p of parts) {
      if (p[0] !== 'm') {
        out.push(p)
        continue
      }
      // Close shades (a tree's tint varies a few percent) share a look, so they merge too.
      const l = looks[p[11] - 1]
      const q = '#' + [1, 3, 5].map((i) => Math.min(255, Math.round(parseInt(l.color.slice(i, i + 2), 16) / MERGE_SHADE) * MERGE_SHADE).toString(16).padStart(2, '0')).join('')
      const look = lookIds.get(JSON.stringify({ ...l, color: q })) ?? (looks.push({ ...l, color: q }), lookIds.set(JSON.stringify({ ...l, color: q }), looks.length), looks.length)
      p[11] = look
      const k = `${Math.floor(p[1] / MERGE_CHUNK)},${Math.floor(p[3] / MERGE_CHUNK)}/${look}`
      if (!groups.has(k)) groups.set(k, [])
      groups.get(k).push(p)
    }
    for (const list of groups.values()) {
      let pos = [], nrm = [], idx = []
      const flush = () => {
        if (!idx.length) return
        const b = bounds(pos)
        for (let v = 0; v < pos.length; v += 3) for (let k = 0; k < 3; k++) pos[v + k] = (pos[v + k] - b.c[k]) / SCALE
        const m = { pos, nrm, idx, size: b.s.map((x) => x / SCALE) }
        const key = remember(m, owner)
        out.push(['m', ...b.c, 0, 0, 0, 1, ...b.s.map((x) => Math.max(THIN, x)), list[0][11], key])
        pos = []; nrm = []; idx = []
      }
      for (const p of list) {
        const m = loose.get(p[12])
        if (idx.length / 3 + m.idx.length / 3 > MERGE_TRIS) flush()
        const [x, y, z, qx, qy, qz, qw] = p.slice(1, 8)
        const k = [0, 1, 2].map((i) => (m.size[i] > 1e-6 ? p[8 + i] / (m.size[i] * SCALE) : 1))
        const rot = (v) => {
          // v' = q v q*
          const tx = 2 * (qy * v[2] - qz * v[1]), ty = 2 * (qz * v[0] - qx * v[2]), tz = 2 * (qx * v[1] - qy * v[0])
          return [v[0] + qw * tx + (qy * tz - qz * ty), v[1] + qw * ty + (qz * tx - qx * tz), v[2] + qw * tz + (qx * ty - qy * tx)]
        }
        const base = pos.length / 3
        for (let v = 0; v < m.pos.length; v += 3) {
          const w = rot([m.pos[v] * SCALE * k[0], m.pos[v + 1] * SCALE * k[1], m.pos[v + 2] * SCALE * k[2]])
          pos.push(w[0] + x, w[1] + y, w[2] + z)
          const n = rot([m.nrm[v] / k[0], m.nrm[v + 1] / k[1], m.nrm[v + 2] / k[2]])
          const l = Math.hypot(n[0], n[1], n[2]) || 1
          nrm.push(n[0] / l, n[1] / l, n[2] / l)
        }
        for (const i of m.idx) idx.push(base + i)
      }
      flush()
    }
    return out
  }

  function remember(m, owner) {
    m.key ??= meshKey(m)
    if (!meshes.has(m.key)) {
      meshes.set(m.key, { key: m.key, owner, pos: m.pos, nrm: m.nrm, idx: m.idx, size: m.size })
      stats.meshes++
      stats.tris += m.idx.length / 3
    }
    return m.key
  }

  // The season the models were drawn in, and its ground colours, for the town's grass.
  const ground = { season: data.season ?? 'summer', grass: data.grass ?? '#7cc54e', meadow: data.ground ?? '#5aa83a' }
  // Where each car wears a hat: place and turn in studs, and how much the hat is scaled.
  const hatSpots = {}
  for (const [id, m] of Object.entries(data.hatSpots ?? {})) {
    const T = decompose(m)
    if (T && !T.mirrored) hatSpots[id] = [...T.p.map((x) => x * SCALE), ...quat(T.axes), T.s[1]]
  }
  return { models: out, scenery, looks, meshes, stats, ground, hatSpots, textures: data.textures ?? [] }
}

function mul(a, b) {
  const p = (s) => [1, 3, 5].map((i) => parseInt(s.slice(i, i + 2), 16) / 255)
  const [x, y] = [p(a), p(b)]
  return '#' + x.map((v, i) => Math.round(v * y[i] * 255).toString(16).padStart(2, '0')).join('')
}

// ---------------------------------------------------------------------------------------------
// Writing

const num = (x) => {
  const r = Math.round(x * 1000) / 1000
  return Object.is(r, -0) ? '0' : String(r)
}
const str = (s) => JSON.stringify(s)

// Meshes are uploaded one pack per model (the model that first draws them), as a .glb.
export function packs(meshes) {
  const byOwner = new Map()
  for (const m of meshes.values()) {
    if (!byOwner.has(m.owner)) byOwner.set(m.owner, [])
    byOwner.get(m.owner).push(m)
  }
  const out = []
  for (const [owner, all] of byOwner) {
    all.sort((a, b) => (a.key < b.key ? -1 : 1))
    // Big owners (the countryside) are split so no upload gets too large.
    let list = [], tris = 0
    const flush = () => {
      if (!list.length) return
      const hash = createHash('sha1').update(list.map((m) => m.key).join(',')).digest('hex').slice(0, 16)
      // (A hat's colours, "hat:cap|#d32f2f,#fafafa", don't belong in a file name.)
      out.push({ name: `${owner.replace(/[|#]/g, '_')}-${hash}`, owner, meshes: list })
      list = []
      tris = 0
    }
    for (const m of all) {
      if (tris + m.idx.length / 3 > PACK_TRIS) flush()
      list.push(m)
      tris += m.idx.length / 3
    }
    flush()
  }
  return out
}

function write(result) {
  const { models, scenery, looks, meshes } = result
  mkdirSync(OUT_DIR, { recursive: true })
  rmSync(GLB_DIR, { recursive: true, force: true })
  mkdirSync(GLB_DIR, { recursive: true })
  const assets = existsSync(ASSETS) ? JSON.parse(readFileSync(ASSETS, 'utf8')) : {}

  const header = (what) => `-- GENERATED by tools/models/build.mjs from the web game's 3D models. Don't edit by hand.\n-- ${what}\n`
  let cat = header('Every building (id@level) and car (id): its parts, from the web game\'s own models.') + `
-- A part is { kind, x, y, z, qx, qy, qz, qw, sx, sy, sz, look, mesh? } in studs, relative to the
-- model's middle on the ground. kind: "b" block, "c" cylinder (along X), "s" ball, "e" squashed
-- ball, "m" mesh (mesh = its key in Meshes). look indexes LOOKS.
local Catalog = {}

Catalog.SCALE = ${SCALE}

-- The season the web game drew these in (trees, leaves and lawn follow it), and its grass colours:
-- grass on the town's own land, meadow beyond it.
Catalog.SEASON = ${str(result.ground.season)}
Catalog.GRASS = ${str(result.ground.grass)}
Catalog.MEADOW = ${str(result.ground.meadow)}

-- The web game's ground textures (textures.ts), uploaded as images: the lawn on the town's land and
-- the meadow past it. span = studs one image covers; image = 0 until upload.mjs uploads it.
Catalog.TEXTURES = {
${(result.textures ?? []).map((t) => `\t${t.key} = { image = ${assets[`texture:${t.name}`] ?? 0}, span = ${num(t.span * SCALE)}, name = ${str(t.name)} },\n`).join('')}}

Catalog.LOOKS = {
`
  for (const l of looks) {
    cat += `\t{ color = ${str(l.color)}, transparency = ${num(l.transparency)}, material = ${str(l.material)}`
    if (l.paint) cat += ', paint = true'
    if (l.text) cat += `, text = { text = ${str(l.text.text)}, fg = ${str(l.text.fg)}, bg = ${str(l.text.bg)} }`
    cat += ' },\n'
  }
  const modelList = (only) => {
    let s = ''
    for (const [name, parts] of Object.entries(models)) {
      if (scenery.has(name) !== only) continue
      s += `\t[${str(name)}] = {\n`
      for (const p of parts) s += `\t\t{ ${str(p[0])}, ${p.slice(1, 11).map(num).join(', ')}, ${p[11]}${p[12] ? `, ${str(p[12])}` : ''} },\n`
      s += '\t},\n'
    }
    return s
  }
  cat += '}\n\n-- Where each car wears a hat ("hat:<id>" models): { x, y, z, qx, qy, qz, qw, scale } from the car\'s\n-- middle on the ground, in studs.\nCatalog.HAT_SPOTS = {\n'
  for (const [id, s] of Object.entries(result.hatSpots ?? {})) cat += `\t[${str(id)}] = { ${s.map(num).join(', ')} },\n`
  cat += '}\n\nCatalog.MODELS = {\n' + modelList(false) + '}\n\nreturn Catalog\n'
  writeFileSync(join(OUT_DIR, 'Catalog.luau'), cat)
  // The countryside, apart so the town's own models stay quick to load. Parts are in studs from
  // the middle of the town (not of the model), in the same form as Catalog's, with its LOOKS.
  const sc = header('The countryside round the town (Outskirts.tsx): the forest ring with its farm and lake, and each plot\'s wild meadow ("wilds:x,z").') + `local Scenery = {}

Scenery.MODELS = {
` + modelList(true) + '}\n\nreturn Scenery\n'
  writeFileSync(join(OUT_DIR, 'Scenery.luau'), sc)

  const list = packs(meshes)
  let mesh = header('Each mesh: the Roblox asset (a model of MeshParts named by key) it was uploaded in, and its size in studs.') + `-- asset = 0 until tools/models/upload.mjs uploads its pack; the game draws a box in its place until then.
local Meshes = {}

Meshes.MESHES = {
`
  for (const pk of list) {
    const asset = assets[pk.name] ?? 0
    writeFileSync(join(GLB_DIR, `${pk.name}.glb`), glb(pk.meshes))
    for (const m of pk.meshes) mesh += `\t[${str(m.key)}] = { asset = ${asset}, size = Vector3.new(${m.size.map((x) => num(x * SCALE)).join(', ')}) },\n`
  }
  mesh += '}\n\nreturn Meshes\n'
  writeFileSync(join(OUT_DIR, 'Meshes.luau'), mesh)
  // Every mesh's geometry, for the preview tools (tools/emulate/render.mjs).
  const all = {}
  for (const m of meshes.values()) all[m.key] = { pos: m.pos.map((x) => Math.round(x * 1e4) / 1e4), idx: m.idx, size: m.size }
  writeFileSync(join(ROOT, 'build/meshes.json'), JSON.stringify(all))
  // The textures for upload.mjs to upload.
  mkdirSync(TEX_DIR, { recursive: true })
  writeFileSync(join(TEX_DIR, 'list.json'), JSON.stringify((result.textures ?? []).map((t) => ({ name: t.name, file: t.file })), null, 1))
  writeFileSync(join(GLB_DIR, 'packs.json'), JSON.stringify(list.map((p) => ({ name: p.name, file: `${p.name}.glb`, meshes: p.meshes.length })), null, 1))
  return list
}

// ---------------------------------------------------------------------------------------------

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  await MeshoptSimplifier.ready
  const args = process.argv.slice(2)
  const file = args[0] === '--json' ? args[1] : render(resolve(args[0] ?? 'web'))
  const result = convert(JSON.parse(readFileSync(file, 'utf8')))
  const list = write(result)
  const s = result.stats
  console.log(`${Object.keys(result.models).length} models, ${s.parts} parts, ${s.meshes} meshes (${s.tris} triangles) in ${list.length} packs`)
}
