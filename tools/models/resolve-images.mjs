// Open Cloud gives back a Decal's id for each picture tools/models/upload.mjs uploads, but an
// ImageLabel or a Texture needs the id of the image inside it. Roblox only names that image to code
// running in a game (InsertService:LoadAsset on the decal), so this runs a short Luau script in the
// live place with Open Cloud's Luau Execution and records each decal's image id in
// tools/models/images.json ({ "<decal id>": <image id> }). build.mjs and tools/splash/build.mjs
// then bake the image ids in. Ids already in images.json are skipped.
//
//   API_KEY=<key> UNIVERSE=<id> PLACE=<id> node tools/models/resolve-images.mjs
//
// The key needs luau-execution-sessions:write on the experience. Without it this leaves a warning
// and the game keeps using the decal ids (the server then looks the images up itself).

import { existsSync, readFileSync, writeFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const HERE = dirname(fileURLToPath(import.meta.url))
const ASSETS = join(HERE, 'assets.json')
const IMAGES = join(HERE, 'images.json')
const { API_KEY: key, UNIVERSE: universe, PLACE: place } = process.env
if (!key || !universe || !place) {
  console.error('needs API_KEY, UNIVERSE and PLACE')
  process.exit(1)
}
const sleep = (ms) => new Promise((r) => setTimeout(r, ms))
const oneLine = (text) => text.replace(/\s+/g, ' ').trim().slice(0, 300)

const assets = JSON.parse(readFileSync(ASSETS, 'utf8'))
const images = existsSync(IMAGES) ? JSON.parse(readFileSync(IMAGES, 'utf8')) : {}
const decals = Object.entries(assets)
  .filter(([name]) => name.startsWith('texture:') || name.startsWith('splash:') || name.startsWith('sky:'))
  .map(([, id]) => id)
const todo = [...new Set(decals)].filter((id) => !images[id])
console.log(`${decals.length} pictures, ${todo.length} to look up`)

const save = () => {
  const live = new Set(decals.map(String))
  const kept = Object.entries(images).filter(([id]) => live.has(id)).sort(([a], [b]) => a.localeCompare(b))
  writeFileSync(IMAGES, JSON.stringify(Object.fromEntries(kept), null, 1) + '\n')
}

const script = (ids) => `
local InsertService = game:GetService("InsertService")
local out = {}
for _, id in { ${ids.join(', ')} } do
	local texture
	for _ = 1, 3 do
		local ok, model = pcall(InsertService.LoadAsset, InsertService, id)
		if ok and model then
			local decal = model:FindFirstChildWhichIsA("Decal", true)
			texture = decal and decal.Texture
			model:Destroy()
			break
		end
		task.wait(1)
	end
	table.insert(out, tostring(id) .. "=" .. tostring(texture))
end
return table.concat(out, ";")
`

async function call(url, init, what) {
  for (let attempt = 1; ; attempt++) {
    const res = await fetch(url, init)
    if (res.ok) return res.json()
    const body = await res.text()
    if ((res.status === 429 || res.status >= 500) && attempt < 6) {
      await sleep(attempt * 10000)
      continue
    }
    const err = new Error(`${what}: HTTP ${res.status} ${oneLine(body)}`)
    err.status = res.status
    throw err
  }
}

async function run(ids) {
  const base = 'https://apis.roblox.com/cloud/v2'
  const headers = { 'x-api-key': key, 'Content-Type': 'application/json' }
  let task = await call(`${base}/universes/${universe}/places/${place}/luau-execution-session-tasks`, { method: 'POST', headers, body: JSON.stringify({ script: script(ids), timeout: '300s' }) }, 'start the lookup')
  for (let i = 0; task.state !== 'COMPLETE' && task.state !== 'FAILED' && task.state !== 'CANCELLED'; i++) {
    if (i > 200) throw new Error('the lookup never finished')
    await sleep(3000)
    task = await call(`${base}/${task.path}`, { headers }, 'check the lookup')
  }
  if (task.state !== 'COMPLETE') throw new Error(`the lookup ${task.state}: ${oneLine(JSON.stringify(task.error ?? {}))}`)
  for (const pair of String(task.output?.results?.[0] ?? '').split(';')) {
    const [id, texture] = pair.split('=')
    const image = texture?.match(/(\d+)\s*$/)?.[1]
    if (image) images[id] = Number(image)
    else console.log(`no image found for ${id} (${texture})`)
  }
}

try {
  for (let i = 0; i < todo.length; i += 60) {
    await run(todo.slice(i, i + 60))
    save()
  }
} catch (err) {
  const why = err.status === 401 || err.status === 403 ? `The Open Cloud key needs Luau Execution (luau-execution-sessions:write) to look up picture ids (${err.message})` : err.message
  console.log(`::warning title=Picture ids not looked up::${why}`)
}
save()
console.log(`${Object.keys(images).length} picture ids known`)
