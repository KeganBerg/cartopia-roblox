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

// The develop API names the owner even while the experience is private (the games API answers
// id 0 then, which Roblox refuses as "Unknown CreatorType").
async function creatorOf(universe) {
  const res = await fetch(`https://develop.roblox.com/v1/universes/${universe}`)
  if (!res.ok) throw new Error(`couldn't look up the experience's owner: HTTP ${res.status}`)
  const u = await res.json()
  if (!u.creatorTargetId) throw new Error(`no owner found for universe ${universe}`)
  return u.creatorType === 'Group' ? { groupId: String(u.creatorTargetId) } : { userId: String(u.creatorTargetId) }
}

// CREATOR_USER_ID or CREATOR_GROUP_ID, when set, say who owns the uploads instead of the lookup.
function creatorFromEnv() {
  if (process.env.CREATOR_GROUP_ID) return { groupId: process.env.CREATOR_GROUP_ID }
  if (process.env.CREATOR_USER_ID) return { userId: process.env.CREATOR_USER_ID }
  return null
}

// Error text on one line, so the whole of it shows in the run's annotation.
const oneLine = (text) => text.replace(/\s+/g, ' ').trim()

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
    const err = new Error(`${what}: HTTP ${res.status} ${oneLine(body).slice(0, 300)}`)
    err.status = res.status
    throw err
  }
}

