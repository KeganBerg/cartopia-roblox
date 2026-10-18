// Bakes the web game's Call Cards (src/ui/call-cards.css: an animated CSS scene per card) into
// pictures and motion Roblox can play, for client/CallCardArt.luau.
//
//   node tools/callcards/build.mjs <web repo>
//   node tools/callcards/build.mjs --ids      only write CallCardLooks.luau again, with the ids uploaded since
//
// Each card is drawn in a headless browser from the web's own CSS, at two card shapes (wide, like
// the picker's big card, and tall, like a Quick Race card), and taken apart into its layers: the
// card's backdrop, then each moving piece (rain, light beams, a spinning sunburst) as its own
// picture. Every moving piece in the web only animates transform and opacity, so the browser is
// asked where each piece is, how it's turned and scaled, and how see-through it is through its
// loop, and Roblox moves the picture the same way. Pieces Roblox can't move like that (a road
// scrolling inside a tilted 3D plane) are baked as a short flipbook instead. A still of each card
// (the web's .still, for pickers) and the ground a car stands on (.cc-ground) are baked too.
//
// The Showroom card takes the colour of whoever wears it: its tinted layers are baked in white and
// Roblox tints them (ImageColor3), the way the web mixes var(--cc) in.
//
// Pictures are packed into 1024x1024 sheets: build/callcards/*.png and build/callcards/list.json
// for tools/models/upload.mjs ("callcard:<name>"), and src/shared/CallCardLooks.luau with the
// uploaded ids from tools/models/assets.json. Run it again after uploading to fill the ids in.

import { createHash } from 'node:crypto'
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs'
import { createServer } from 'node:http'
import { createRequire } from 'node:module'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const HERE = dirname(fileURLToPath(import.meta.url))
const ROOT = resolve(HERE, '../..')
const idsOnly = process.argv[2] === '--ids'
const web = resolve(idsOnly ? 'web' : (process.argv[2] ?? 'web'))
const OUT = join(ROOT, 'build/callcards')
mkdirSync(OUT, { recursive: true })
const sharp = createRequire(join(ROOT, 'tools/models/package.json'))('sharp')

// The two card shapes baked (CSS px). A holder picks the nearer one and covers itself with it.
const SHAPES = { wide: [380, 210], tall: [240, 300] }
// Where the card sits in the page, with room round it for pieces bigger than the card.
const AT = [700, 560]
const VIEW = [2000, 1700]
const PAGE = 1024
const GAP = 2
// Stills are drawn at half size: they only ever show small (picker swatches, chips).
const STILL = 0.5

