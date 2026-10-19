// Makes the game page trailer (store/trailer.mp4): a 20 second, 1920x1080 clip in five scenes,
// drawn from the web game's own art the same way promo.mjs draws the thumbnails. The page is a CSS
// animation; every frame is set by hand (document.getAnimations() at that time) and screenshotted,
// so the video is smooth however slow the machine is. ffmpeg joins the frames.
//
//   node tools/store/trailer.mjs <web repo>     (needs Playwright and ffmpeg; CHROMIUM= points at a browser)

import { mkdirSync, readFileSync, existsSync, rmSync } from 'node:fs'
import { createServer } from 'node:http'
import { dirname, extname, join, resolve, normalize } from 'node:path'
import { createRequire } from 'node:module'
import { fileURLToPath } from 'node:url'
import { execSync, execFileSync } from 'node:child_process'
import { tmpdir } from 'node:os'

const HERE = dirname(fileURLToPath(import.meta.url))
const ROOT = resolve(HERE, '../..')
const web = resolve(process.argv[2] ?? 'web')
const FPS = 30
const SECONDS = 20
const FRAMES = join(tmpdir(), 'cartopia-trailer')
rmSync(FRAMES, { recursive: true, force: true })
mkdirSync(FRAMES, { recursive: true })

const globalRoot = execSync('npm root -g').toString().trim()
const { chromium } = createRequire(join(globalRoot, 'x.js'))('playwright')

const N = '#14213d'
const WM_PATH = readFileSync(join(web, 'scripts/splash/wordmark.path'), 'utf8').trim()
const wordmark = (cls) => `<svg class="wm ${cls}" viewBox="-70 170 4070 1150"><defs><linearGradient id="g${cls}" x1="0" y1="246" x2="0" y2="1195" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="#fff8d6"/><stop offset=".45" stop-color="#ffe066"/><stop offset="1" stop-color="#ffaa1a"/></linearGradient><path id="w${cls}" d="${WM_PATH}"/></defs><use href="#w${cls}" y="60" fill="${N}" stroke="${N}" stroke-width="120" stroke-linejoin="round"/><use href="#w${cls}" fill="url(#g${cls})" stroke="${N}" stroke-width="120" stroke-linejoin="round" paint-order="stroke"/></svg>`
const car = (id, paint, cls, kind = 'hero') =>
  `<div class="car ${cls}"><img src="/splash/${kind}-${id}.webp"><i style="background:${paint};-webkit-mask:url(/splash/${kind}-${id}-mask.webp) 0 0/100% 100%"></i></div>`
const cap = (text, cls) => `<div class="cap ${cls}">${text}</div>`

