// Pictures of the web game's own drag strip at each venue, to set beside the Roblox race screen's
// (clicks.luau SHOTS=1 and render.mjs). Mounts the web game's RaceScene on its own page with Vite
// and photographs it with Playwright, the cars held at a given distance down the strip.
//
//   node tools/emulate/webrace.mjs <web repo> <out dir> [dist in race metres] [venue...]
//
// Writes <out dir>/web-<venue>.png. CHROMIUM=<path> picks the browser.

import { mkdirSync, rmSync, writeFileSync } from 'node:fs'
import { createRequire } from 'node:module'
import { join, resolve } from 'node:path'

const [webArg, outArg, distArg, ...only] = process.argv.slice(2)
const web = resolve(webArg ?? 'web')
const out = resolve(outArg ?? 'build')
const dist = Number(distArg ?? 0)
const page = join(web, 'rbx-race-preview')
mkdirSync(page, { recursive: true })
mkdirSync(out, { recursive: true })
writeFileSync(join(page, 'index.html'), `<!doctype html><html><body style="margin:0;overflow:hidden"><div id="root" style="width:1280px;height:800px"></div><script type="module" src="./main.tsx"></script></body></html>`)
writeFileSync(join(page, 'main.tsx'), `
import { createRoot } from 'react-dom/client'
import { Canvas } from '@react-three/fiber'
import { RaceScene } from '../src/scene/RaceScene'
import { venue } from '../src/scene/venues'
import { CARS } from '../src/game/data'
import { TRACK } from '../src/game/race'
import { raceWeather } from '../src/game/weather'

const q = new URLSearchParams(location.search)
const v = venue(q.get('v') ?? 'main')
const d = Number(q.get('d') ?? 0)
const me = { current: { dist: d } }, them = { current: { dist: d * 0.97 } }
const car = CARS.find((c) => c.id === 'pocket') ?? CARS[0]
createRoot(document.getElementById('root')!).render(
  <Canvas camera={{ position: [0.4, 2.2, -4.2], fov: 55 }} gl={{ preserveDrawingBuffer: true }}>
    <RaceScene track={TRACK} me={me} them={them} mine={{ body: car.body, model: car.id, color: '#e53935' }} theirs={{ body: car.body, model: car.id, color: '#1e88e5' }} venue={v} weather={raceWeather(v.id, 'preview', 'clear')} night={false} />
  </Canvas>,
)
`)

const req = createRequire(join(web, 'package.json'))
const { createServer } = await import(req.resolve('vite'))
const server = await createServer({ root: web, server: { port: 0, host: '127.0.0.1' }, logLevel: 'error' })
await server.listen()
const port = server.httpServer.address().port
const { chromium } = req('playwright')
const browser = await chromium.launch({ ...(process.env.CHROMIUM ? { executablePath: process.env.CHROMIUM } : {}), args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'] })
const tab = await browser.newPage({ viewport: { width: 1280, height: 800 } })
tab.on('pageerror', (e) => console.error(e.message))
const venues = only.length ? only : ['main', 'beach', 'desert', 'snow', 'farm', 'docks']
for (const v of venues) {
  await tab.goto(`http://127.0.0.1:${port}/rbx-race-preview/index.html?v=${v}&d=${dist}`)
  // Long enough for the chase camera to settle behind the cars.
  await tab.waitForTimeout(9000)
  await tab.screenshot({ path: join(out, `web-${v}.png`) })
  console.log(`wrote web-${v}.png`)
}
await browser.close()
await server.close()
rmSync(page, { recursive: true, force: true })
