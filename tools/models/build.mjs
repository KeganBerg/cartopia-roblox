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
import { polishBuilding } from './walk.mjs'

const HERE = dirname(fileURLToPath(import.meta.url))
const ROOT = resolve(HERE, '../..')
const OUT_DIR = join(ROOT, 'src/shared/Models')
const LEVELS_DIR = join(ROOT, 'src/server/Levels')
const GLB_DIR = join(ROOT, 'build/meshes')
const TEX_DIR = join(ROOT, 'build/textures')
const ASSETS = join(HERE, 'assets.json')

export const SCALE = 10
// Thinnest a part may be (studs). Flat panels and discs get this thickness.
const THIN = 0.05
// Thickness of a pad lying on a sidewalk (studs), enough to stay clear of the paving at a distance.
const PAD = 0.3
// Countryside meshes are merged per MERGE_CHUNK studs of ground, up to MERGE_TRIS triangles each
// (Roblox takes up to 20,000 a mesh).
const MERGE_CHUNK = 700
const MERGE_TRIS = 10000
// The far land (horizon:land) reaches 15,000 studs out and is only ever seen from afar, so it
// merges over bigger patches (a part can measure at most 2,048 studs).
const HORIZON_CHUNK = 1400
// and rounds its colours more coarsely, so fewer looks share each patch.
const HORIZON_SHADE = 20
// Countryside colours are rounded to steps of this much (of 255) so near shades merge.
const MERGE_SHADE = 14
// Race venue pieces smaller than this (studs, longest side) are merged like the countryside, plain
// blocks included: a farm strip is 30,000 pieces. Bigger ones (the road, the ground) stay parts,
// cut into lengths of at most LONGEST, the most a Roblox part can measure.
const RACE_SMALL = 60
const LONGEST = 2000
// Flat race pieces lower than this (web units) are ground layers (see the layer spread in convert).
const RACE_LAYERS = 0.06
// A mesh pack (one uploaded model) holds up to this many triangles.
const PACK_TRIS = 60000
// Meshes denser than this many triangles are simplified, keeping the shape within ERROR of its size.
const DENSE = 400
const KEEP = 0.4
const ERROR = 0.004

// ---------------------------------------------------------------------------------------------
// Rendering

// How far (studs, each way from its middle) the shared world's ground reaches, as server/World
// works it out: half a plot past the last ring, and 600 more. The far land starts there.
function worldReach() {
  const src = readFileSync(join(ROOT, 'src/server/World.luau'), 'utf8')
  const pitch = Number(src.match(/World\.PITCH = (\d+)/)?.[1])
  const rings = Number(src.match(/local RINGS = (\d+)/)?.[1])
  if (!pitch || !rings) throw new Error('server/World.luau has no PITCH or RINGS')
  return (rings + 0.5) * pitch + 600
}