// Runs in the page: builds a card from the web's CSS and answers where its pieces are.
const PAGE_JS = String.raw`
const stage = document.getElementById('stage')
let holder, root, els, rects
const S = (el, k, v) => el.style.setProperty(k, v, 'important')
const anims = (el) => el.getAnimations()
const periodOf = (a) => {
  const t = a.effect.getComputedTiming()
  return Math.round(t.duration * (String(t.direction).startsWith('alternate') ? 2 : 1))
}
const gcd = (a, b) => (b ? gcd(b, a % b) : a)
const loopOf = (list) => {
  let p = 0
  for (const a of list) {
    const q = Math.round(periodOf(a) / 10) * 10
    p = p ? (p * q) / gcd(p, q) : q
  }
  // Loops that never line up: the longest one.
  return p > 30000 ? Math.max(...list.map(periodOf)) : p
}
const paints = (el) => {
  const cs = getComputedStyle(el)
  const alpha = (c) => { const m = c.match(/rgba?\(([^)]*)\)/); if (!m) return 1; const v = m[1].split(/[ ,\/]+/).filter(Boolean); return v.length > 3 ? parseFloat(v[3]) : 1 }
  return cs.backgroundImage !== 'none' || alpha(cs.backgroundColor) > 0 || cs.boxShadow !== 'none' ||
    ['Top', 'Right', 'Bottom', 'Left'].some((s) => parseFloat(cs['border' + s + 'Width']) > 0 && cs['border' + s + 'Style'] !== 'none')
}
const clipsKids = (el) => {
  const cs = getComputedStyle(el)
  return cs.overflow !== 'visible' || (cs.maskImage && cs.maskImage !== 'none') || (cs.webkitMaskImage && cs.webkitMaskImage !== 'none') || cs.clipPath !== 'none' || cs.filter !== 'none'
}
const is3d = (el) => { const t = getComputedStyle(el).transform; return t !== 'none' && !new DOMMatrix(t).is2D }
const reset = () => { for (const el of els) el.removeAttribute('style') }
const setTime = (list, t) => { for (const a of list) { a.pause(); a.currentTime = t + 1000 * periodOf(a) } }

function track(chain, from = root) {
  const list = chain.flatMap(anims)
  const P = list.length ? loopOf(list) : 0
  const step = chain.some((el) => getComputedStyle(el).animationTimingFunction.includes('steps'))
  const N = P ? (step ? 256 : 120) : 0
  const samples = []
  for (let k = 0; k <= N; k++) {
    if (P) setTime(list, (k / N) * P)
    let M = new DOMMatrix(), a = 1, parent = rects.get(from)
    for (const el of chain) {
      const r = rects.get(el), cs = getComputedStyle(el)
      const X = cs.transform === 'none' ? new DOMMatrix() : new DOMMatrix(cs.transform)
      const o = cs.transformOrigin.split(' ').map(parseFloat)
      M = M.translate(r.x - parent.x, r.y - parent.y).translate(o[0], o[1]).multiply(X).translate(-o[0], -o[1])
      a *= parseFloat(cs.opacity)
      parent = r
    }
    samples.push({ m: [M.a, M.b, M.c, M.d, M.e, M.f], a })
  }
  // A slant that never changes is baked into the picture; one that does is averaged.
  let hs = samples.map(({ m: [a, b, c, d] }) => (a * c + b * d) / (a * a + b * b))
  let shear = hs.reduce((x, y) => x + y, 0) / hs.length
  if (Math.abs(shear) < 0.005) shear = 0
  return { p: P / 1000, step, shear, spread: Math.max(...hs) - Math.min(...hs), samples }
}

window.cc = {
  mount(id, W, H, v, still) {
    for (const s of ['plain', 'tint', 'untinted']) document.getElementById(s).media = s === v ? 'all' : 'not all'
    stage.innerHTML = ''
    holder = document.createElement('div')
    holder.className = 'holder'
    holder.style.width = W + 'px'
    holder.style.height = H + 'px'
    root = document.createElement('span')
    root.className = 'cc cc-' + id + (still ? ' still' : '')
    for (const c of ['cc-c', 'cc-a', 'cc-b']) {
      const i = document.createElement('i')
      i.className = c
      for (const p of ['pb', 'pa']) { const b = document.createElement('b'); b.className = p; i.append(b) }
      root.append(i)
    }
    holder.append(root)
    stage.append(holder)
    els = [root, ...root.querySelectorAll('i, b')]
    // Where everything sits before any transform.
    for (const el of els) { S(el, 'animation', 'none'); S(el, 'transform', 'none') }
    rects = new Map(els.map((el) => { const r = el.getBoundingClientRect(); return [el, { x: r.x, y: r.y, w: r.width, h: r.height }] }))
    reset()
    const items = [{ kind: 'root', o: 0 }]
    const is = [...root.children].map((el, n) => ({ el, n, z: parseInt(getComputedStyle(el).zIndex) || 0 })).sort((a, b) => a.z - b.z || a.n - b.n)
    let o = 1
    for (const { el: i } of is) {
      const kids = [...i.children].filter(paints)
      const moving = kids.some((b) => anims(b).length)
      const flat3d = is3d(i) || kids.some(is3d)
      const idx = els.indexOf(i)
      // A still window that only clips (overflow), with pieces moving behind it: Roblox clips too.
      const cs = getComputedStyle(i)
      const onlyOverflow = cs.overflow !== 'visible' && cs.clipPath === 'none' && cs.filter === 'none' && (!cs.maskImage || cs.maskImage === 'none') && (!cs.webkitMaskImage || cs.webkitMaskImage === 'none')
      if (!flat3d && kids.length && moving && onlyOverflow && !anims(i).length) {
        const m = track([i]).samples[0].m
        const sx = Math.hypot(m[0], m[1]), sy = (m[0] * m[3] - m[1] * m[2]) / sx
        if (Math.abs(sx - 1) < 0.01 && Math.abs(sy - 1) < 0.01) {
          const r = rects.get(i), h = rects.get(root)
          const cx = m[0] * r.w / 2 + m[2] * r.h / 2 + m[4], cy = m[1] * r.w / 2 + m[3] * r.h / 2 + m[5]
          const clip = { cx, cy, w: r.w, h: r.h, r: Math.atan2(m[1], m[0]) * 180 / Math.PI }
          const ks = []
          if (paints(i)) ks.push({ idx, track: track([], i), o: 0 })
          for (const b of kids) ks.push({ idx: els.indexOf(b), track: track([b], i), o: 0 })
          items.push({ kind: 'clip', clip, kids: ks, o: o++ })
          continue
        }
      }
      if (flat3d || (kids.length && clipsKids(i) && moving)) {
        items.push({ kind: 'flip', idx, p: loopOf([i, ...kids].flatMap(anims)) / 1000, o: o++ })
        continue
      }
      if (kids.length && clipsKids(i)) {
        items.push({ kind: 'el', idx, group: true, track: track([i]), o: o++ })
        continue
      }
      // A piece turning inside a squashed parent (a spinning disc seen edge-on) slants differently
      // every frame, which Roblox can't do: a flipbook then.
      const kt = kids.map((b) => track([i, b]))
      if (kt.some((t) => t.spread > 0.05)) {
        items.push({ kind: 'flip', idx, p: loopOf([i, ...kids].flatMap(anims)) / 1000, o: o++ })
        continue
      }
      if (paints(i)) items.push({ kind: 'el', idx, track: track([i]), o: o++ })
      kids.forEach((b, n) => items.push({ kind: 'el', idx: els.indexOf(b), track: kt[n], o: o++ }))
    }
    return { items }
  },
  prep(opt) {
    reset()
    for (const a of document.getAnimations()) { a.pause(); a.currentTime = 0 }
    if (opt.root) {
      for (const el of els) if (el !== root) S(el, 'visibility', 'hidden')
      return
    }
    if (opt.all) return
    if (opt.flip != null) {
      const i = els[opt.flip]
      for (const el of els) if (el !== i && el.parentElement !== i) S(el, 'visibility', 'hidden')
      S(i, 'visibility', 'visible')
      setTime([i, ...i.children].flatMap(anims), opt.t * 1000)
      return
    }
    const t = els[opt.el]
    for (const el of els) { S(el, 'animation', 'none'); S(el, 'transform', 'none'); S(el, 'opacity', '1'); S(el, 'visibility', 'hidden'); if (el !== els[opt.el] || !opt.group) S(el, 'overflow', 'visible') }
    S(root, 'overflow', 'visible')
    S(root, 'contain', 'none')
    S(t, 'visibility', 'visible')
    if (opt.shear) { S(t, 'transform', 'matrix(1, 0, ' + opt.shear + ', 1, 0, 0)'); S(t, 'transform-origin', '0 0') }
    const parts = [t]
    if (opt.group) for (const b of t.children) { b.style.removeProperty('transform'); S(b, 'visibility', 'visible'); parts.push(b) }
    let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity
    for (const p of parts) { const r = p.getBoundingClientRect(); x0 = Math.min(x0, r.x); y0 = Math.min(y0, r.y); x1 = Math.max(x1, r.right); y1 = Math.max(y1, r.bottom) }
    const r = rects.get(t)
    return { x: x0, y: y0, w: x1 - x0, h: y1 - y0, ox: r.x, oy: r.y }
  },
  // The ground under a car (.cc-ground) on a 600x400 stage, its light in white, for a car 200px tall.
  ground() {
    stage.innerHTML = ''
    const g = document.createElement('div')
    g.className = 'gholder'
    g.style.cssText = '--H: 200px; --g: .7; --cc-glow: #ffffff'
    const i = document.createElement('i')
    i.className = 'cc-ground'
    g.append(i)
    stage.append(g)
    const r = i.getBoundingClientRect(), s = g.getBoundingClientRect()
    return { x: r.x, y: r.y, w: r.width, h: r.height, gx: s.x + 300, gy: s.y + 280, H: 200 }
  },
}
window.READY = true
`

