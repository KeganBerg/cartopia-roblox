// @vitest-environment jsdom
// Renders every building and car the web game draws and writes what it drew: each mesh's shape,
// place, size and look. tools/models/build.mjs copies this file into the web game's src folder,
// runs it with the web game's own test runner, and turns the result into Roblox parts.
//
// Nothing here draws to a screen: @react-three/test-renderer builds the same three.js scene the
// game would show, and this walks it.
import { closeSync, mkdirSync, openSync, writeFileSync, writeSync } from 'fs'
import { createHash } from 'crypto'
import { basename, dirname, join } from 'path'
import { deflateSync } from 'zlib'
import { it, vi } from 'vitest'
import ReactThreeTestRenderer from '@react-three/test-renderer'
import {
  Color, Euler, InstancedMesh, Matrix4, Mesh, Quaternion, Vector3,
  type BufferGeometry, type Material, type MeshBasicMaterial, type MeshStandardMaterial, type Object3D,
} from 'three'
import { BUILDINGS, CARS } from './game/data'

// Batch (scene/Batch.tsx) merges a scene's meshes into a few big ones, baking their colours into
// vertices. The race venues are exported with it switched off, so every piece keeps its own shape
// and look (the countryside is still exported merged, as it always was).
const batching = vi.hoisted(() => ({ off: false }))
vi.mock('./scene/Batch', async (load) => {
  const real = (await load()) as Record<string, unknown>
  const React = await import('react')
  const Plain = (p: { children?: React.ReactNode }) => React.createElement('group', null, p.children)
  return { ...real, Batch: (p: Record<string, unknown>) => React.createElement((batching.off ? Plain : real.Batch) as React.FC, p) }
})
// Every hand-drawn texture (scene/textures.ts) is tagged with the name of the function that made it,
// so build.mjs can give the surface the nearest Roblox material (brick walls as Brick, shingles as
// RoofShingles): seen up close in walk mode, a flat colour reads as an untextured wall.
vi.mock('./scene/textures', async (load) => {
  const real = (await load()) as Record<string, unknown>
  const out: Record<string, unknown> = {}
  for (const [name, f] of Object.entries(real)) {
    out[name] = typeof f === 'function' && name.endsWith('Tex')
      ? (...args: unknown[]) => {
          const t = (f as (...a: unknown[]) => unknown)(...args) as { userData?: Record<string, unknown> } | null
          if (t && typeof t === 'object' && t.userData) t.userData.rbxTex = name
          return t
        }
      : f
  }
  return out
})
// Screen effects and the sky's reflections need a real renderer and draw no shapes.
vi.mock('./scene/PostFx', async (load) => ({ ...((await load()) as object), PostFx: () => null }))
vi.mock('./scene/SkyEnv', async (load) => ({ ...((await load()) as object), SkyEnv: () => null }))
// The Speedway's race and crowd (SpeedwayLife.tsx) move every frame, so the game draws them on each
// player's own screen (client/SpeedwayLife.luau) instead of baking one still frame into the model.
vi.mock('./scene/SpeedwayLife', async (load) => ({ ...((await load()) as object), SpeedwayLife: () => null }))
// The nightclub's dancers, bouncer and searchlights (ClubLife.tsx) too: client/ClubLife.luau.
vi.mock('./scene/ClubLife', async (load) => ({ ...((await load()) as object), ClubLife: () => null }))

// --- A canvas that remembers what was painted on it ---------------------------------------
// Signs and other painted textures are drawn on 2D canvases. jsdom has none, so this records
// the colours and text instead: a painted texture becomes a colour, or a colour with lettering.
type Paint = { fills: { color: string; area: number }[]; texts: { text: string; color: string }[]; w: number; h: number }
const paints = new WeakMap<HTMLCanvasElement, Paint>()
const noop = () => undefined
HTMLCanvasElement.prototype.getContext = function (this: HTMLCanvasElement) {
  const canvas = this
  if (painting) return rasterContext(canvas)
  const rec: Paint = paints.get(canvas) ?? { fills: [], texts: [], w: canvas.width, h: canvas.height }
  paints.set(canvas, rec)
  const state: Record<string | symbol, unknown> = { fillStyle: '#000000', strokeStyle: '#000000', canvas }
  return new Proxy(state, {
    get(t, k) {
      if (k in t) return t[k]
      if (k === 'fillRect') return (_x: number, _y: number, w: number, h: number) => {
        rec.w = canvas.width; rec.h = canvas.height
        if (typeof t.fillStyle === 'string') rec.fills.push({ color: t.fillStyle, area: Math.abs(w * h) })
      }
      if (k === 'fillText') return (text: string) => {
        if (typeof t.fillStyle === 'string') rec.texts.push({ text: String(text), color: t.fillStyle })
      }
      if (k === 'measureText') return (s: string) => ({ width: String(s).length * 10 })
      if (k === 'getImageData' || k === 'createImageData') return (_x: number, _y: number, w = 1, h = 1) => ({ data: new Uint8ClampedArray(w * h * 4), width: w, height: h })
      if (k === 'createLinearGradient' || k === 'createRadialGradient' || k === 'createPattern') return () => ({ addColorStop: noop })
      return noop
    },
    set(t, k, v) {
      t[k] = v
      return true
    },
  }) as unknown as CanvasRenderingContext2D
} as unknown as HTMLCanvasElement['getContext']

// --- A canvas that really paints, for the ground textures ---------------------------------
// The lawn and meadow are textured images in the web game (textures.ts grassTex, meadowTex), not
// flat colours. While `painting` is on, canvases get this small software painter instead (the
// shapes those textures use: rectangles, ellipses, arcs and short strokes), so the images can go to
// Roblox as they are. No antialiasing; at 256 pixels nobody sees it.
let painting = false
const pixels = new WeakMap<HTMLCanvasElement, { w: number; h: number; px: Float32Array }>()

function rgba(style: unknown): [number, number, number, number] {
  if (typeof style !== 'string') return [0, 0, 0, 1]
  const c = new Color().setStyle(style).getHexString()
  const a = /^(?:rgba|hsla)\(.*,\s*([\d.]+)\s*\)$/.exec(style.trim())
  return [parseInt(c.slice(0, 2), 16), parseInt(c.slice(2, 4), 16), parseInt(c.slice(4, 6), 16), a ? Number(a[1]) : 1]
}

