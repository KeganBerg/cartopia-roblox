// Bakes the web game's currency icons (CoinIcon, BuckIcon, PartsIcon and FuelIcon in the web
// repo's src/ui/Icon.tsx) and the Drive button's car and town into one picture Roblox can show, so the HUD's coin, gem and parts pills
// draw the web's smooth vector art instead of emoji or shapes built from frames. Each icon is
// drawn ICON pixels square, side by side, with a pixel of clear space round it so neighbours
// never bleed in when Roblox scales it down.
// Writes build/icons/icons.png and build/icons/list.json for tools/models/upload.mjs
// ("icons:<name>"), and src/shared/IconImages.luau with the uploaded id from
// tools/models/assets.json. Run it again after uploading to fill the id in.
//
//   node tools/icons/build.mjs

import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs'
import { createHash } from 'node:crypto'
import { dirname, join, resolve } from 'node:path'
import { createRequire } from 'node:module'
import { fileURLToPath } from 'node:url'

const HERE = dirname(fileURLToPath(import.meta.url))
const ROOT = resolve(HERE, '../..')
const sharp = createRequire(join(ROOT, 'tools/models/package.json'))('sharp')
const OUT = join(ROOT, 'build/icons')
mkdirSync(OUT, { recursive: true })

const ICON = 128
const CELL = ICON + 4

// The web's drop shadow under each icon (theme.css .cur: drop-shadow(0 1px 0 rgba(0,0,0,.25))),
// in the icon's own 24-unit grid.
const shadow = (body) => `<filter id="d" x="-10%" y="-10%" width="120%" height="130%"><feDropShadow dx="0" dy="1" stdDeviation="0" flood-color="#000" flood-opacity=".25"/></filter><g filter="url(#d)">${body}</g>`

const teeth = [0, 45, 90, 135, 180, 225, 270, 315]
// Copied from src/ui/Icon.tsx in the web repo; keep them the same.
const SVG = {
  coin: `<circle cx="12" cy="12.8" r="10.5" fill="#b86e00"/>
<circle cx="12" cy="11.6" r="10.5" fill="#ffc533"/>
<circle cx="12" cy="11.6" r="7.6" fill="#ffd95c" stroke="#e8a20c" stroke-width="1.4"/>
<path d="M12.9 6.8v1a3 3 0 0 1 2.3 1.6l-1.5.8a1.6 1.6 0 0 0-1.6-.9c-.8 0-1.3.4-1.3.9 0 .6.6.8 1.7 1.1 1.7.4 3 1 3 2.7 0 1.3-1 2.3-2.6 2.5v1h-1.6v-1a3.2 3.2 0 0 1-2.6-1.8l1.5-.8a1.8 1.8 0 0 0 1.8 1.1c.9 0 1.4-.4 1.4-1s-.6-.8-1.8-1.1c-1.5-.4-2.8-1-2.8-2.6 0-1.2.9-2.2 2.4-2.5v-1Z" fill="#a35f00"/>`,
  bucks: `<path d="M7 3.5h10l5 6.2L12 21.8 2 9.7Z" fill="#0d5fb3" transform="translate(0 1)"/>
<path d="M7 3.5h10l5 6.2L12 21.8 2 9.7Z" fill="#35a8ff"/>
<path d="M7 3.5h10l5 6.2H2Z" fill="#8fd3ff"/>
<path d="m7 3.5 2.5 6.2L12 3.5l2.5 6.2L17 3.5M2 9.7h20M9.5 9.7 12 21.8l2.5-12.1" fill="none" stroke="#1676d2" stroke-width=".9" stroke-linejoin="round"/>
<path d="M8 5h2.3l-1.4 3.4L7 6.3Z" fill="#fff" opacity=".8"/>`,
  parts: `<g transform="translate(0 1)" fill="#4a5560">${teeth.map((a) => `<rect x="10" y="1" width="4" height="5" rx="1" transform="rotate(${a} 12 12)"/>`).join('')}<circle cx="12" cy="12" r="7.5"/></g>
<g fill="#a9b6c2">${teeth.map((a) => `<rect x="10" y="1" width="4" height="5" rx="1" transform="rotate(${a} 12 12)"/>`).join('')}<circle cx="12" cy="12" r="7.5"/></g>
<circle cx="12" cy="12" r="5.6" fill="#cfd8e0"/>
<circle cx="12" cy="12" r="2.8" fill="#4a5560"/>`,
  fuel: `<path d="M7 2.5h5l1.5 1.5H18a2 2 0 0 1 2 2V20a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V8.5Z" fill="#9b1c1c" transform="translate(0 1)"/>
<path d="M7 2.5h5l1.5 1.5H18a2 2 0 0 1 2 2V20a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V8.5Z" fill="#f04438"/>
<path d="M8.5 1.5h4v3h-4Z" fill="#3a4148"/>
<path d="M12 9.5c1.8 2.4 3 4 3 5.6a3 3 0 0 1-6 0c0-1.6 1.2-3.2 3-5.6Z" fill="#fff"/>
<path d="M6 9.2 8.6 6.5H17" stroke="#fff" stroke-opacity=".45" stroke-width="1.2" fill="none" stroke-linecap="round"/>`,
  // The HUD's Drive button (Roblox only, no web original): a red car side on, and the town it
  // takes you back to. Drawn here so they sit dead centre, which emoji glyphs don't.
  car: `<g transform="translate(0 -2.8)"><path d="M3 15.2c0-1.3.7-2.2 1.9-2.5l2.2-.6 2.6-3.3c.5-.6 1.2-.9 2-.9h3.6c.8 0 1.5.4 2 1l2.3 3 1.6.4c1.1.3 1.8 1.2 1.8 2.3v1.8c0 .6-.4 1-1 1H4c-.6 0-1-.4-1-1Z" fill="#a3161c" transform="translate(0 1)"/>
<path d="M3 15.2c0-1.3.7-2.2 1.9-2.5l2.2-.6 2.6-3.3c.5-.6 1.2-.9 2-.9h3.6c.8 0 1.5.4 2 1l2.3 3 1.6.4c1.1.3 1.8 1.2 1.8 2.3v1.8c0 .6-.4 1-1 1H4c-.6 0-1-.4-1-1Z" fill="#ef3e3e"/>
<path d="M8.6 12.1 10.6 9.6c.3-.3.6-.5 1-.5h1.6v3Zm5.8 0v-3h1.3c.4 0 .8.2 1 .5l1.9 2.5Z" fill="#bfe6ff"/>
<path d="M5 13.4h14" stroke="#fff" stroke-opacity=".35" stroke-width=".9" stroke-linecap="round"/>
<circle cx="7.6" cy="17.3" r="2.5" fill="#263238"/><circle cx="7.6" cy="17.3" r="1.1" fill="#cfd8dc"/>
<circle cx="16.6" cy="17.3" r="2.5" fill="#263238"/><circle cx="16.6" cy="17.3" r="1.1" fill="#cfd8dc"/>
<rect x="19.6" y="13.6" width="1.6" height="1.2" rx=".5" fill="#ffe082"/></g>`,
  town: `<g transform="translate(0 1)" fill="#1f3358"><rect x="2.5" y="10" width="6" height="11" rx="1"/><rect x="8" y="4" width="7" height="17" rx="1"/><rect x="14.5" y="8" width="7" height="13" rx="1"/></g>
<rect x="2.5" y="10" width="6" height="11" rx="1" fill="#5aa9ff"/>
<rect x="8" y="4" width="7" height="17" rx="1" fill="#ffb547"/>
<rect x="14.5" y="8" width="7" height="13" rx="1" fill="#4fd1c5"/>
<g fill="#fff" opacity=".85"><rect x="4" y="12" width="1.4" height="1.4" rx=".3"/><rect x="6" y="12" width="1.4" height="1.4" rx=".3"/><rect x="4" y="15" width="1.4" height="1.4" rx=".3"/><rect x="6" y="15" width="1.4" height="1.4" rx=".3"/>
<rect x="9.6" y="6.5" width="1.5" height="1.5" rx=".3"/><rect x="12" y="6.5" width="1.5" height="1.5" rx=".3"/><rect x="9.6" y="9.5" width="1.5" height="1.5" rx=".3"/><rect x="12" y="9.5" width="1.5" height="1.5" rx=".3"/><rect x="9.6" y="12.5" width="1.5" height="1.5" rx=".3"/><rect x="12" y="12.5" width="1.5" height="1.5" rx=".3"/>
<rect x="16" y="10.5" width="1.5" height="1.5" rx=".3"/><rect x="18.5" y="10.5" width="1.5" height="1.5" rx=".3"/><rect x="16" y="13.5" width="1.5" height="1.5" rx=".3"/><rect x="18.5" y="13.5" width="1.5" height="1.5" rx=".3"/></g>
<rect x="10.4" y="17" width="2.2" height="4" rx=".4" fill="#7a4a00"/>`,
}
const names = Object.keys(SVG)

