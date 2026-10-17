// Pictures what the game built in the emulator (tools/emulate/*.luau): every part, drawn with
// three.js the way Roblox shapes it (blocks, cylinders along X, balls, meshes stretched to their
// part), plus the screens (ScreenGui) laid over it as HTML when given.
//
//   node tools/emulate/render.mjs <web repo> <scene.json> <out.png> [gui.json]
//
// Uses the web repo's three.js and Playwright. CHROMIUM=<path> picks the browser.

import { readFileSync, writeFileSync, mkdirSync, copyFileSync } from 'node:fs'
import { createServer } from 'node:http'
import { dirname, join, resolve } from 'node:path'
import { createRequire } from 'node:module'
import { fileURLToPath } from 'node:url'

const HERE = dirname(fileURLToPath(import.meta.url))
const ROOT = resolve(HERE, '../..')

export async function render({ web, scene, out, gui, width = 1280, height = 800, camera }) {
  const dir = join(resolve(web), '.rbx-preview')
  mkdirSync(dir, { recursive: true })
  const req = createRequire(join(resolve(web), 'package.json'))
  const threeDir = dirname(req.resolve('three'))
  for (const f of ['three.module.js', 'three.core.js']) copyFileSync(join(threeDir, f), join(dir, f))
  const meshes = JSON.parse(readFileSync(join(ROOT, 'build/meshes.json'), 'utf8'))
  const used = {}
  for (const p of scene.parts) if (p.mesh && meshes[p.mesh]) used[p.mesh] = meshes[p.mesh]
  writeFileSync(join(dir, 'scene.js'), `window.SCENE = ${JSON.stringify({ ...scene, meshes: used, gui: gui ?? null, camera: camera ?? null })}`)
  writeFileSync(join(dir, 'scene.html'), PAGE)
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
  const page = await browser.newPage({ viewport: { width, height } })
  page.on('pageerror', (e) => console.error(e))
  await page.goto(`http://127.0.0.1:${server.address().port}/scene.html`)
  await page.waitForFunction('window.DONE === true', null, { timeout: 180000 })
  await page.screenshot({ path: out, timeout: 180000 })
  await browser.close()
  server.close()
}

