// Checks the Call Card bake: draws each card the way the web does (its own CSS, frozen at a moment)
// next to the way Roblox plays it back from build/callcards (the same sums client/CallCardArt.luau
// does: each layer's picture placed, turned, scaled and faded from its keys), at the same moment.
//
//   node tools/callcards/compare.mjs <web repo> <out.png> [seconds] [card ...]
//
// Rows are cards; columns are web wide | Roblox wide | web tall | Roblox tall.

import { readFileSync } from 'node:fs'
import { createServer } from 'node:http'
import { createRequire } from 'node:module'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const HERE = dirname(fileURLToPath(import.meta.url))
const ROOT = resolve(HERE, '../..')
const [webArg, out, tArg, ...only] = process.argv.slice(2)
const web = resolve(webArg ?? 'web')
const T = Number(tArg ?? 0.7)
const { data, list } = JSON.parse(readFileSync(join(ROOT, 'build/callcards/bake.json'), 'utf8'))
const css = readFileSync(join(web, 'src/ui/call-cards.css'), 'utf8')
const ids = only.length ? only : Object.keys(data.cards)
const TINT = '#5aa9ff'

const page = `<!doctype html><html><head><style>${css}
body { margin: 0; background: #e8edf5; font: 12px sans-serif; }
.row { display: flex; gap: 10px; padding: 6px 10px; align-items: flex-start; }
.row b { width: 90px; }
.box { position: relative; overflow: hidden; border-radius: 12px; background: #0b1430; flex: none; }
.p { position: absolute; left: 0; top: 0; transform-origin: 50% 50%; background-repeat: no-repeat; }
</style></head><body><div id="grid"></div><script>
const D = ${JSON.stringify(data)}
const SHEETS = ${JSON.stringify(list.map((e) => e.file))}
const ev = (k, u, step) => {
  if (typeof k === 'number') return k
  for (let i = 0; i + 2 < k.length; i += 2) {
    if (u < k[i + 2]) return step ? k[i + 1] : k[i + 1] + ((k[i + 3] - k[i + 1]) * (u - k[i])) / (k[i + 2] - k[i])
  }
  return k[k.length - 1]
}
function pic(parent, img, x, y, w, h, r, a, tint) {
  const [s, ix, iy, iw, ih] = D.images[img]
  const el = document.createElement('i')
  el.className = 'p'
  const sx = w / iw, sy = h / ih
  const url = 'url(' + SHEETS[s] + ')'
  const geo = { left: x + 'px', top: y + 'px', width: w + 'px', height: h + 'px', transform: 'rotate(' + r + 'deg)', opacity: a }
  const size = 1024 * sx + 'px ' + 1024 * sy + 'px', pos = -ix * sx + 'px ' + -iy * sy + 'px'
  if (tint) Object.assign(el.style, geo, { background: '${TINT}', maskImage: url, maskSize: size, maskPosition: pos, maskRepeat: 'no-repeat' })
  else Object.assign(el.style, geo, { backgroundImage: url, backgroundSize: size, backgroundPosition: pos })
  parent.append(el)
}
function layer(parent, l, t) {
  if (l.flip) {
    const u = (t % l.p) / l.p
    pic(parent, l.flip[Math.floor(u * l.flip.length) % l.flip.length], l.x, l.y, l.w, l.h, 0, 1, l.tint)
    return
  }
  if (l.clip) {
    const c = l.clip
    const win = document.createElement('div')
    Object.assign(win.style, { position: 'absolute', left: c.cx - c.w / 2 + 'px', top: c.cy - c.h / 2 + 'px', width: c.w + 'px', height: c.h + 'px', overflow: 'hidden', transform: 'rotate(' + c.r + 'deg)' })
    parent.append(win)
    for (const k of l.kids) layer(win, k, t)
    return
  }
  const u = (t % (l.p || 1)) / (l.p || 1)
  const w = ev(l.w, u, l.step), h = ev(l.h, u, l.step)
  pic(parent, l.img, ev(l.cx, u, l.step) - w / 2, ev(l.cy, u, l.step) - h / 2, w, h, ev(l.r, u, l.step), ev(l.a, u, l.step), l.tint)
}
function replay(id, shape, t) {
  const [W, H] = D.shapes[shape]
  const box = document.createElement('div')
  box.className = 'box'
  Object.assign(box.style, { width: W + 'px', height: H + 'px' })
  const s = D.cards[id][shape]
  pic(box, s.base, 0, 0, W, H, 0, 1)
  for (const l of s.layers) layer(box, l, t)
  return box
}
function real(id, shape) {
  const [W, H] = D.shapes[shape]
  const box = document.createElement('div')
  box.className = 'box'
  Object.assign(box.style, { width: W + 'px', height: H + 'px' })
  box.innerHTML = '<span class="cc cc-' + id + '" style="--cc: ${TINT}"><i class="cc-c"></i><i class="cc-a"></i><i class="cc-b"></i></span>'
  return box
}
const grid = document.getElementById('grid')
for (const id of ${JSON.stringify(ids)}) {
  const row = document.createElement('div')
  row.className = 'row'
  const b = document.createElement('b')
  b.textContent = id
  row.append(b, real(id, 'wide'), replay(id, 'wide', ${T}), real(id, 'tall'), replay(id, 'tall', ${T}))
  grid.append(row)
}
for (const a of document.getAnimations()) { a.pause(); a.currentTime = ${T} * 1000 }
window.READY = true
</script></body></html>`

const server = createServer((q, r) => {
  const f = decodeURIComponent(new URL(q.url, 'http://x').pathname).slice(1)
  if (f.endsWith('.png')) return r.writeHead(200, { 'content-type': 'image/png' }).end(readFileSync(join(ROOT, 'build/callcards', f)))
  r.writeHead(200, { 'content-type': 'text/html' }).end(page)
})
await new Promise((res) => server.listen(0, '127.0.0.1', res))
const { chromium } = createRequire(join(web, 'package.json'))('playwright')
const browser = await chromium.launch(process.env.CHROMIUM ? { executablePath: process.env.CHROMIUM } : {})
const pg = await browser.newPage({ viewport: { width: 1360, height: 400 } })
await pg.goto(`http://127.0.0.1:${server.address().port}/`)
await pg.waitForFunction('window.READY === true')
await pg.waitForTimeout(500)
await pg.screenshot({ path: out, fullPage: true, animations: 'allow' })
await browser.close()
server.close()
console.log(`wrote ${out}`)
