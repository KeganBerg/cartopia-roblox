// Makes the bold game page pictures, in the style of Roblox's big games: a close-up icon, thumbnails
// with a big caption each, and round badge art for the Bank's packs (one per pack, for the Store row
// and the purchase prompts). Everything is drawn from the web game's own art (public/splash: the
// car hero renders and their paint masks, the town and street renders; scripts/splash/wordmark.path)
// in the web game's Lilita One lettering.
// Writes store/icon.png, store/thumb-*.jpg and store/badges/<pack id>.png.
//
//   node tools/store/promo.mjs <web repo>     (needs Playwright; CHROMIUM= points at a browser)

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
mkdirSync(join(OUT, 'badges'), { recursive: true })

const globalRoot = execSync('npm root -g').toString().trim()
const { chromium } = createRequire(join(globalRoot, 'x.js'))('playwright')

const N = '#14213d'
const WM_PATH = readFileSync(join(web, 'scripts/splash/wordmark.path'), 'utf8').trim()
const FONT = `<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Lilita+One&display=swap">`

// A car's hero render in a paint: the render, with the paint multiplied in through its mask.
const car = (id, paint, style = '') =>
  `<div class="car" style="${style}"><img src="/splash/hero-${id}.webp"><i style="background:${paint};-webkit-mask:url(/splash/hero-${id}-mask.webp) 0 0/100% 100%"></i></div>`
// Side view (car-*.webp), the way the drag strip shows them.
const side = (id, paint, style = '') =>
  `<div class="car" style="${style}"><img src="/splash/car-${id}.webp"><i style="background:${paint};-webkit-mask:url(/splash/car-${id}-mask.webp) 0 0/100% 100%"></i></div>`

const wordmark = (style) => `<svg class="wm" style="${style}" viewBox="-70 170 4070 1150"><defs><linearGradient id="g" x1="0" y1="246" x2="0" y2="1195" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="#fff8d6"/><stop offset=".45" stop-color="#ffe066"/><stop offset="1" stop-color="#ffaa1a"/></linearGradient><path id="w" d="${WM_PATH}"/></defs><use href="#w" y="60" fill="${N}" stroke="${N}" stroke-width="120" stroke-linejoin="round"/><use href="#w" fill="url(#g)" stroke="${N}" stroke-width="120" stroke-linejoin="round" paint-order="stroke"/></svg>`

// Sparkles: four-point stars.
const star = (x, y, s, c = '#fff') =>
  `<svg style="position:absolute;left:${x}px;top:${y}px;width:${s}px;height:${s}px;filter:drop-shadow(0 0 ${s / 5}px rgba(255,255,255,.8))" viewBox="-10 -10 20 20"><path d="M0-10C1-2 2-1 10 0C2 1 1 2 0 10C-1 2-2 1-10 0C-2-1-1-2 0-10Z" fill="${c}"/></svg>`

const BASE = `
*{box-sizing:border-box}html,body{margin:0;overflow:hidden;font-family:'Lilita One',system-ui,sans-serif}
.sun{position:absolute;inset:0;overflow:hidden;background:radial-gradient(circle at var(--cx,50%) var(--cy,45%),#fff4c9,#ffc46b 28%,#ff9b5c 58%,#ef6f8e 85%,#b54a8f)}
.sun::before{content:"";position:absolute;left:calc(var(--cx,50%) - 150vmax);top:calc(var(--cy,45%) - 150vmax);width:300vmax;height:300vmax;background:repeating-conic-gradient(rgba(255,255,255,.22) 0 6deg,transparent 6deg 15deg)}
.car{position:absolute;isolation:isolate}
.car img{display:block;width:100%;filter:drop-shadow(0 .6vmin 0 ${N}) drop-shadow(0 0 .5vmin ${N})}
.car i{position:absolute;inset:0;mix-blend-mode:multiply}
.cap{position:absolute;left:0;right:0;text-align:center;color:#fff;letter-spacing:.02em;line-height:.95;
  -webkit-text-stroke:.22em ${N};paint-order:stroke fill;text-shadow:0 .09em 0 ${N},0 .2em .3em rgba(10,16,40,.45)}
.cap b{font-weight:400;background:linear-gradient(#fff8d6,#ffe066 45%,#ffaa1a);-webkit-background-clip:text;background-clip:text;color:transparent;-webkit-text-stroke:0}
.wm{position:absolute;filter:drop-shadow(0 6px 10px rgba(20,33,61,.35))}
.vig{position:absolute;inset:0;box-shadow:inset 0 0 18vmin rgba(10,16,40,.5);pointer-events:none}
`
// Two-layer caption: stroke under, gradient fill on top (background-clip text can't take a stroke).
const caption = (text, style, size) => `<div class="cap" style="font-size:${size}px;${style}">${text}</div><div class="cap" style="font-size:${size}px;${style};-webkit-text-stroke:0;text-shadow:none"><b>${text}</b></div>`