// Scenes: [start, end] in seconds; each fades in over 0.3 s.
const FAN = [['vanta', '#00e5ff'], ['sturm', '#ff6d00'], ['kaze', '#ffd600'], ['hotshot', '#d32f2f'], ['gtr', '#ff6d00'], ['scatto', '#1e88e5'], ['firebolt', '#7c4dff'], ['schoolbus', '#fbc02d'], ['sora', '#e91e63']]
const css = `
*{box-sizing:border-box}html,body{margin:0;width:1280px;height:720px;overflow:hidden;background:${N};font-family:'Lilita One',system-ui,sans-serif}
.scene{position:absolute;inset:0;overflow:hidden;opacity:0}
.sun{position:absolute;inset:0;overflow:hidden;background:radial-gradient(circle at 50% 55%,#fff4c9,#ffc46b 28%,#ff9b5c 58%,#ef6f8e 85%,#b54a8f)}
.sun::before{content:"";position:absolute;left:-1100px;top:-1300px;width:3480px;height:3480px;background:repeating-conic-gradient(rgba(255,255,255,.22) 0 6deg,transparent 6deg 15deg);animation:spin 20s linear both}
@keyframes spin{to{transform:rotate(90deg)}}
.car{position:absolute;isolation:isolate}
.car img{display:block;width:100%;filter:drop-shadow(0 4px 0 ${N}) drop-shadow(0 0 3px ${N})}
.car i{position:absolute;inset:0;mix-blend-mode:multiply}
.cap{position:absolute;left:0;right:0;text-align:center;color:#ffe066;font-size:104px;line-height:1;letter-spacing:.02em;
  -webkit-text-stroke:20px ${N};paint-order:stroke fill;text-shadow:0 9px 0 ${N},0 16px 26px rgba(10,16,40,.45)}
.wm{position:absolute;filter:drop-shadow(0 6px 10px rgba(20,33,61,.35))}
.vig{position:absolute;inset:0;box-shadow:inset 0 0 140px rgba(10,16,40,.5)}
@keyframes show{from{opacity:0}to{opacity:1}}
@keyframes pop{0%{transform:scale(.2) rotate(-8deg);opacity:0}60%{transform:scale(1.12) rotate(2deg);opacity:1}100%{transform:scale(1) rotate(0)}}
@keyframes drop{0%{transform:translateY(-140px) scale(.8);opacity:0}70%{transform:translateY(10px) scale(1.04);opacity:1}100%{transform:none}}
@keyframes slidein{from{transform:translateX(1200px) rotate(-6deg)}to{transform:translateX(0) rotate(-4deg)}}
@keyframes pan{from{transform:scale(1.15) translate(4%,3%)}to{transform:scale(1.35) translate(-4%,-3%)}}
@keyframes bob{0%,100%{transform:translateY(0)}50%{transform:translateY(-6px)}}
@keyframes street{from{transform:translateX(0)}to{transform:translateX(-2600px)}}
@keyframes zoom{from{transform:scale(1)}to{transform:scale(1.08)}}

/* 1: logo (0-3.2) */
#s1{animation:show .01s 0s both,show .3s 3.2s reverse both}
#s1 .wm{left:140px;top:150px;width:1000px;animation:pop .7s .2s both}
#s1 .hs{left:420px;top:390px;width:440px;animation:slidein .6s 1s both cubic-bezier(.2,1.3,.4,1)}
/* 2: town (3.2-7.2) */
#s2{animation:show .3s 3.2s both}
#s2 img.town{position:absolute;left:-200px;top:-220px;width:1680px;animation:pan 4.4s 3.2s linear both}
#s2 .cap{top:30px;animation:drop .5s 3.5s both}
/* 3: cars (7.2-11.4) */
#s3{animation:show .3s 7.2s both}
#s3 .cap{top:24px;animation:drop .5s 7.4s both}
/* 4: race (11.4-16.2) */
#s4{animation:show .3s 11.4s both;background:linear-gradient(#5ec8ff,#bfe9ff 55%)}
#s4 .strip{position:absolute;left:0;top:150px;height:390px;display:flex;animation:street 4.8s 11.4s linear both}
#s4 .strip img{height:390px}
#s4 .road{position:absolute;left:0;right:0;top:520px;bottom:0;background:linear-gradient(#59606b,#3d434c)}
#s4 .lane{position:absolute;left:0;width:5200px;top:610px;height:10px;background:repeating-linear-gradient(90deg,#fff 0 60px,transparent 60px 120px);animation:street 1.2s 11.4s linear 4 both}
#s4 .a{left:60px;top:370px;width:380px;animation:race-a 4.8s 11.4s both}
#s4 .b{left:60px;top:455px;width:400px;animation:race-b 4.8s 11.4s both}
@keyframes race-a{0%{transform:translateX(-600px)}30%{transform:translateX(120px)}70%{transform:translateX(380px)}100%{transform:translateX(560px)}}
@keyframes race-b{0%{transform:translateX(-700px)}30%{transform:translateX(160px)}70%{transform:translateX(420px)}100%{transform:translateX(800px)}}
#s4 .cap{top:30px;animation:drop .5s 11.6s both}
#s4 .win{top:150px;font-size:90px;color:#fff;animation:pop .5s 14.6s both}
/* 5: end (16.2-20) */
#s5{animation:show .3s 16.2s both}
#s5 .sun{background:radial-gradient(circle at 50% 50%,#ffd9a3,#ff9d6c 30%,#d4618f 62%,#6c4aa1)}
#s5 .wm{left:190px;top:60px;width:900px;animation:pop .7s 16.4s both}
#s5 .cap{top:310px;font-size:110px;animation:pop .5s 17.1s both}
#s5 .l{left:40px;top:450px;width:360px;animation:slidein .6s 17.5s both}
#s5 .r{left:880px;top:460px;width:350px;animation:slidein .6s 17.6s both}
`
const fan = FAN.map(([id, p], i) => {
  const k = i - 4
  const w = 330 - Math.abs(k) * 30
  return `<div style="position:absolute;left:${640 + k * 140 - w / 2}px;top:${250 + Math.abs(k) * 34}px;width:${w}px;z-index:${10 - Math.abs(k)};animation:pop .45s ${7.6 + (4 - Math.abs(k)) * 0.25 + (k > 0 ? 0.12 : 0)}s both">${car(id, p, '').replace('class="car "', 'class="car" style="position:relative"')}</div>`
}).join('')

