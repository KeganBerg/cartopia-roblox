// Makes the pictures for the Roblox game page (the icon and the thumbnails) out of the web game's
// own loading screen: its sunburst, wordmark, town renders and car hero renders (scripts/splash/
// and public/splash/ in the web repo). The thumbnails are the web loading screen itself at
// 1920x1080 (a 1280x720 screen at 1.5x) with the loading pill hidden; the icon is the same sunburst, wordmark and car drawn
// square. Writes store/icon.png and store/thumb-*.jpg, which are uploaded by hand on the
// game page (see tools/store/check.mjs).
//
//   node tools/store/shoot.mjs <web repo>     (needs Playwright; CHROMIUM= points at a browser)

import { mkdirSync, readFileSync, existsSync } from 'node:fs'
import { createServer } from 'node:http'
import { dirname, extname, join, resolve, normalize } from 'node:path'
import { createRequire } from 'node:module'
import { fileURLToPath } from 'node:url'
import { execSync } from 'node:child_process'

const HERE = dirname(fileURLToPath(import.meta.url))
const ROOT = resolve(HERE, '../..')
const OUT = join(ROOT, 'store')
const web = resolve(process.argv[2] ?? 'web')
mkdirSync(OUT, { recursive: true })

const globalRoot = execSync('npm root -g').toString().trim()
const { chromium } = createRequire(join(globalRoot, 'x.js'))('playwright')

// One line per thumbnail, in the order they show on the game page.
const THUMBS = [
  { name: 'thumb-1', time: 0, season: 'fall', car: 'hotshot', color: '#d32f2f' },
  { name: 'thumb-2', time: 0.3, season: 'summer', car: 'gtr', color: '#1e88e5' },
  { name: 'thumb-3', time: 0.5, season: 'winter', car: 'lambo', color: '#43a047' },
  { name: 'thumb-4', time: 0, season: 'spring', car: 'schoolbus', color: '#fbc02d' },
]
const ICON = { car: 'hotshot', color: '#d32f2f' }

const N = '#14213d'
const WM_PATH = readFileSync(join(web, 'scripts/splash/wordmark.path'), 'utf8').trim()
const iconHtml = `<!doctype html><html><head><meta charset="utf-8"><style>
html,body{margin:0;width:512px;height:512px;overflow:hidden;background:#ef6f8e}
.sun{position:absolute;inset:0;background:radial-gradient(circle at 50% 40%,#fff4c9,#ffc46b 30%,#ff9b5c 62%,#ef6f8e)}
.sun::before{content:"";position:absolute;left:-256px;top:-307px;width:1024px;height:1024px;background:repeating-conic-gradient(rgba(255,255,255,.22) 0 6deg,transparent 6deg 15deg)}
.wm{position:absolute;left:26px;top:34px;width:460px;filter:drop-shadow(0 6px 10px rgba(20,33,61,.35))}
.car{position:absolute;left:50%;bottom:30px;width:440px;transform:translateX(-50%);isolation:isolate}
.car img{display:block;width:100%}
.paint{position:absolute;inset:0;mix-blend-mode:multiply;background:${ICON.color};-webkit-mask:url(/public/splash/hero-${ICON.car}-mask.webp) 0 0/100% 100%}
.car::after{content:"";position:absolute;left:4%;right:4%;bottom:-4%;height:26%;border-radius:50%;background:radial-gradient(closest-side,rgba(10,14,30,.55),rgba(10,14,30,0));z-index:-1}
</style></head><body><div class="sun"></div>
<svg class="wm" viewBox="-70 170 4070 1150"><defs><linearGradient id="g" x1="0" y1="246" x2="0" y2="1195" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="#fff8d6"/><stop offset=".45" stop-color="#ffe066"/><stop offset="1" stop-color="#ffaa1a"/></linearGradient><path id="w" d="${WM_PATH}"/></defs><use href="#w" y="60" fill="${N}" stroke="${N}" stroke-width="120" stroke-linejoin="round"/><use href="#w" fill="url(#g)" stroke="${N}" stroke-width="120" stroke-linejoin="round" paint-order="stroke"/></svg>
<div class="car"><img src="/public/splash/hero-${ICON.car}.webp"><div class="paint"></div></div></body></html>`

// Serves the web repo: "/" is index.html, "/splash/..." comes from public/, the game's own code
// is left out so the loading screen stays up.
const TYPES = { '.html': 'text/html', '.webp': 'image/webp', '.png': 'image/png', '.svg': 'image/svg+xml', '.js': 'text/javascript' }
const server = createServer((req, res) => {
  const path = decodeURIComponent(new URL(req.url, 'http://x').pathname)
  if (path === '/__icon.html') return res.writeHead(200, { 'content-type': 'text/html' }).end(iconHtml)
  const file = path === '/' ? join(web, 'index.html') : path.startsWith('/public/') ? join(web, normalize(path)) : join(web, 'public', normalize(path))
  if (!file.startsWith(web) || path.startsWith('/src/') || !existsSync(file)) return res.writeHead(404).end()
  res.writeHead(200, { 'content-type': TYPES[extname(file)] ?? 'application/octet-stream' }).end(readFileSync(file))
})
await new Promise((r) => server.listen(0, r))
const base = `http://127.0.0.1:${server.address().port}`

const browser = await chromium.launch({ executablePath: process.env.CHROMIUM || undefined })
try {
  for (const t of THUMBS) {
    const page = await browser.newPage({ viewport: { width: 1280, height: 720 }, deviceScaleFactor: 1.5, reducedMotion: 'reduce' })
    await page.addInitScript((c) => localStorage.setItem('cartopia-splash-car', JSON.stringify(c)), { model: t.car, color: t.color })
    await page.goto(`${base}/?time=${t.time}&season=${t.season}`)
    await page.addStyleTag({ content: '#splash .ld{display:none!important}' })
    await page.waitForSelector('#splash .town.on')
    await page.waitForSelector('#splash .car.on')
    await page.evaluate(() => document.fonts.ready)
    await page.waitForTimeout(900)
    await page.screenshot({ path: join(OUT, `${t.name}.jpg`), type: 'jpeg', quality: 90 })
    await page.close()
    console.log(`${t.name}.jpg`)
  }
  const page = await browser.newPage({ viewport: { width: 512, height: 512 } })
  await page.goto(`${base}/__icon.html`)
  await page.waitForFunction(() => [...document.images].every((i) => i.complete && i.naturalWidth))
  await page.screenshot({ path: join(OUT, 'icon.png') })
  console.log('icon.png')
} finally {
  await browser.close()
  server.close()
}