const page = (w, h, body, extra = '') => `<!doctype html><html><head><meta charset="utf-8">${FONT}<style>${BASE}html,body{width:${w}px;height:${h}px}${extra}</style></head><body>${body}</body></html>`

const PAGES = {}

// The icon: one car, close and big, bursting out of the sunburst.
PAGES.icon = page(512, 512, `<div class="sun" style="--cx:50%;--cy:38%"></div>
${car('hotshot', '#d32f2f', 'left:-46px;top:92px;width:604px;transform:rotate(-6deg)')}
${star(36, 40, 64)}${star(418, 70, 42)}${star(440, 22, 22)}${star(70, 140, 26)}
<div class="vig" style="box-shadow:inset 0 0 70px rgba(10,16,40,.45)"></div>`)

// Thumbnails: a big caption over the game's own art.
const FAN = [['vanta', '#00e5ff'], ['sturm', '#ff6d00'], ['kaze', '#ffd600'], ['hotshot', '#d32f2f'], ['gtr', '#ff6d00'], ['scatto', '#1e88e5'], ['firebolt', '#7c4dff']]
PAGES['thumb-1'] = page(1920, 1080, `<div class="sun" style="--cy:62%"></div>
${caption('COLLECT <span style="font-size:1.25em">65</span> CARS!', 'top:40px', 170)}
${FAN.map(([id, p], i) => {
  const k = i - 3
  const w = 560 - Math.abs(k) * 60
  return car(id, p, `left:${960 + k * 250 - w / 2}px;top:${440 + Math.abs(k) * 40}px;width:${w}px;z-index:${10 - Math.abs(k)};transform:rotate(${k * 2}deg)`)
}).join('')}
${star(120, 300, 90)}${star(1720, 320, 80)}${star(1600, 220, 40)}${star(260, 230, 40)}
<div class="vig"></div>`)

PAGES['thumb-2'] = page(1920, 1080, `<img src="/splash/town-summer-day.webp" style="position:absolute;left:-200px;top:-260px;width:2400px">
<div style="position:absolute;inset:0;background:linear-gradient(rgba(20,33,61,.55),rgba(20,33,61,0) 40%)"></div>
${caption('BUILD YOUR <b>OWN</b> TOWN!', 'top:44px', 170)}
${car('schoolbus', '#fbc02d', 'left:1240px;top:600px;width:620px')}
${star(1780, 560, 70)}<div class="vig"></div>`)

PAGES['thumb-3'] = page(1920, 1080, `<div style="position:absolute;inset:0;background:linear-gradient(#5ec8ff,#bfe9ff 55%)"></div>
<img src="/splash/street-summer-day.webp" style="position:absolute;left:-900px;top:300px;height:560px">
<div style="position:absolute;left:0;right:0;top:820px;bottom:0;background:linear-gradient(#59606b,#3d434c)"></div>
<div style="position:absolute;left:0;right:0;top:930px;height:16px;background:repeating-linear-gradient(90deg,#fff 0 90px,transparent 90px 170px)"></div>
${[0, 1, 2, 3, 4, 5].map((i) => `<div style="position:absolute;left:${-100 + i * 70}px;top:${640 + i * 50}px;width:${520 - i * 40}px;height:12px;border-radius:6px;background:rgba(255,255,255,.85)"></div>`).join('')}
${side('vanta', '#00e5ff', 'left:260px;top:600px;width:760px')}
${side('sturm', '#ff6d00', 'left:980px;top:700px;width:820px')}
${caption('RACE YOUR <b>FRIENDS!</b>', 'top:60px', 180)}
<div class="vig"></div>`)