const { data, list } = idsOnly ? JSON.parse(readFileSync(join(OUT, 'bake.json'), 'utf8')) : await bake()

async function bake() {
  const cssAll = readFileSync(join(web, 'src/ui/call-cards.css'), 'utf8')
  const cut = cssAll.indexOf("/* A tier's frame")
  if (cut < 0) throw new Error("call-cards.css changed: no \"A tier's frame\" section")
  // Pseudo-elements become real elements (b.pb, b.pa) so the browser can say where they are.
  const pseudo = (s) => s.replaceAll('::before', ' > b.pb').replaceAll('::after', ' > b.pa')
  const scenes = pseudo(cssAll.slice(0, cut))
  const groundRule = cssAll.match(/\.cc-ground \{[\s\S]*?\}\n/)?.[0]
  if (!groundRule) throw new Error('call-cards.css has no .cc-ground')
  const callSrc = readFileSync(join(web, 'src/game/callCards.ts'), 'utf8')
  const ids = [...callSrc.matchAll(/\{ id: (?:STOCK_CARD|'(\w+)'), name:/g)].map((m) => m[1] ?? 'showroom')
  // Where each card's ground is (--f), its light (--cc-glow) and bottom colour (--cc-base).
  const stage = {}
  for (const id of ids) {
    const rule = cssAll.match(new RegExp(`\\.cc-on-${id} \\{([^}]*)\\}`))?.[1] ?? ''
    stage[id] = { f: Number(rule.match(/--f:\s*([.\d]+)/)?.[1] ?? 0.7), glow: rule.match(/--cc-glow:\s*(#[0-9a-f]{6})/)?.[1] ?? null, base: rule.match(/--cc-base:\s*(#[0-9a-f]{6})/)?.[1] ?? '#0b1430' }
  }

  // The Showroom's tinted layers alone (var(--cc) in white) and its plain layers alone.
  const splitBg = (value, tint) => {
    const parts = []
    let depth = 0, from = 0
    for (let i = 0; i < value.length; i++) {
      const c = value[i]
      if (c === '(') depth++
      else if (c === ')') depth--
      else if (c === ',' && depth === 0) { parts.push(value.slice(from, i)); from = i + 1 }
    }
    parts.push(value.slice(from))
    const kept = parts.filter((p) => p.includes('var(--cc)') === tint)
    return kept.length ? kept.join(',') : 'none'
  }
  const variant = (tint) => scenes.replace(/(\.cc-showroom[^{]*\{)([^}]*)\}/g, (_, head, body) =>
    head + body.replace(/background:([^;}]*)/g, (__, v) => `background:${splitBg(v, tint)}`) + (tint ? '; --cc: #ffffff' : '') + '}')

  const page = `<!doctype html><html><head><style>
  html, body { margin: 0; background: transparent; }
  .holder { position: absolute; left: ${AT[0]}px; top: ${AT[1]}px; }
  .gholder { position: absolute; left: ${AT[0]}px; top: ${AT[1]}px; width: 600px; height: 400px; container-type: size; }
  </style>
  <style id="plain">${scenes}</style>
  <style id="tint" media="not all">${variant(true)}</style>
  <style id="untinted" media="not all">${variant(false)}</style>
  <style>${groundRule}</style>
  </head><body><div id="stage"></div><script>${PAGE_JS}</script></body></html>`
  const server = createServer((q, r) => r.writeHead(200, { 'content-type': 'text/html' }).end(page))
  await new Promise((res) => server.listen(0, '127.0.0.1', res))
  const req = createRequire(join(web, 'package.json'))
  const { chromium } = req('playwright')
  const browser = await chromium.launch(process.env.CHROMIUM ? { executablePath: process.env.CHROMIUM } : {})
  const pg = await browser.newPage({ viewport: { width: VIEW[0], height: VIEW[1] } })
  pg.on('pageerror', (e) => console.error(e))
  await pg.goto(`http://127.0.0.1:${server.address().port}/`)
  await pg.waitForFunction('window.READY === true')

  const images = [] // { buf, w, h, card } (packed later)
  let current = ''
  const hashes = new Map()
  const addImage = async (buf, scale = 1) => {
    const hash = createHash('sha1').update(buf).digest('hex')
    if (hashes.has(hash)) return hashes.get(hash)
    let img = sharp(buf)
    const meta = await img.metadata()
    let w = meta.width, h = meta.height
    // Bigger than a sheet (a huge spinning sunburst): drawn smaller, Roblox scales it back up.
    const fit = Math.min(1, (PAGE - 2 * GAP) / Math.max(w, h), scale)
    if (fit < 1) {
      w = Math.max(1, Math.round(w * fit)); h = Math.max(1, Math.round(h * fit))
      buf = await img.resize(w, h, { fit: 'fill' }).png().toBuffer()
    }
    const n = images.length
    images.push({ buf, w, h, card: current })
    hashes.set(hash, n)
    return n
  }
  // The box of pixels that aren't see-through, or null for an empty picture.
  const trim = async (buf) => {
    const { data: px, info } = await sharp(buf).ensureAlpha().raw().toBuffer({ resolveWithObject: true })
    let x0 = info.width, y0 = info.height, x1 = -1, y1 = -1
    for (let y = 0; y < info.height; y++) for (let x = 0; x < info.width; x++) {
      if (px[(y * info.width + x) * 4 + 3] > 1) { if (x < x0) x0 = x; if (x > x1) x1 = x; if (y < y0) y0 = y; if (y > y1) y1 = y }
    }
    if (x1 < 0) return null
    const w = x1 - x0 + 1, h = y1 - y0 + 1
    return { x: x0, y: y0, w, h, buf: await sharp(buf).extract({ left: x0, top: y0, width: w, height: h }).png().toBuffer() }
  }
  const shot = (clip) => pg.screenshot({ clip, omitBackground: true, animations: 'allow' })
  const clamp = (r) => {
    const x = Math.max(0, Math.floor(r.x)), y = Math.max(0, Math.floor(r.y))
    return { x, y, width: Math.min(VIEW[0], Math.ceil(r.x + r.w)) - x, height: Math.min(VIEW[1], Math.ceil(r.y + r.h)) - y }
  }

  // A piece Roblox moves: drawn flat (unturned, unfaded) with any fixed slant baked in, and where
  // its middle is, its size, turn and opacity through its loop.
  const moving = async (item, tint) => {
    const tr = item.track
    const box = await pg.evaluate(([idx, shear, group]) => window.cc.prep({ el: idx, shear, group }), [item.idx, tr.shear, item.group])
    const PAD = 40
    const clip = clamp({ x: box.x - PAD, y: box.y - PAD, w: box.w + 2 * PAD, h: box.h + 2 * PAD })
    if (clip.width <= 0 || clip.height <= 0) return null
    const t = await trim(await shot(clip))
    if (!t) return null
    // Picture pixel p -> the piece's own coordinates q = H^-1 (p + d), d = clip corner - layout corner.
    const dx = clip.x + t.x - box.ox, dy = clip.y + t.y - box.oy
    const layer = { o: item.o + (tint ? 0.5 : 0), img: await addImage(t.buf), tint, step: tr.step || undefined, p: tr.p }
    const ch = { cx: [], cy: [], w: [], h: [], r: [], a: [] }
    let lastR = null
    for (const s of tr.samples) {
      const [a, b, c, d, e, f] = s.m
      // L = M * H^-1, H = [[1, shear], [0, 1]].
      const la = a, lb = b, lc = c - a * tr.shear, ld = d - b * tr.shear
      let r = (Math.atan2(lb, la) * 180) / Math.PI
      if (lastR !== null) while (r - lastR > 180) r -= 360
      if (lastR !== null) while (r - lastR < -180) r += 360
      lastR = r
      const sx = Math.hypot(la, lb)
      const sy = (la * ld - lb * lc) / sx
      // The picture's middle, in the piece's coordinates, then on the card.
      const px = dx + t.w / 2, py = dy + t.h / 2
      const qx = px - tr.shear * py, qy = py
      ch.cx.push(a * qx + c * qy + e)
      ch.cy.push(b * qx + d * qy + f)
      ch.w.push(t.w * sx)
      ch.h.push(t.h * sy)
      ch.r.push(r)
      ch.a.push(s.a)
    }
    const TOL = { cx: 0.25, cy: 0.25, w: 0.25, h: 0.25, r: 0.15, a: 0.004 }
    for (const k of Object.keys(ch)) layer[k] = keys(ch[k], TOL[k], tr.step)
    return layer
  }

  const data = { shapes: SHAPES, still: STILL, cards: {}, ground: null }
  for (const id of ids) {
    current = id
    const card = { ...stage[id] }
    for (const [shape, [W, H]] of Object.entries(SHAPES)) {
      const variants = id === 'showroom' ? ['untinted', 'tint'] : ['plain']
      const layers = []
      for (const v of variants) {
        const tint = v === 'tint'
        const info = await pg.evaluate(([id, W, H, v]) => window.cc.mount(id, W, H, v), [id, W, H, v])
        for (const item of info.items) {
          if (item.kind === 'root') {
            await pg.evaluate(() => window.cc.prep({ root: true }))
            const buf = await shot({ x: AT[0], y: AT[1], width: W, height: H })
            if (!tint) card[shape] = { base: await addImage(buf), layers }
            else {
              const t = await trim(buf)
              if (t) layers.push({ o: 0.5, img: await addImage(t.buf), tint: true, cx: t.x + t.w / 2, cy: t.y + t.h / 2, w: t.w, h: t.h, r: 0, a: 1, p: 1 })
            }
            continue
          }
          if (item.kind === 'flip') {
            // The whole piece as the browser draws it on the card, frame by frame, cropped to
            // where it ever shows.
            const F = item.p ? Math.max(12, Math.min(24, Math.round(item.p * 30))) : 1
            const bufs = []
            for (let k = 0; k < F; k++) {
              await pg.evaluate(([idx, t]) => window.cc.prep({ flip: idx, t }), [item.idx, (k / F) * (item.p || 0)])
              bufs.push(await shot({ x: AT[0], y: AT[1], width: W, height: H }))
            }
            let box = null
            for (const buf of bufs) {
              const t = await trim(buf)
              if (t) box = box ? { x0: Math.min(box.x0, t.x), y0: Math.min(box.y0, t.y), x1: Math.max(box.x1, t.x + t.w), y1: Math.max(box.y1, t.y + t.h) } : { x0: t.x, y0: t.y, x1: t.x + t.w, y1: t.y + t.h }
            }
            if (!box) continue
            const rect = { left: box.x0, top: box.y0, width: box.x1 - box.x0, height: box.y1 - box.y0 }
            const frames = []
            for (const buf of bufs) frames.push(await addImage(await sharp(buf).extract(rect).png().toBuffer()))
            layers.push({ o: item.o + (tint ? 0.5 : 0), flip: frames, x: rect.left, y: rect.top, w: rect.width, h: rect.height, p: item.p || 1, tint })
            continue
          }
          if (item.kind === 'clip') {
            // A window the pieces inside move behind (the web's overflow: hidden), turned as the
            // web turns it; the pieces' motion is in the window's own coordinates.
            const kids = []
            for (const k of item.kids) {
              const l = await moving(k, tint)
              if (l) kids.push(l)
            }
            if (kids.length) layers.push({ o: item.o + (tint ? 0.5 : 0), clip: item.clip, kids, tint })
            continue
          }
          const l = await moving(item, tint)
          if (l) layers.push(l)
        }
      }
      layers.sort((x, y) => x.o - y.o)
      // The still (pickers): no motion at all, as the web's .still.
      await pg.evaluate(([id, W, H]) => window.cc.mount(id, W, H, 'plain', true), [id, W, H])
      await pg.evaluate(() => window.cc.prep({ all: true }))
      const still = await sharp(await shot({ x: AT[0], y: AT[1], width: W, height: H })).resize(Math.round(W * STILL), Math.round(H * STILL)).png().toBuffer()
      current = '~stills'
      card[shape].still = await addImage(still)
      current = id
    }
    data.cards[id] = card
    console.log(`${id}: ${card.wide.layers.length} + ${card.tall.layers.length} layers`)
  }
  // The ground a car stands on, its light in white for Roblox to tint.
  {
    const r = await pg.evaluate(() => window.cc.ground())
    const clip = clamp({ x: r.x - 40, y: r.y - 40, w: r.w + 80, h: r.h + 80 })
    const t = await trim(await shot(clip))
    data.ground = { img: (await addImage(t.buf)) + 1, H: r.H, x: clip.x + t.x - r.gx, y: clip.y + t.y - r.gy, w: t.w, h: t.h }
  }
  await browser.close()
  server.close()

  // Shelf-pack the pictures into sheets, a card at a time and tallest first, so a card's pictures
  // share as few sheets as possible.
  const sheets = []
  const place = (i) => {
    const im = images[i]
    for (const s of sheets.slice(-3)) {
      for (const sh of s.shelves) {
        if (im.h <= sh.h && im.h >= sh.h * 0.6 && sh.x + im.w + GAP <= PAGE) {
          im.at = { sheet: s.n, x: sh.x, y: sh.y }
          sh.x += im.w + GAP
          s.items.push(i)
          return
        }
      }
      if (s.top + im.h + GAP <= PAGE) {
        const sh = { y: s.top, h: im.h, x: GAP }
        s.shelves.push(sh)
        s.top += im.h + GAP
        im.at = { sheet: s.n, x: sh.x, y: sh.y }
        sh.x += im.w + GAP
        s.items.push(i)
        return
      }
    }
    sheets.push({ n: sheets.length, top: GAP, shelves: [], items: [] })
    place(i)
  }
  const byCard = new Map()
  images.forEach((im, i) => byCard.set(im.card, [...(byCard.get(im.card) ?? []), i]))
  // The stills first and together: a picker shows every card's at once.
  const groups = [...byCard.entries()].sort(([a], [b]) => (b === '~stills') - (a === '~stills')).map(([, v]) => v)
  for (const idxs of groups) for (const i of idxs.sort((a, b) => images[b].h - images[a].h)) place(i)
  const list = []
  for (const s of sheets) {
    const png = await sharp({ create: { width: PAGE, height: PAGE, channels: 4, background: { r: 0, g: 0, b: 0, alpha: 0 } } })
      .composite(s.items.map((i) => ({ input: images[i].buf, left: images[i].at.x, top: images[i].at.y })))
      .png({ compressionLevel: 9 }).toBuffer()
    const key = `sheet-${s.n}`
    const hash = createHash('sha1').update(png).digest('hex').slice(0, 8)
    writeFileSync(join(OUT, `${key}.png`), png)
    list.push({ key, name: `${key}-${hash}`, file: `${key}.png` })
  }
  data.images = images.map((im) => [im.at.sheet, im.at.x, im.at.y, im.w, im.h])
  writeFileSync(join(OUT, 'list.json'), JSON.stringify(list, null, 1))
  writeFileSync(join(OUT, 'bake.json'), JSON.stringify({ data, list }))
  return { data, list }
}

// A channel's samples (0..1 of the loop, evenly) as keys: one number when it never changes,
// else { t, v, t, v, ... } with the points a straight line between neighbours would give dropped.
function keys(vals, tol, step) {
  const n = vals.length - 1
  const lo = Math.min(...vals), hi = Math.max(...vals)
  const r = (x) => Math.round(x * 1000) / 1000
  if (hi - lo <= tol) return r((lo + hi) / 2)
  if (step) {
    // Held values: a key wherever it changes.
    const out = [0, r(vals[0])]
    for (let i = 1; i <= n; i++) if (Math.abs(vals[i] - vals[i - 1]) > tol) out.push(r(i / n), r(vals[i]))
    return out
  }
  const keep = new Array(n + 1).fill(false)
  keep[0] = keep[n] = true
  const rdp = (a, b) => {
    let worst = -1, at = -1
    for (let i = a + 1; i < b; i++) {
      const guess = vals[a] + ((vals[b] - vals[a]) * (i - a)) / (b - a)
      const off = Math.abs(vals[i] - guess)
      if (off > worst) { worst = off; at = i }
    }
    if (worst > tol) { keep[at] = true; rdp(a, at); rdp(at, b) }
  }
  rdp(0, n)
  const out = []
  for (let i = 0; i <= n; i++) if (keep[i]) out.push(r(i / n), r(vals[i]))
  return out
}

// ---- Luau ----
const assets = JSON.parse(readFileSync(join(ROOT, 'tools/models/assets.json'), 'utf8'))
// The image inside each uploaded decal where tools/models/resolve-images.mjs found it (else the
// game's server looks it up, see server/Pictures).
const imagesFile = join(ROOT, 'tools/models/images.json')
const resolved = existsSync(imagesFile) ? JSON.parse(readFileSync(imagesFile, 'utf8')) : {}
const sheetIds = list.map((e) => { const id = assets[`callcard:${e.name}`] ?? 0; return resolved[id] ?? id })
const lua = (v, ind = '') => {
  if (v === null || v === undefined) return 'nil'
  if (typeof v === 'number') return String(v)
  if (typeof v === 'boolean') return String(v)
  if (typeof v === 'string') return JSON.stringify(v)
  if (Array.isArray(v)) return `{ ${v.map((x) => lua(x, ind)).join(', ')} }`
  const ks = Object.keys(v).filter((k) => v[k] !== undefined && v[k] !== null)
  return `{ ${ks.map((k) => `${/^[a-z_]\w*$/i.test(k) ? k : `["${k}"]`} = ${lua(v[k], ind)}`).join(', ')} }`
}
// A layer as the Luau reads it: pictures counted from 1, loops rounded.
const r3 = (x) => Math.round(x * 1000) / 1000
const layerOut = (l) => {
  if (l.flip) return { flip: l.flip.map((i) => i + 1), x: l.x, y: l.y, w: l.w, h: l.h, p: r3(l.p), tint: l.tint || undefined }
  if (l.clip) return { clip: { cx: r3(l.clip.cx), cy: r3(l.clip.cy), w: r3(l.clip.w), h: r3(l.clip.h), r: r3(l.clip.r) }, kids: l.kids.map(layerOut), tint: l.tint || undefined }
  return { img: l.img + 1, tint: l.tint || undefined, step: l.step, p: r3(l.p), cx: l.cx, cy: l.cy, w: l.w, h: l.h, r: l.r, a: l.a }
}
const lines = [
  '--!strict',
  "-- Generated by tools/callcards/build.mjs from the web game's Call Cards (src/ui/call-cards.css); do not edit.",
  '-- Each card at two shapes (wide, tall; CSS px): its backdrop, its layers bottom to top and a',
  '-- half-size still. A picture is an index into `images` ({ sheet, x, y, w, h } in pixels of the',
  '-- sheet). A moving layer gives its middle (cx, cy), size (w, h), turn (r, degrees) and opacity',
  '-- (a) through its loop of p seconds: a number when fixed, else { t, value, t, value, ... } with t',
  '-- from 0 to 1 (`step`: hold each value instead of easing between). A flipbook layer plays its',
  '-- frames (pictures covering x, y, w, h of the card) evenly through p seconds. A clip layer is a',
  '-- window (middle cx, cy, size w, h, turned r) its kids move behind, in the window\'s own pixels.',
  '-- `tint` layers take the wearer\'s colour. The ground (CallCardGround) is for a car H px tall,',
  '-- placed from where its wheels touch.',
  '-- Sheet ids are 0 until tools/models/upload.mjs uploads them.',
  '',
  'return {',
  `\tsheets = ${lua(sheetIds)},`,
  `\tshapes = ${lua(data.shapes)},`,
  `\tstill = ${data.still},`,
  `\timages = {`,
  ...data.images.map((im) => `\t\t${lua(im)},`),
  '\t},',
  `\tground = ${lua(data.ground)},`,
  '\tcards = {',
]
for (const [id, c] of Object.entries(data.cards)) {
  lines.push(`\t\t${id} = {`)
  lines.push(`\t\t\tf = ${c.f}, glow = ${lua(c.glow)}, base = ${lua(c.base)},`)
  for (const shape of Object.keys(data.shapes)) {
    const s = c[shape]
    lines.push(`\t\t\t${shape} = {`)
    lines.push(`\t\t\t\tbase = ${s.base + 1}, still = ${s.still + 1},`)
    lines.push('\t\t\t\tlayers = {')
    for (const l of s.layers) lines.push(`\t\t\t\t\t${lua(layerOut(l))},`)
    lines.push('\t\t\t\t},')
    lines.push('\t\t\t},')
  }
  lines.push('\t\t},')
}
lines.push('\t},', '}', '')
const text = lines.join('\n')
writeFileSync(join(ROOT, 'src/shared/CallCardLooks.luau'), text)
console.log(`${Object.keys(data.cards).length} call cards, ${data.images.length} pictures on ${list.length} sheets, ${sheetIds.filter(Boolean).length} uploaded`)