const layers = []
for (const [i, name] of names.entries()) {
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="${ICON}" height="${ICON}">${shadow(SVG[name])}</svg>`
  const png = await sharp(Buffer.from(svg), { density: 72 * (ICON / 24) }).resize(ICON, ICON).png().toBuffer()
  layers.push({ input: png, left: i * CELL + 2, top: 2 })
}
const sheet = await sharp({ create: { width: CELL * names.length, height: CELL, channels: 4, background: { r: 0, g: 0, b: 0, alpha: 0 } } })
  .composite(layers)
  .png({ compressionLevel: 9 })
  .toBuffer()
const hash = createHash('sha1').update(sheet).digest('hex').slice(0, 8)
writeFileSync(join(OUT, 'icons.png'), sheet)
const entry = { key: 'icons', name: `icons-${hash}`, file: 'icons.png' }
writeFileSync(join(OUT, 'list.json'), JSON.stringify([entry], null, 1))

const assets = JSON.parse(readFileSync(join(ROOT, 'tools/models/assets.json'), 'utf8'))
const IMAGES = join(ROOT, 'tools/models/images.json')
const images = existsSync(IMAGES) ? JSON.parse(readFileSync(IMAGES, 'utf8')) : {}
const decal = assets[`icons:${entry.name}`]
const id = decal ? images[decal] ?? decal : 0
const lines = [
  '--!strict',
  '-- Generated by tools/icons/build.mjs from the web game\'s currency icons (ui/Icon.tsx); do not edit.',
  '-- sheet is 0 until tools/models/upload.mjs uploads it; the HUD then draws its own stand-ins.',
  '-- Each icon is size pixels square, at the given offset in the sheet.',
  '',
  'return {',
  `\tsheet = ${id},`,
  `\tsize = ${ICON},`,
  '\tat = {',
  ...names.map((n, i) => `\t\t${n} = Vector2.new(${i * CELL + 2}, 2),`),
  '\t},',
  '}',
  '',
]
writeFileSync(join(ROOT, 'src/shared/IconImages.luau'), lines.join('\n'))
console.log(`${names.length} icons, ${id ? 'uploaded' : 'not uploaded yet'}`)
