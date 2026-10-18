// Pictures of the web game's own Rusty's search (ui/Rescue.tsx SearchScreen over scene/RescueScene),
// to set beside the Roblox one (clicks.luau SHOTS=1 and render.mjs). Runs the web game with Vite,
// gives the town Rusty's, starts a search at a spot and photographs it with Playwright: as it
// opens, then with some spots searched.
//
//   node tools/emulate/webrescue.mjs <web repo> <out dir> [WxH ...]
//
// Writes <out dir>/web-rescue-<spot>-<W>x<H>-<step>.png. CHROMIUM=<path> picks the browser;
// SPOTS=suburbs,desert picks the spots.

import { mkdirSync } from 'node:fs'
import { createRequire } from 'node:module'
import { join, resolve } from 'node:path'

const [webArg, outArg, ...sizes] = process.argv.slice(2)
const web = resolve(webArg ?? 'web')
const out = resolve(outArg ?? 'build')
mkdirSync(out, { recursive: true })
const req = createRequire(join(web, 'package.json'))
const { createServer } = await import(req.resolve('vite'))
const server = await createServer({ root: web, server: { port: 0, host: '127.0.0.1' }, logLevel: 'error' })
await server.listen()
const port = server.httpServer.address().port
const { chromium } = req('playwright')
const browser = await chromium.launch({ ...(process.env.CHROMIUM ? { executablePath: process.env.CHROMIUM } : {}), args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'] })
const spots = (process.env.SPOTS ?? 'suburbs').split(',')
for (const size of sizes.length ? sizes : ['1280x800', '844x390']) {
  const [width, height] = size.split('x').map(Number)
  for (const spot of spots) {
    const tab = await browser.newPage({ viewport: { width, height } })
    tab.on('pageerror', (e) => console.error(e.message))
    // Midday, so the lot is lit as the Roblox previews are (the web's sky follows the clock).
    await tab.clock.setFixedTime(new Date('2026-10-18T13:00:00'))
    await tab.goto(`http://127.0.0.1:${port}/`)
    await tab.waitForFunction(() => !!window.__game, null, { timeout: 60000 })
    await tab.waitForTimeout(2500)
    const dismiss = async () => {
      for (const name of ['Got it', "Let's go!"]) {
        const b = tab.getByRole('button', { name })
        if (await b.count()) await b.first().click({ force: true }).catch(() => {})
      }
    }
    await dismiss()
    // A town with Rusty's and the money to search anywhere; the tutorial done.
    await tab.evaluate((spot) => {
      const g = window.__game
      const s = g.getState()
      const has = s.buildings.some((b) => b.def === 'rescue')
      const free = (x, z) => !s.buildings.some((b) => Math.abs(b.x - x) < 3 && Math.abs(b.z - z) < 3)
      let at = [0, 0]
      for (let x = -6; x < 12 && !has; x++) for (let z = -6; z < 12; z++) if (free(x, z)) { at = [x, z]; x = 99; break }
      g.setState({
        tutorial: 99, level: 30, coins: 1e6, bucks: 500,
        buildings: has ? s.buildings : [...s.buildings, { uid: 'rusty', def: 'rescue', x: at[0], z: at[1], rot: 0, level: 1 }],
      })
      g.getState().startSearch(spot)
      g.getState().openPanel('rescue')
    }, spot)
    await tab.waitForTimeout(+(process.env.INTRO ?? 9000))
    await dismiss()
    await tab.screenshot({ path: join(out, `web-rescue-${spot}-${size}-start.png`) })
    console.log(`wrote web-rescue-${spot}-${size}-start.png`)
    // Two spots searched: the truck drives to each and the tarp comes off.
    for (const i of [0, 2]) {
      await tab.evaluate((i) => window.__rescuePick?.(i), i)
      await tab.waitForTimeout(+(process.env.PICK ?? 6000))
    }
    await dismiss()
    await tab.screenshot({ path: join(out, `web-rescue-${spot}-${size}-found.png`) })
    console.log(`wrote web-rescue-${spot}-${size}-found.png`)
    await tab.close()
  }
}
await browser.close()
await server.close()
