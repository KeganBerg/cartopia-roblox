// Sets the game page description (the start place's description, which Roblox shows for the
// experience) from store/description.txt, with Open Cloud's Update Place.
//
//   API_KEY=<key> UNIVERSE=<id> PLACE=<id> node tools/store/describe.mjs
//
// The key needs the "universe.place:write" permission.

import { readFileSync } from 'node:fs'
import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const HERE = dirname(fileURLToPath(import.meta.url))
const KEY = process.env.API_KEY
const GAME = process.env.UNIVERSE || '10771588518'
const PLACE = process.env.PLACE || '82604390904451'
if (!KEY) throw new Error('API_KEY is not set')
const description = readFileSync(resolve(HERE, '../../store/description.txt'), 'utf8').trim()
if (description.length > 1000) throw new Error(`the description is ${description.length} characters; Roblox allows 1000`)

const res = await fetch(`https://apis.roblox.com/cloud/v2/universes/${GAME}/places/${PLACE}?updateMask=description`, {
  method: 'PATCH',
  headers: { 'x-api-key': KEY, 'content-type': 'application/json' },
  body: JSON.stringify({ description }),
})
const text = await res.text()
if (!res.ok) {
  console.log(`::error::Roblox didn't take the description: HTTP ${res.status} ${text.replace(/\s+/g, ' ').slice(0, 300)}`)
  if (res.status === 401 || res.status === 403) console.log('::error::The ROBLOX_API_KEY needs the "universe.place:write" permission for this experience.')
  process.exit(1)
}
console.log(`Description set (${description.length} characters).`)
