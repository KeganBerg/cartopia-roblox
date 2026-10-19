// Makes what the Bank sells on Roblox (server/Purchases), each named exactly like its pack: a
// Developer Product per gem pack, and a Game Pass per car pack (with its round badge,
// store/badges/<pack id>.png, as the icon) so car packs show in the game page's Store row. The Robux price comes from the web game's dollar price, turned
// into Robux at Roblox's own Robux store rates (tools/products/prices.json "match-dollars"), so a
// price change on the web carries over; prices.json overrides can fix a pack's price, or null stops
// selling it (taken off sale if it was). Existing products and passes are found by name and
// only changed when their price or sale state differs. The server finds the products by name too;
// a pass can't be looked up that way in game, so the passes' ids are written to
// src/shared/GamePasses.luau, which the "Bank products" workflow commits. A car pack's old
// Developer Product, if it has one, is taken off sale.
//
//   API_KEY=<key> UNIVERSE=<id> node tools/products/sync.mjs [--check]
//
// The key needs the "developer-product:read", "developer-product:write", "game-pass:read" and
// "game-pass:write" permissions. With --check it only prints what it would do.

import { readFileSync, writeFileSync } from 'node:fs'
import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const HERE = dirname(fileURLToPath(import.meta.url))
const KEY = process.env.API_KEY
const GAME = process.env.UNIVERSE || '10771588518'
const CHECK = process.argv.includes('--check')
const API = `https://apis.roblox.com/developer-products/v2/universes/${GAME}/developer-products`
const PASSES = `https://apis.roblox.com/game-passes/v1/universes/${GAME}/game-passes`
if (!KEY) throw new Error('API_KEY is not set')
const headers = { 'x-api-key': KEY }

const prices = JSON.parse(readFileSync(resolve(HERE, 'prices.json'), 'utf8'))
// The packs, read from the converted web module's Luau so this needs no TypeScript.
const luau = readFileSync(resolve(HERE, '../../src/shared/Game/bucksPacks.luau'), 'utf8')
const field = (block, k) => new RegExp(`\\b${k} = "?([^",\\n]+)"?`).exec(block)?.[1]
const PACKS = [...luau.matchAll(/\{([^{}]*)\}/g)].map((m) => m[1]).filter((b) => field(b, 'id') && field(b, 'bucks')).map((b) => ({
  id: field(b, 'id'), name: field(b, 'name'), usd: +field(b, 'price'), bucks: +field(b, 'bucks'), bonus: +field(b, 'bonus'), car: field(b, 'car'),
}))
// Every pack still sold (ALL_PACKS: the first copy of each id; RETIRED_PACKS come after and stay unsold).
const retired = luau.slice(luau.indexOf('RETIRED_PACKS'))
const sold = PACKS.filter((p, i, all) => all.findIndex((q) => q.id === p.id) === i && !new RegExp(`id = "${p.id}"`).test(retired))
if (prices.rule !== 'match-dollars') throw new Error(`prices.json: unknown rule ${prices.rule}`)
const unknown = Object.keys(prices.overrides ?? {}).filter((id) => !sold.some((p) => p.id === id))
if (unknown.length) throw new Error(`prices.json overrides name packs the game doesn't sell: ${unknown.join(', ')}`)

// Roblox's Robux store: what a player pays for that many Robux. Between two bundles the rate runs
// straight from one to the next; below the smallest it's the $4.99 rate. Rounded to 10 Robux.
const BUNDLES = [[0, 0], [4.99, 400], [9.99, 800], [19.99, 1700], [49.99, 4500], [99.99, 10000]]
export function robuxFor(usd) {
  let i = 1
  while (i < BUNDLES.length - 1 && usd > BUNDLES[i][0]) i++
  const [x0, y0] = BUNDLES[i - 1], [x1, y1] = BUNDLES[i]
  return Math.max(10, Math.round((y0 + ((usd - x0) * (y1 - y0)) / (x1 - x0)) / 10) * 10)
}
const priceOf = (p) => (p.id in (prices.overrides ?? {}) ? prices.overrides[p.id] : robuxFor(p.usd))

const oneLine = (text) => text.replace(/\s+/g, ' ').trim().slice(0, 400)
const sleep = (ms) => new Promise((r) => setTimeout(r, ms))
async function call(method, url, form, what) {
  for (let attempt = 1; ; attempt++) {
    const res = await fetch(url, { method, headers, body: form })
    const text = await res.text()
    if (res.status === 403 && /game-pass/.test(url)) throw new Error(`${what}: HTTP 403 ${oneLine(text)}. The key needs "game-pass:read" and "game-pass:write".`)
    if (res.ok) return text ? JSON.parse(text) : {}
    if ((res.status === 429 || res.status >= 500) && attempt < 5) {
      await sleep(attempt * 5000)
      continue
    }
    throw new Error(`${what}: HTTP ${res.status} ${oneLine(text)}`)
  }
}

const describe = (p) => (p.car ? `A pack-only car and ${p.bucks.toLocaleString('en-US')} gems. One per account.` : `${(p.bucks + p.bonus).toLocaleString('en-US')} gems, with coins and parts for your level.`)
const robuxOf = (d) => d.priceInformation?.defaultPriceInRobux ?? d.priceInformation?.priceInRobux ?? d.priceInformation?.price ?? null

