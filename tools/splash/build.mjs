// Turns the web game's loading screen art (scripts/splash/build.mjs and public/splash/ in the web
// repo) into images Roblox can show, for the loading screen (src/first/LoadingScreen.luau):
//   - the "Cartopia" wordmark, from the web's own outline (scripts/splash/wordmark.path)
//   - the sunburst panel for each time of day, wide-screen and phone shapes (the web draws it with
//     CSS gradients, which Roblox doesn't have)
//   - the town renders for this season (the one tools/models/build.mjs baked into Catalog.SEASON)
//   - every car's hero render, and its paint layer: the render's own pixels inside the paint mask,
//     which Roblox tints with ImageColor3 the way the web multiplies the player's paint over it
//   - the dark edge the web puts round the screen
// Writes build/splash/*.png and build/splash/list.json for tools/models/upload.mjs, and
// src/first/SplashImages.luau with the uploaded ids from tools/models/assets.json
// ("splash:<name>"). Run it again after uploading to fill the ids in.
//
//   node tools/splash/build.mjs <web repo>

import { mkdirSync, readFileSync, readdirSync, writeFileSync } from 'node:fs'
import { createHash } from 'node:crypto'
import { dirname, join, resolve } from 'node:path'
import { createRequire } from 'node:module'
import { fileURLToPath } from 'node:url'

const HERE = dirname(fileURLToPath(import.meta.url))
const ROOT = resolve(HERE, '../..')
const sharp = createRequire(join(ROOT, 'tools/models/package.json'))('sharp')
const web = resolve(process.argv[2] ?? 'web')
const OUT = join(ROOT, 'build/splash')
mkdirSync(OUT, { recursive: true })

const N = '#14213d'
const season = readFileSync(join(ROOT, 'src/shared/Models/Catalog.luau'), 'utf8').match(/Catalog\.SEASON = "(\w+)"/)?.[1] ?? 'summer'

// The sun's colours by time of day (scripts/splash/build.mjs: --s1..--s4, --ray, --rim).
const SUN = {
  day: { s: ['#fff4c9', '#ffc46b', '#ff9b5c', '#ef6f8e'], ray: 'rgba(255,255,255,.2)', rim: 'rgba(255,255,255,.55)' },
  dusk: { s: ['#ffd9a3', '#ff9d6c', '#d4618f', '#6c4aa1'], ray: 'rgba(255,236,200,.16)', rim: 'rgba(255,255,255,.55)' },
  night: { s: ['#5a5fc0', '#3a3f96', '#262b6c', '#151a45'], ray: 'rgba(170,180,255,.1)', rim: 'rgba(160,175,255,.35)' },
}
// The panel's shape on each kind of screen: the web's .sun box and gradient centre, and the size
// the picture is drawn at (the ellipse's own proportions on a typical screen of that kind, so the
// rays aren't stretched). PAD is the margin round the ellipse for its rim and glow, as a share of
// the ellipse's size; LoadingScreen.luau sizes the picture with the same margin.
const SHAPES = {
  wide: { cx: 0.62, cy: 0.42, w: 716, h: 1024 },
  tall: { cx: 0.5, cy: 0.52, w: 1024, h: 970 },
}
const PAD = 0.06