function rasterContext(canvas: HTMLCanvasElement): CanvasRenderingContext2D {
  const w = canvas.width, h = canvas.height
  const img = { w, h, px: new Float32Array(w * h * 4) }
  pixels.set(canvas, img)
  let paths: [number, number][][] = []
  let cur: [number, number][] | null = null
  const ctx = {
    canvas, fillStyle: '#000000' as unknown, strokeStyle: '#000000' as unknown, globalAlpha: 1, lineWidth: 1,
    beginPath() { paths = []; cur = null },
    moveTo(x: number, y: number) { cur = [[x, y]]; paths.push(cur) },
    lineTo(x: number, y: number) { if (!cur) ctx.moveTo(x, y); else cur.push([x, y]) },
    closePath() { if (cur && cur.length) cur.push(cur[0]) },
    quadraticCurveTo(cx: number, cy: number, x: number, y: number) {
      if (!cur) ctx.moveTo(cx, cy)
      const [x0, y0] = cur![cur!.length - 1]
      for (let i = 1; i <= 8; i++) {
        const t = i / 8, u = 1 - t
        cur!.push([u * u * x0 + 2 * u * t * cx + t * t * x, u * u * y0 + 2 * u * t * cy + t * t * y])
      }
    },
    ellipse(cx: number, cy: number, rx: number, ry: number, rot: number, a0: number, a1: number) {
      if (!cur) { cur = []; paths.push(cur) }
      const n = Math.max(12, Math.ceil(Math.max(rx, ry) * Math.abs(a1 - a0) / 3))
      const cr = Math.cos(rot), sr = Math.sin(rot)
      for (let i = 0; i <= n; i++) {
        const a = a0 + ((a1 - a0) * i) / n, ex = Math.cos(a) * rx, ey = Math.sin(a) * ry
        cur.push([cx + ex * cr - ey * sr, cy + ex * sr + ey * cr])
      }
    },
    arc(cx: number, cy: number, r: number, a0: number, a1: number) { ctx.ellipse(cx, cy, r, r, 0, a0, a1) },
    rect(x: number, y: number, rw: number, rh: number) { ctx.moveTo(x, y); ctx.lineTo(x + rw, y); ctx.lineTo(x + rw, y + rh); ctx.lineTo(x, y + rh); ctx.closePath() },
    fillRect(x: number, y: number, rw: number, rh: number) {
      const x0 = Math.round(x), y0 = Math.round(y)
      const x1 = Math.max(x0 + 1, Math.round(x + rw)), y1 = Math.max(y0 + 1, Math.round(y + rh))
      const c = rgba(ctx.fillStyle)
      for (let py = Math.max(0, y0); py < Math.min(h, y1); py++) for (let px = Math.max(0, x0); px < Math.min(w, x1); px++) blend(px, py, c)
    },
    fill() {
      const c = rgba(ctx.fillStyle)
      const edges: [number, number, number, number][] = []
      for (const path of paths) for (let i = 0; i < path.length; i++) {
        const a = path[i], b = path[(i + 1) % path.length]
        if (a[1] !== b[1]) edges.push([a[0], a[1], b[0], b[1]])
      }
      for (let py = 0; py < h; py++) {
        const y = py + 0.5
        const hits: [number, number][] = []
        for (const [x0, y0, x1, y1] of edges) {
          if ((y0 <= y && y1 > y) || (y1 <= y && y0 > y)) hits.push([x0 + ((y - y0) / (y1 - y0)) * (x1 - x0), y1 > y0 ? 1 : -1])
        }
        if (!hits.length) continue
        hits.sort((p, q) => p[0] - q[0])
        let wind = 0
        for (let i = 0; i < hits.length - 1; i++) {
          wind += hits[i][1]
          if (wind === 0) continue
          for (let px = Math.max(0, Math.ceil(hits[i][0] - 0.5)); px < Math.min(w, Math.ceil(hits[i + 1][0] - 0.5)); px++) blend(px, py, c)
        }
      }
    },
    stroke() {
      const c = rgba(ctx.strokeStyle)
      const r = Math.max(0.5, ctx.lineWidth / 2)
      const hit = new Set<number>()
      for (const path of paths) for (let i = 0; i + 1 < path.length; i++) {
        const [ax, ay] = path[i], [bx, by] = path[i + 1]
        const dx = bx - ax, dy = by - ay, l2 = dx * dx + dy * dy || 1
        for (let py = Math.max(0, Math.floor(Math.min(ay, by) - r)); py <= Math.min(h - 1, Math.ceil(Math.max(ay, by) + r)); py++)
          for (let px = Math.max(0, Math.floor(Math.min(ax, bx) - r)); px <= Math.min(w - 1, Math.ceil(Math.max(ax, bx) + r)); px++) {
            const t = Math.max(0, Math.min(1, ((px + 0.5 - ax) * dx + (py + 0.5 - ay) * dy) / l2))
            if (Math.hypot(px + 0.5 - ax - t * dx, py + 0.5 - ay - t * dy) <= r) hit.add(py * w + px)
          }
      }
      for (const i of hit) blend(i % w, Math.floor(i / w), c)
    },
    save: noop, restore: noop, translate: noop, rotate: noop, scale: noop, setTransform: noop, clearRect: noop,
    fillText: noop, strokeText: noop, measureText: (t: string) => ({ width: String(t).length * 10 }),
  }
  function blend(px: number, py: number, [r, g, b, a]: number[]) {
    const k = (py * w + px) * 4, al = a * ctx.globalAlpha, da = img.px[k + 3]
    const oa = al + da * (1 - al)
    if (oa <= 0) return
    img.px[k] = (r * al + img.px[k] * da * (1 - al)) / oa
    img.px[k + 1] = (g * al + img.px[k + 1] * da * (1 - al)) / oa
    img.px[k + 2] = (b * al + img.px[k + 2] * da * (1 - al)) / oa
    img.px[k + 3] = oa
  }
  return ctx as unknown as CanvasRenderingContext2D
}

// An RGBA PNG of a painted canvas.
function png(canvas: HTMLCanvasElement): Buffer {
  const img = pixels.get(canvas)
  if (!img) throw new Error('that canvas was not painted')
  const { w, h, px } = img
  const raw = Buffer.alloc((w * 4 + 1) * h)
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
    const k = (y * w + x) * 4, o = y * (w * 4 + 1) + 1 + x * 4
    raw[o] = Math.round(px[k]); raw[o + 1] = Math.round(px[k + 1]); raw[o + 2] = Math.round(px[k + 2]); raw[o + 3] = Math.round(px[k + 3] * 255)
  }
  const crcTable = Array.from({ length: 256 }, (_, n) => { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; return c >>> 0 })
  const crc = (b: Buffer) => { let c = 0xffffffff; for (const v of b) c = crcTable[(c ^ v) & 255] ^ (c >>> 8); return (c ^ 0xffffffff) >>> 0 }
  const chunk = (type: string, data: Buffer) => {
    const len = Buffer.alloc(4); len.writeUInt32BE(data.length)
    const body = Buffer.concat([Buffer.from(type, 'ascii'), data])
    const sum = Buffer.alloc(4); sum.writeUInt32BE(crc(body))
    return Buffer.concat([len, body, sum])
  }
  const head = Buffer.alloc(13)
  head.writeUInt32BE(w, 0); head.writeUInt32BE(h, 4); head[8] = 8; head[9] = 6
  return Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk('IHDR', head), chunk('IDAT', deflateSync(raw)), chunk('IEND', Buffer.alloc(0))])
}

// --- Walking a scene ----------------------------------------------------------------------
const hex = (c: Color) => '#' + c.getHexString()
const r4 = (n: number) => Math.round(n * 1e4) / 1e4

type Look = {
  c: string // colour
  o: number // opacity, 1 = solid
  e?: string // glow colour
  met?: number
  rough?: number
  basic?: boolean // unlit
  text?: { text: string; fg: string; bg: string }
  tex?: string // the texture's maker in scene/textures.ts (brickTex, sidingTex...)
}

function cssColor(s: string): string | null {
  try {
    return hex(new Color().setStyle(s))
  } catch {
    return null
  }
}

function lookOf(m: Material, tint?: Color): Look | null {
  const sm = m as MeshStandardMaterial & { color?: Color; emissive?: Color; emissiveIntensity?: number; map?: { image?: unknown; userData?: Record<string, unknown> } | null }
  if (!m.visible || (m as { colorWrite?: boolean }).colorWrite === false) return null
  const o = m.transparent ? m.opacity : 1
  if (o < 0.02) return null
  const color = sm.color ? sm.color.clone() : new Color(1, 1, 1)
  // Live water (liveWater.ts) is white until its shader paints it: run the shader hook on a stand-in
  // to read its deep and shallow colours, and take the colour between them.
  if (m.userData?.live && m.onBeforeCompile) {
    const sh = { uniforms: {} as Record<string, { value: unknown }>, vertexShader: '', fragmentShader: '', defines: {} }
    try {
      m.onBeforeCompile(sh as never, null as never)
    } catch {
      // Only the uniforms matter here.
    }
    const deep = sh.uniforms.uDeep?.value as Color | undefined, shallow = sh.uniforms.uShallow?.value as Color | undefined
    if (deep && shallow) color.copy(deep).lerp(shallow, 0.5)
  }
  if (tint) color.multiply(tint)
  const look: Look = { c: hex(color), o: r4(o) }
  const img = sm.map?.image as HTMLCanvasElement | undefined
  const paint = img && paints.get(img)
  const raster = img && !paint && batching.off ? pixels.get(img) : undefined
  if (raster) {
    // An image painted for real (the ground textures): its average colour. Race venues only; the
    // countryside was always exported with the material's own colour, and its meshes are uploaded.
    const sum = [0, 0, 0]
    let n = 0
    for (let k = 0; k < raster.px.length; k += 4) {
      const a = raster.px[k + 3]
      for (let c = 0; c < 3; c++) sum[c] += raster.px[k + c] * a
      n += a
    }
    if (n > 0) look.c = hex(new Color(sum[0] / n / 255, sum[1] / n / 255, sum[2] / n / 255).convertSRGBToLinear().multiply(color))
  }
  if (paint) {
    // The largest fill is the board's colour; lettering keeps its own.
    const bg = paint.fills.reduce<{ color: string; area: number } | null>((a, f) => (!a || f.area > a.area ? f : a), null)
    const bgc = bg && cssColor(bg.color)
    if (bgc) look.c = hex(new Color(bgc).multiply(color))
    const label = paint.texts.map((t) => t.text).join(' ').trim()
    if (label) look.text = { text: label, fg: cssColor(paint.texts[0].color) ?? '#000000', bg: bgc ?? look.c }
  }
  if (sm.emissive && (sm.emissiveIntensity ?? 1) > 0 && sm.emissive.getHex() !== 0) {
    look.e = hex(sm.emissive.clone().multiplyScalar(Math.min(1, sm.emissiveIntensity ?? 1)))
  }
  const tex = sm.map?.userData?.rbxTex
  if (typeof tex === 'string') look.tex = tex
  if ('metalness' in sm) look.met = r4(sm.metalness)
  if ('roughness' in sm) look.rough = r4(sm.roughness)
  if ((m as { type: string }).type === 'MeshBasicMaterial') look.basic = true
  return look
}

