// Uploads the mesh packs build.mjs wrote (build/meshes/*.glb) to Roblox as Model assets with
// Open Cloud, and records each pack's asset id in tools/models/assets.json. A pack's name carries
// a hash of its meshes, so a changed model gets a new pack and a new upload, and packs already in
// assets.json are skipped. Run build.mjs again afterwards so Meshes.luau picks up the new ids.
//
//   API_KEY=<key> UNIVERSE=<id> node tools/models/upload.mjs
//
// The key needs Assets read and write. The assets go to whoever owns the experience (a user or a
// group), looked up from UNIVERSE, so the game can load them with InsertService.

import { existsSync, readFileSync, writeFileSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const HERE = dirname(fileURLToPath(import.meta.url))
const ROOT = resolve(HERE, '../..')
const ASSETS = join(HERE, 'assets.json')
const GLB_DIR = join(ROOT, 'build/meshes')
const API = 'https://apis.roblox.com/assets/v1'

const sleep = (ms) => new Promise((r) => setTimeout(r, ms))

async function creatorOf(universe) {
  const res = await fetch(`https://games.roblox.com/v1/games?universeIds=${universe}`)
  if (!res.ok) throw new Error(`couldn't look up the experience's owner: HTTP ${res.status}`)
  const game = (await res.json()).data?.[0]
  if (!game) throw new Error(`no experience with universe id ${universe}`)
  return game.creator.type === 'Group' ? { groupId: String(game.creator.id) } : { userId: String(game.creator.id) }
}

// Roblox answers 429 or 5xx when busy; wait and try again a few times.
async function call(url, init, what) {
  for (let attempt = 1; ; attempt++) {
    const res = await fetch(url, init)
    if (res.ok) return res.json()
    const body = await res.text()
    if ((res.status === 429 || res.status >= 500) && attempt < 6) {
      await sleep(attempt * 10000)
      continue
    }
    const err = new Error(`${what}: HTTP ${res.status} ${body.slice(0, 300)}`)
    err.status = res.status
    throw err
  }
}

async function upload(key, creator, name, file) {
  const form = new FormData()
  form.append('request', JSON.stringify({ assetType: 'Model', displayName: `Cartopia ${name}`.slice(0, 50), description: 'Cartopia 3D models', creationContext: { creator } }))
  form.append('fileContent', new Blob([readFileSync(file)], { type: 'model/gltf-binary' }), `${name}.glb`)
  let op = await call(`${API}/assets`, { method: 'POST', headers: { 'x-api-key': key }, body: form }, `upload ${name}`)
  for (let i = 0; !op.done; i++) {
    if (i > 60) throw new Error(`upload ${name}: Roblox didn't finish processing it`)
    await sleep(2000)
    op = await call(`${API}/${op.path}`, { headers: { 'x-api-key': key } }, `check ${name}`)
  }
  if (op.error) throw new Error(`upload ${name}: ${JSON.stringify(op.error)}`)
  return Number(op.response.assetId)
}

const key = process.env.API_KEY
const universe = process.env.UNIVERSE
if (!key || !universe) {
  console.error('needs API_KEY and UNIVERSE')
  process.exit(1)
}
const packs = JSON.parse(readFileSync(join(GLB_DIR, 'packs.json'), 'utf8'))
const assets = existsSync(ASSETS) ? JSON.parse(readFileSync(ASSETS, 'utf8')) : {}
const todo = packs.filter((p) => !assets[p.name])
console.log(`${packs.length} packs, ${todo.length} to upload`)
if (todo.length) {
  const creator = await creatorOf(universe)
  let done = 0
  try {
    for (const p of todo) {
      assets[p.name] = await upload(key, creator, p.name, join(GLB_DIR, p.file))
      done++
      // Save as we go, so a run that stops halfway keeps what it uploaded.
      writeFileSync(ASSETS, JSON.stringify(Object.fromEntries(Object.entries(assets).sort()), null, 1) + '\n')
      console.log(`${p.name} -> ${assets[p.name]}`)
    }
  } catch (err) {
    console.error(err.message)
    if (err.status === 401 || err.status === 403) {
      // The key can't upload assets yet. The game still works, with boxes in place of these shapes.
      console.log(`::warning title=3D shapes not uploaded::The Open Cloud key needs Assets read and write to upload the models (${done} of ${todo.length} uploaded).`)
      process.exit(0)
    }
    process.exit(1)
  }
}
// Drop ids of packs no model uses any more.
const live = new Set(packs.map((p) => p.name))
for (const name of Object.keys(assets)) if (!live.has(name)) delete assets[name]
writeFileSync(ASSETS, JSON.stringify(Object.fromEntries(Object.entries(assets).sort()), null, 1) + '\n')