// A mesh pack goes up as a Model; a ground texture as a Decal, whose id Open Cloud gives back is
// the image's own, ready for a Texture; a sound as Audio.
const KINDS = {
  model: { assetType: 'Model', description: 'Cartopia 3D models', type: 'model/gltf-binary', ext: 'glb' },
  image: { assetType: 'Decal', description: 'Cartopia picture', type: 'image/png', ext: 'png' },
  audio: { assetType: 'Audio', description: 'Cartopia music and sounds, made for the game', type: 'audio/mpeg', ext: 'mp3' },
}
async function upload(key, creator, name, file, image = false, audio = false) {
  const kind = KINDS[audio ? 'audio' : image ? 'image' : 'model']
  const form = new FormData()
  const request = { assetType: kind.assetType, displayName: `Cartopia ${name.replaceAll(':', ' ').replaceAll('/', ' ')}`.slice(0, 50), description: kind.description, creationContext: { creator, expectedPrice: 0 } }
  form.append('request', JSON.stringify(request))
  form.append('fileContent', new Blob([readFileSync(file)], { type: kind.type }), `${name.replaceAll(/[:/]/g, '-')}.${kind.ext}`)
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
const TEX_DIR = join(ROOT, 'build/textures')
const texList = existsSync(join(TEX_DIR, 'list.json')) ? JSON.parse(readFileSync(join(TEX_DIR, 'list.json'), 'utf8')) : []
// The loading screen's pictures (tools/splash/build.mjs).
const SPLASH_DIR = join(ROOT, 'build/splash')
const splashList = existsSync(join(SPLASH_DIR, 'list.json')) ? JSON.parse(readFileSync(join(SPLASH_DIR, 'list.json'), 'utf8')) : []
// The sky's faces (tools/sky/build.mjs).
const SKY_DIR = join(ROOT, 'build/sky')
const skyList = existsSync(join(SKY_DIR, 'list.json')) ? JSON.parse(readFileSync(join(SKY_DIR, 'list.json'), 'utf8')) : []
// Textures and pictures share assets.json with the packs, as "texture:<name>", "splash:<name>" and
// "sky:<name>".
const packs = [
  ...JSON.parse(readFileSync(join(GLB_DIR, 'packs.json'), 'utf8')).map((p) => ({ ...p, path: join(GLB_DIR, p.file) })),
  ...texList.map((t) => ({ name: `texture:${t.name}`, path: join(TEX_DIR, t.file), image: true })),
  ...splashList.map((t) => ({ name: `splash:${t.name}`, path: join(SPLASH_DIR, t.file), image: true })),
  ...skyList.map((t) => ({ name: `sky:${t.name}`, path: join(SKY_DIR, t.file), image: true })),
]
// The game's music and sounds (tools/audio/build.mjs), as "audio:<file>:<hash>". Roblox caps
// how many sounds an account uploads a month, so they go up after everything else, the effects and
// the tutorial's voice first, and a refusal leaves the rest for a later run.
const AUDIO_DIR = join(ROOT, 'audio')
const audioList = existsSync(join(AUDIO_DIR, 'list.json')) ? JSON.parse(readFileSync(join(AUDIO_DIR, 'list.json'), 'utf8')) : []
const FIRST = ['sprites/sfx', 'sprites/voice', 'music/', 'sprites/weather', 'rave/', 'club/']
const rank = (file) => FIRST.findIndex((p) => file.startsWith(p))
const sounds = audioList
  .map((e) => ({ name: `audio:${e.file.replace(/\.mp3$/, '')}:${e.hash}`, path: join(AUDIO_DIR, e.file), audio: true, rank: rank(e.file) }))
  .sort((a, b) => a.rank - b.rank)
const assets = existsSync(ASSETS) ? JSON.parse(readFileSync(ASSETS, 'utf8')) : {}
const save = () => writeFileSync(ASSETS, JSON.stringify(Object.fromEntries(Object.entries(assets).sort()), null, 1) + '\n')
const todo = packs.filter((p) => !assets[p.name])
const soundTodo = sounds.filter((p) => !assets[p.name])
console.log(`${packs.length} packs, ${todo.length} to upload; ${sounds.length} sound files, ${soundTodo.length} to upload`)
let creator = null
const whoUploads = async () => (creator ??= creatorFromEnv() ?? (await creatorOf(universe)))
if (todo.length) {
  let done = 0
  try {
    const creator = await whoUploads()
    console.log(`uploading as ${JSON.stringify(creator)}`)
    // A few at a time: Roblox takes a few seconds to process each one.
    const queue = [...todo]
    const worker = async () => {
      for (let p = queue.shift(); p; p = queue.shift()) {
        assets[p.name] = await upload(key, creator, p.name, p.path, p.image)
        done++
        // Save as we go, so a run that stops halfway keeps what it uploaded.
        writeFileSync(ASSETS, JSON.stringify(Object.fromEntries(Object.entries(assets).sort()), null, 1) + '\n')
        console.log(`${p.name} -> ${assets[p.name]}`)
      }
    }
    await Promise.all(Array.from({ length: 4 }, worker))
  } catch (err) {
    // Never stops the publish: the game draws a box for each shape not uploaded, and the next
    // run tries again.
    const why = err.status === 401 || err.status === 403 ? `The Open Cloud key needs Assets read and write to upload the models (${err.message})` : err.message
    console.log(`::warning title=3D shapes not all uploaded::${why} (${done} of ${todo.length} uploaded).`)
    process.exit(0)
  }
}
// Sounds one at a time, in order, so a monthly cap stops at the least needed ones.
if (soundTodo.length) {
  let done = 0
  try {
    const creator = await whoUploads()
    for (const p of soundTodo) {
      assets[p.name] = await upload(key, creator, p.name, p.path, false, true)
      done++
      save()
      console.log(`${p.name} -> ${assets[p.name]}`)
    }
  } catch (err) {
    // Never stops the publish either: a sound not uploaded yet stays silent until a later run.
    const why = err.status === 401 || err.status === 403 ? `The Open Cloud key needs Assets read and write to upload the sounds (${err.message})` : err.status === 429 || /quota|limit/i.test(err.message) ? `Roblox's monthly audio upload limit was reached; the rest go up on a later run (${err.message})` : err.message
    console.log(`::warning title=Sounds not all uploaded::${why} (${done} of ${soundTodo.length} uploaded).`)
  }
}
// Drop ids of packs no model uses any more.
const live = new Set([...packs, ...sounds].map((p) => p.name))
for (const name of Object.keys(assets)) if (!live.has(name)) delete assets[name]
writeFileSync(ASSETS, JSON.stringify(Object.fromEntries(Object.entries(assets).sort()), null, 1) + '\n')