const visible = (o: Object3D, root: Object3D) => {
  for (let c: Object3D | null = o; c && c !== root.parent; c = c.parent) if (!c.visible) return false
  return true
}

// One drawn piece: its geometry (by id), where it is, and how it looks.
type Piece = { g: number; group?: number; m: number[]; look: Look }

type Geo = { type: string; params: Record<string, unknown>; pos: number[]; idx: number[]; nrm?: number[]; col?: number[] }

function walk(root: Object3D, geos: Map<BufferGeometry, number>, geoList: Geo[]) {
  root.updateMatrixWorld(true)
  const inv = new Matrix4().copy(root.matrixWorld).invert()
  const out: Piece[] = []
  const geoId = (g: BufferGeometry) => {
    let id = geos.get(g)
    if (id !== undefined) return id
    const pos = g.getAttribute('position')
    if (!pos) return -1
    const p: number[] = []
    for (let i = 0; i < pos.count; i++) p.push(r4(pos.getX(i)), r4(pos.getY(i)), r4(pos.getZ(i)))
    const idx: number[] = g.index ? Array.from(g.index.array as ArrayLike<number>) : Array.from({ length: pos.count }, (_, i) => i)
    const n = g.getAttribute('normal')
    const nrm: number[] | undefined = n ? [] : undefined
    if (n && nrm) for (let i = 0; i < n.count; i++) nrm.push(r4(n.getX(i)), r4(n.getY(i)), r4(n.getZ(i)))
    const c = g.getAttribute('color')
    const col: number[] | undefined = c ? [] : undefined
    if (c && col) for (let i = 0; i < c.count; i++) col.push(r4(c.getX(i)), r4(c.getY(i)), r4(c.getZ(i)))
    id = geoList.length
    geoList.push({ type: g.type, params: { ...((g as { parameters?: Record<string, unknown> }).parameters ?? {}) }, pos: p, idx, nrm, col })
    // Material groups: which triangles each material slot draws.
    ;(geoList[id] as Geo & { groups?: { start: number; count: number; materialIndex: number }[] }).groups = g.groups.map((x) => ({ start: x.start, count: x.count, materialIndex: x.materialIndex ?? 0 }))
    geos.set(g, id)
    return id
  }
  root.traverse((o) => {
    const mesh = o as Mesh
    if (!mesh.isMesh || !visible(o, root)) return
    const g = geoId(mesh.geometry)
    if (g < 0) return
    const mats = Array.isArray(mesh.material) ? mesh.material : [mesh.material]
    const base = new Matrix4().multiplyMatrices(inv, mesh.matrixWorld)
    const emit = (m: Matrix4, tint?: Color) => {
      const groups = mesh.geometry.groups
      if (Array.isArray(mesh.material) && groups.length) {
        groups.forEach((gr, gi) => {
          const look = lookOf(mats[gr.materialIndex ?? 0], tint)
          if (look) out.push({ g, group: gi, m: m.elements.map(r4), look })
        })
      } else {
        const look = lookOf(mats[0], tint)
        if (look) out.push({ g, m: m.elements.map(r4), look })
      }
    }
    const inst = mesh as InstancedMesh
    if (inst.isInstancedMesh) {
      const im = new Matrix4()
      const tint = new Color()
      for (let i = 0; i < inst.count; i++) {
        inst.getMatrixAt(i, im)
        const s = new Vector3().setFromMatrixScale(im)
        if (s.x * s.y * s.z === 0) continue // a hidden slot
        if (inst.instanceColor) inst.getColorAt(i, tint)
        emit(new Matrix4().multiplyMatrices(base, im), inst.instanceColor ? tint.clone() : undefined)
      }
    } else emit(base)
  })
  return out
}

