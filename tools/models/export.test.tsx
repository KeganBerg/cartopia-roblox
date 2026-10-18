// @vitest-environment jsdom
// Renders every building and car the web game draws and writes what it drew: each mesh's shape,
// place, size and look. tools/models/build.mjs copies this file into the web game's src folder,
// runs it with the web game's own test runner, and turns the result into Roblox parts.
//
// Nothing here draws to a screen: @react-three/test-renderer builds the same three.js scene the
// game would show, and this walks it.
import { writeFileSync } from 'fs'
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
  const LEVELS = (process.env.RBX_LEVELS ?? '1').split(',').map(Number)
  for (const d of BUILDINGS) {
    for (const level of LEVELS) models.push({ id: d.id, kind: 'building', level, pieces: await render(<BuildingModel def={d} level={level} />) })
  }
  // Each car twice in two paints: the pieces that change colour are its paint.
  for (const c of CARS) {
    const a = await render(<CarModel body={c.body} model={c.id} color="#ff00ff" />)
    const b = await render(<CarModel body={c.body} model={c.id} color="#00ff00" />)
    const paint = a.flatMap((p, i) => (b[i] && b[i].look.c !== p.look.c ? [i] : []))
    const pieces = await render(<CarModel body={c.body} model={c.id} color={c.colors[0]} />)
    models.push({ id: c.id, kind: 'car', pieces, paint })
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
  writeFileSync(OUT, JSON.stringify({ geos: geoList, models, season: SEASON, grass: PAL.grass, ground: PAL.ground, greens }))
}, 1_800_000)

// Keep these referenced so tree-shaking type checks don't complain.
void Quaternion