function sunSvg(look, shape) {
  const { w, h, cx, cy } = shape
  const W = w * (1 + 2 * PAD)
  const H = h * (1 + 2 * PAD)
  const ox = w * PAD
  const oy = h * PAD
  const px = ox + cx * w
  const py = oy + cy * h
  // CSS "circle" gradients reach the farthest corner of the box.
  const far = Math.max(...[[0, 0], [w, 0], [0, h], [w, h]].map(([x, y]) => Math.hypot(x - cx * w, y - cy * h)))
  const rays = []
  const R = Math.hypot(W, H)
  for (let a = 0; a < 360; a += 15) {
    const p = (d) => `${px + R * Math.sin((d * Math.PI) / 180)},${py - R * Math.cos((d * Math.PI) / 180)}`
    rays.push(`<polygon points="${px},${py} ${p(a)} ${p(a + 6)}"/>`)
  }
  const rim = Math.min(w, h) * 0.012
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H}" viewBox="0 0 ${W} ${H}">
<defs>
<radialGradient id="g" gradientUnits="userSpaceOnUse" cx="${px}" cy="${py}" r="${far}">
<stop offset="0" stop-color="${look.s[0]}"/><stop offset=".3" stop-color="${look.s[1]}"/><stop offset=".62" stop-color="${look.s[2]}"/><stop offset="1" stop-color="${look.s[3]}"/>
</radialGradient>
<clipPath id="c"><ellipse cx="${W / 2}" cy="${H / 2}" rx="${w / 2}" ry="${h / 2}"/></clipPath>
<filter id="b" x="-20%" y="-20%" width="140%" height="140%"><feGaussianBlur stdDeviation="${Math.min(w, h) * 0.025}"/></filter>
</defs>
<ellipse cx="${W / 2}" cy="${H / 2 + rim}" rx="${w / 2 + rim}" ry="${h / 2 + rim}" fill="rgba(10,16,40,.45)" filter="url(#b)"/>
<ellipse cx="${W / 2}" cy="${H / 2}" rx="${w / 2 + rim}" ry="${h / 2 + rim}" fill="${look.rim}"/>
<g clip-path="url(#c)"><rect width="${W}" height="${H}" fill="url(#g)"/><g fill="${look.ray}">${rays.join('')}</g></g>
</svg>`
}

function wordmarkSvg() {
  const path = readFileSync(join(web, 'scripts/splash/wordmark.path'), 'utf8').trim()
  return `<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="1024" height="${Math.round((1024 * 1150) / 4070)}" viewBox="-70 170 4070 1150"><defs><linearGradient id="g" x1="0" y1="246" x2="0" y2="1195" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="#fff8d6"/><stop offset=".45" stop-color="#ffe066"/><stop offset="1" stop-color="#ffaa1a"/></linearGradient><path id="w" d="${path}"/></defs><use xlink:href="#w" y="60" fill="${N}" stroke="${N}" stroke-width="120" stroke-linejoin="round"/><use xlink:href="#w" fill="${N}" stroke="${N}" stroke-width="120" stroke-linejoin="round"/><use xlink:href="#w" fill="url(#g)"/></svg>`
}

// The web's inset shadow round the screen (box-shadow: inset 0 0 18vmin rgba(10,16,40,.45)).
function vignetteSvg() {
  return `<svg xmlns="http://www.w3.org/2000/svg" width="512" height="512"><defs><filter id="b" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="40"/></filter></defs><rect x="-60" y="-60" width="632" height="632" fill="none" stroke="rgba(10,16,40,.45)" stroke-width="150" filter="url(#b)"/></svg>`
}

const list = []
async function emit(key, image) {
  const png = await image.png({ compressionLevel: 9 }).toBuffer()
  const hash = createHash('sha256').update(png).digest('hex').slice(0, 16)
  const file = `${key}-${hash}.png`
  writeFileSync(join(OUT, file), png)
  list.push({ key, name: `${key}-${hash}`, file })
}

await emit('wordmark', sharp(Buffer.from(wordmarkSvg())))
await emit('vignette', sharp(Buffer.from(vignetteSvg())))
for (const [tod, look] of Object.entries(SUN)) {
  for (const [kind, shape] of Object.entries(SHAPES)) await emit(`sun-${tod}-${kind}`, sharp(Buffer.from(sunSvg(look, shape))))
  // Roblox shows images up to 1024 pixels on a side.
  const town = (f) => sharp(join(web, 'public/splash', f)).resize(1024, 1024, { fit: 'inside' })
  await emit(`town-${tod}-wide`, town(`town-${season}-${tod}.webp`))
  await emit(`town-${tod}-tall`, town(`town-${season}-${tod}-p.webp`))
}
const cars = readdirSync(join(web, 'public/splash'))
  .map((f) => f.match(/^hero-([a-z0-9]+)-mask\.webp$/)?.[1])
  .filter(Boolean)
  .sort()
const size = {}
for (const id of cars) {
  const hero = sharp(join(web, 'public/splash', `hero-${id}.webp`)).ensureAlpha()
  const { data, info } = await hero.clone().raw().toBuffer({ resolveWithObject: true })
  const mask = await sharp(join(web, 'public/splash', `hero-${id}-mask.webp`)).ensureAlpha().resize(info.width, info.height, { fit: 'fill' }).raw().toBuffer()
  const paint = Buffer.alloc(data.length)
  for (let i = 0; i < data.length; i += 4) {
    paint[i] = data[i]
    paint[i + 1] = data[i + 1]
    paint[i + 2] = data[i + 2]
    paint[i + 3] = Math.round((data[i + 3] * mask[i + 3]) / 255)
  }
  size[id] = [info.width, info.height]
  await emit(`car-${id}`, hero)
  await emit(`paint-${id}`, sharp(paint, { raw: { width: info.width, height: info.height, channels: 4 } }))
}
writeFileSync(join(OUT, 'list.json'), JSON.stringify(list, null, 1))

const assets = JSON.parse(readFileSync(join(ROOT, 'tools/models/assets.json'), 'utf8'))
const id = (key) => assets[`splash:${list.find((e) => e.key === key).name}`] ?? 0
const lines = [
  '--!strict',
  '-- Generated by tools/splash/build.mjs from the web game\'s loading screen art; do not edit.',
  '-- Image ids (0 until tools/models/upload.mjs uploads them; the loading screen then draws its own',
  `-- stand-ins). Town renders are for ${season}, the season baked into Shared.Models.Catalog.`,
  '',
  'return {',
  `\tSEASON = "${season}",`,
  `\tPAD = ${PAD},`,
  `\tSHAPES = { wide = { cx = ${SHAPES.wide.cx}, cy = ${SHAPES.wide.cy} }, tall = { cx = ${SHAPES.tall.cx}, cy = ${SHAPES.tall.cy} } },`,
  `\twordmark = ${id('wordmark')},`,
  `\tvignette = ${id('vignette')},`,
  '\tsun = {',
  ...Object.keys(SUN).map((t) => `\t\t${t} = { wide = ${id(`sun-${t}-wide`)}, tall = ${id(`sun-${t}-tall`)} },`),
  '\t},',
  '\ttown = {',
  ...Object.keys(SUN).map((t) => `\t\t${t} = { wide = ${id(`town-${t}-wide`)}, tall = ${id(`town-${t}-tall`)} },`),
  '\t},',
  '\t-- Each car\'s hero render and paint layer, and the render\'s size in pixels.',
  '\tcars = {',
  ...cars.map((c) => `\t\t${c} = { car = ${id(`car-${c}`)}, paint = ${id(`paint-${c}`)}, w = ${size[c][0]}, h = ${size[c][1]} },`),
  '\t},',
  '}',
  '',
]
writeFileSync(join(ROOT, 'src/first/SplashImages.luau'), lines.join('\n'))
console.log(`${list.length} splash images for ${season}, ${list.filter((e) => assets[`splash:${e.name}`]).length} uploaded`)
