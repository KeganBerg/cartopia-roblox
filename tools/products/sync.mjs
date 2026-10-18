// Makes the Roblox Developer Products the Bank sells (server/Purchases): one per gem pack and car
// pack, named exactly like the pack. The Robux price comes from the web game's dollar price, turned
// into Robux at Roblox's own Robux store rates (tools/products/prices.json "match-dollars"), so a
// price change on the web carries over; prices.json overrides can fix a pack's price, or null stops
// selling it (taken off sale if it was). Existing products are found by name and
// only changed when their price or sale state differs. The server finds the products by name too,
// so no product id goes into the code.
//
//   API_KEY=<key> UNIVERSE=<id> node tools/products/sync.mjs [--check]
//
// The key needs the "developer-product:read" and "developer-product:write" permissions. With
// --check it only prints what it would do.

import { readFileSync } from 'node:fs'
import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const HERE = dirname(fileURLToPath(import.meta.url))
const KEY = process.env.API_KEY
const GAME = process.env.UNIVERSE || '10771588518'
const CHECK = process.argv.includes('--check')
const API = `https://apis.roblox.com/developer-products/v2/universes/${GAME}/developer-products`
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

const have = new Map()
let token = ''
do {
  const page = await call('GET', `${API}/creator?pageSize=50${token ? `&pageToken=${encodeURIComponent(token)}` : ''}`, undefined, 'listing products')
  for (const d of page.developerProducts ?? []) have.set(d.name, d)
  token = page.nextPageToken
} while (token)
console.log(`${have.size} products on Roblox now`)

let changed = 0
for (const p of sold) {
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
