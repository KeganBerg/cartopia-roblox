// Pictures what the game built in the emulator (tools/emulate/*.luau): every part, drawn with
// three.js the way Roblox shapes it (blocks, cylinders along X, balls, meshes stretched to their
// part), plus the screens (ScreenGui) laid over it as HTML when given.
//
//   node tools/emulate/render.mjs <web repo> <scene.json> <out.png> [gui.json]
//
// SIZE=390x844 draws at another screen size (1280x800 by default).
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
  // Lune writes an empty list as {}.
  if (!Array.isArray(scene.parts)) scene = { ...scene, parts: [] }
  // One folder per run, so renders running side by side don't swap scenes.
  const dir = join(resolve(web), '.rbx-preview', String(process.pid))
  mkdirSync(dir, { recursive: true })
  const req = createRequire(join(resolve(web), 'package.json'))
  const threeDir = dirname(req.resolve('three'))
  for (const f of ['three.module.js', 'three.core.js']) copyFileSync(join(threeDir, f), join(dir, f))
  const meshes = JSON.parse(readFileSync(join(ROOT, 'build/meshes.json'), 'utf8'))
  const used = {}
  for (const p of scene.parts) if (p.mesh && meshes[p.mesh]) used[p.mesh] = meshes[p.mesh]
  // Meshes the screens' 3D pictures (ViewportFrames) show.
  const visit = (n) => {
    if (!n || typeof n !== 'object') return
    if (n.viewport?.parts) for (const p of n.viewport.parts) if (p.mesh && meshes[p.mesh]) used[p.mesh] = meshes[p.mesh]
    for (const v of Object.values(n)) if (v && typeof v === 'object') visit(v)
  }
  visit(gui)
  // The ground textures parts carry (images build.mjs's export painted).
  const textures = {}
  const wantTexture = (name) => {
    if (name && !textures[name]) {
      try { textures[name] = 'data:image/png;base64,' + readFileSync(join(ROOT, 'build/textures', `${name}.png`)).toString('base64') } catch {}
    }
  }
  for (const p of scene.parts) wantTexture(p.texture?.image)
  // Custom paint patterns, on any part in the world or a 3D picture.
  const patterns = (n) => {
    if (!n || typeof n !== 'object') return
    if (Array.isArray(n.patterns)) for (const t of n.patterns) wantTexture(t.image)
    for (const v of Object.values(n)) if (v && typeof v === 'object') patterns(v)
  }
  patterns(scene.parts)
  patterns(gui)
  // The loading screen's pictures (tools/splash/build.mjs), by key.
  const images = {}
  try {
    const list = JSON.parse(readFileSync(join(ROOT, 'build/splash/list.json'), 'utf8'))
    const want = new Set()
    const find = (n) => {
      if (!n || typeof n !== 'object') return
      if (n.image?.key) want.add(n.image.key)
      for (const v of Object.values(n)) if (v && typeof v === 'object') find(v)
    }
    find(gui)
    for (const e of list) if (want.has(e.key)) images[e.key] = 'data:image/png;base64,' + readFileSync(join(ROOT, 'build/splash', e.file)).toString('base64')
  } catch {}
  // The sky's faces (tools/sky/build.mjs) for the step the scene asks for.
  const sky = {}
  if (scene.sky) {
    for (const face of ['Lf', 'Bk', 'Rt', 'Ft', 'Up', 'Dn']) sky[face] = 'data:image/png;base64,' + readFileSync(join(ROOT, 'build/sky', `${scene.sky.season}-${scene.sky.step}-${face}.png`)).toString('base64')
  }
  writeFileSync(join(dir, 'scene.js'), `window.SCENE = ${JSON.stringify({ ...scene, meshes: used, textures, images, sky, gui: gui ?? null, camera: camera ?? null })}`)
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
  page.on('console', (m) => m.type() === 'error' && console.error(m.text()))
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
// Roblox's wedge: the full bottom, the full back (+Z) face, and a slope down to the front edge.
const wedgeGeo = (() => {
  const v = [[-0.5, -0.5, -0.5], [0.5, -0.5, -0.5], [0.5, -0.5, 0.5], [-0.5, -0.5, 0.5], [-0.5, 0.5, 0.5], [0.5, 0.5, 0.5]]
  const tris = [[0, 1, 2], [0, 2, 3], [3, 2, 5], [3, 5, 4], [0, 4, 5], [0, 5, 1], [0, 3, 4], [1, 5, 2]]
  const g = new T.BufferGeometry()
  g.setAttribute('position', new T.Float32BufferAttribute(tris.flatMap((t) => t.flatMap((k) => v[k])), 3))
  g.computeVertexNormals()
  return g
})()
const unit = { Wedge: wedgeGeo, Block: new T.BoxGeometry(1, 1, 1), Cylinder: new T.CylinderGeometry(0.5, 0.5, 1, 28).rotateZ(-Math.PI / 2), Ball: new T.SphereGeometry(0.5, 24, 16), ellipsoid: new T.SphereGeometry(0.5, 24, 16) }
const MAT = { Neon: { emissive: 0.9 }, Metal: { metalness: 0.55, roughness: 0.35 }, Glass: { roughness: 0.1 }, Grass: { roughness: 1 }, Asphalt: { roughness: 1 }, Concrete: { roughness: 0.95 } }
const geoCache = {}
// Ground textures, as Roblox's Texture lays them on a part's top face.
const TEX = {}
for (const [name, url] of Object.entries(S.textures || {})) {
  const t = await new T.TextureLoader().loadAsync(url)
  t.colorSpace = T.SRGBColorSpace
  t.wrapS = t.wrapT = T.RepeatWrapping
  TEX[name] = t
}
// Every part as Roblox shapes it: blocks, cylinders along X, balls, meshes stretched to their part.
function addParts(scene, parts) {
for (const p of parts) {
  let geo = unit[p.shape] || unit.Block
  let scale = p.size
  if (p.mesh && S.meshes[p.mesh]) {
    const m = S.meshes[p.mesh]
    geo = geoCache[p.mesh] ??= (() => { const g = new T.BufferGeometry(); g.setAttribute('position', new T.Float32BufferAttribute(m.pos, 3)); g.setIndex(m.idx); g.computeVertexNormals(); return g })()
    scale = p.size.map((v, i) => (m.size[i] < 1e-4 ? 1 : v / m.size[i]))
  }
  const look = MAT[p.material] || {}
  const mat = new T.MeshStandardMaterial({ color: '#' + p.color, transparent: p.transparency > 0, opacity: 1 - p.transparency, roughness: look.roughness ?? 0.6, metalness: look.metalness ?? 0, emissive: look.emissive ? '#' + p.color : '#000', emissiveIntensity: look.emissive ?? 0, flatShading: !!p.mesh })
  if (p.shape === 'Wedge') mat.side = T.DoubleSide
  let mats = mat
  if (p.texture && TEX[p.texture.image] && !p.mesh && (p.shape === 'Block' || !p.shape)) {
    const t = TEX[p.texture.image].clone()
    t.repeat.set(p.size[0] / p.texture.span[0], p.size[2] / p.texture.span[1])
    t.offset.set(p.texture.offset[0] / p.texture.span[0], p.texture.offset[1] / p.texture.span[1])
    const top = mat.clone(); top.map = t; top.color.set('#ffffff')
    mats = [mat, mat, top, mat, mat, mat]
  }
  const mesh = new T.Mesh(geo, mats)
  const [x, y, z, a, b, c, d, e, f, g, h, i] = p.cf
  const m4 = new T.Matrix4().set(a, b, c, x, d, e, f, y, g, h, i, z, 0, 0, 0, 1)
  mesh.matrixAutoUpdate = false
  mesh.matrix.copy(m4)
  // A real MeshPart from an uploaded pack: Roblox's glTF import turned its geometry half round.
  if (p.imported) mesh.matrix.multiply(new T.Matrix4().makeRotationY(Math.PI))
  mesh.matrix.multiply(new T.Matrix4().makeScale(...scale))
  mesh.castShadow = p.transparency < 0.5 && Math.max(...p.size) < 500
  mesh.receiveShadow = true
  scene.add(mesh)
  // Custom paint patterns: each face's tile laid flat over the triangles facing that way, as
  // Roblox's Texture projects onto a part's face.
  for (const t of [...(p.patterns || [])].sort((a, b) => (a.z ?? 1) - (b.z ?? 1))) {
    if (!TEX[t.image]) continue
    const TILE = { Front: [[-1, 0, 0], [0, -1, 0]], Back: [[1, 0, 0], [0, -1, 0]], Right: [[0, 0, -1], [0, -1, 0]], Left: [[0, 0, 1], [0, -1, 0]], Top: [[1, 0, 0], [0, 0, 1]], Bottom: [[-1, 0, 0], [0, 0, 1]] }
    const AXIS = { Top: [1, 1], Bottom: [1, -1], Right: [0, 1], Left: [0, -1], Back: [2, 1], Front: [2, -1] }[t.face]
    if (!AXIS) continue
    const src = geo.index ? geo.toNonIndexed() : geo
    const pos = src.getAttribute('position')
    const keep = [], uv = []
    const v = (i) => [pos.getX(i), pos.getY(i), pos.getZ(i)]
    for (let i = 0; i + 2 < pos.count; i += 3) {
      const [a, b, c] = [v(i), v(i + 1), v(i + 2)]
      const n = new T.Vector3(...b.map((x, k) => x - a[k])).cross(new T.Vector3(...c.map((x, k) => x - a[k])))
      const m = [Math.abs(n.x * scale[0] ** -1), Math.abs(n.y / scale[1]), Math.abs(n.z / scale[2])]
      const dom = m.indexOf(Math.max(...m))
      if (dom !== AXIS[0] || Math.sign([n.x, n.y, n.z][dom]) !== AXIS[1]) continue
      for (const q of [a, b, c]) {
        keep.push(...q)
        const s = q.map((x, k) => x * scale[k])
        // Along the tile's U (across) and V (down) as Roblox lays it on that face, less its offset.
        const [U, V] = TILE[t.face]
        const dot = (a) => a[0] * s[0] + a[1] * s[1] + a[2] * s[2]
        const off = t.offset ?? [0, 0]
        uv.push((dot(U) - off[0]) / t.span, -(dot(V) - off[1]) / t.span)
      }
    }
    if (!keep.length) continue
    const og = new T.BufferGeometry()
    og.setAttribute('position', new T.Float32BufferAttribute(keep, 3))
    og.setAttribute('uv', new T.Float32BufferAttribute(uv, 2))
    og.computeVertexNormals()
    const map = TEX[t.image].clone()
    map.needsUpdate = true
    const over = new T.Mesh(og, new T.MeshStandardMaterial({ map, color: '#' + (t.color ?? 'ffffff'), transparent: true, opacity: 1 - (t.transparency ?? 0), roughness: 0.6, polygonOffset: true, polygonOffsetFactor: -2 - (t.z ?? 1), polygonOffsetUnits: -2 - (t.z ?? 1) }))
    over.matrixAutoUpdate = false
    over.matrix.copy(mesh.matrix)
    scene.add(over)
  }
  if (p.text) {
    const cv = document.createElement('canvas'); cv.width = 512; cv.height = Math.max(64, Math.round(512 * p.size[1] / Math.max(p.size[0], 0.01)))
    const x2 = cv.getContext('2d'); x2.fillStyle = '#' + p.text.bg; x2.fillRect(0, 0, cv.width, cv.height); x2.fillStyle = '#' + p.text.fg
    // Chequers (the finish line): two rows of squares, as Builder draws them.
    if (p.text.checker) for (let i = 0; i < p.text.checker; i++) for (let j = 0; j < 2; j++) if ((i + j) % 2) x2.fillRect(i * cv.width / p.text.checker, j * cv.height / 2, cv.width / p.text.checker + 1, cv.height / 2 + 1)
    let fs = cv.height * 0.7; x2.font = '900 ' + fs + 'px Arial Black, sans-serif'; x2.textAlign = 'center'; x2.textBaseline = 'middle'
    while (x2.measureText(p.text.text).width > cv.width * 0.88 && fs > 10) { fs -= 2; x2.font = '900 ' + fs + 'px Arial Black, sans-serif' }
    if (!p.text.checker) x2.fillText(p.text.text, cv.width / 2, cv.height / 2 + 2)
    const tex = new T.CanvasTexture(cv); tex.colorSpace = T.SRGBColorSpace
    const face = new T.Mesh(new T.PlaneGeometry(1, 1), new T.MeshBasicMaterial({ map: tex }))
    face.matrixAutoUpdate = false
    face.matrix.copy(m4).multiply(new T.Matrix4().makeTranslation(0, 0, p.size[2] / 2 + 0.02)).multiply(new T.Matrix4().makeScale(p.size[0], p.size[1], 1))
    scene.add(face)
  }
}
}
addParts(scene, S.parts)
// A near plane well out from the camera: the software renderer's depth buffer is coarse, and road
// paint a tenth of a stud above the asphalt sank into it.
const cam = new T.PerspectiveCamera(S.camera?.fov ?? 40, W / H, 8, S.sky?.Up ? 40000 : 6000)
const c = S.camera ?? { at: [0, 0, 0], from: [260, 300, 330] }
cam.position.set(...c.from); cam.lookAt(new T.Vector3(...c.at))
// Haze starts past what the camera looks at, as the game's light Atmosphere does.
const reach = cam.position.distanceTo(new T.Vector3(...c.at))
scene.fog = S.fog ? new T.Fog('#' + S.fog.color, S.fog.start, S.fog.end) : new T.Fog('#bcd9f2', reach * 1.1, reach + 3000)
// The sky: each face is a picture of what a camera looking that way saw (tools/sky/build.mjs),
// so each hangs square in front of the camera that way, a skybox round where it stands. Hung the
// way Roblox hangs them: Left, Back, Right, Front an upright strip, Up's top edge on Left and
// Down's top edge on Right (a cubemap's py turned clockwise, ny anticlockwise).
if (S.sky?.Up) {
  const FACES = { Lf: [[1, 0, 0], [0, 1, 0]], Bk: [[0, 0, 1], [0, 1, 0]], Rt: [[-1, 0, 0], [0, 1, 0]], Ft: [[0, 0, -1], [0, 1, 0]], Up: [[0, 1, 0], [1, 0, 0]], Dn: [[0, -1, 0], [-1, 0, 0]] }
  const D = 20000
  for (const [face, [look, up]] of Object.entries(FACES)) {
    const t = await new T.TextureLoader().loadAsync(S.sky[face])
    t.colorSpace = T.SRGBColorSpace
    const L = new T.Vector3(...look), U = new T.Vector3(...up), R = new T.Vector3().crossVectors(L, U)
    const q = new T.Mesh(new T.PlaneGeometry(2 * D, 2 * D), new T.MeshBasicMaterial({ map: t, fog: false, toneMapped: false, depthWrite: false }))
    q.matrixAutoUpdate = false
    q.matrix.makeBasis(R, U, L.clone().negate()).setPosition(L.clone().multiplyScalar(D).add(cam.position))
    q.renderOrder = -1
    scene.add(q)
  }
}
renderer.render(scene, cam)

