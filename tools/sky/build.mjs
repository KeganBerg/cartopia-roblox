// Bakes the web game's free-view sky (Horizon.tsx's sky shader: the season's blues, golden hour,
// night with stars, and its puffy low-poly clouds) into Roblox skyboxes, one for each step of the
// town's day, for client/Horizon.luau to swap through as the clock turns.
//
//   node tools/sky/build.mjs <web repo>
//   node tools/sky/build.mjs --ids      only write SkyImages.luau again, with the ids uploaded since
//
// The shader and its colour keys are read from the web game's own Horizon.tsx, so the bake follows
// it. The sun, the moon and the golden glow on the sun's side are left out: Roblox draws its own sun
// where DayNight puts it, and its Atmosphere glare adds the glow round it, so they can't end up on
// different sides of the sky. The glow is baked instead as an even golden band round the horizon.
//
// Writes build/sky/*.png and build/sky/list.json for tools/models/upload.mjs ("sky:<name>"), and
// src/shared/Models/SkyImages.luau with the uploaded ids from tools/models/assets.json. Run it again
// after uploading to fill the ids in.
//
// Faces follow Roblox's skybox layout: Left, Back, Right, Front side by side as one upright strip
// (a cubemap's nx, pz, px, nz). Up and Down are a cubemap's py and ny turned a quarter turn, py
// clockwise and ny anticlockwise (Roblox's "Custom Skyboxes 101"), so Left meets Up's top edge and
// Down's bottom edge, Right meets Up's bottom and Down's top. (Up folded straight over Left's top,
// as the docs' unfolded picture looks, put both half a turn out: hard-edged squares overhead.)

import { createHash } from 'node:crypto'
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs'
import { createServer } from 'node:http'
import { createRequire } from 'node:module'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const HERE = dirname(fileURLToPath(import.meta.url))
const ROOT = resolve(HERE, '../..')
const idsOnly = process.argv[2] === '--ids'
const web = resolve(idsOnly ? 'web' : (process.argv[2] ?? 'web'))
const OUT = join(ROOT, 'build/sky')
mkdirSync(OUT, { recursive: true })
const SIZE = 1024

const season = readFileSync(join(ROOT, 'src/shared/Models/Catalog.luau'), 'utf8').match(/Catalog\.SEASON = "(\w+)"/)?.[1] ?? 'summer'

const { steps, list, faces } = idsOnly ? JSON.parse(readFileSync(join(OUT, 'steps.json'), 'utf8')) : await bake()

