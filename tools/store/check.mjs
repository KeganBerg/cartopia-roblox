// Prints what the Roblox game page shows now: the icon (and whether moderation has approved it)
// and the thumbnails. The pictures themselves (store/, made by tools/store/shoot.mjs) are uploaded
// by hand in the Creator Dashboard (Configurations > Places > start place > Icon / Thumbnails):
// Open Cloud can't set the game's own-language icon or thumbnails (the game-internationalization
// endpoints answer "You can't update translations for source language", legacy-publish is 404).
//
//   API_KEY=<key> UNIVERSE=<id> node tools/store/check.mjs
//
// It also saves the pictures Roblox is serving into build/game-page/; the workflow pushes them
// to the game-page-check branch so they can be looked at.

import { mkdirSync, writeFileSync } from 'node:fs'

const KEY = process.env.API_KEY
const GAME = process.env.UNIVERSE || '10771588518'
const API = `https://apis.roblox.com/legacy-game-internationalization/v1`
if (!KEY) throw new Error('API_KEY is not set')
const headers = { 'x-api-key': KEY }

async function get(url) {
  const res = await fetch(url, { headers })
  const text = await res.text()
  if (!res.ok) throw new Error(`HTTP ${res.status} ${text.replace(/\s+/g, ' ').slice(0, 300)}`)
  return JSON.parse(text)
}

async function save(name, url) {
  if (!url) return
  mkdirSync('build/game-page', { recursive: true })
  const res = await fetch(url)
  if (res.ok) writeFileSync(`build/game-page/${name}.png`, Buffer.from(await res.arrayBuffer()))
}

async function report() {
  const pub = await fetch(`https://thumbnails.roblox.com/v1/games/icons?universeIds=${GAME}&size=512x512&format=Png`).then((r) => r.json()).catch(() => null)
  console.log(`Public icon: ${JSON.stringify(pub?.data?.[0] ?? pub)}`)
  const thumbs = await fetch(`https://thumbnails.roblox.com/v1/games/multiget/thumbnails?universeIds=${GAME}&size=768x432&format=Png`).then((r) => r.json()).catch(() => null)
  console.log(`Public thumbnails: ${JSON.stringify(thumbs?.data?.[0] ?? thumbs)}`)
  await save('icon', pub?.data?.[0]?.imageUrl)
  for (const [i, t] of (thumbs?.data?.[0]?.thumbnails ?? []).entries()) await save(`thumb-${i + 1}`, t.imageUrl)
  // The owner's view also says whether moderation has passed the icon.
  const icon = await get(`${API}/game-icon/games/${GAME}`).then((r) => JSON.stringify(r.data), (err) => err.message)
  console.log(`Icon (owner view): ${icon}`)
}

await report()