// Screens: ScreenGui frames as absolutely placed boxes, drawn as Roblox would: children over
// parents, siblings by ZIndex, UIStroke outlines outside the box (text strokes around the
// letters), UIGradient colour stops and rotation, and Roblox's Fredoka One and Nunito fonts.
const fonts = document.createElement('link')
fonts.rel = 'stylesheet'
fonts.href = 'https://fonts.googleapis.com/css2?family=Fredoka+One&family=Nunito:wght@400;700;800;900&display=block'
document.head.append(fonts)
const ui = document.getElementById('ui')
const FAMILY = { FredokaOne: "'Fredoka One','Arial Rounded MT Bold',system-ui,sans-serif", Nunito: "Nunito,system-ui,sans-serif" }
const rgba = (h, t = 0) => { const n = parseInt(h, 16); return 'rgba(' + (n >> 16 & 255) + ',' + (n >> 8 & 255) + ',' + (n & 255) + ',' + (1 - t).toFixed(3) + ')' }
function fill(node) {
  if (node.bg == null || node.bgT >= 1) return null
  if (!node.grad) return rgba(node.bg, node.bgT)
  const g = node.grad, n = g.stops.length
  const stops = g.stops.map(([t, c], i) => rgba(c, 1 - (1 - node.bgT) * (1 - (g.t0 + (g.t1 - g.t0) * t))) + ' ' + (t * 100).toFixed(1) + '%')
  return 'linear-gradient(' + (g.rot + 90) + 'deg,' + stops.join(',') + ')'
}
// A ViewportFrame's picture: its own little scene, drawn from its camera with the frame's lighting.
let vr = null
function picture(v, w, h) {
  vr ??= new T.WebGLRenderer({ antialias: true, alpha: true, preserveDrawingBuffer: true })
  vr.outputColorSpace = T.SRGBColorSpace
  vr.toneMapping = T.ACESFilmicToneMapping
  vr.setPixelRatio(2)
  vr.setSize(w, h)
  const sc = new T.Scene()
  sc.add(new T.HemisphereLight(0xffffff, '#' + (v.ambient || 'aaafb9'), 1.6))
  const light = new T.DirectionalLight(0xffffff, 2)
  light.position.set(1, 2, 1.2)
  sc.add(light)
  addParts(sc, v.parts)
  const [x, y, z, a, b, c, d, e, f, g, hh, i] = v.cam.cf
  const cam = new T.PerspectiveCamera(v.cam.fov, w / h, 0.1, 5000)
  new T.Matrix4().set(a, b, c, x, d, e, f, y, g, hh, i, z, 0, 0, 0, 1).decompose(cam.position, cam.quaternion, cam.scale)
  vr.render(sc, cam)
  return vr.domElement.toDataURL()
}