async function bake() {
  // The shader and colours, from the web game.
  const src = readFileSync(join(web, 'src/scene/Horizon.tsx'), 'utf8')
  const glsl = (name) => {
    const m = src.match(new RegExp(`const ${name} = /\\* glsl \\*/ \`([\\s\\S]*?)\``))
    if (!m) throw new Error(`Horizon.tsx has no ${name}`)
    return m[1]
  }
  const swap = (text, from, to) => {
    if (!text.includes(from)) throw new Error(`Horizon.tsx's sky shader changed: no "${from}"`)
    return text.replace(from, to)
  }
  const VERT = swap(glsl('SKY_VERT'), 'gl_Position.z = gl_Position.w * 0.99999;', '')
  let FRAG = glsl('SKY_FRAG')
  // The glow along the horizon, evenly all the way round (about what the sun's side shows, spread).
  FRAG = swap(FRAG, 'uDusk * pow(side, 2.5)', 'uDusk * 0.35')
  // No moon disc (the moon's glow goes with uMoonLit = 0, the sun with uSunCol = 0).
  FRAG = swap(FRAG, 'if (m > 0.998)', 'if (false)')
  const skyText = src.match(/const SKY = (\{[\s\S]*?\n\})\n/)?.[1]
  if (!skyText) throw new Error('Horizon.tsx has no SKY colours')
  const SKY = new Function('SEASON', `return ${skyText}`)(season)

  // The town clock (web game/clock.ts): d is how far the phase is from midnight (0 at midnight,
  // 0.5 at noon); dawn and dusk mirror each other.
  const clockSrc = readFileSync(join(web, 'src/game/clock.ts'), 'utf8')
  const easeSrc = clockSrc.match(/const ease = \((\w+): number\) => ([^\n]+)/)
  if (!easeSrc) throw new Error('clock.ts has no ease')
  const easeFn = new Function(easeSrc[1], `return ${easeSrc[2]}`)
  const night = (d) => (d <= 0.1 ? 1 : d >= 0.3 ? 0 : easeFn((0.3 - d) / 0.2))
  const dusk = (d) => easeFn(Math.max(0, 1 - Math.abs(d - 0.22) / 0.13))
  // The steps baked: plain day, through golden hour, to full night.
  const STEPS = [0.5, 0.33, 0.29, 0.25, 0.21, 0.17, 0.13, 0.09]
  // The sun's direction (web look.ts lightDir) only shades the clouds' bright sides here.
  const NOON = [25, 40, 15].map((v) => v / Math.hypot(25, 40, 15))
  function sunDir(d) {
    const x = Math.min(1, Math.max(0, (d - 0.2) / 0.3))
    const high = x * x * (3 - 2 * x)
    const el = ((22 + 43 * high) * Math.PI) / 180
    const az = Math.atan2(NOON[0], NOON[2]) - (1 - high) * 1.1
    const v = [Math.sin(az) * Math.cos(el), Math.sin(el), Math.cos(az) * Math.cos(el)]
    v[1] *= 1 - 0.75 * dusk(d)
    const l = Math.hypot(...v)
    return v.map((c) => c / l)
  }
  const steps = STEPS.map((d) => ({ d, night: night(d), dusk: dusk(d), sun: sunDir(d) }))

  // Each face: where the camera looks and which way is up in the picture (see the layout above;
  // Left looks along +x, so Back is +z, Right -x and Front -z).
  const FACES = {
    Lf: { look: [1, 0, 0], up: [0, 1, 0] },
    Bk: { look: [0, 0, 1], up: [0, 1, 0] },
    Rt: { look: [-1, 0, 0], up: [0, 1, 0] },
    Ft: { look: [0, 0, -1], up: [0, 1, 0] },
    Up: { look: [0, 1, 0], up: [1, 0, 0] },
    Dn: { look: [0, -1, 0], up: [-1, 0, 0] },
  }

  const req = createRequire(join(web, 'package.json'))
  const threeDir = dirname(req.resolve('three'))
  const files = { 'three.module.js': readFileSync(join(threeDir, 'three.module.js')), 'three.core.js': readFileSync(join(threeDir, 'three.core.js')) }
  files['bake.html'] = `<!doctype html><html><body style="margin:0">
  <script type="importmap">{"imports":{"three":"./three.module.js"}}</script>
  <script type="module">
  import * as T from 'three'
  const SKY = ${JSON.stringify(SKY)}
  const renderer = new T.WebGLRenderer({ antialias: true, preserveDrawingBuffer: true })
  renderer.setSize(${SIZE}, ${SIZE})
  renderer.toneMapping = T.NeutralToneMapping
  renderer.outputColorSpace = T.SRGBColorSpace
  document.body.append(renderer.domElement)
  const C = (h) => new T.Color(h)
  const mat = new T.ShaderMaterial({
    vertexShader: ${JSON.stringify(VERT)},
    fragmentShader: ${JSON.stringify(FRAG)},
    defines: { OCTAVES: 4, MOON_R: '0.0340' },
    side: T.BackSide, depthWrite: false, fog: false,
    uniforms: {
      uZenith: { value: new T.Color() }, uHorizon: { value: new T.Color() }, uGlow: { value: C(SKY.dusk.glow) }, uSunDir: { value: new T.Vector3() }, uSunCol: { value: new T.Color(0, 0, 0) },
      uMoonDir: { value: new T.Vector3(0, -1, 0) }, uCloudLit: { value: new T.Color() }, uCloudShade: { value: new T.Color() }, uNight: { value: 0 }, uDusk: { value: 0 }, uCover: { value: 0 },
      uTime: { value: 0 }, uDrift: { value: new T.Vector2() }, uMoonPhase: { value: 0 }, uMoonLit: { value: 0 }, uMoonFlip: { value: 1 },
    },
  })
  const scene = new T.Scene()
  scene.add(new T.Mesh(new T.SphereGeometry(10, 64, 32), mat))
  const cam = new T.PerspectiveCamera(90, 1, 0.1, 100)
  // As Horizon.tsx's Sky does each frame, for clear weather.
  window.bake = (step, look, up) => {
    const u = mat.uniforms, n = step.night, k = step.dusk
    u.uNight.value = n
    u.uDusk.value = k
    u.uZenith.value.copy(C(SKY.day.zenith)).lerp(C(SKY.night.zenith), n).lerp(C(SKY.dusk.zenith), k * (1 - n) * 0.8)
    u.uHorizon.value.copy(C(SKY.day.horizon)).lerp(C(SKY.night.horizon), n).lerp(C(SKY.dusk.horizon), k * (1 - n * 0.6))
    u.uCloudLit.value.copy(C(SKY.cloud.day)).lerp(C(SKY.cloud.night), n).lerp(C(SKY.cloud.dusk), k * (1 - n))
    u.uCloudShade.value.copy(C(SKY.cloud.dayShade)).lerp(C(SKY.cloud.nightShade), n).lerp(C(SKY.cloud.duskShade), k * (1 - n))
    u.uSunDir.value.set(...step.sun)
    cam.position.set(0, 0, 0)
    cam.up.set(...up)
    cam.lookAt(...look)
    renderer.render(scene, cam)
    return renderer.domElement.toDataURL('image/png')
  }
  // The horizon colour the far land fades into (Horizon.tsx: skyHorizon), for the Atmosphere.
  window.haze = (step) => {
    const n = step.night, k = step.dusk
    const z = C(SKY.day.zenith).lerp(C(SKY.night.zenith), n).lerp(C(SKY.dusk.zenith), k * (1 - n) * 0.8)
    return C(SKY.day.horizon).lerp(C(SKY.night.horizon), n).lerp(C(SKY.dusk.horizon), k * (1 - n * 0.6)).lerp(z, 0.18).getHexString()
  }
  window.READY = true
  </script></body></html>`

  const server = createServer((q, r) => {
    const f = decodeURIComponent(new URL(q.url, 'http://x').pathname).slice(1)
    if (!files[f]) return r.writeHead(404).end()
    r.writeHead(200, { 'content-type': f.endsWith('.js') ? 'text/javascript' : 'text/html' })
    r.end(files[f])
  })
  await new Promise((res) => server.listen(0, '127.0.0.1', res))
  const { chromium } = req('playwright')
  const browser = await chromium.launch({ ...(process.env.CHROMIUM ? { executablePath: process.env.CHROMIUM } : {}), args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'] })
  const page = await browser.newPage({ viewport: { width: SIZE, height: SIZE } })
  page.on('pageerror', (e) => console.error(e))
  page.on('console', (m) => m.type() === 'error' && console.error(m.text()))
  await page.goto(`http://127.0.0.1:${server.address().port}/bake.html`)
  await page.waitForFunction('window.READY === true', null, { timeout: 120000 })

  const list = []
  for (const [i, step] of steps.entries()) {
    step.haze = await page.evaluate((s) => window.haze(s), step)
    for (const [face, f] of Object.entries(FACES)) {
      const url = await page.evaluate(([s, l, u]) => window.bake(s, l, u), [step, f.look, f.up])
      const png = Buffer.from(url.split(',')[1], 'base64')
      const key = `${season}-${i}-${face}`
      const hash = createHash('sha1').update(png).digest('hex').slice(0, 8)
      const file = `${key}.png`
      writeFileSync(join(OUT, file), png)
      list.push({ key, name: `${key}-${hash}`, file, step: i, face })
    }
  }
  await browser.close()
  server.close()
  writeFileSync(join(OUT, 'list.json'), JSON.stringify(list, null, 1))
  writeFileSync(join(OUT, 'steps.json'), JSON.stringify({ steps, list, faces: Object.keys(FACES) }))
  return { steps, list, faces: Object.keys(FACES) }
}

const assets = JSON.parse(readFileSync(join(ROOT, 'tools/models/assets.json'), 'utf8'))
const id = (key) => assets[`sky:${list.find((e) => e.key === key).name}`] ?? 0
const r3 = (x) => Math.round(x * 1000) / 1000
const lines = [
  '--!strict',
  "-- Generated by tools/sky/build.mjs from the web game's sky (Horizon.tsx); do not edit.",
  `-- The ${season} sky through the town's day, as Roblox skyboxes. Each step is for a distance d of`,
  '-- the clock\'s phase from midnight (0 midnight, 0.5 noon; dawn mirrors dusk), with the colour',
  '-- the far land fades into. Image ids are 0 until tools/models/upload.mjs uploads them.',
  '',
  'return {',
  `\tSEASON = "${season}",`,
  '\tsteps = {',
  ...steps.map((s, i) => `\t\t{ d = ${s.d}, haze = "#${s.haze}", night = ${r3(s.night)}, dusk = ${r3(s.dusk)}, faces = { ${faces.map((f) => `${f} = ${id(`${season}-${i}-${f}`)}`).join(', ')} } },`),
  '\t},',
  '}',
  '',
]
writeFileSync(join(ROOT, 'src/shared/Models/SkyImages.luau'), lines.join('\n'))
console.log(`${list.length} sky faces for ${season}, ${list.filter((e) => assets[`sky:${e.name}`]).length} uploaded`)
