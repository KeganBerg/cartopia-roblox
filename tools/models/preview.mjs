// Pictures of converted models next to the web game's originals, to check the conversion by eye.
//
//   node tools/models/preview.mjs <web repo> <export.json> <out.png> <model> [model...]
//
// Left of each pair: the meshes exactly as the web game drew them (from export.test.tsx).
// Right: the Roblox parts build.mjs made from them (blocks, cylinders, balls and meshes), drawn
// the way Roblox will place them. Uses the web repo's three.js and Playwright's Chromium.

import { readFileSync, writeFileSync, mkdirSync, copyFileSync } from 'node:fs'
import { createServer } from 'node:http'
import { dirname, join, resolve } from 'node:path'
import { createRequire } from 'node:module'
import { fileURLToPath } from 'node:url'
import { MeshoptSimplifier } from 'meshoptimizer'
import { convert, loadModels, SCALE } from './build.mjs'

const HERE = dirname(fileURLToPath(import.meta.url))

export async function preview({ web, data, out, names, cols = 4, size = 360, view }) {
  await MeshoptSimplifier.ready
  const result = convert(data)
  const want = names.map((n) => {
    const [id, level] = n.split('@')
    const model = data.models.find((m) => m.id === id && (m.kind === 'car' || (m.level ?? 1) === Number(level ?? 1)))
    if (!model) throw new Error(`no model ${n}`)
    return { name: n, model, parts: result.models[model.kind === 'car' ? id : `${id}@${model.level ?? 1}`] }
  })
  // Only the geometry and meshes these models use.
  const geoIds = new Set(want.flatMap((w) => w.model.pieces.map((p) => p.g)))
  const geos = {}
  for (const g of geoIds) geos[g] = { pos: data.geos[g].pos, idx: data.geos[g].idx, groups: data.geos[g].groups, col: data.geos[g].col }
  const meshKeys = new Set(want.flatMap((w) => w.parts.filter((p) => p[0] === 'm').map((p) => p[12])))
  const meshes = {}
  for (const k of meshKeys) {
    const m = result.meshes.get(k)
    meshes[k] = { pos: m.pos, idx: m.idx, nrm: m.nrm, size: m.size.map((x) => x * SCALE) }
  }
  const payload = { scale: SCALE, cols, size, view: view ?? null, items: want.map((w) => ({ name: w.name, pieces: w.model.pieces, parts: w.parts })), geos, meshes, looks: result.looks }

  const dir = join(resolve(web), '.rbx-preview')
  mkdirSync(dir, { recursive: true })
  const req = createRequire(join(resolve(web), 'package.json'))
  const threeDir = dirname(req.resolve('three'))
  writeFileSync(join(dir, 'data.js'), `window.DATA = ${JSON.stringify(payload)}`)
  for (const f of ['three.module.js', 'three.core.js']) copyFileSync(join(threeDir, f), join(dir, f))
  writeFileSync(join(dir, 'index.html'), PAGE())
  // Module scripts need http, not file://.
  const server = createServer((q, r) => {
    const f = join(dir, decodeURIComponent(new URL(q.url, 'http://x').pathname))
    try {
      const body = readFileSync(f)
      r.writeHead(200, { 'content-type': f.endsWith('.js') ? 'text/javascript' : 'text/html' })
      r.end(body)
    } catch {
      r.writeHead(404).end()
    }
  })
  await new Promise((res) => server.listen(0, '127.0.0.1', res))
  const port = server.address().port
  const { chromium } = req('playwright')
  const browser = await chromium.launch({ ...(process.env.CHROMIUM ? { executablePath: process.env.CHROMIUM } : {}), args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'] })
  const rows = Math.ceil(want.length / cols)
  const page = await browser.newPage({ viewport: { width: cols * size * 2 + (cols - 1) * 12, height: rows * (size + 28) } })
  page.on('console', (m) => m.type() === 'error' && console.error(m.text()))
  page.on('pageerror', (e) => console.error(e))
  await page.goto(`http://127.0.0.1:${port}/index.html`)
  await page.waitForFunction('window.DONE === true', null, { timeout: 120000 })
  await page.screenshot({ path: out })
  await browser.close()
  server.close()
}

const PAGE = () => `<!doctype html><html><head><meta charset="utf-8">
<style>body{margin:0;background:#1d2733;font:600 15px system-ui;color:#fff}
.grid{display:grid;gap:0 12px}.cell{position:relative}.cell span{position:absolute;left:8px;top:6px;text-shadow:0 1px 2px #000}
.cell b{position:absolute;bottom:6px;font-weight:600;font-size:12px;opacity:.85}.cell b.l{left:8px}.cell b.r{left:calc(50% + 8px)}
canvas{display:block}</style>
<script type="importmap">{"imports":{"three":"./three.module.js"}}</script>
<script src="data.js"></script></head><body><div class="grid" id="g"></div>
<script type="module">
import * as T from 'three'
const D = window.DATA
const g = document.getElementById('g')
g.style.gridTemplateColumns = 'repeat(' + D.cols + ', ' + (D.size * 2) + 'px)'
const renderer = new T.WebGLRenderer({ antialias: true, preserveDrawingBuffer: true })
renderer.setSize(D.size * 2, D.size)
renderer.toneMapping = T.ACESFilmicToneMapping
renderer.outputColorSpace = T.SRGBColorSpace
const LOOK = D.looks
function lit(scene) {
  scene.add(new T.HemisphereLight(0xdfefff, 0x5a6a40, 1.6))
  const sun = new T.DirectionalLight(0xffffff, 2.2); sun.position.set(5, 9, 6); scene.add(sun)
}
function webScene(item) {
  const s = new T.Scene(); lit(s)
  for (const p of item.pieces) {
    const src = D.geos[p.g]
    const geo = new T.BufferGeometry()
    geo.setAttribute('position', new T.Float32BufferAttribute(src.pos, 3))
    let idx = src.idx
    if (p.group !== undefined && src.groups[p.group]) { const gr = src.groups[p.group]; idx = idx.slice(gr.start, gr.start + gr.count) }
    geo.setIndex(idx)
    if (src.col) geo.setAttribute('color', new T.Float32BufferAttribute(src.col, 3))
    geo.computeVertexNormals()
    const m = new T.MeshStandardMaterial({ color: p.look.c, transparent: p.look.o < 1, opacity: p.look.o, roughness: p.look.rough ?? 0.7, metalness: Math.min(0.5, p.look.met ?? 0), vertexColors: !!src.col, emissive: p.look.e ?? '#000', side: T.DoubleSide, flatShading: true })
    const mesh = new T.Mesh(geo, m)
    mesh.matrixAutoUpdate = false
    mesh.matrix.fromArray(p.m).premultiply(new T.Matrix4().makeScale(D.scale, D.scale, D.scale))
    s.add(mesh)
  }
  return s
}
const unit = { b: new T.BoxGeometry(1, 1, 1), c: new T.CylinderGeometry(0.5, 0.5, 1, 24).rotateZ(-Math.PI / 2), s: new T.SphereGeometry(0.5, 24, 16), e: new T.SphereGeometry(0.5, 24, 16) }
function robloxScene(item) {
  const s = new T.Scene(); lit(s)
  for (const p of item.parts) {
    const [k, x, y, z, qx, qy, qz, qw, sx, sy, sz, li, key] = p
    const L = LOOK[li - 1]
    const mat = new T.MeshStandardMaterial({ color: L.color, transparent: L.transparency > 0, opacity: 1 - L.transparency, roughness: L.material === 'Metal' ? 0.35 : 0.6, metalness: L.material === 'Metal' ? 0.5 : 0, emissive: L.material === 'Neon' ? L.color : '#000', emissiveIntensity: 0.8 })
    let geo = unit[k], scale = [sx, sy, sz]
    if (k === 'm') {
      const m = D.meshes[key]
      geo = new T.BufferGeometry()
      geo.setAttribute('position', new T.Float32BufferAttribute(m.pos, 3))
      geo.setAttribute('normal', new T.Float32BufferAttribute(m.nrm, 3))
      geo.setIndex(m.idx)
      // Roblox stretches a mesh to its part's size, like this.
      scale = [sx / Math.max(m.size[0], 1e-6) * D.scale, sy / Math.max(m.size[1], 1e-6) * D.scale, sz / Math.max(m.size[2], 1e-6) * D.scale]
      scale = scale.map((v, i) => (m.size[i] < 1e-4 ? 1 : v))
    }
    const mesh = new T.Mesh(geo, mat)
    mesh.position.set(x, y, z); mesh.quaternion.set(qx, qy, qz, qw); mesh.scale.set(...scale)
    s.add(mesh)
    if (L.text) {
      const c = document.createElement('canvas'); c.width = 512; c.height = 128
      const x2 = c.getContext('2d'); x2.fillStyle = L.text.bg; x2.fillRect(0, 0, 512, 128); x2.fillStyle = L.text.fg
      x2.font = '900 70px Arial Black, Impact, sans-serif'; x2.textAlign = 'center'; x2.textBaseline = 'middle'
      let fs = 70; while (x2.measureText(L.text.text).width > 480 && fs > 20) { fs -= 4; x2.font = '900 ' + fs + 'px Arial Black, Impact, sans-serif' }
      x2.fillText(L.text.text, 256, 68)
      const tex = new T.CanvasTexture(c); tex.colorSpace = T.SRGBColorSpace
      const face = new T.Mesh(new T.PlaneGeometry(1, 1), new T.MeshBasicMaterial({ map: tex }))
      face.position.set(0, 0, 0.5 + 0.01 / Math.max(sz, 0.01)); mesh.add(face)
    }
  }
  return s
}
function frame(scene) {
  scene.updateMatrixWorld(true)
  const box = new T.Box3().setFromObject(scene)
  const c = box.getCenter(new T.Vector3()), r = box.getSize(new T.Vector3()).length() / 2
  const cam = new T.PerspectiveCamera(35, 1, 0.1, 5000)
  const v = D.view ?? [1, 0.75, 1.15]
  cam.position.copy(c).add(new T.Vector3(...v).normalize().multiplyScalar(r * 2.6)); cam.lookAt(c)
  return cam
}
for (const item of D.items) {
  const a = webScene(item), b = robloxScene(item)
  const cam = frame(a)
  renderer.setScissorTest(true)
  renderer.setClearColor(0x9fc6e8)
  renderer.setViewport(0, 0, D.size, D.size); renderer.setScissor(0, 0, D.size, D.size); renderer.render(a, cam)
  renderer.setClearColor(0xa8d0ee)
  renderer.setViewport(D.size, 0, D.size, D.size); renderer.setScissor(D.size, 0, D.size, D.size); renderer.render(b, cam)
  const img = new Image(); img.src = renderer.domElement.toDataURL()
  const cell = document.createElement('div'); cell.className = 'cell'
  cell.append(img); const t = document.createElement('span'); t.textContent = item.name; cell.append(t)
  const l = document.createElement('b'); l.className = 'l'; l.textContent = 'web'; const r = document.createElement('b'); r.className = 'r'; r.textContent = 'Roblox'
  cell.append(l, r); g.append(cell)
  await new Promise((res) => img.onload = res)
}
window.DONE = true
</script></body></html>`

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const [web, json, out, ...names] = process.argv.slice(2)
  await preview({ web, data: loadModels(json), out, names })
  console.log(`wrote ${out}`)
}