// --- Pattern tiles -------------------------------------------------------------------------
// Value noise that repeats every `p` cells, so a tile's edges meet.
const hash2 = (x: number, y: number, seed: number) => {
  const v = Math.sin(x * 127.1 + y * 311.7 + seed * 74.7) * 43758.5453
  return v - Math.floor(v)
}
function noise(x: number, y: number, p: number, seed: number) {
  const ix = Math.floor(x), iy = Math.floor(y)
  const fx = x - ix, fy = y - iy
  const sx = fx * fx * (3 - 2 * fx), sy = fy * fy * (3 - 2 * fy)
  const w = (i: number) => ((i % p) + p) % p
  const h = (i: number, j: number) => hash2(w(i), w(j), seed)
  const top = h(ix, iy) + (h(ix + 1, iy) - h(ix, iy)) * sx
  const bottom = h(ix, iy + 1) + (h(ix + 1, iy + 1) - h(ix, iy + 1)) * sx
  return top + (bottom - top) * sy
}
// The shader's three-octave noise, at f cells a unit over a tile `span` units wide.
const fbm = (u: number, v: number, f: number, span: number, seed: number) => {
  const p = Math.round(f * span)
  const k = p / span
  return noise(u * k, v * k, p, seed) * 0.55 + noise(u * k * 2, v * k * 2, p * 2, seed + 1) * 0.3 + noise(u * k * 4, v * k * 4, p * 4, seed + 2) * 0.15
}
const smooth = (a: number, b: number, x: number) => {
  const t = Math.min(1, Math.max(0, (x - a) / (b - a)))
  return t * t * (3 - 2 * t)
}
type Over = [number, number, number, number]
const CLEAR: Over = [0, 0, 0, 0]
const BLACK = (a: number): Over => [3, 3, 3, a]
const WHITE = (a: number): Over => [255, 255, 255, a]
// Camo's blobs: dark, darker, and light flecks between the dark ones.
const camo = (u: number, v: number, span: number, edge: number): Over => {
  const a = fbm(u, v, 6.5, span, 1), b = fbm(u, v, 6.5, span, 11), l = fbm(u, v, 8, span, 21)
  const darker = smooth(0.56 - edge, 0.56 + edge, b), dark = smooth(0.5 - edge, 0.5 + edge, a)
  if (darker > 0.5) return BLACK(0.74)
  if (dark > 0.5) return BLACK(0.45)
  return smooth(0.63 - edge, 0.63 + edge, l) > 0.5 ? WHITE(0.4) : CLEAR
}
// [pattern id, tile size (units), colour at (u, v)].
const PATTERN_TILES: [string, number, (u: number, v: number, span: number) => Over][] = [
  ['camo', 2, (u, v, s) => camo(u, v, s, 0.012)],
  ['digicamo', 2, (u, v, s) => {
    const c = s / 72
    return camo(Math.floor(u / c) * c, Math.floor(v / c) * c, s, 0)
  }],
  ['tiger', 2, (u, v, s) => {
    // Dark stripes across, wavering, thinning out to points.
    const w = u * ((2 * Math.PI * 13) / s) + v * ((2 * Math.PI * 4) / s) + fbm(u, v, 4, s, 31) * 6
    const t = Math.sin(w) * 0.5 + 0.5
    const k = 0.55 + 0.4 * hash2(Math.floor(w / (2 * Math.PI)), 0, 37)
    return BLACK(0.94 * smooth(k, k + 0.05, t))
  }],
  ['checker', 2, (u, v, s) => ((Math.floor(u / (s / 28)) + Math.floor(v / (s / 28))) % 2 ? BLACK(0.99) : CLEAR)],
  ['carbon', 2, (u, v, s) => {
    const c = s / 90
    const cx = Math.floor(u / c), cy = Math.floor(v / c)
    const along = (cx + cy) % 2 === 0
    const across = along ? v / c - cy : u / c - cx
    const sheen = 0.5 + 0.5 * Math.sin(across * Math.PI)
    return BLACK(1 - 0.35 * sheen * (along ? 0.75 : 0.45))
  }],
  ['hex', 0.075 * 1.732 * 15, (u, v) => {
    // A honeycomb of cells in two shades, with dark seams.
    const hx = u / 0.075, hy = v / 0.075
    const ry = 1.732
    const mod = (a: number, b: number) => a - b * Math.floor(a / b)
    const a = [mod(hx, 1) - 0.5, mod(hy, ry) - ry / 2]
    const b = [mod(hx - 0.5, 1) - 0.5, mod(hy - ry / 2, ry) - ry / 2]
    const g = a[0] * a[0] + a[1] * a[1] < b[0] * b[0] + b[1] * b[1] ? a : b
    const d = Math.max(Math.abs(g[0]) * 0.5 + Math.abs(g[1]) * 0.866, Math.abs(g[0]))
    if (smooth(0.44, 0.47, d) > 0.5) return BLACK(0.6)
    return hash2(Math.floor(hx - g[0] + 0.5), Math.floor(hy - g[1] + 0.5), 41) > 0.5 ? CLEAR : BLACK(0.22)
  }],
  ['splatter', 2, (u, v, s) => {
    if (fbm(u, v, 14, s, 51) > 0.7) return BLACK(0.88)
    if (noise((u * 140) / s, (v * 140) / s, 140, 61) > 0.93 && fbm(u, v, 6, s, 71) > 0.5) return WHITE(0.95)
    return fbm(u, v, 9, s, 81) > 0.65 ? WHITE(0.75) : CLEAR
  }],
  ['flames', 2, (u, v, s) => {
    // Tongues licking back along the tile, yellow at the root through orange to red tips, outlined.
    const w = ((v * 44) / s) * 2 + fbm(u, v, 5, s, 91) * 3
    const tongue = Math.pow(Math.sin(w) * 0.5 + 0.5, 1.6)
    const back = s - u
    const edge = (0.4 * (1 - tongue) + 0.04) * s * 0.5
    if (back < edge) return CLEAR
    if (back < edge + 0.02) return BLACK(1)
    const t = smooth(edge + 0.02, edge + 0.3 * s, back)
    return [255 * (0.85 + 0.15 * t), 255 * (0.06 + 0.79 * t), 255 * (0.02 + 0.08 * t), 1]
  }],
  ['signature', 2.5, (u, v, s) => {
    // A dark sash sweeping back, edged in gold.
    const side = (v * 1.4 - u * 0.55) * 1.6 * (2 / s)
    const f = Math.abs(side - Math.floor(side) - 0.5) - 0.28
    if (Math.abs(f) < 0.012) return [255, 200, 61, 1]
    return f > 0.02 ? CLEAR : BLACK(0.78)
  }],
  ['pinstripe', 2, (u, v) => (Math.abs((v / 0.05) % 1 - 0.5) * 0.05 < 0.0025 ? WHITE(0.65) : CLEAR)],
  ['polka', 0.06 * 33, (u, v) => {
    const dx = (u / 0.06) % 1 - 0.5, dy = (v / 0.06) % 1 - 0.5
    return Math.hypot(dx, dy) < 0.285 ? WHITE(0.75) : CLEAR
  }],
]

const OUT = process.env.RBX_MODELS_OUT ?? 'rbx-models.json'