async function list(url, key, what) {
  const all = new Map()
  let token = ''
  do {
    const page = await call('GET', `${url}/creator?pageSize=50${token ? `&pageToken=${encodeURIComponent(token)}` : ''}`, undefined, what)
    for (const d of page[key] ?? []) all.set(d.name, d)
    token = page.nextPageToken
  } while (token)
  return all
}
const have = await list(API, 'developerProducts', 'listing products')
console.log(`${have.size} products on Roblox now`)
const passes = await list(PASSES, 'gamePasses', 'listing game passes')
console.log(`${passes.size} game passes on Roblox now`)

let changed = 0
// Car packs: Game Passes, and their old Developer Product (if any) off sale.
const ids = {}
for (const p of sold.filter((q) => q.car)) {
  const old = have.get(p.name)
  if (old?.isForSale) {
    console.log(`${p.name}: a Game Pass now, taking its Developer Product off sale (product ${old.productId})`)
    const form = new FormData()
    form.append('isForSale', 'false')
    if (!CHECK) await call('PATCH', `${API}/${old.productId}`, form, p.name)
    changed++
  }
  const price = priceOf(p)
  const d = passes.get(p.name)
  if (d) ids[p.id] = d.gamePassId
  const form = new FormData()
  if (price == null) {
    if (d?.isForSale) {
      console.log(`${p.name}: no price, taking its pass off sale`)
      form.append('isForSale', 'false')
      if (!CHECK) await call('PATCH', `${PASSES}/${d.gamePassId}`, form, p.name)
      changed++
    } else console.log(`${p.name}: no price yet, skipped`)
    continue
  }
  if (!Number.isInteger(price) || price < 1) throw new Error(`${p.id}: price ${price} isn't a whole number of Robux`)
  if (!d) {
    console.log(`${p.name}: making its Game Pass at R$ ${price}`)
    form.append('name', p.name)
    form.append('description', describe(p))
    form.append('price', String(price))
    form.append('isForSale', 'true')
    form.append('imageFile', new Blob([readFileSync(resolve(HERE, `../../store/badges/${p.id}.png`))], { type: 'image/png' }), `${p.id}.png`)
    if (!CHECK) {
      const made = await call('POST', PASSES, form, p.name)
      console.log(`  pass ${made.gamePassId}`)
      ids[p.id] = made.gamePassId
    }
    changed++
    continue
  }
  const now = robuxOf(d)
  if (now === price && d.isForSale) {
    console.log(`${p.name}: R$ ${price}, up to date (pass ${d.gamePassId})`)
    continue
  }
  console.log(`${p.name}: R$ ${now ?? '?'} -> R$ ${price}${d.isForSale ? '' : ', putting it on sale'} (pass ${d.gamePassId})`)
  form.append('price', String(price))
  form.append('isForSale', 'true')
  if (!CHECK) await call('PATCH', `${PASSES}/${d.gamePassId}`, form, p.name)
  changed++
}
if (!CHECK) {
  const rows = Object.keys(ids).sort().map((id) => `\t["${id}"] = ${ids[id]},`)
  writeFileSync(
    resolve(HERE, '../../src/shared/GamePasses.luau'),
    `--!strict\n-- Made by tools/products/sync.mjs (the "Bank products" workflow): each car pack's Game Pass id, by\n-- pack id. Empty until the passes are made.\nreturn {\n${rows.join('\n')}\n} :: { [string]: number }\n`,
  )
}

// Gem packs: Developer Products.
for (const p of sold.filter((q) => !q.car)) {
  const price = priceOf(p)
  const d = have.get(p.name)
  const form = new FormData()
  if (price == null) {
    if (d?.isForSale) {
      console.log(`${p.name}: no price, taking it off sale`)
      form.append('isForSale', 'false')
      if (!CHECK) await call('PATCH', `${API}/${d.productId}`, form, p.name)
      changed++
    } else console.log(`${p.name}: no price yet, skipped`)
    continue
  }
  if (!Number.isInteger(price) || price < 1) throw new Error(`${p.id}: price ${price} isn't a whole number of Robux`)
  if (!d) {
    console.log(`${p.name}: making it at R$ ${price}`)
    form.append('name', p.name)
    form.append('description', describe(p))
    form.append('price', String(price))
    form.append('isForSale', 'true')
    if (!CHECK) {
      const made = await call('POST', API, form, p.name)
      console.log(`  product ${made.productId}`)
    }
    changed++
    continue
  }
  const now = robuxOf(d)
  if (now === price && d.isForSale) {
    console.log(`${p.name}: R$ ${price}, up to date (product ${d.productId})`)
    continue
  }
  console.log(`${p.name}: R$ ${now ?? '?'} -> R$ ${price}${d.isForSale ? '' : ', putting it on sale'} (product ${d.productId})`)
  form.append('price', String(price))
  form.append('isForSale', 'true')
  if (!CHECK) await call('PATCH', `${API}/${d.productId}`, form, p.name)
  changed++
}
if (!have.size) console.log('(Price details Roblox returns, for reference: none yet)')
else console.log(`Price details Roblox returns, for reference: ${JSON.stringify([...have.values()][0].priceInformation ?? null)}`)
console.log(CHECK ? `${changed} products would change` : `${changed} products changed`)
