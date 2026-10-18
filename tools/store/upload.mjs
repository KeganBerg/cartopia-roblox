// Puts the pictures tools/store/shoot.mjs made (store/icon.png, store/thumb-*.jpg) on the Roblox
// game page: the icon, and the thumbnails in name order, replacing whatever thumbnails are there.
// It first prints what the page shows now (icon state, thumbnail count) so a run's log also says
// why the page might still look blank (nothing uploaded yet, or a picture waiting for moderation).
//
//   API_KEY=<key> UNIVERSE=<id> node tools/store/upload.mjs [--check]
//
// The key needs the legacy "universe: manage" permission (scope legacy-universe:manage). With
// --check it only prints the current state.

import { readFileSync, readdirSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const HERE = dirname(fileURLToPath(import.meta.url))
const DIR = resolve(HERE, '../../store')
const KEY = process.env.API_KEY
const GAME = process.env.UNIVERSE || '10771588518'
const LANG = 'en'
const API = `https://apis.roblox.com/legacy-game-internationalization/v1`
if (!KEY) throw new Error('API_KEY is not set')
const headers = { 'x-api-key': KEY }

const oneLine = (text) => text.replace(/\s+/g, ' ').trim().slice(0, 400)
const sleep = (ms) => new Promise((r) => setTimeout(r, ms))

async function call(method, url, body, what) {
  for (let attempt = 1; ; attempt++) {
    const res = await fetch(url, { method, headers: body && !(body instanceof FormData) ? { ...headers, 'content-type': 'application/json' } : headers, body: body instanceof FormData ? body : body && JSON.stringify(body) })
    const text = await res.text()
    if (res.ok) return text ? JSON.parse(text) : {}
    if ((res.status === 429 || res.status >= 500) && attempt < 5) {
      await sleep(attempt * 5000)
      continue
    }
    const err = new Error(`${what}: HTTP ${res.status} ${oneLine(text)}`)
    err.status = res.status
    err.body = text
    throw err
  }
}

// The legacy endpoints take the picture as a multipart file; Roblox's docs don't name the field,
// so try the name the old web API used first, then the plain ones.
async function sendFile(url, file, what) {
  let last
  for (const field of ['request.files', 'files', 'file']) {
    const form = new FormData()
    form.append(field, new Blob([readFileSync(join(DIR, file))], { type: file.endsWith('.jpg') ? 'image/jpeg' : 'image/png' }), file)
    try {
      return await call('POST', url, form, what)
    } catch (err) {
      last = err
      if (!/File not present|"code":\s*46|\b46\b/i.test(err.body ?? '')) throw err
    }
  }
  throw last
}

async function report() {
  const pub = await fetch(`https://thumbnails.roblox.com/v1/games/icons?universeIds=${GAME}&size=512x512&format=Png`).then((r) => r.json()).catch(() => null)
  console.log(`Public icon: ${JSON.stringify(pub?.data?.[0] ?? pub)}`)
  const thumbs = await fetch(`https://thumbnails.roblox.com/v1/games/multiget/thumbnails?universeIds=${GAME}&size=768x432&format=Png`).then((r) => r.json()).catch(() => null)
  console.log(`Public thumbnails: ${JSON.stringify(thumbs?.data?.[0] ?? thumbs)}`)
  try {
    console.log(`Icon (owner view): ${JSON.stringify((await call('GET', `${API}/game-icon/games/${GAME}`, null, 'icon')).data)}`)
  } catch (err) {
    console.log(`Icon (owner view): ${err.message}`)
  }
  try {
    const list = await call('GET', `${API}/game-thumbnails/games/${GAME}/images`, null, 'thumbnails')
    console.log(`Thumbnails (owner view): ${JSON.stringify(list.data)}`)
    return list.data?.find((d) => d.languageCode === LANG)?.mediaAssets ?? []
  } catch (err) {
    console.log(`Thumbnails (owner view): ${err.message}`)
    return null
  }
}

const existing = await report()
if (process.argv.includes('--check')) process.exit(0)

try {
  await sendFile(`${API}/game-icon/games/${GAME}/language-codes/${LANG}`, 'icon.png', 'upload icon')
} catch (err) {
  if (err.status === 401 || err.status === 403) {
    console.log(`::error::Roblox refused the upload (HTTP ${err.status}). The ROBLOX_API_KEY needs the legacy "universe" permission with "manage" (legacy-universe:manage), for experience ${GAME}.`)
    process.exit(1)
  }
  throw err
}
console.log('Icon uploaded')

const ids = []
for (const file of readdirSync(DIR).filter((f) => /^thumb-.*\.jpg$/.test(f)).sort()) {
  const res = await sendFile(`${API}/game-thumbnails/games/${GAME}/language-codes/${LANG}/image`, file, `upload ${file}`)
  ids.push(Number(res.mediaAssetId))
  console.log(`${file} uploaded: ${res.mediaAssetId}`)
}
for (const old of existing ?? []) {
  const id = Number(old.id ?? old.mediaAssetId ?? old.imageId ?? old)
  if (!id || ids.includes(id)) continue
  await call('DELETE', `${API}/game-thumbnails/games/${GAME}/language-codes/${LANG}/images/${id}`, null, `delete old thumbnail ${id}`).catch((err) => console.log(err.message))
  console.log(`Old thumbnail ${id} removed`)
}
await call('POST', `${API}/game-thumbnails/games/${GAME}/language-codes/${LANG}/images/order`, { mediaAssetIds: ids }, 'order thumbnails')
console.log('Thumbnails ordered')
await report()