const PAGE = `<!doctype html><html><head><meta charset="utf-8">
<style>html,body{margin:0;overflow:hidden;background:#87b7e0}#ui{position:fixed;inset:0;pointer-events:none;font-family:'Fredoka One','Arial Rounded MT Bold',system-ui,sans-serif}
#ui div{position:absolute;box-sizing:border-box;display:flex;align-items:center;justify-content:center;white-space:nowrap}</style>
<script type="importmap">{"imports":{"three":"./three.module.js"}}</script>
<script src="scene.js"></script></head><body><div id="ui"></div>
<script type="module">
import * as T from 'three'
const S = window.SCENE
const W = innerWidth, H = innerHeight
const renderer = new T.WebGLRenderer({ antialias: true, preserveDrawingBuffer: true })
renderer.setSize(W, H)
renderer.toneMapping = T.ACESFilmicToneMapping
renderer.outputColorSpace = T.SRGBColorSpace
renderer.shadowMap.enabled = true
document.body.prepend(renderer.domElement)
const scene = new T.Scene()
scene.background = new T.Color('#8ec5f0')
scene.fog = new T.Fog('#bcd9f2', 600, 1600)
scene.add(new T.HemisphereLight(0xdfefff, 0x5a6a40, 1.5))
const sun = new T.DirectionalLight(0xfff4e0, 2.4)
sun.position.set(300, 500, 200); sun.castShadow = true
sun.shadow.mapSize.set(4096, 4096)
Object.assign(sun.shadow.camera, { left: -400, right: 400, top: 400, bottom: -400, near: 10, far: 1500 })
scene.add(sun)
const unit = { Block: new T.BoxGeometry(1, 1, 1), Cylinder: new T.CylinderGeometry(0.5, 0.5, 1, 28).rotateZ(-Math.PI / 2), Ball: new T.SphereGeometry(0.5, 24, 16), ellipsoid: new T.SphereGeometry(0.5, 24, 16) }
const MAT = { Neon: { emissive: 0.9 }, Metal: { metalness: 0.55, roughness: 0.35 }, Glass: { roughness: 0.1 }, Grass: { roughness: 1 }, Asphalt: { roughness: 1 }, Concrete: { roughness: 0.95 } }
const geoCache = {}
for (const p of S.parts) {
  let geo = unit[p.shape] || unit.Block
  let scale = p.size
  if (p.mesh && S.meshes[p.mesh]) {
    const m = S.meshes[p.mesh]
    geo = geoCache[p.mesh] ??= (() => { const g = new T.BufferGeometry(); g.setAttribute('position', new T.Float32BufferAttribute(m.pos, 3)); g.setIndex(m.idx); g.computeVertexNormals(); return g })()
    scale = p.size.map((v, i) => (m.size[i] < 1e-4 ? 1 : v / m.size[i]))
  }
  const look = MAT[p.material] || {}
  const mat = new T.MeshStandardMaterial({ color: '#' + p.color, transparent: p.transparency > 0, opacity: 1 - p.transparency, roughness: look.roughness ?? 0.6, metalness: look.metalness ?? 0, emissive: look.emissive ? '#' + p.color : '#000', emissiveIntensity: look.emissive ?? 0, flatShading: !!p.mesh })
  const mesh = new T.Mesh(geo, mat)
  const [x, y, z, a, b, c, d, e, f, g, h, i] = p.cf
  const m4 = new T.Matrix4().set(a, b, c, x, d, e, f, y, g, h, i, z, 0, 0, 0, 1)
  mesh.matrixAutoUpdate = false
  mesh.matrix.copy(m4).multiply(new T.Matrix4().makeScale(...scale))
  mesh.castShadow = p.transparency < 0.5 && Math.max(...p.size) < 500
  mesh.receiveShadow = true
  scene.add(mesh)
  if (p.text) {
    const cv = document.createElement('canvas'); cv.width = 512; cv.height = Math.max(64, Math.round(512 * p.size[1] / Math.max(p.size[0], 0.01)))
    const x2 = cv.getContext('2d'); x2.fillStyle = '#' + p.text.bg; x2.fillRect(0, 0, cv.width, cv.height); x2.fillStyle = '#' + p.text.fg
    let fs = cv.height * 0.7; x2.font = '900 ' + fs + 'px Arial Black, sans-serif'; x2.textAlign = 'center'; x2.textBaseline = 'middle'
    while (x2.measureText(p.text.text).width > cv.width * 0.88 && fs > 10) { fs -= 2; x2.font = '900 ' + fs + 'px Arial Black, sans-serif' }
    x2.fillText(p.text.text, cv.width / 2, cv.height / 2 + 2)
    const tex = new T.CanvasTexture(cv); tex.colorSpace = T.SRGBColorSpace
    const face = new T.Mesh(new T.PlaneGeometry(1, 1), new T.MeshBasicMaterial({ map: tex }))
    face.matrixAutoUpdate = false
    face.matrix.copy(m4).multiply(new T.Matrix4().makeTranslation(0, 0, p.size[2] / 2 + 0.02)).multiply(new T.Matrix4().makeScale(p.size[0], p.size[1], 1))
    scene.add(face)
  }
}
const cam = new T.PerspectiveCamera(S.camera?.fov ?? 40, W / H, 1, 5000)
const c = S.camera ?? { at: [0, 0, 0], from: [260, 300, 330] }
cam.position.set(...c.from); cam.lookAt(new T.Vector3(...c.at))
renderer.render(scene, cam)

// Screens: ScreenGui frames as absolutely placed boxes, in tree order.
const ui = document.getElementById('ui')
function draw(node, into = ui, ox = 0, oy = 0) {
  if (node.visible === false) return
  const el = document.createElement('div')
  const [px, py, pw, ph] = node.abs
  Object.assign(el.style, { left: px - ox + 'px', top: py - oy + 'px', width: pw + 'px', height: ph + 'px' })
  const alpha = node.bgT > 0 ? Math.round((1 - node.bgT) * 255).toString(16).padStart(2, '0') : ''
  if (node.bg != null && node.bgT < 1) el.style.background = node.grad ? 'linear-gradient(#' + node.grad[0] + alpha + ',#' + node.grad[1] + alpha + ')' : '#' + node.bg + alpha
  if (node.corner != null) el.style.borderRadius = node.corner + 'px'
  // UIStroke borders sit outside the box, so a shadow ring rather than a CSS border.
  if (node.stroke) el.style.boxShadow = '0 0 0 ' + node.stroke[0] + 'px #' + node.stroke[1]
  if (node.text) {
    el.textContent = node.text
    el.style.color = '#' + node.textColor
    el.style.fontSize = node.textSize + 'px'
    el.style.justifyContent = node.xAlign === 'Left' ? 'flex-start' : node.xAlign === 'Right' ? 'flex-end' : 'center'
    if (node.textStroke) el.style.webkitTextStroke = '1.2px #14213d', el.style.paintOrder = 'stroke fill', el.style.textShadow = '0 2px 0 #14213d'
  }
  if (node.clip) el.style.overflow = 'hidden'
  into.append(el)
  // Children nest inside so a clipping frame (a scrolling list) hides what runs past it.
  for (const k of Array.isArray(node.children) ? node.children : []) draw(k, el, px, py)
}
if (S.gui) {
  for (const b of Array.isArray(S.gui.bubbles) ? S.gui.bubbles : []) {
    const v = new T.Vector3(...b.at).project(cam)
    if (v.z > 1) continue
    const x = (v.x + 1) / 2 * W - b.size[0] / 2, y = (1 - v.y) / 2 * H - b.size[1] / 2
    const ready = b.text.startsWith('🪙'), run = b.text.startsWith('⏱')
    draw({ abs: [x, y, b.size[0], b.size[1]], bg: 'ffffff', bgT: 0, grad: ready ? ['ffd84a', 'f0a400'] : run ? ['34507f', '1f3358'] : ['ffffff', 'e3ecf7'], corner: 14, stroke: [3, '14213d'], text: b.text, textColor: 'ffffff', textSize: 18, textStroke: true })
  }
  for (const n of [].concat(S.gui.nodes || S.gui)) draw(n)
}
window.DONE = true
</script></body></html>`

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const [web, sceneFile, out, guiFile, cam] = process.argv.slice(2)
  await render({ web, scene: JSON.parse(readFileSync(sceneFile, 'utf8')), out, gui: guiFile && guiFile !== '-' ? JSON.parse(readFileSync(guiFile, 'utf8')) : null, camera: cam ? JSON.parse(cam) : undefined })
  console.log(`wrote ${out}`)
}