PAGES['thumb-4'] = page(1920, 1080, `<div class="sun" style="--cx:30%;--cy:55%;--x:0"></div>
${wordmark('left:90px;top:330px;width:860px')}
${caption('PLAY FREE NOW!', 'left:60px;right:auto;width:920px;top:680px', 110)}
${car('hotshot', '#d32f2f', 'left:960px;top:240px;width:960px;transform:rotate(-4deg)')}
${star(1700, 180, 90)}${star(980, 200, 50)}<div class="vig"></div>`)

// Badges: a coin with a coloured rim and the pack's car, or its gems.
const gem = (x, y, s, c1, c2) => `<svg style="position:absolute;left:${x}px;top:${y}px;width:${s}px;height:${s}px;filter:drop-shadow(0 6px 0 ${N})" viewBox="0 0 100 90"><path d="M20 4h60l18 26-48 56L2 30z" fill="${c1}" stroke="${N}" stroke-width="5" stroke-linejoin="round"/><path d="M2 30h96M20 4l14 26 16 56 16-56 14-26M34 30 50 4l16 26" fill="none" stroke="${c2}" stroke-width="3" stroke-linejoin="round"/><path d="M24 10h20l-8 16H14z" fill="#fff" opacity=".55"/></svg>`
const badge = (rim, inner, content) => page(512, 512, `
<div style="position:absolute;left:16px;top:16px;width:480px;height:480px;border-radius:50%;background:${N}"></div>
<div style="position:absolute;left:30px;top:30px;width:452px;height:452px;border-radius:50%;background:conic-gradient(from 200deg,${rim[0]},${rim[1]},${rim[0]})"></div>
<div style="position:absolute;left:58px;top:58px;width:396px;height:396px;border-radius:50%;overflow:hidden;background:radial-gradient(circle at 50% 35%,${inner[0]},${inner[1]});box-shadow:inset 0 0 0 8px ${N}">
<div style="position:absolute;left:-200px;top:-200px;width:800px;height:800px;background:repeating-conic-gradient(rgba(255,255,255,.16) 0 7deg,transparent 7deg 18deg)"></div></div>
${content}`, 'html,body{background:transparent}')

