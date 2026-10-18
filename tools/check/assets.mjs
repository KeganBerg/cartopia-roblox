// Prints what Roblox says about the loading screen's pictures and a few ground textures: each
// asset's type, state and moderation verdict (Open Cloud Assets API), and the start of what
// asset delivery hands back for it (a decal comes back as a little model naming its image).
//
//   API_KEY=<key> node tools/check/assets.mjs [name filter]

import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const HERE = dirname(fileURLToPath(import.meta.url))
const assets = JSON.parse(readFileSync(join(HERE, '../models/assets.json'), 'utf8'))
const key = process.env.API_KEY
const filter = process.argv[2] ?? ''
const headers = { 'x-api-key': key }

const picks = Object.entries(assets).filter(([name]) =>
  filter ? name.includes(filter) : /^splash:(wordmark|vignette|sun-day|town-day|car-hotshot)/.test(name) || /^texture:/.test(name),
).slice(0, 30)

for (const [name, id] of picks) {
  const info = await fetch(`https://apis.roblox.com/assets/v1/assets/${id}?readMask=assetType,state,moderationResult,displayName`, { headers })
  const infoText = (await info.text()).replace(/\s+/g, ' ').slice(0, 300)
  const del = await fetch(`https://apis.roblox.com/asset-delivery-api/v1/assetId/${id}`, { headers })
  let delText = (await del.text()).replace(/\s+/g, ' ').slice(0, 300)
  let body = ''
  try {
    const loc = JSON.parse(delText).location
    if (loc) {
      const file = await fetch(loc)
      const buf = Buffer.from(await file.arrayBuffer())
      body = buf.subarray(0, 4).toString('hex') === '89504e47' ? `PNG ${buf.length} bytes` : buf.toString('utf8', 0, 400).replace(/\s+/g, ' ')
    }
  } catch {}
  console.log(`${name} ${id}\n  info ${info.status} ${infoText}\n  delivery ${del.status} ${delText}\n  file ${body}`)
}