function draw(node, into = ui, ox = 0, oy = 0) {
  if (node.visible === false) return
  const el = document.createElement('div')
  const [px, py, pw, ph] = node.abs
  Object.assign(el.style, { left: px - ox + 'px', top: py - oy + 'px', width: pw + 'px', height: ph + 'px' })
  const bg = fill(node)
  if (bg) el.style.background = bg
  if (node.corner != null) el.style.borderRadius = Math.min(node.corner, pw / 2, ph / 2) + 'px'
  // UIStroke borders sit outside the box, so a shadow ring rather than a CSS border.
  if (node.stroke && node.stroke[2] < 1) el.style.boxShadow = '0 0 0 ' + node.stroke[0] + 'px ' + rgba(node.stroke[1], node.stroke[2])
  if (node.rot) el.style.transform = 'rotate(' + node.rot + 'deg)'
  if (node.text) {
    const t = document.createElement('span')
    t.textContent = node.text
    Object.assign(t.style, { color: rgba(node.textColor, node.textT || 0), fontSize: node.textSize + 'px', fontFamily: FAMILY[node.font] || FAMILY.FredokaOne, fontWeight: node.font === 'Nunito' ? node.weight : 400, lineHeight: '1.15', textAlign: node.xAlign === 'Left' ? 'left' : node.xAlign === 'Right' ? 'right' : 'center', whiteSpace: node.wrapped ? 'normal' : 'pre', position: 'static', width: node.wrapped ? '100%' : 'auto' })
    el.style.justifyContent = node.xAlign === 'Left' ? 'flex-start' : node.xAlign === 'Right' ? 'flex-end' : 'center'
    el.style.alignItems = node.yAlign === 'Top' ? 'flex-start' : node.yAlign === 'Bottom' ? 'flex-end' : 'center'
    // Roblox's text stroke is an outline of that thickness around each letter.
    if (node.textStroke && node.textStroke[2] < 1) Object.assign(t.style, { webkitTextStroke: node.textStroke[0] * 2 + 'px ' + rgba(node.textStroke[1], node.textStroke[2]), paintOrder: 'stroke fill' })
    el.append(t)
  }
  if (node.viewport && node.viewport.cam && node.viewport.parts.length && pw > 4 && ph > 4) {
    const img = document.createElement('img')
    img.src = picture(node.viewport, pw, ph)
    Object.assign(img.style, { position: 'absolute', left: 0, top: 0, width: '100%', height: '100%' })
    el.append(img)
  }
  if (node.image && S.images?.[node.image.key] && node.image.t < 1) {
    // An ImageLabel: fitted like Roblox's ScaleType, tinted (ImageColor3 multiplies) when not white.
    const src = S.images[node.image.key]
    const fit = { Crop: 'cover', Fit: 'contain' }[node.image.scale] || 'fill'
    const wrap = document.createElement('div')
    Object.assign(wrap.style, { position: 'absolute', left: 0, top: 0, width: '100%', height: '100%', opacity: 1 - node.image.t, isolation: 'isolate' })
    const img = document.createElement('img')
    img.src = src
    Object.assign(img.style, { position: 'absolute', left: 0, top: 0, width: '100%', height: '100%', objectFit: fit })
    wrap.append(img)
    if (node.image.color && node.image.color.toLowerCase() !== 'ffffff') {
      const tint = document.createElement('div')
      const mask = { WebkitMaskImage: 'url(' + src + ')', maskImage: 'url(' + src + ')', WebkitMaskSize: '100% 100%', maskSize: '100% 100%' }
      Object.assign(tint.style, { position: 'absolute', left: 0, top: 0, width: '100%', height: '100%', background: '#' + node.image.color, mixBlendMode: 'multiply' }, mask)
      wrap.append(tint)
    }
    el.append(wrap)
  }
  if (node.clip) el.style.overflow = 'hidden'
  into.append(el)
  // Children nest inside so a clipping frame (a scrolling list) hides what runs past it.
  const kids = (Array.isArray(node.children) ? node.children : []).map((k, i) => [k, i]).sort((a, b) => (a[0].z ?? 1) - (b[0].z ?? 1) || a[1] - b[1])
  for (const [k] of kids) draw(k, el, px, py)
}
if (S.gui) {
  const nodes = [].concat(S.gui.nodes || S.gui)
  const boards = nodes.filter((n) => n.billboard)
  // Older dumps only had the bubble text; newer ones lay out each BillboardGui like a screen.
  if (!boards.length) for (const b of Array.isArray(S.gui.bubbles) ? S.gui.bubbles : []) {
    const v = new T.Vector3(...b.at).project(cam)
    if (v.z > 1) continue
    const x = (v.x + 1) / 2 * W - b.size[0] / 2, y = (1 - v.y) / 2 * H - b.size[1] / 2
    draw({ abs: [x, y, b.size[0], b.size[1]], bg: 'ffffff', bgT: 0, corner: 14, stroke: [3, '14213d', 0], text: b.text, textColor: '1b2a4a', textSize: 18 })
  }
  for (const b of boards) {
    const v = new T.Vector3(...b.at).project(cam)
    if (v.z > 1) continue
    const dx = (v.x + 1) / 2 * W - b.abs[2] / 2, dy = (1 - v.y) / 2 * H - b.abs[3] / 2
    const move = (n) => { if (n.abs) n.abs = [n.abs[0] + dx, n.abs[1] + dy, n.abs[2], n.abs[3]]; for (const c of Array.isArray(n.children) ? n.children : []) move(c) }
    move(b)
    draw(b)
  }
  for (const n of nodes) if (!n.billboard) draw(n)
}
await document.fonts.ready
await new Promise((r) => setTimeout(r, 300))
window.DONE = true
</script></body></html>`

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const [web, sceneFile, out, guiFile, cam] = process.argv.slice(2)
  await render({ web, scene: JSON.parse(readFileSync(sceneFile, 'utf8')), out, gui: guiFile && guiFile !== '-' ? JSON.parse(readFileSync(guiFile, 'utf8')) : null, camera: cam ? JSON.parse(cam) : undefined, ...(process.env.SIZE ? { width: +process.env.SIZE.split('x')[0], height: +process.env.SIZE.split('x')[1] } : {}) })
  console.log(`wrote ${out}`)
}