it('exports every building and car', async () => {
  const geos = new Map<BufferGeometry, number>()
  const geoList: Geo[] = []
  const models: { id: string; kind: string; level?: number; pieces: Piece[]; paint?: number[] }[] = []
  // The far land's wind turbines, for the rotors client/Horizon spins: [x, y, z, yaw, tint].
  const turbines: number[][] = []
  const { BuildingModel } = await import('./scene/BuildingModel')
  const { CarModel } = await import('./scene/CarModel')
  const render = async (el: React.ReactElement) => {
    const r = await ReactThreeTestRenderer.create(el)
    const pieces = walk(r.scene.instance as Object3D, geos, geoList)
    await r.unmount()
    return pieces
  }
  // The ground textures, painted first (textures.ts keeps each image once it's made): the lawn on
  // the town's own land, one image per four tiles, and the meadow past it, one per 16 units.
  const { grassTex, meadowTex } = await import('./scene/textures')
  const { TILE } = await import('./game/data')
  const textures: { key: string; name: string; file: string; span: number }[] = []
  painting = true
  for (const [key, make, span] of [['grass', grassTex, 4 * TILE], ['meadow', meadowTex, 16]] as const) {
    const data = png(make().image as HTMLCanvasElement)
    const name = `${key}-${createHash('sha1').update(data).digest('hex').slice(0, 16)}`
    const file = join(dirname(OUT), 'textures', `${name}.png`)
    mkdirSync(dirname(file), { recursive: true })
    writeFileSync(file, data)
    textures.push({ key, name, file: `${name}.png`, span })
  }
  painting = false
  // Custom paint patterns (panelPaint.ts's panPattern), as tiles laid over a panel in its own
  // colour: each pixel is the black, white or fire colour the shader mixes into the panel's colour,
  // and how much. Worked out flat, on one face, from the shader's own sums.
  for (const [id, span, at] of PATTERN_TILES) {
    const N = 256
    const px = new Float32Array(N * N * 4)
    for (let y = 0; y < N; y++) for (let x = 0; x < N; x++) {
      const [r, g, b, a] = at(((x + 0.5) / N) * span, ((y + 0.5) / N) * span, span)
      const k = (y * N + x) * 4
      px[k] = r; px[k + 1] = g; px[k + 2] = b; px[k + 3] = a
    }
    const cv = document.createElement('canvas')
    pixels.set(cv, { w: N, h: N, px })
    const data = png(cv)
    const name = `pattern-${id}-${createHash('sha1').update(data).digest('hex').slice(0, 16)}`
    const file = join(dirname(OUT), 'textures', `${name}.png`)
    mkdirSync(dirname(file), { recursive: true })
    writeFileSync(file, data)
    textures.push({ key: `pattern_${id}`, name, file: `${name}.png`, span })
  }
  if (process.env.RBX_ONLY === 'textures') return void writeFileSync(OUT, JSON.stringify({ textures }))
  const LEVELS = (process.env.RBX_LEVELS ?? '1').split(',').map(Number)
  // RBX_ONLY=outskirts skips the buildings, cars and street pieces (a quicker run while working on
  // the countryside).
  const only = process.env.RBX_ONLY
  // The Speedway grows with its level (taller glass, a canopy from 4, the upper deck from 7 that
  // the fans in client/SpeedwayLife.luau stand on), so it's drawn at every level.
  const levelsOf = (id: string) => (id === 'stadium' ? [...new Set([...LEVELS, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10])].sort((a, b) => a - b) : LEVELS)
  if (!only) for (const d of BUILDINGS) {
    for (const level of levelsOf(d.id)) models.push({ id: d.id, kind: 'building', level, lot: [d.w * TILE, d.h * TILE], pieces: await render(<BuildingModel def={d} level={level} />) })
  }
  // Mods (CarMods.tsx, the Rims and Stance looks): each car drawn with one part fitted at a time
  // and compared with the stock car. The pieces the part adds are its model ("mod:<car>:<part>"),
  // and the stock pieces it takes away (a roof rack where the roof gear was) are listed by index.
  // A stance moves the whole body, so it's kept as numbers instead: how far the body rises.
  const { MODS, modFits } = await import('./game/data')
  // Drawn with geometry lists of their own, so only the pieces a mod adds reach the export.
  type Drawn = { pieces: Piece[]; list: Geo[] }
  const renderApart = async (el: React.ReactElement): Promise<Drawn> => {
    const list: Geo[] = []
    const r = await ReactThreeTestRenderer.create(el)
    const pieces = walk(r.scene.instance as Object3D, new Map(), list)
    await r.unmount()
    return { pieces, list }
  }
  const geoHash = (G: Geo) => createHash('sha1').update(JSON.stringify([G.type, G.params, G.pos, G.idx, G.col ?? null])).digest('hex').slice(0, 16)
  const sigs = new WeakMap<Geo, string>()
  const sigOf = (p: Piece, list: Geo[]) => {
    const G = list[p.g]
    let h = sigs.get(G)
    if (!h) sigs.set(G, (h = geoHash(G)))
    return `${h}/${p.group ?? ''}/${p.m.join(',')}/${JSON.stringify(p.look)}`
  }
  // A piece drawn apart, with its geometry moved into the export's own list (once per shape).
  const byHash = new Map<string, number>()
  const adopt = (p: Piece, list: Geo[]): Piece => {
    const G = list[p.g]
    const h = sigs.get(G) ?? geoHash(G)
    let g = byHash.get(h)
    if (g === undefined) byHash.set(h, (g = geoList.push(G) - 1))
    return { ...p, g }
  }
  // The stock pieces missing from `next`, and the indices of `next`'s pieces stock doesn't have.
  const diff = (stock: Piece[], next: Drawn) => {
    const left = new Map<string, number[]>()
    stock.forEach((p, i) => {
      const k = sigOf(p, geoList)
      left.set(k, [...(left.get(k) ?? []), i])
    })
    const added: number[] = []
    next.pieces.forEach((p, i) => {
      const hit = left.get(sigOf(p, next.list))
      if (hit?.length) hit.shift()
      else added.push(i)
    })
    return { dropped: [...left.values()].flat().sort((a, b) => a - b), added }
  }
  const modDrops: Record<string, Record<string, number[]>> = {}
  const wheelsOf: Record<string, number[]> = {}
  const rimsOf: Record<string, number[]> = {}
  // Custom panel paint (panelPaint.ts): the hood, the doors and the roof can each have their own
  // colour and pattern. The web's shader picks the panel per pixel from where it is on the body;
  // here the body's paint is cut into those panels the same way, triangle by triangle, as models
  // of their own ("panel:<car>:<hood|doors|roof|body>"), which take the place of its paint.
  const { freshGeo } = await import('./scene/CarModel')
  const { isBike } = await import('./game/data')
  const panelDrops: Record<string, number[]> = {}
  // Each car's trim pieces (game/trim.ts): drawn with a tint, headlights and handles in colours
  // nothing else on a car uses, the pieces that change are its glass, lamps and handles.
  const trimOf: Record<string, Record<string, number[]>> = {}
  const TRIM_MARK: Record<string, string> = { tint: '#0c0e10', lights: '#d3a6ff', handles: '#161616' }
  const panelOf = (p: number[], n: number[], z: number[]) => {
    if (p[1] > z[1] + 0.015 && p[2] < z[0] + 0.02) return 'roof'
    if (n[1] > 0.35 && p[2] > z[0]) return 'hood'
    if (Math.abs(n[0]) > 0.55 && p[2] < z[2] && p[2] > z[3] && p[1] < z[1]) return 'doors'
    return 'body'
  }
  const cutPanels = (car: string, body: string, pieces: Piece[], paint: number[]) => {
    const zones = isBike(body as never) ? undefined : freshGeo(body as never, {}, car).zones
    if (!zones || !paint.length) return
    const out: Record<string, Piece[]> = {}
    for (const i of paint) {
      const piece = pieces[i]
      const G = geoList[piece.g]
      const M = new Matrix4().fromArray(piece.m)
      const tri = (G as Geo & { groups?: { start: number; count: number }[] }).groups?.[piece.group ?? -1]
      const idx = tri ? G.idx.slice(tri.start, tri.start + tri.count) : G.idx
      const cut: Record<string, { pos: number[]; nrm: number[] }> = {}
      for (let t = 0; t + 2 < idx.length; t += 3) {
        const vs = [0, 1, 2].map((k) => G.pos.slice(idx[t + k] * 3, idx[t + k] * 3 + 3))
        const mid = [0, 1, 2].map((a) => (vs[0][a] + vs[1][a] + vs[2][a]) / 3)
        const e1 = new Vector3(...vs[1]).sub(new Vector3(...vs[0])), e2 = new Vector3(...vs[2]).sub(new Vector3(...vs[0]))
        const face = e1.cross(e2).normalize()
        const n = G.nrm ? [0, 1, 2].map((a) => G.nrm![idx[t] * 3 + a] + G.nrm![idx[t + 1] * 3 + a] + G.nrm![idx[t + 2] * 3 + a]) : [face.x, face.y, face.z]
        const len = Math.hypot(n[0], n[1], n[2]) || 1
        const panel = panelOf(mid, n.map((x) => x / len), zones)
        const into = (cut[panel] ??= { pos: [], nrm: [] })
        for (let k = 0; k < 3; k++) {
          const v = new Vector3(...vs[k]).applyMatrix4(M)
          into.pos.push(r4(v.x), r4(v.y), r4(v.z))
          if (G.nrm) {
            const w = new Vector3(...G.nrm.slice(idx[t + k] * 3, idx[t + k] * 3 + 3)).transformDirection(M)
            into.nrm.push(r4(w.x), r4(w.y), r4(w.z))
          }
        }
      }
      for (const [panel, { pos, nrm }] of Object.entries(cut)) {
        const g = geoList.push({ type: 'BufferGeometry', params: {}, pos, idx: pos.map((_, k) => k).slice(0, pos.length / 3), nrm: G.nrm ? nrm : undefined }) - 1
        ;(out[panel] ??= []).push({ g, m: new Matrix4().elements.map(r4), look: piece.look })
      }
    }
    // Only cars whose panels are really apart (some have no hood or doors of their own).
    if (Object.keys(out).length < 2) return
    for (const [panel, list] of Object.entries(out)) models.push({ id: `panel:${car}:${panel}`, kind: 'piece', pieces: list, paint: list.map((_, k) => k) })
    panelDrops[car] = paint
  }
  const stanceOf: Record<string, Record<string, number>> = {}
  // Each car twice in two paints: the pieces that change colour are its paint.
  if (!only) for (const c of CARS) {
    const a = await render(<CarModel body={c.body} model={c.id} color="#ff00ff" />)
    const b = await render(<CarModel body={c.body} model={c.id} color="#00ff00" />)
    const paint = a.flatMap((p, i) => (b[i] && b[i].look.c !== p.look.c ? [i] : []))
    const pieces = await render(<CarModel body={c.body} model={c.id} color={c.colors[0]} />)
    models.push({ id: c.id, kind: 'car', pieces, paint })
    // Its racing stripes (drawn only when painted on), in a colour nothing else on a car uses: the
    // game lays them over the car and paints them the stripe colour.
    const striped = await render(<CarModel body={c.body} model={c.id} color={c.colors[0]} stripe="#0000fe" />)
    const stripes = striped.filter((p) => p.look.c === '#0000fe')
    if (stripes.length) models.push({ id: `stripe:${c.id}`, kind: 'piece', pieces: stripes })
    cutPanels(c.id, c.body, pieces, paint)
    const trimmed = (await renderApart(<CarModel body={c.body} model={c.id} color="#ff00ff" trim={{ tint: 'limo', lights: 'violet', handles: 'black' }} />)).pieces
    for (const [kind, mark] of Object.entries(TRIM_MARK)) {
      const list = a.flatMap((p, i) => (trimmed[i] && trimmed[i].look.c !== p.look.c && trimmed[i].look.c === mark ? [i] : []))
      if (list.length) (trimOf[c.id] ??= {})[kind] = list
    }
    if (process.env.RBX_MODS === '0') continue
    for (const m of MODS) {
      if (!modFits(m, c.body) || m.slot === 'tires') continue
      const ma = await renderApart(<CarModel body={c.body} model={c.id} color="#ff00ff" mods={[m.id]} />)
      const { dropped, added } = diff(a, ma)
      if (m.slot === 'stance') {
        // The body's paint, moved up or down: how far it rose.
        const at = ma.pieces.find((p) => p.look.c === '#ff00ff')
        const was = a.find((p) => p.look.c === '#ff00ff')
        if (at && was) (stanceOf[c.id] ??= {})[m.id] = r4(at.m[13] - was.m[13])
        continue
      }
      if (!added.length && !dropped.length) continue
      const mc = await renderApart(<CarModel body={c.body} model={c.id} color={c.colors[0]} mods={[m.id]} />)
      models.push({ id: `mod:${c.id}:${m.id}`, kind: 'piece', pieces: added.map((i) => adopt(mc.pieces[i], mc.list)), paint: added.flatMap((i, k) => (ma.pieces[i].look.c === '#ff00ff' ? [k] : [])) })
      if (dropped.length) (modDrops[c.id] ??= {})[m.id] = dropped
      // The stock rims are what a set of rims replaces; with the tyres round them they're the
      // wheels (each piece centred on a rim's hub), which a stance resizes.
      if (m.slot === 'rims' && !rimsOf[c.id]) {
        rimsOf[c.id] = dropped
        const hubs = dropped.map((i) => a[i].m.slice(12, 15))
        wheelsOf[c.id] = a.flatMap((p, i) => (hubs.some((h) => Math.abs(p.m[13] - h[1]) < 1e-3 && Math.abs(p.m[14] - h[2]) < 1e-3 && Math.abs(p.m[12] - h[0]) < 0.2) ? [i] : []))
      }
    }
  }
  // Hats (CarHat.tsx), each standing on its own origin, once in every colour it comes in (named as
  // CarHat caches them: "hat:<id>|<colours>"). The shapes are the same in each colour, so only the
  // looks add up.
  const { HATS, hatChoices, hatPaint } = await import('./game/hats')
  const { HatModel } = await import('./scene/CarHat')
  const hatSpotOf: Record<string, number[]> = {}
  if (!only) {
    for (const h of HATS) {
      const choices = hatChoices(h)
      const fits: { id: string; colors?: string[] }[] = [{ id: h.id }]
      if (choices) for (const a of choices) {
        fits.push({ id: h.id, colors: [a] })
        if (h.colors === 'twoTone') for (const b of choices) if (b !== a) fits.push({ id: h.id, colors: [a, b] })
      }
      const done = new Set<string>()
      for (const fit of fits) {
        const id = `hat:${h.id}|${hatPaint(fit).join(',')}`
        if (done.has(id)) continue
        done.add(id)
        models.push({ id, kind: 'piece', pieces: await render(<HatModel hat={fit} />) })
      }
    }
    // Where each car wears a hat (CarModel's hatSpot): drawn wearing the Hard Hat, the hat's own
    // pieces (the same shapes as the Hard Hat drawn alone) give its place, tilt and size.
    const alone = await render(<HatModel hat={{ id: 'hardhat' }} />)
    const hatGeos = new Set(alone.map((p) => p.g))
    for (const c of CARS) {
      const worn = await render(<CarModel body={c.body} model={c.id} color={c.colors[0]} hat={{ id: 'hardhat' }} />)
      const p = worn.find((x) => hatGeos.has(x.g))
      if (p) hatSpotOf[c.id] = p.m
    }
  }
  // Street pieces the town is assembled from (TownView draws each road tile from these, the way
  // World.tsx's RoadTile does): sidewalks for every side and pair of ends, the rounded corners,
  // manholes, and sidewalk furniture standing at its spot's origin, facing south.
  const piece = async (id: string, el: React.ReactElement) => models.push({ id, kind: 'piece', pieces: await render(<group>{el}</group>) })
  const { Sidewalk, CornerCurb, CornerFillet, StreetProp, Hydrant, StreetLamp } = await import('./scene/Roadside')
  const { Manhole } = await import('./scene/BuildingDetail')
  const { PROPS } = await import('./game/streetFurniture')
  const ENDS = ['corner', 'ramp', 'open'] as const
  for (const side of ['e', 'w', 's', 'n'] as const) {
    for (const a of ENDS) for (const b of ENDS) await piece(`walk:${side}:${a}:${b}`, <Sidewalk side={side} ends={[a, b]} />)
    await piece(`walk:${side}:open:open:drain`, <Sidewalk side={side} ends={['open', 'open']} drain />)
  }
  for (let turn = 0; turn < 4; turn++) {
    await piece(`curb:${turn}`, <CornerCurb turn={turn} />)
    await piece(`fillet:${turn}`, <CornerFillet turn={turn} />)
  }
  await piece('manhole', <Manhole x={0} z={0} />)
  for (const kind of PROPS) await piece(`prop:${kind}`, <StreetProp kind={kind} side="s" x={0} z={0} />)
  await piece('prop:hydrant', <Hydrant side="s" x={0} z={0} />)
  await piece('prop:lamp', <StreetLamp side="s" x={0} z={0} />)
  // The landmarks merged level 10 houses become (merge.ts isLandmark, isGlobe): the Vanguard Tower
  // fills a 2x2 lot, the Globe Tower a 2x4 (long side along x). TownView draws them in place of
  // the scaled-up house.
  const { VanguardTower } = await import('./scene/Landmark')
  const { GlobeTower } = await import('./scene/GlobeTower')
  await piece('landmark:vanguard', <VanguardTower />)
  await piece('landmark:globe', <GlobeTower />)
  // Lawn detail (Tufts.tsx): one of each shape, in each of the season's tints it comes in.
  const { Scatter } = await import('./scene/Outskirts')
  const { PAL, SEASON } = await import('./scene/season')
  const { shade } = await import('./scene/flora')
  const greens = SEASON === 'winter' ? ['#c9b98f', '#bfae84', '#d6c79d'] : [shade(PAL.grass, -0.1), shade(PAL.grass, 0.06), PAL.grassSpeckle[2], PAL.grassSpeckle[3], shade(PAL.grass, -0.16)]
  for (const [i, tint] of greens.entries()) await piece(`tuft:${i + 1}`, <Scatter sets={{ tuft: [{ x: 0, z: 0, tint }] }} />)
  for (const [i, tint] of ['#ffffff', '#e8e8e8', '#d6d6d6'].entries()) await piece(`rock:${i + 1}`, <Scatter sets={{ rock: [{ x: 0, z: 0, tint, sy: 0.7 }] }} />)
  for (const k of ['heap', 'mushroom', 'flower'] as const) await piece(k, <Scatter sets={{ [k]: [{ x: 0, z: 0 }] }} />)
  // The countryside past the town (Outskirts.tsx): the forest ring with its farm and lake, which
  // never changes, and the wild meadow on each plot, for whichever plots the player hasn't bought.
  // Outskirts draws <Wilds> (loose instanced meshes), then <TownLine> and <Forest> (a group each);
  // TownView draws the fence itself. Each plot's wilds are drawn with every other plot bought, so
  // its trees keep back from the town line on every side.
  const { Outskirts } = await import('./scene/Outskirts')
  const { PLOT_MIN, PLOT_MAX } = await import('./game/data')
  const plots: string[] = []
  for (let x = PLOT_MIN; x <= PLOT_MAX; x++) for (let z = PLOT_MIN; z <= PLOT_MAX; z++) plots.push(`${x},${z}`)
  // The lake's fisherman, his rowboat and the gulls (LakeLife.tsx) are only put in place by their
  // useFrame, so the forest is drawn a few frames in; until then they sat at the town's middle.
  const { useThree: useOutskirtsThree } = await import('@react-three/fiber')
  const outskirtsState: { now?: { internal: { subscribers: { ref: { current: (s: unknown, dt: number) => void } }[] } } } = {}
  const GrabOutskirts = () => {
    outskirtsState.now = useOutskirtsThree() as never
    return null
  }
  const outskirts = async (id: string, land: string[], forest: boolean) => {
    const r = await ReactThreeTestRenderer.create(
      <>
        <Outskirts land={land} exits="" small={false} />
        <GrabOutskirts />
      </>,
    )
    if (forest) for (let i = 0; i < 30; i++) for (const sub of outskirtsState.now!.internal.subscribers) sub.ref.current(outskirtsState.now, 1 / 60)
    const top = (r.scene.instance as Object3D).children[0]
    const groups = top.children.filter((c) => (c as { isGroup?: boolean }).isGroup)
    if (forest) models.push({ id, kind: 'scenery', pieces: walk(groups[groups.length - 1], geos, geoList) })
    else {
      // Everything but the groups (and the fireflies, which aren't meshes) is the wilds.
      const kept = top.children.slice()
      top.children = kept.filter((c) => !groups.includes(c))
      models.push({ id, kind: 'scenery', pieces: walk(top, geos, geoList) })
      top.children = kept
    }
    await r.unmount()
  }
  if (!only || only === 'outskirts') {
    await outskirts('outskirts:forest', plots, true)
    for (const key of plots) await outskirts(`wilds:${key}`, plots.filter((k) => k !== key), false)
  }
  // The world past the countryside (Horizon.tsx, the web's free view): land rolling out to the
  // horizon with its mountains and wind farm, the lake, farms and railway, the highway and the far
  // city, and balloons. One still frame of it at noon in fair weather; the sky is baked into
  // skybox pictures separately (tools/sky/build.mjs).
  if (!only || only === 'outskirts' || only === 'horizon') await horizon()
  // What flies over the town now and then (SkyExtras.tsx FlyBys, models in FlyByModels.tsx and
  // Balloon.tsx), each at the size the town sees it: an airliner in each livery, the news
  // helicopter, the banner plane with each banner, the blimp, the town's balloon in each of its
  // colourings and the cartoon rocket. client/SkyExtras flies them. Contrails (a shader) stay behind.
  if (!only || only === 'flyby') await flyBys()
  async function flyBys() {
    const { Airliner, BannerPlane, Blimp, NewsHeli, LIVERIES, BANNERS, airlinerGeo, rocketGeo, flyMat } = await import('./scene/FlyByModels')
    const { BalloonModel } = await import('./scene/Balloon')
    const { signTexture } = await import('./scene/signTexture')
    const one = async (id: string, el: React.ReactElement, prep?: (root: Object3D) => void) => {
      const r = await ReactThreeTestRenderer.create(el)
      const root = r.scene.instance as Object3D
      root.traverse((o) => {
        if ((o as Mesh).isMesh && ((o as Mesh).material as { isShaderMaterial?: boolean }).isShaderMaterial) o.visible = false
      })
      prep?.(root)
      models.push({ id, kind: 'piece', pieces: walk(root, geos, geoList) })
      await r.unmount()
    }
    for (let i = 0; i < LIVERIES.length; i++)
      await one(`fly:plane:${i + 1}`, <group scale={0.9}><Airliner livery={{ current: i }} /></group>, (root) =>
        root.traverse((o) => {
          if ((o as Mesh).isMesh && (o as Mesh).geometry === airlinerGeo(0)) (o as Mesh).geometry = airlinerGeo(i)
        }))
    await one('fly:heli', <group scale={1.2}><NewsHeli /></group>)
    for (let i = 0; i < BANNERS.length; i++) await one(`fly:banner:${i + 1}`, <group scale={1.3}><BannerPlane message={{ current: i }} /></group>, (root) => {
      // The banner's lettering is set on its first frame: set it now.
      root.traverse((o) => {
        const m = (o as Mesh).material as MeshStandardMaterial | undefined
        if (m && !Array.isArray(m) && m.map && m.type === 'MeshStandardMaterial' && m !== flyMat) m.map = signTexture(BANNERS[i], '#ffffff', '#d32f2f', 5.2)
      })
    })
    await one('fly:blimp', <group scale={1.4}><Blimp /></group>)
    const COLOURS = [['#e53935', '#fdd835'], ['#1e88e5', '#ffffff'], ['#43a047', '#ff7043'], ['#8e24aa', '#ffca28']]
    for (let i = 0; i < COLOURS.length; i++) await one(`fly:balloon:${i + 1}`, <group scale={0.27}><BalloonModel c={COLOURS[i]} /></group>)
    await one('fly:rocket', (
      <group>
        <mesh geometry={rocketGeo} material={flyMat} />
        <group position={[0, -0.78, 0]}>
          <mesh position={[0, -0.3, 0]} rotation-x={Math.PI}><coneGeometry args={[0.22, 0.6, 10]} /><meshBasicMaterial color="#ff9800" toneMapped={false} /></mesh>
          <mesh position={[0, -0.2, 0]} rotation-x={Math.PI}><coneGeometry args={[0.12, 0.4, 10]} /><meshBasicMaterial color="#fff59d" toneMapped={false} /></mesh>
        </group>
      </group>
    ))
  }
  async function horizon() {
    const { Horizon } = await import('./scene/Horizon')
    const { useThree } = await import('@react-three/fiber')
    const { DAY_MS } = await import('./game/clock')
    const { weatherNow } = await import('./game/weather')
    const st: { state?: { internal: { subscribers: { ref: { current: (s: unknown, dt: number) => void } }[] } } } = {}
    const Grab = () => {
      st.state = useThree() as never
      return null
    }
    // Noon on the first fair day from a fixed date, so lamps stay off and the balloons fly.
    let noon = Math.ceil(Date.UTC(2026, 0, 1) / DAY_MS) * DAY_MS
    for (let i = 0; i < 500 && weatherNow(noon).kind !== 'clear'; i++) noon += DAY_MS
    const realNow = Date.now
    Date.now = () => noon
    try {
      const r = await ReactThreeTestRenderer.create(
        <>
          <Grab />
          <Horizon />
        </>,
        { width: 1280, height: 800 },
      )
      for (let i = 0; i < 3; i++) for (const sub of st.state!.internal.subscribers) sub.ref.current(st.state, 1 / 60)
      const root = r.scene.instance as Object3D
      const dimmed: [MeshStandardMaterial, number][] = []
      root.traverse((o) => {
        const m = (o as Mesh).material as (MeshBasicMaterial & MeshStandardMaterial) | undefined
        if (!m || Array.isArray(m)) return
        // Unlit pieces: lamps and blinking aircraft lights, shown only after dark or now and then,
        // and the flocks of birds, which would hang still in the air.
        if (m.isMeshBasicMaterial) o.visible = false
        // The city's lit windows are for the night (a faint glow by day would read as Neon).
        // Materials can be shared with what's exported after, so each is put back below.
        if (m.isMeshStandardMaterial && m.emissiveIntensity) {
          dimmed.push([m, m.emissiveIntensity])
          m.emissiveIntensity = 0
        }
      })
      // The wind farm's rotors and the hot-air balloons move, so they stay out of the still land:
      // client/Horizon builds and moves them itself, the rotors round the hubs kept here (the
      // middle of each rotor, its heading, and its tint, which the web starts its spin from).
      root.traverse((o) => {
        const im = o as InstancedMesh
        if (!im.isInstancedMesh || im.frustumCulled) return
        const g = im.geometry as BufferGeometry & { parameters?: Record<string, number> }
        const prm = g.parameters ?? {}
        const color = (im.material as MeshStandardMaterial).color?.getHexString()
        const rotor = g.type === 'BufferGeometry' && color === 'f2f4f5'
        const balloon =
          (g.type === 'SphereGeometry' && prm.radius === 1) ||
          (g.type === 'CylinderGeometry' && prm.radiusTop === 9.15) ||
          (g.type === 'BoxGeometry' && prm.width === 3.2 && prm.height === 2.6)
        if (!rotor && !balloon) return
        im.visible = false
        if (!rotor) return
        const m = new Matrix4(), at = new Vector3(), q = new Quaternion(), s = new Vector3()
        for (let i = 0; i < im.count; i++) {
          im.getMatrixAt(i, m)
          m.decompose(at, q, s)
          const e = new Euler().setFromQuaternion(q, 'YXZ')
          const spin = ((e.z % (2 * Math.PI)) + 2 * Math.PI) % (2 * Math.PI)
          turbines.push([r4(at.x), r4(at.y), r4(at.z), r4(e.y), r4(spin / (2 * Math.PI))])
        }
      })
      if (!turbines.length) throw new Error('horizon: no wind turbine rotors found')
      // The sky dome (a shader sphere): Roblox shows the baked skybox instead.
      const pieces = walk(root, geos, geoList).filter((p) => {
        const g = geoList[p.g]
        return !(g.type === 'SphereGeometry' && (g.params.radius as number) >= 1000)
      })
      for (const [m, v] of dimmed) m.emissiveIntensity = v
      models.push({ id: 'horizon:land', kind: 'scenery', pieces })
      console.log(`horizon:land: ${pieces.length} pieces`)
      await r.unmount()
    } finally {
      Date.now = realNow
    }
  }
  // The drag strip at each venue (RaceScene.tsx), everything but the cars: the road and its
  // markings, the sidewalks or shoulders, lamps, banners, barriers, bunting, the crowd, and the
  // venue's own scenery out to the horizon (RaceVenues.tsx, or Skyline.tsx on Main Street). The
  // shops along Main Street aren't in it: the race screen lines the street with them itself.
  // Far-off pieces ride along with the camera in the web game (too distant to show parallax):
  // the scene is drawn twice with the camera in two places, and whatever moved with it becomes
  // "race:<venue>:far", drawn round the camera; the rest is "race:<venue>".
  if (!only || only === 'race') await races()
  async function races() {
    const { RaceScene } = await import('./scene/RaceScene')
    const { VENUES } = await import('./scene/venues')
    const { TRACK } = await import('./game/race')
    const { useThree } = await import('@react-three/fiber')
    const car = CARS[0]
    const cam: { now?: Object3D; state?: { internal: { subscribers: { ref: { current: (s: unknown, dt: number) => void } }[] } } } = {}
    const Grab = () => {
      cam.now = useThree((s) => s.camera)
      cam.state = useThree() as never
      return null
    }
    // A frame as the game draws one: every useFrame callback once, in order (the test renderer's
    // advanceFrames runs each callback many times before the next, and drops their errors).
    const frame = (n: number) => {
      for (let i = 0; i < n; i++) for (const sub of cam.state!.internal.subscribers) sub.ref.current(cam.state, 1 / 60)
    }
    const { raceWeather } = await import('./game/weather')
    const { DIST } = await import('./game/distance')
    const { PAINT_RIVALS } = await import('./game/paintRivals')
    // Every venue over a quarter mile; the longer strips (a half mile, a mile: the street, scenery
    // and finish line run on further) for the venues that race over them, as "race:<venue>:<dist>".
    // Their horizon is the quarter mile's.
    const strips: { v: (typeof VENUES)[number]; dist: keyof typeof DIST }[] = VENUES.map((v) => ({ v, dist: 'quarter' as const }))
    for (const d of ['half', 'mile'] as const) {
      for (const v of VENUES) if (PAINT_RIVALS.some((r) => r.venue === v.id && r.dist === d)) strips.push({ v, dist: d })
    }
    batching.off = true
    for (const { v, dist } of strips) {
      const track = DIST[dist].m
      const id = dist === 'quarter' ? `race:${v.id}` : `race:${v.id}:${dist}`
      const me = { current: { dist: 0 } }, them = { current: { dist: 0 } }
      const r = await ReactThreeTestRenderer.create(
        <>
          <Grab />
          <RaceScene track={track} me={me} them={them} mine={{ body: car.body, model: car.id, color: '#ff0000' }} theirs={{ body: car.body, model: car.id, color: '#00ff00' }} venue={v} weather={raceWeather(v.id, 'export', 'clear')} night={false} />
        </>,
        { width: 1280, height: 800 },
      )
      frame(300)
      const root = r.scene.instance as Object3D
      // The racers (each a group drawn 1.4x) stay out, and so does the countdown bar under the START
      // banner (StartLights, at 0, 2.5, -0.85), which the race screen lights itself.
      const racers = new Set<Object3D>()
      root.traverse((o) => {
        if (!(o as { isGroup?: boolean }).isGroup) return
        if (Math.abs(o.scale.x - 1.4) < 1e-6 || o.position.distanceTo(new Vector3(0, 2.5, -0.85)) < 1e-6) racers.add(o)
      })
      for (const o of racers) o.visible = false
      const z0 = cam.now!.position.z
      const first = walk(root, geos, geoList)
      // Down the road a way, and drawn again.
      me.current.dist = them.current.dist = TRACK * 0.6
      for (const o of racers) o.visible = true
      frame(300)
      for (const o of racers) o.visible = false
      const dz = cam.now!.position.z - z0
      const second = walk(root, geos, geoList)
      if (first.length !== second.length) throw new Error(`${id}: ${first.length} pieces, then ${second.length}`)
      if (Math.abs(dz) < 1) throw new Error(`${id}: the camera didn't move`)
      const near: Piece[] = [], far: Piece[] = []
      first.forEach((p, i) => {
        const q = second[i]
        // The sky dome: Roblox draws its own sky.
        const g = geoList[p.g]
        if (p.look.basic && g.type === 'SphereGeometry' && (g.params.radius as number) > 50) return
        // Pools of lamplight on the ground (LightPool): see-through glows that brighten at night.
        if (p.look.o < 1 && (g.type === 'PlaneGeometry' || g.type === 'CircleGeometry')) return
        const moved = q.m[14] - p.m[14]
        const rides = q.g === p.g && Math.abs(moved - dz) < 0.05 && [12, 13].every((k) => Math.abs(q.m[k] - p.m[k]) < 1e-3)
        if (rides) far.push({ ...p, m: p.m.map((x, k) => (k === 14 ? r4(x - z0) : x)) })
        else near.push(p)
      })
      models.push({ id, kind: 'race', pieces: near })
      if (dist === 'quarter') models.push({ id: `race:${v.id}:far`, kind: 'race', pieces: far })
      console.log(`${id}: ${near.length} pieces, ${far.length} far`)
      await r.unmount()
    }
    batching.off = false
  }
  // Each car's size in town traffic (townCarSize.ts): drawn smaller so it fits its lane.
  const { townSize, bodyScale } = await import('./scene/townCarSize')
  const townSizes: Record<string, [number, number, number]> = {}
  for (const c of CARS) {
    const s = townSize(c.body)
    townSizes[c.id] = [r4(s.len), r4(s.wid), r4(bodyScale(c.body))]
  }
  // The shapes go in a file of their own, one per line: all of them in one string is more than
  // JavaScript can hold (build.mjs loadModels reads them back).
  const fd = openSync(`${OUT}.geos`, 'w')
  for (const g of geoList) writeSync(fd, JSON.stringify(g) + '\n')
  closeSync(fd)
  writeFileSync(OUT, JSON.stringify({ geosFile: `${basename(OUT)}.geos`, models, hatSpots: hatSpotOf, modDrops, wheelsOf, rimsOf, stanceOf, panelDrops, trimOf, townSizes, turbines, season: SEASON, grass: PAL.grass, ground: PAL.ground, greens, textures }))
}, 1_800_000)

// Keep these referenced so tree-shaking type checks don't complain.
void Quaternion
