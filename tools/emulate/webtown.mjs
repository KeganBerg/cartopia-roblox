// A picture of the web game's town with a given layout of buildings (levels and merges), to set
// beside the Roblox one (town.luau TOWN_FILE= and render.mjs). Runs the web game with Vite, puts
// the file's buildings on the starter town's roads and photographs it with Playwright.
//
//   node tools/emulate/webtown.mjs <web repo> <town.json> <out dir> [WxH ...]
//
// Writes <out dir>/web-town-<W>x<H>.png. CHROMIUM=<path> picks the browser.

import { mkdirSync } from 'node:fs'
import { createRequire } from 'node:module'
import { join, resolve } from 'node:path'

import { readFileSync } from 'node:fs'

const [webArg, townArg, outArg, ...sizes] = process.argv.slice(2)
const town = JSON.parse(readFileSync(townArg, 'utf8'))
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
for (const size of sizes.length ? sizes : ['1280x800', '844x390']) {
  const [width, height] = size.split('x').map(Number)
  const tab = await browser.newPage({ viewport: { width, height } })
  tab.on('pageerror', (e) => console.error(e.message))
  // Midday, as the Roblox previews are lit (the web's sky follows the clock).
  await tab.addInitScript(() => {
    const off = new Date('2026-10-18T13:00:00').getTime() - Date.now()
    const Real = Date
    const now = () => Real.now() + off
    class Shifted extends Real {
      constructor(...a) { super(...(a.length ? a : [now()])) }
      static now() { return now() }
    }
    window.Date = Shifted
  })
  await tab.goto(`http://127.0.0.1:${port}/`)
  await tab.waitForFunction(() => !!window.__game, null, { timeout: 60000 })
  await tab.waitForTimeout(2500)
  const dismiss = async () => {
    for (const name of ['Got it', "Let's go!", 'Nice!', 'Continue']) {
      const b = tab.getByRole('button', { name })
      if (await b.count()) await b.first().click({ force: true }).catch(() => {})
    }
  }
  await dismiss()
  await tab.evaluate((buildings) => {
    window.__game.setState({ tutorial: 99, level: 60, buildings: buildings })
  }, town.buildings)
  // Whatever opened on its own (the daily spin, a welcome back) closes.
  for (let i = 0; i < 4; i++) {
    await tab.waitForTimeout(+(process.env.WAIT ?? 2500))
    await dismiss()
    await tab.evaluate(() => window.__game.getState().closePanel())
    await tab.keyboard.press('Escape')
  }
  await tab.waitForTimeout(1500)
  await tab.screenshot({ path: join(out, `web-town-${size}.png`) })
  console.log(`wrote web-town-${size}.png`)
  await tab.close()
}
await browser.close()
await server.close()