function render(web) {
  const test = join(web, 'src/__rbx_export__.test.tsx')
  const out = join(ROOT, 'build/models.json')
  mkdirSync(dirname(out), { recursive: true })
  copyFileSync(join(HERE, 'export.test.tsx'), test)
  try {
    execFileSync('npx', ['vitest', 'run', 'src/__rbx_export__.test.tsx'], {
      cwd: web,
      stdio: 'inherit',
      env: { ...process.env, RBX_MODELS_OUT: out, RBX_WORLD_REACH: String(worldReach()) },
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

// The Roblox material nearest each of the web game's hand-drawn textures (scene/textures.ts), for
// buildings: players walk right up to them, where a flat colour reads as an untextured wall. Ground
// textures (grass, asphalt) stay as they are: the town's ground is drawn to its own rules.
const TEX_MATERIAL = {
  brickTex: 'Brick',
  sidingTex: 'WoodPlanks',
  shingleTex: 'RoofShingles',
  gravelTex: 'Pebble',
  concreteTex: 'Concrete',
  paverTex: 'Pavement',
  corrugatedTex: 'Metal',
  shutterTex: 'Metal',
  containerTex: 'Metal',
  curtainTex: 'Fabric',
  sandTex: 'Sand',
  beachSandTex: 'Sand',
  snowTex: 'Snow',
  soilTex: 'Ground',
  dirtTex: 'Ground',
  windowTex: 'Glass',
}

// The windows walk.mjs adds to bare walls: a pale frame round dark glass.
const WINDOW_FRAME = { c: '#eceff1', o: 1 }
const WINDOW_GLASS = { c: '#5b7a90', o: 1, tex: 'windowTex' }

function lookKey(look, paint, building = false) {
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
  else if (building && TEX_MATERIAL[look.tex]) material = TEX_MATERIAL[look.tex]
  const color = material === 'Neon' && look.e ? look.e : c
  return { color, transparency, material, text: look.text ?? null, paint: !!paint }
}

// ---------------------------------------------------------------------------------------------
// Meshes

// The triangles of a geometry (or of one of its material groups), as positions, normals and
// indices, split by vertex colour when it has them (each colour becomes its own mesh). The far
// land's (far) are read as three.js stores them, in linear light, and rounded to HORIZON_SHADE
// steps there and then: its terrain has a shade of its own on every facet.
const toSrgb = (x) => (x <= 0.0031308 ? x * 12.92 : 1.055 * x ** (1 / 2.4) - 0.055)
function trianglesOf(geo, group, far = false) {
  const g = group === undefined ? null : geo.groups?.[group]
  const start = g ? g.start : 0
  const end = g ? Math.min(geo.idx.length, g.start + g.count) : geo.idx.length
  const byColor = new Map()
  for (let i = start; i + 2 < end; i += 3) {
    const tri = [geo.idx[i], geo.idx[i + 1], geo.idx[i + 2]]
    let key = ''
    if (geo.col) {
      const v = tri[0] * 3
      const level = far ? (x) => Math.min(255, Math.round((toSrgb(x) * 255) / HORIZON_SHADE) * HORIZON_SHADE) : (x) => Math.round(x * 255)
      key = '#' + [geo.col[v], geo.col[v + 1], geo.col[v + 2]].map((x) => level(Math.max(0, Math.min(1, x))).toString(16).padStart(2, '0')).join('')
    }
    if (!byColor.has(key)) byColor.set(key, [])
    byColor.get(key).push(...tri)
  }
  return [...byColor].map(([color, idx]) => ({ color: color || null, idx }))
}

// Welds vertices that share a position and normal, drops unused ones, and simplifies dense
// meshes (unless keep: the far land's terrain, cut up by colour into loose facets that
// simplifying would punch holes in). Returns positions, normals and indices.
function cleanMesh(pos, nrm, idx, keep = false) {
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
  if (tris.length / 3 > DENSE && !keep) {
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
  const lookId = (look, paint, building) => {
    const l = lookKey(look, paint, building)
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
  const stats = { parts: 0, meshes: 0, tris: 0, moved: 0, windows: 0 }

  const meshKey = (m) => createHash('sha1').update(new Float32Array(m.pos)).update(new Uint32Array(m.idx)).digest('hex').slice(0, 16)

  const out = {}
  const piecesToParts = {}
  const loose = new Map()
  const scenery = new Set()
  const races = new Set()
  for (const model of models) {
    const merged = model.kind === 'scenery' || model.kind === 'race'
    if (merged) scenery.add(model.id)
    if (model.kind === 'race') races.add(model.id)
    // Countryside meshes are only uploaded merged (mergeScenery), so their pieces aren't kept.
    const keep = merged ? (m) => ((m.key ??= meshKey(m)), loose.set(m.key, m), m.key) : remember
    const name = model.kind === 'building' ? `${model.id}@${model.level ?? 1}${model.block ? `/${model.block}` : ''}` : model.id
    const paint = new Set(model.paint ?? [])
    // A car's mods and custom paint panels share one pack ("mod:<car>"), which the game loads only
    // when that car needs it.
    const packOwner = model.id.startsWith('mod:') || model.id.startsWith('panel:') ? `mod:${model.id.split(':')[1]}` : model.id
    const parts = []
    // Which parts (1-based, as Luau counts) each piece became, for the stock pieces a mod takes away.
    const partsOf = []
    model.pieces.forEach((piece, i) => {
      const from = parts.length
      convertPiece(piece, i)
      partsOf[i] = Array.from({ length: parts.length - from }, (_, k) => from + k + 1)
    })
    if (model.kind === 'car' || data.spinsOf?.[model.id]) piecesToParts[model.id] = partsOf
    function convertPiece(piece, i) {
      const geo = geos[piece.g]
      // The web game stacks the strip's flat layers (ground, asphalt, paint) a hundredth of a unit
      // apart (layers.ts LAYER) and nudges paint forward in depth (decal). Roblox has no such nudge, and a
      // tenth of a stud flickers at a distance, so race venues spread those layers four times wider.
      if (model.kind === 'race' && (geo.type === 'PlaneGeometry' || geo.type === 'CircleGeometry') && Math.abs(piece.m[13]) < RACE_LAYERS) {
        piece = { ...piece, m: piece.m.map((x, k) => (k === 13 ? x * 4 : x)) }
      }
      const T = decompose(piece.m)
      const P = geo.params
      const look = lookId(piece.look, paint.has(i), model.kind === 'building')
      const add = (kind, p, axes, size, extra) => {
        const q = quat(axes)
        parts.push([kind, ...p.map((x) => x * SCALE), ...q, ...size.map((x) => Math.max(THIN, x * SCALE)), look, ...(extra ? [extra] : [])])
        stats.parts++
      }
      // Small race pieces (anything but signs) go to the mesh merge whatever their shape.
      const small = model.kind === 'race' && !piece.look.text && T && Math.max(...bounds(geo.pos).s.map((x, k) => x * T.s[k])) * SCALE < RACE_SMALL
      if (T && !T.mirrored && piece.group === undefined && pristine(geo) && !small) {
        const [X, Y, Z] = T.axes
        const [sx, sy, sz] = T.s
        const full = (start, length) => (start ?? 0) === 0 && near(length ?? Math.PI * 2, Math.PI * 2, 1e-3)
        if (geo.type === 'BoxGeometry') {
          // A thin pad lying on a sidewalk (the yellow tactile pads at crosswalks) stands a few
          // hundredths of a stud proud of the paving, which flickers against it in Roblox: it's
          // made PAD studs thick, its underside where it was.
          const h = P.height * sy
          if (model.id.startsWith('walk:') && Y[1] > 0.99 && h * SCALE < PAD && T.p[1] - h / 2 > 0.002) {
            const bottom = T.p[1] - h / 2
            return add('b', [T.p[0], bottom + PAD / SCALE / 2, T.p[2]], T.axes, [P.width * sx, PAD / SCALE, P.depth * sz])
          }
          return add('b', T.p, T.axes, [P.width * sx, h, P.depth * sz])
        }
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
      for (const sub of trianglesOf(geo, piece.group, model.id.startsWith('horizon:'))) {
        const subLook = sub.color ? lookId({ ...piece.look, c: mul(piece.look.c, sub.color) }, paint.has(i), model.kind === 'building') : look
        const ck = `${piece.g}/${piece.group ?? 0}/${sub.color}`
        let m = cleaned.get(ck)
        if (!m) {
          m = cleanMesh(geo.pos, geo.nrm, sub.idx, model.id.startsWith('horizon:'))
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
          const key = keep(m, packOwner)
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
          const key = keep(baked, packOwner)
          add('m', b.c, [[1, 0, 0], [0, 1, 0], [0, 0, 1]], b.s, key)
        }
        // Look for vertex-coloured meshes: the last part takes the sub-mesh's colour.
        if (sub.color) parts[parts.length - 1][11] = subLook
      }
    }
    if (model.kind === 'building') {
      const r = polishBuilding(parts, model.lot?.map((x) => x * SCALE), looks, lookId(WINDOW_FRAME, false, true), lookId(WINDOW_GLASS, false, true))
      stats.moved += r.moved
      stats.windows += r.windows
      if (process.env.WALK_LOG && (r.moved || r.windows)) console.log(`${name}: ${r.moved} moved, ${r.windows} windows`)
    }
    out[name] = scenery.has(model.id) ? mergeScenery(model.kind === 'race' ? cutLong(parts) : parts, model.id) : parts
  }

  // Blocks longer than a Roblox part can be, cut into equal lengths along their long sides.
  function cutLong(parts) {
    const out = []
    for (const p of parts) {
      const size = p.slice(8, 11)
      const n = size.map((x) => Math.ceil(x / LONGEST))
      if (p[0] !== 'b' || n.every((k) => k === 1)) {
        out.push(p)
        continue
      }
      const [qx, qy, qz, qw] = p.slice(4, 8)
      // The block's own axes, from its rotation.
      const axes = [
        [1 - 2 * (qy * qy + qz * qz), 2 * (qx * qy + qz * qw), 2 * (qx * qz - qy * qw)],
        [2 * (qx * qy - qz * qw), 1 - 2 * (qx * qx + qz * qz), 2 * (qy * qz + qx * qw)],
        [2 * (qx * qz + qy * qw), 2 * (qy * qz - qx * qw), 1 - 2 * (qx * qx + qy * qy)],
      ]
      const piece = size.map((x, k) => x / n[k])
      for (let i = 0; i < n[0]; i++) for (let j = 0; j < n[1]; j++) for (let k = 0; k < n[2]; k++) {
        const off = [i, j, k].map((t, a) => (t + 0.5) * piece[a] - size[a] / 2)
        const at = [0, 1, 2].map((c) => p[1 + c] + axes[0][c] * off[0] + axes[1][c] * off[1] + axes[2][c] * off[2])
        out.push([p[0], ...at, qx, qy, qz, qw, ...piece, ...p.slice(11)])
      }
    }
    return out
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
      const shade = owner.startsWith('horizon:') ? HORIZON_SHADE : MERGE_SHADE
      const q = '#' + [1, 3, 5].map((i) => Math.min(255, Math.round(parseInt(l.color.slice(i, i + 2), 16) / shade) * shade).toString(16).padStart(2, '0')).join('')
      const look = lookIds.get(JSON.stringify({ ...l, color: q })) ?? (looks.push({ ...l, color: q }), lookIds.set(JSON.stringify({ ...l, color: q }), looks.length), looks.length)
      p[11] = look
      const chunk = owner.startsWith('horizon:') ? HORIZON_CHUNK : MERGE_CHUNK
      const k = `${Math.floor(p[1] / chunk)},${Math.floor(p[3] / chunk)}/${look}`
      if (!groups.has(k)) groups.set(k, [])
      groups.get(k).push(p)
    }
    // The far land's pieces are huge (the terrain is one mesh, split only by colour), so its
    // triangles are sorted into patches one by one; elsewhere a piece goes whole to its patch.
    const horizon = owner.startsWith('horizon:')
    for (const list of horizon ? regroup(groups) : groups.values()) {
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
        const m = p.world ?? placed(p)
        if (idx.length / 3 + m.idx.length / 3 > MERGE_TRIS) flush()
        const base = pos.length / 3
        pos.push(...m.pos)
        nrm.push(...m.nrm)
        for (const i of m.idx) idx.push(base + i)
      }
      flush()
    }
    return out
  }

  // A merged piece's mesh moved into place: positions in studs, as the patch holds them.
  function placed(p) {
    const m = loose.get(p[12])
    const [x, y, z, qx, qy, qz, qw] = p.slice(1, 8)
    const k = [0, 1, 2].map((i) => (m.size[i] > 1e-6 ? p[8 + i] / (m.size[i] * SCALE) : 1))
    const rot = (v) => {
      // v' = q v q*
      const tx = 2 * (qy * v[2] - qz * v[1]), ty = 2 * (qz * v[0] - qx * v[2]), tz = 2 * (qx * v[1] - qy * v[0])
      return [v[0] + qw * tx + (qy * tz - qz * ty), v[1] + qw * ty + (qz * tx - qx * tz), v[2] + qw * tz + (qx * ty - qy * tx)]
    }
    const pos = [], nrm = []
    for (let v = 0; v < m.pos.length; v += 3) {
      const w = rot([m.pos[v] * SCALE * k[0], m.pos[v + 1] * SCALE * k[1], m.pos[v + 2] * SCALE * k[2]])
      pos.push(w[0] + x, w[1] + y, w[2] + z)
      const n = rot([m.nrm[v] / k[0], m.nrm[v + 1] / k[1], m.nrm[v + 2] / k[2]])
      const l = Math.hypot(n[0], n[1], n[2]) || 1
      nrm.push(n[0] / l, n[1] / l, n[2] / l)
    }
    return { pos, nrm, idx: m.idx }
  }

  // Cuts triangles longer than a patch in half, longest side first, until none is (the lake is
  // one ring of triangles 13,000 studs long).
  function split(m) {
    const pos = [], nrm = [], idx = []
    const v = (i) => [m.pos.slice(i * 3, i * 3 + 3), m.nrm.slice(i * 3, i * 3 + 3)]
    const put = (tri) => {
      const d = [0, 1, 2].map((j) => Math.hypot(...tri[j][0].map((x, k) => x - tri[(j + 1) % 3][0][k])))
      const j = d.indexOf(Math.max(...d))
      if (d[j] <= 450) {
        for (const [p, n] of tri) {
          idx.push(pos.length / 3)
          pos.push(...p)
          nrm.push(...n)
        }
        return
      }
      const a = tri[j], b = tri[(j + 1) % 3], c = tri[(j + 2) % 3]
      const mid = [a[0].map((x, k) => (x + b[0][k]) / 2), a[1].map((x, k) => (x + b[1][k]) / 2)]
      put([a, mid, c])
      put([mid, b, c])
    }
    for (let t = 0; t < m.idx.length; t += 3) put([v(m.idx[t]), v(m.idx[t + 1]), v(m.idx[t + 2])])
    return { pos, nrm, idx }
  }

  // The far land's groups again, each triangle in the patch (a cube, mountains being tall) its middle lies in. Each patch's
  // triangles come back as pieces of their own (world set), at most MERGE_TRIS a piece.
  function* regroup(groups) {
    const patches = new Map()
    for (const list of groups.values()) {
      for (const p of list) {
        const m = split(placed(p))
        for (let t = 0; t < m.idx.length; t += 3) {
          const c = [0, 1, 2].map((k) => Math.floor((m.pos[m.idx[t] * 3 + k] + m.pos[m.idx[t + 1] * 3 + k] + m.pos[m.idx[t + 2] * 3 + k]) / 3 / HORIZON_CHUNK))
          const key = `${c.join(',')}/${p[11]}`
          let into = patches.get(key)
          if (!into) patches.set(key, (into = { look: p[11], pos: [], nrm: [], idx: [] }))
          for (let j = 0; j < 3; j++) {
            const v = m.idx[t + j]
            into.idx.push(into.pos.length / 3)
            into.pos.push(m.pos[v * 3], m.pos[v * 3 + 1], m.pos[v * 3 + 2])
            into.nrm.push(m.nrm[v * 3], m.nrm[v * 3 + 1], m.nrm[v * 3 + 2])
          }
        }
      }
    }
    for (const d of patches.values()) {
      const piece = []
      piece[11] = d.look
      piece.world = { pos: d.pos, nrm: d.nrm, idx: d.idx }
      yield [piece]
    }
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
  // Mods: the stock car parts each one takes away, every car's stock wheel parts, and how far
  // each stance moves a car's body (studs).
  const toParts = (car, list) => list.flatMap((i) => piecesToParts[car]?.[i] ?? [])
  const modDrops = {}
  for (const [car, byMod] of Object.entries(data.modDrops ?? {}))
    for (const [mod, list] of Object.entries(byMod)) (modDrops[car] ??= {})[mod] = toParts(car, list)
  const wheels = {}
  for (const [car, list] of Object.entries(data.wheelsOf ?? {})) wheels[car] = toParts(car, list)
  const rims = {}
  for (const [car, list] of Object.entries(data.rimsOf ?? {})) rims[car] = toParts(car, list)
  const panelDrops = {}
  for (const [car, list] of Object.entries(data.panelDrops ?? {})) panelDrops[car] = toParts(car, list)
  const trim = {}
  for (const [car, byKind] of Object.entries(data.trimOf ?? {}))
    for (const [kind, list] of Object.entries(byKind)) (trim[car] ??= {})[kind] = toParts(car, list)
  // A fly-over's turning parts: the point and axis they turn about (studs) and how fast.
  const spins = {}
  for (const [id, list] of Object.entries(data.spinsOf ?? {}))
    spins[id] = list.map((s) => ({ at: s.at.map((x) => x * SCALE), axis: s.axis, speed: s.speed, parts: toParts(id, s.pieces) }))
  const stance = {}
  for (const [car, byMod] of Object.entries(data.stanceOf ?? {}))
    for (const [mod, rise] of Object.entries(byMod)) (stance[car] ??= {})[mod] = rise * SCALE
  return { models: out, scenery, races, looks, meshes, stats, ground, hatSpots, modDrops, wheels, rims, panelDrops, trim, stance, spins, townSizes: data.townSizes ?? {}, turbines: (data.turbines ?? []).map(([x, y, z, yaw, tint]) => [x * SCALE, y * SCALE, z * SCALE, yaw, tint]), textures: [...(data.textures ?? []), ...skinTextures()] }
}

// The car skins baked by skins.mjs (kept in tools/models/skins/), as textures to upload: each
// skin's base ("skin_<n>") and its glow at each moment ("skinglow_<n>", "skinglow2_<n>", ..., with
// how deep under the paint the glow lies and the time between moments), and each skin's picker
// swatch ("skinswatch_<id>"), named by their content.
function skinTextures() {
  const dir = join(HERE, 'skins')
  if (!existsSync(join(dir, 'skins.json'))) return []
  const { span, step, skins, swatches = [] } = JSON.parse(readFileSync(join(dir, 'skins.json'), 'utf8'))
  mkdirSync(TEX_DIR, { recursive: true })
  const out = []
  const add = (key, file, extra = {}) => {
    const data = readFileSync(join(dir, file))
    const name = `${file.replace(/\.png$/, '')}-${createHash('sha1').update(data).digest('hex').slice(0, 16)}`
    copyFileSync(join(dir, file), join(TEX_DIR, `${name}.png`))
    out.push({ key, name, file: `${name}.png`, span, ...extra })
  }
  for (const s of skins) {
    add(`skin_${s.n}`, s.base)
    s.glows.forEach((file, k) => add(k === 0 ? `skinglow_${s.n}` : `skinglow${k + 1}_${s.n}`, file, { ...(s.depth ? { depth: s.depth } : {}), ...(step ? { step } : {}) }))
  }
  for (const w of swatches) add(`skinswatch_${w.id}`, w.file)
  return out
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

// Meshes are uploaded as .glb packs. A car's mods (loaded when it needs them), the far land and the
// race venues (loaded later) keep a pack per model; everything else a new server loads at once is
// shared out into a few bigger packs per kind (buildings and cars, stripes, hats, ...), since each
// pack is a separate load and hundreds of small ones kept a new server's first players waiting.
// A model always lands in the same pack (picked by a hash of its name), so changing one model
// uploads only its own pack again.
const PACK_AIM = 40000 // triangles a shared pack is sized for
const ownPack = (owner) => /^(mod|horizon|race):/.test(owner)
export function packs(meshes) {
  const byOwner = new Map()
  for (const m of meshes.values()) {
    if (!byOwner.has(m.owner)) byOwner.set(m.owner, [])
    byOwner.get(m.owner).push(m)
  }
  const trisOf = (list) => list.reduce((n, m) => n + m.idx.length / 3, 0)
  // The kind of a model: what its name starts with ("stripe:hotshot" -> stripe), or "model".
  const kindOf = (owner) => (owner.includes(':') ? owner.split(':')[0] : 'model')
  const kindTris = new Map()
  for (const [owner, all] of byOwner) {
    if (!ownPack(owner)) kindTris.set(kindOf(owner), (kindTris.get(kindOf(owner)) ?? 0) + trisOf(all))
  }
  const groups = new Map()
  for (const [owner, all] of byOwner) {
    let group = owner
    // (Big models, the countryside's, fill packs of their own.)
    if (!ownPack(owner) && trisOf(all) < PACK_AIM / 2) {
      const kind = kindOf(owner)
      const count = Math.max(1, Math.ceil(kindTris.get(kind) / PACK_AIM))
      const pick = parseInt(createHash('sha1').update(owner).digest('hex').slice(0, 8), 16) % count
      group = `${kind}-${pick + 1}`
    }
    if (!groups.has(group)) groups.set(group, [])
    groups.get(group).push(...all)
  }
  const out = []
  for (const [owner, all] of groups) {
    all.sort((a, b) => (a.key < b.key ? -1 : 1))
    // Big ones are split so no upload gets too large.
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
  const { models, scenery, races, looks, meshes } = result
  mkdirSync(OUT_DIR, { recursive: true })
  rmSync(GLB_DIR, { recursive: true, force: true })
  mkdirSync(GLB_DIR, { recursive: true })
  const assets = existsSync(ASSETS) ? JSON.parse(readFileSync(ASSETS, 'utf8')) : {}
  // The image inside each uploaded texture decal, where tools/models/resolve-images.mjs found it.
  const IMAGES = join(HERE, 'images.json')
  const images = existsSync(IMAGES) ? JSON.parse(readFileSync(IMAGES, 'utf8')) : {}
  const imageOf = (decal) => (decal ? images[decal] ?? decal : 0)

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
-- the meadow past it, and the custom paint patterns (pattern_<id>). span = studs one image covers;
-- image = 0 until upload.mjs uploads it.
Catalog.TEXTURES = {
${(result.textures ?? []).map((t) => `\t${t.key} = { image = ${imageOf(assets[`texture:${t.name}`])}, span = ${num(t.span * SCALE)}, name = ${str(t.name)}${t.depth ? `, depth = ${num(t.depth * SCALE)}` : ''}${t.step ? `, step = ${num(t.step)}` : ''} },\n`).join('')}}

Catalog.LOOKS = {
`
  for (const l of looks) {
    cat += `\t{ color = ${str(l.color)}, transparency = ${num(l.transparency)}, material = ${str(l.material)}`
    if (l.paint) cat += ', paint = true'
    if (l.text) cat += `, text = { text = ${str(l.text.text)}, fg = ${str(l.text.fg)}, bg = ${str(l.text.bg)} }`
    cat += ' },\n'
  }
  // which: 'town' (Catalog), 'scenery' (the countryside) or 'race' (the race venues).
  // A building's levels above 1 and its merged blocks ("id@level/2x1x1") go to the server, one
  // module per building (LEVELS_DIR): only TownView draws them. (Not the Speedway's levels: the
  // players' own screens put its crowd on its stands.)
  const grownOf = (name) => {
    const m = /^(.+)@(\d+)(\/.+)?$/.exec(name)
    return m && (+m[2] > 1 || m[3]) && m[1] !== 'stadium' ? m[1] : null
  }
  const modelList = (which, only) => {
    let s = ''
    for (const [name, parts] of Object.entries(models)) {
      const grown = grownOf(name)
      if ((races.has(name) ? 'race' : scenery.has(name) ? 'scenery' : grown ? 'level' : 'town') !== which) continue
      if (only && grown !== only) continue
      s += `\t[${str(name)}] = {\n`
      for (const p of parts) s += `\t\t{ ${str(p[0])}, ${p.slice(1, 11).map(num).join(', ')}, ${p[11]}${p[12] ? `, ${str(p[12])}` : ''} },\n`
      s += '\t},\n'
    }
    return s
  }
  cat += '}\n\n-- Where each car wears a hat ("hat:<id>" models): { x, y, z, qx, qy, qz, qw, scale } from the car\'s\n-- middle on the ground, in studs.\nCatalog.HAT_SPOTS = {\n'
  for (const [id, s] of Object.entries(result.hatSpots ?? {})) cat += `\t[${str(id)}] = { ${s.map(num).join(', ')} },\n`
  const lists = (o) => Object.entries(o).map(([k, v]) => `[${str(k)}] = { ${v.map(num).join(', ')} }`).join(', ')
  cat += '}\n\n-- Mods ("mod:<car>:<mod>" models): the car\'s own parts (indices into its MODELS entry) each mod\n-- takes away, by car then mod.\nCatalog.MOD_DROPS = {\n'
  for (const [car, byMod] of Object.entries(result.modDrops ?? {})) cat += `\t[${str(car)}] = { ${lists(byMod)} },\n`
  cat += '}\n\n-- Each car\'s stock wheel parts (tyres and rims), which a set of rims replaces.\nCatalog.WHEELS = {\n'
  for (const [car, list] of Object.entries(result.wheels ?? {})) cat += `\t[${str(car)}] = { ${list.map(num).join(', ')} },\n`
  cat += '}\n\n-- Each car\'s stock rims (custom paint colours them).\nCatalog.RIMS = {\n'
  for (const [car, list] of Object.entries(result.rims ?? {})) cat += `\t[${str(car)}] = { ${list.map(num).join(', ')} },\n`
  cat += '}\n\n-- The car parts its custom paint panels ("panel:<car>:<hood|doors|roof|body>" models) take the\n-- place of: its paint.\nCatalog.PANEL_DROPS = {\n'
  for (const [car, list] of Object.entries(result.panelDrops ?? {})) cat += `\t[${str(car)}] = { ${list.map(num).join(', ')} },\n`
  cat += '}\n\n-- Each car\'s trim parts (game/trim.ts): its glass (tint), headlights and door handles.\nCatalog.TRIM = {\n'
  for (const [car, byKind] of Object.entries(result.trim ?? {})) cat += `\t[${str(car)}] = { ${lists(byKind)} },\n`
  cat += '}\n\n-- Each fly-over\'s turning parts (rotors, props, FlyByModels.tsx): the point and axis they turn\n-- about from the model\'s middle, in studs, radians a second, and the parts (indices into MODELS).\nCatalog.SPINS = {\n'
  for (const [id, list] of Object.entries(result.spins ?? {}))
    cat += `\t[${str(id)}] = {\n${list.map((s) => `\t\t{ at = { ${s.at.map(num).join(', ')} }, axis = { ${s.axis.map(num).join(', ')} }, speed = ${num(s.speed)}, parts = { ${s.parts.map(num).join(', ')} } },\n`).join('')}\t},\n`
  cat += '}\n\n-- How far each stance mod moves a car\'s body up (or down), in studs.\nCatalog.STANCE = {\n'
  for (const [car, byMod] of Object.entries(result.stance ?? {})) cat += `\t[${str(car)}] = { ${Object.entries(byMod).map(([k, v]) => `${k} = ${num(v)}`).join(', ')} },\n`
  cat += '}\n\n-- Each car in town traffic (townCarSize.ts): { length, width } in web units, and the scale it\'s\n-- drawn at.\nCatalog.TOWN_SIZE = {\n'
  for (const [car, v] of Object.entries(result.townSizes ?? {})) cat += `\t[${str(car)}] = { ${v.map(num).join(', ')} },\n`
  cat += '}\n\nCatalog.MODELS = {\n' + modelList('town') + '}\n\nreturn Catalog\n'
  writeFileSync(join(OUT_DIR, 'Catalog.luau'), cat)
  // Each building's grown levels (server/Levels/<id>.luau), loaded by TownView when a town has one.
  rmSync(LEVELS_DIR, { recursive: true, force: true })
  mkdirSync(LEVELS_DIR, { recursive: true })
  for (const id of new Set(Object.keys(models).map(grownOf).filter(Boolean))) {
    writeFileSync(join(LEVELS_DIR, `${id}.luau`), header(`${id} at the levels where its design changes (id@level) and merged (id@level/<block scale>), as Catalog.MODELS (parts and looks alike).`) + 'return {\n' + modelList('level', id) + '}\n')
  }
  // The countryside, apart so the town's own models stay quick to load. Parts are in studs from
  // the middle of the town (not of the model), in the same form as Catalog's, with its LOOKS.
  const sc = header('The countryside round the town (Outskirts.tsx): the forest ring with its farm and lake, and each plot\'s wild meadow ("wilds:x,z").') + `local Scenery = {}

Scenery.MODELS = {
` + modelList('scenery') + `}

-- The far land's wind turbines (Horizon.tsx WindFarm), whose rotors client/Horizon spins: the
-- middle of each rotor in studs from the middle of the town, its heading, and its tint (0-1).
Scenery.TURBINES = {
${(result.turbines ?? []).map((t) => `\t{ ${t.map(num).join(', ')} },\n`).join('')}}

return Scenery
`
  writeFileSync(join(OUT_DIR, 'Scenery.luau'), sc)
  // The drag strip at each race venue, in studs from the start line's middle: "race:<venue>", and
  // "race:<venue>:far", the horizon, drawn round the camera (it rides along with it).
  const rs = header('The drag strip and its scenery at each race venue (RaceScene.tsx, RaceVenues.tsx, Skyline.tsx).') + `local RaceScenery = {}

RaceScenery.MODELS = {
` + modelList('race') + '}\n\nreturn RaceScenery\n'
  writeFileSync(join(OUT_DIR, 'RaceScenery.luau'), rs)

  const list = packs(meshes)
  let mesh = header('Each mesh: the Roblox asset (a model of MeshParts named by key) it was uploaded in, and its size in studs.') + `-- asset = 0 until tools/models/upload.mjs uploads its pack; the game draws a box in its place until then.\n-- lazy: in a car's mod pack, loaded only when a car needs it (Builder.loadFor).\n-- late: the far land's, loaded after everything else (Builder.loadLate), so towns don't wait for it.
local Meshes = {}

Meshes.MESHES = {
`
  for (const pk of list) {
    const asset = assets[pk.name] ?? 0
    writeFileSync(join(GLB_DIR, `${pk.name}.glb`), glb(pk.meshes))
    const lazy = pk.owner.startsWith('mod:') ? ', lazy = true' : pk.owner.startsWith('horizon:') ? ', late = true' : ''
    for (const m of pk.meshes) mesh += `\t[${str(m.key)}] = { asset = ${asset}, size = Vector3.new(${m.size.map((x) => num(x * SCALE)).join(', ')})${lazy} },\n`
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

// Reads the export: the models, and their shapes from the file beside it, one per line (too many
// for one JSON string). Older exports carry the shapes inline.
export function loadModels(file) {
  const data = JSON.parse(readFileSync(file, 'utf8'))
  if (!data.geos && data.geosFile) {
    const buf = readFileSync(join(dirname(file), data.geosFile))
    data.geos = []
    for (let at = 0; at < buf.length; ) {
      let end = buf.indexOf(10, at)
      if (end < 0) end = buf.length
      if (end > at) data.geos.push(JSON.parse(buf.toString('utf8', at, end)))
      at = end + 1
    }
  }
  return data
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  await MeshoptSimplifier.ready
  const args = process.argv.slice(2)
  const file = args[0] === '--json' ? args[1] : render(resolve(args[0] ?? 'web'))
  const result = convert(loadModels(file))
  const list = write(result)
  const s = result.stats
  console.log(`${Object.keys(result.models).length} models, ${s.parts} parts, ${s.meshes} meshes (${s.tris} triangles) in ${list.length} packs; ${s.moved} props moved out of walls, ${s.windows} windows added`)
}
