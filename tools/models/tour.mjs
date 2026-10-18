// Walks round converted buildings at a player's eye height and pictures each side, to check what
// players see up close in walk mode (the web game only ever shows them from its high camera).
//
//   node tools/models/tour.mjs <web repo> <export.json> <out.png> <model> [model...]
//
// One row per model: front (the street side, web +Z), right, back and left, from 5 studs up and
// DIST studs off the wall, with Roblox's default field of view. Draws the Roblox parts build.mjs
// makes, meshes from their real geometry. Uses the web repo's three.js and Playwright's Chromium.

import { readFileSync, writeFileSync, mkdirSync, copyFileSync } from 'node:fs'
import { createServer } from 'node:http'
import { dirname, join, resolve } from 'node:path'
import { createRequire } from 'node:module'
import { fileURLToPath } from 'node:url'
import { MeshoptSimplifier } from 'meshoptimizer'
import { convert, loadModels, SCALE } from './build.mjs'

const W = Number(process.env.TOUR_W ?? 360)
const H = Number(process.env.TOUR_H ?? 240)

export async function tour({ web, data, out, names, dist = 22 }) {
  await MeshoptSimplifier.ready
  const result = convert(data)
  const items = names.map((n) => {
    const parts = result.models[n.includes('@') || !data.models.some((m) => m.kind === 'building' && m.id === n) ? n : `${n}@1`]
    if (!parts) throw new Error(`no model ${n}`)
    return { name: n, parts }
  })
  const meshes = {}
  for (const k of new Set(items.flatMap((i) => i.parts.filter((p) => p[0] === 'm').map((p) => p[12])))) {
    const m = result.meshes.get(k)
    meshes[k] = { pos: m.pos, idx: m.idx, nrm: m.nrm, size: m.size.map((x) => x * SCALE) }
  }
  const dir = join(resolve(web), '.rbx-preview', `tour-${process.pid}`)
  mkdirSync(dir, { recursive: true })
  const req = createRequire(join(resolve(web), 'package.json'))
  const threeDir = dirname(req.resolve('three'))
  writeFileSync(join(dir, 'data.js'), `window.DATA = ${JSON.stringify({ items, meshes, looks: result.looks, dist, W, H })}`)
  for (const f of ['three.module.js', 'three.core.js']) copyFileSync(join(threeDir, f), join(dir, f))
  writeFileSync(join(dir, 'index.html'), PAGE)
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
  const { chromium } = req('playwright')
  const browser = await chromium.launch({ ...(process.env.CHROMIUM ? { executablePath: process.env.CHROMIUM } : {}), args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'] })
  const page = await browser.newPage({ viewport: { width: W * 4 + 36, height: items.length * (H + 4) } })
  page.on('pageerror', (e) => console.error(e))
  await page.goto(`http://127.0.0.1:${server.address().port}/index.html`)
  await page.waitForFunction('window.DONE === true', null, { timeout: 300000 })
  await page.screenshot({ path: out, fullPage: true })
  await browser.close()
  server.close()
}

const PAGE = `<!doctype html><html><head><meta charset="utf-8">
<style>body{margin:0;background:#1d2733;font:600 14px system-ui;color:#fff}
.row{display:flex;gap:12px;margin-bottom:4px;position:relative}.row span{position:absolute;left:8px;top:6px;text-shadow:0 1px 2px #000;z-index:1}</style>
<script type="importmap">{"imports":{"three":"./three.module.js"}}</script>
<script src="data.js"></script></head><body>
<script type="module">
import * as T from 'three'
const D = window.DATA
const renderer = new T.WebGLRenderer({ antialias: true, preserveDrawingBuffer: true })
renderer.setSize(D.W, D.H)
renderer.toneMapping = T.ACESFilmicToneMapping
renderer.outputColorSpace = T.SRGBColorSpace
const unit = { b: new T.BoxGeometry(1, 1, 1), c: new T.CylinderGeometry(0.5, 0.5, 1, 24).rotateZ(-Math.PI / 2), s: new T.SphereGeometry(0.5, 24, 16), e: new T.SphereGeometry(0.5, 24, 16) }
// Rough stand-ins for Roblox's material textures, so a Brick wall reads as brick here too.
const texCache = {}
function matTex(material) {
  if (material in texCache) return texCache[material]
  const draw = {
    Brick: (g) => { g.fillStyle = '#fff'; g.fillRect(0, 0, 64, 64); g.fillStyle = '#c8c8c8'; for (let y = 0; y < 64; y += 8) { g.fillRect(0, y, 64, 1.5); for (let x = (y / 8) % 2 ? 8 : 0; x < 64; x += 16) g.fillRect(x, y, 1.5, 8) } },
    WoodPlanks: (g) => { g.fillStyle = '#fff'; g.fillRect(0, 0, 64, 64); g.fillStyle = '#cfcfcf'; for (let y = 0; y < 64; y += 8) g.fillRect(0, y, 64, 1.5) },
    RoofShingles: (g) => { g.fillStyle = '#fff'; g.fillRect(0, 0, 64, 64); g.fillStyle = '#b8b8b8'; for (let y = 0; y < 64; y += 8) { g.fillRect(0, y, 64, 2); for (let x = (y / 8) % 2 ? 6 : 0; x < 64; x += 12) g.fillRect(x, y, 1.5, 8) } },
    Metal: (g) => { g.fillStyle = '#fff'; g.fillRect(0, 0, 64, 64); g.fillStyle = '#d0d0d0'; for (let x = 0; x < 64; x += 16) g.fillRect(x, 0, 1.5, 64) },
    Fabric: (g) => { g.fillStyle = '#fff'; g.fillRect(0, 0, 64, 64); g.fillStyle = '#e0e0e0'; for (let x = 0; x < 64; x += 4) g.fillRect(x, 0, 1, 64) },
  }[material] ?? (['Concrete', 'Pebble', 'Pavement', 'Sand', 'Ground', 'Snow'].includes(material) ? (g) => { g.fillStyle = '#fff'; g.fillRect(0, 0, 64, 64); for (let i = 0; i < 500; i++) { const v = 200 + Math.floor(Math.random() * 55); g.fillStyle = 'rgb(' + v + ',' + v + ',' + v + ')'; g.fillRect(Math.random() * 64, Math.random() * 64, 2, 2) } } : null)
  if (!draw) return (texCache[material] = null)
  const c = document.createElement('canvas'); c.width = c.height = 64
  draw(c.getContext('2d'))
  const t = new T.CanvasTexture(c); t.wrapS = t.wrapT = T.RepeatWrapping; t.colorSpace = T.SRGBColorSpace
  return (texCache[material] = t)
}
function scene(item) {
  const s = new T.Scene()
  s.add(new T.HemisphereLight(0xdfefff, 0x5a6a40, 1.5))
  const sun = new T.DirectionalLight(0xffffff, 2.2); sun.position.set(40, 90, 60); s.add(sun)
  const ground = new T.Mesh(new T.PlaneGeometry(400, 400), new T.MeshStandardMaterial({ color: '#8fbf5a' }))
  ground.rotation.x = -Math.PI / 2; ground.position.y = -0.05; s.add(ground)
  for (const p of item.parts) {
    const [k, x, y, z, qx, qy, qz, qw, sx, sy, sz, li, key] = p
    const L = D.looks[li - 1]
    const mat = new T.MeshStandardMaterial({ color: L.color, transparent: L.transparency > 0, opacity: 1 - L.transparency, roughness: L.material === 'Metal' ? 0.35 : 0.6, metalness: L.material === 'Metal' ? 0.5 : 0, emissive: L.material === 'Neon' ? L.color : '#000', emissiveIntensity: 0.8 })
    const tex = k === 'b' && matTex(L.material)
    if (tex) {
      // One tile of the pattern every 8 studs, on each face of the block.
      mat.map = tex.clone(); mat.map.needsUpdate = true; mat.map.repeat.set(Math.max(sx, sz) / 8, sy / 8)
    }
    if (L.material === 'Glass' && L.transparency === 0) { mat.roughness = 0.1; mat.metalness = 0.6 }
    let geo = unit[k], scale = [sx, sy, sz]
    if (k === 'm') {
      const m = D.meshes[key]
      geo = new T.BufferGeometry()
      geo.setAttribute('position', new T.Float32BufferAttribute(m.pos, 3))
      geo.setAttribute('normal', new T.Float32BufferAttribute(m.nrm, 3))
      geo.setIndex(m.idx)
      scale = scale.map((v, i) => (m.size[i] < 1e-4 ? 1 : v / Math.max(m.size[i], 1e-6)))
    }
    const mesh = new T.Mesh(geo, mat)
    mesh.position.set(x, y, z); mesh.quaternion.set(qx, qy, qz, qw); mesh.scale.set(...scale)
    s.add(mesh)
    if (L.text) {
      const c = document.createElement('canvas'); c.width = 512; c.height = 128
      const x2 = c.getContext('2d'); x2.fillStyle = L.text.bg; x2.fillRect(0, 0, 512, 128); x2.fillStyle = L.text.fg
      x2.font = '900 60px sans-serif'; x2.textAlign = 'center'; x2.textBaseline = 'middle'; x2.fillText(L.text.text, 256, 68)
      const tex = new T.CanvasTexture(c); tex.colorSpace = T.SRGBColorSpace
      const face = new T.Mesh(new T.PlaneGeometry(1, 1), new T.MeshBasicMaterial({ map: tex }))
      face.position.set(0, 0, 0.5 + 0.01 / Math.max(sz, 0.01)); mesh.add(face)
    }
  }
  s.background = new T.Color(0xa8d0ee)
  return s
}
for (const item of D.items) {
  const s = scene(item)
  s.updateMatrixWorld(true)
  const box = new T.Box3()
  for (const m of s.children) if (m.isMesh && m.geometry.type !== 'PlaneGeometry') box.expandByObject(m)
  const c = box.getCenter(new T.Vector3()), size = box.getSize(new T.Vector3())
  const row = document.createElement('div'); row.className = 'row'
  const t = document.createElement('span'); t.textContent = item.name; row.append(t)
  for (const [dx, dz] of [[0, 1], [1, 0], [0, -1], [-1, 0]]) {
    const half = Math.abs(dx) * size.x / 2 + Math.abs(dz) * size.z / 2
    const cam = new T.PerspectiveCamera(70, D.W / D.H, 0.1, 2000)
    cam.position.set(c.x + dx * (half + D.dist), 5, c.z + dz * (half + D.dist))
    cam.lookAt(c.x + dx * half, 9, c.z + dz * half)
    renderer.render(s, cam)
    const img = new Image(); img.src = renderer.domElement.toDataURL(); row.append(img)
    await new Promise((res) => (img.onload = res))
  }
  document.body.append(row)
}
window.DONE = true
</script></body></html>`

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const [web, json, out, ...names] = process.argv.slice(2)
  await tour({ web, data: loadModels(json), out, names, dist: Number(process.env.DIST ?? 22) })
  console.log(`wrote ${out}`)
}
