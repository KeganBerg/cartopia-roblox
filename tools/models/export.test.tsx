// @vitest-environment jsdom
// Renders every building and car the web game draws and writes what it drew: each mesh's shape,
// place, size and look. tools/models/build.mjs copies this file into the web game's src folder,
// runs it with the web game's own test runner, and turns the result into Roblox parts.
//
// Nothing here draws to a screen: @react-three/test-renderer builds the same three.js scene the
// game would show, and this walks it.
import { mkdirSync, writeFileSync } from 'fs'
import { createHash } from 'crypto'
import { dirname, join } from 'path'
import { deflateSync } from 'zlib'
import { it } from 'vitest'
import ReactThreeTestRenderer from '@react-three/test-renderer'
import {
  Color, InstancedMesh, Matrix4, Mesh, Quaternion, Vector3,
  type BufferGeometry, type Material, type MeshStandardMaterial, type Object3D,
} from 'three'
import { BUILDINGS, CARS } from './game/data'

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

const OUT = process.env.RBX_MODELS_OUT ?? 'rbx-models.json'

it('exports every building and car', async () => {
  const geos = new Map<BufferGeometry, number>()
  const geoList: Geo[] = []
  const models: { id: string; kind: string; level?: number; pieces: Piece[]; paint?: number[] }[] = []
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
  if (process.env.RBX_ONLY === 'textures') return void writeFileSync(OUT, JSON.stringify({ textures }))
  const LEVELS = (process.env.RBX_LEVELS ?? '1').split(',').map(Number)
  // RBX_ONLY=outskirts skips the buildings, cars and street pieces (a quicker run while working on
  // the countryside).
  const only = process.env.RBX_ONLY
  if (!only) for (const d of BUILDINGS) {
    for (const level of LEVELS) models.push({ id: d.id, kind: 'building', level, pieces: await render(<BuildingModel def={d} level={level} />) })
  }
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
  const outskirts = async (id: string, land: string[], forest: boolean) => {
    const r = await ReactThreeTestRenderer.create(<Outskirts land={land} exits="" small={false} />)
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
  await outskirts('outskirts:forest', plots, true)
  for (const key of plots) await outskirts(`wilds:${key}`, plots.filter((k) => k !== key), false)
  writeFileSync(OUT, JSON.stringify({ geos: geoList, models, hatSpots: hatSpotOf, season: SEASON, grass: PAL.grass, ground: PAL.ground, greens, textures }))
}, 1_800_000)

// Keep these referenced so tree-shaking type checks don't complain.
void Quaternion