const PACKS = {
  handful: { gems: 1 }, stack: { gems: 2 }, bag: { gems: 3 }, vault: { gems: 4 }, truck: { gems: 5 }, tanker: { gems: 6, gold: true },
  'car-scatto': { car: 'scatto', paint: '#d32f2f' }, 'car-stinger': { car: 'stinger', paint: '#ffd600' },
  'car-thunderjet': { car: 'thunderjet', paint: '#1e88e5' }, 'car-sora': { car: 'sora', paint: '#e91e63' },
  'car-hayate': { car: 'hayate', paint: '#00c853' }, 'car-kestrel': { car: 'kestrel', paint: '#ff6d00' },
  'car-firebolt': { car: 'firebolt', paint: '#d50000', super: true }, 'car-kaze': { car: 'kaze', paint: '#ffd600', super: true },
  'car-sturm': { car: 'sturm', paint: '#ff6d00', super: true }, 'car-vanta': { car: 'vanta', paint: '#00e5ff', super: true },
}
// Two sparkles, kept inside the inner circle so a round crop never cuts them.
const SPARKLES = star(330, 112, 46) + star(132, 150, 28)
// A picture's size, from its WebP header (VP8X, lossy VP8 or lossless VP8L).
function webpSize(file) {
  const b = readFileSync(file)
  const kind = b.toString('ascii', 12, 16)
  if (kind === 'VP8X') return [1 + b.readUIntLE(24, 3), 1 + b.readUIntLE(27, 3)]
  if (kind === 'VP8 ') return [b.readUInt16LE(26) & 0x3fff, b.readUInt16LE(28) & 0x3fff]
  const bits = b.readUInt32LE(21)
  return [1 + (bits & 0x3fff), 1 + ((bits >> 14) & 0x3fff)]
}
// A car sized so its picture's corners stay inside the badge's inner circle (radius 198, less its
// 8px ring) and centred on it, a little low so the car sits on the circle's middle.
function badgeCar(id, paint) {
  const [w, h] = webpSize(join(web, 'public/splash', `hero-${id}.webp`))
  const R = 186
  const width = Math.round((2 * R * w) / Math.hypot(w, h))
  const height = (width * h) / w
  return car(id, paint, `left:${Math.round(256 - width / 2)}px;top:${Math.round(266 - height / 2)}px;width:${width}px`)
}
for (const [id, p] of Object.entries(PACKS)) {
  if (p.car) {
    const rim = p.super ? ['#ffd54f', '#ff6f00'] : ['#64b5f6', '#1565c0']
    const inner = p.super ? ['#fff3c4', '#ff8a3d'] : ['#d6f0ff', '#4aa3f0']
    PAGES[`badges/${id}`] = badge(rim, inner, badgeCar(p.car, p.paint) + (p.super ? SPARKLES : ''))
  } else {
    const rim = p.gold ? ['#ffe082', '#ff8f00'] : ['#80deea', '#00838f']
    const n = p.gems
    // A bigger pile of gems for each bigger pack.
    const spots = [
      [[156, 136, 200]],
      [[110, 160, 170], [236, 150, 170]],
      [[90, 200, 150], [262, 200, 150], [176, 120, 160]],
      [[80, 230, 130], [190, 240, 130], [300, 230, 130], [184, 130, 140]],
      [[70, 250, 120], [180, 262, 120], [290, 250, 120], [124, 150, 130], [240, 150, 130]],
      [[70, 260, 112], [174, 272, 112], [282, 260, 112], [118, 170, 120], [230, 170, 120], [174, 82, 128]],
    ][n - 1]
    // The pile, shrunk to fit the inner circle and centred on it (a gem is s wide, 0.9 s tall).
    const x0 = Math.min(...spots.map((g) => g[0])), x1 = Math.max(...spots.map((g) => g[0] + g[2]))
    const y0 = Math.min(...spots.map((g) => g[1])), y1 = Math.max(...spots.map((g) => g[1] + 0.9 * g[2]))
    const k = Math.min(1, 300 / Math.max(x1 - x0, y1 - y0))
    const at = (v, from, to, mid) => mid + (v - (from + to) / 2) * k
    const gems = spots.map(([x, y, s]) => gem(at(x, x0, x1, 256), at(y, y0, y1, 262), s * k, '#00e5ff', '#b2ffff')).join('')
    const extra = n > 3 ? SPARKLES : ''
    PAGES[`badges/${id}`] = badge(rim, p.gold ? ['#fff8e1', '#ffb300'] : ['#e0fbff', '#26c6da'], gems + extra)
  }
}

const TYPES = { '.html': 'text/html', '.webp': 'image/webp', '.png': 'image/png', '.svg': 'image/svg+xml', '.jpg': 'image/jpeg' }
const server = createServer((req, res) => {
  const path = decodeURIComponent(new URL(req.url, 'http://x').pathname)
  if (path.startsWith('/__/')) return res.writeHead(200, { 'content-type': 'text/html' }).end(PAGES[path.slice(4)])
  const file = join(web, 'public', normalize(path))
  if (!file.startsWith(join(web, 'public')) || !existsSync(file)) return res.writeHead(404).end()
  res.writeHead(200, { 'content-type': TYPES[extname(file)] ?? 'application/octet-stream' }).end(readFileSync(file))
})
await new Promise((r) => server.listen(0, r))
const base = `http://127.0.0.1:${server.address().port}`

const only = process.argv[3]
const browser = await chromium.launch({ executablePath: process.env.CHROMIUM || undefined })
try {
  for (const name of Object.keys(PAGES).filter((n) => !only || n.includes(only))) {
    const big = name.startsWith('thumb')
    const page = await browser.newPage({ viewport: big ? { width: 1920, height: 1080 } : { width: 512, height: 512 } })
    await page.goto(`${base}/__/${name}`)
    await page.evaluate(() => document.fonts.ready)
    await page.waitForFunction(() => [...document.images].every((i) => i.complete && i.naturalWidth))
    const file = join(OUT, big ? `${name}.jpg` : `${name}.png`)
    await page.screenshot(big ? { path: file, type: 'jpeg', quality: 90 } : { path: file, omitBackground: name.startsWith('badges') })
    await page.close()
    console.log(file.slice(ROOT.length + 1))
  }
} finally {
  await browser.close()
  server.close()
}