const html = `<!doctype html><html><head><meta charset="utf-8"><link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Lilita+One&display=swap"><style>${css}</style></head><body>
<div class="scene" id="s1"><div class="sun"></div>${wordmark('a')}${car('hotshot', '#d32f2f', 'hs')}<div class="vig"></div></div>
<div class="scene" id="s2"><img class="town" src="/splash/town-summer-day.webp"><div class="vig"></div>${cap('BUILD YOUR TOWN!', '')}</div>
<div class="scene" id="s3"><div class="sun"></div>${fan}${cap('COLLECT 65 CARS!', '')}<div class="vig"></div></div>
<div class="scene" id="s4"><div class="strip"><img src="/splash/street-summer-day.webp"><img src="/splash/street-summer-day.webp"></div><div class="road"></div><div class="lane"></div>
${car('vanta', '#00e5ff', 'a', 'car')}${car('sturm', '#ff6d00', 'b', 'car')}${cap('RACE YOUR FRIENDS!', '')}${cap('WIN!', 'win')}<div class="vig"></div></div>
<div class="scene" id="s5"><div class="sun"></div>${wordmark('b')}${cap('PLAY FREE NOW!', '')}${car('hotshot', '#d32f2f', 'l')}${car('gtr', '#ff6d00', 'r')}<div class="vig"></div></div>
</body></html>`

const TYPES = { '.webp': 'image/webp', '.png': 'image/png' }
const server = createServer((req, res) => {
  const path = decodeURIComponent(new URL(req.url, 'http://x').pathname)
  if (path === '/') return res.writeHead(200, { 'content-type': 'text/html' }).end(html)
  const file = join(web, 'public', normalize(path))
  if (!file.startsWith(join(web, 'public')) || !existsSync(file)) return res.writeHead(404).end()
  res.writeHead(200, { 'content-type': TYPES[extname(file)] ?? 'application/octet-stream' }).end(readFileSync(file))
})
await new Promise((r) => server.listen(0, r))

const browser = await chromium.launch({ executablePath: process.env.CHROMIUM || undefined })
try {
  const page = await browser.newPage({ viewport: { width: 1280, height: 720 }, deviceScaleFactor: 1.5 })
  await page.goto(`http://127.0.0.1:${server.address().port}/`)
  await page.evaluate(() => document.fonts.ready)
  await page.waitForFunction(() => [...document.images].every((i) => i.complete && i.naturalWidth))
  for (let f = 0; f < FPS * SECONDS; f++) {
    await page.evaluate((ms) => document.getAnimations().forEach((a) => { a.pause(); a.currentTime = ms }), (f * 1000) / FPS)
    await page.screenshot({ path: join(FRAMES, `${String(f).padStart(4, '0')}.jpg`), type: 'jpeg', quality: 92 })
  }
} finally {
  await browser.close()
  server.close()
}
// A silent sound track too: some players won't take a video without one.
execFileSync('ffmpeg', ['-y', '-loglevel', 'error', '-framerate', String(FPS), '-i', join(FRAMES, '%04d.jpg'), '-f', 'lavfi', '-i', 'anullsrc=r=48000:cl=stereo',
  '-shortest', '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-crf', '18', '-preset', 'slow', '-c:a', 'aac', '-movflags', '+faststart', join(ROOT, 'store/trailer.mp4')])
console.log('store/trailer.mp4')
