// Turns Kegan's recordings of the web game's sounds into the files the Roblox game uploads, in
// audio/, and lists them in audio/list.json for tools/models/upload.mjs ("audio:<file>:<hash>").
//
//   node tools/audio/build.mjs <folder of recordings>   rebuild audio/ (needs ffmpeg)
//   node tools/audio/build.mjs --ids                    only write src/shared/AudioAssets.luau
//
// The folder (the project's cartopia-roblox-music) holds town/ (the town music, season-time-name),
// club/ (the nightclub's tracks, 01-deep...), rave/ (Rave Mode's build-up and looping drop),
// ambience/ (season-time-weather loops, plus thunder), sfx/ (one file per sound effect) and voice/
// (the tutorial's lines). Roblox caps how many sounds an account can upload a month, so the short
// ones share a file: every sound effect goes in one sprite, the voice lines in another, and each
// season's weather loops in a third, with where each sound starts and how long it runs. The game
// plays a part of a sprite with a Sound's PlaybackRegion.
//
// Anything that loops (the club tracks, the rave drop, the weather) is written with half a second
// of its own end before it and of its own start after it, and loops over the middle. Wherever the
// decoder's start-up delay shifts the loop by a few milliseconds, it still loops from a point to
// the same point one length later: no click or gap at the seam.
//
// The music and the club tracks stay one file each (two minutes apiece is too long to share).
// Run it again after adding recordings; only changed files get a new hash and a new upload.

import { createHash } from 'node:crypto'
import { execFileSync } from 'node:child_process'
import { copyFileSync, existsSync, mkdirSync, readdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const HERE = dirname(fileURLToPath(import.meta.url))
const ROOT = resolve(HERE, '../..')
const OUT = join(ROOT, 'audio')
const LIST = join(OUT, 'list.json')
const ASSETS = join(ROOT, 'tools/models/assets.json')
const LUAU = join(ROOT, 'src/shared/AudioAssets.luau')

const RATE = 44100
const CH = 2
const FRAME = 4 * CH // bytes per sample frame, f32
const GAP = 0.3 // silence between the sounds in a sprite (s)
const WRAP = 0.5 // a loop's own end before it and start after it (s)

const sec = (buf) => buf.length / FRAME / RATE
const silence = (s) => Buffer.alloc(Math.round(s * RATE) * FRAME)
const cut = (buf, from, to) => buf.subarray(Math.round(from * RATE) * FRAME, Math.round(to * RATE) * FRAME)
const r3 = (x) => Math.round(x * 1000) / 1000

function decode(file) {
  return execFileSync('ffmpeg', ['-v', 'error', '-i', file, '-f', 'f32le', '-ac', String(CH), '-ar', String(RATE), '-'], { maxBuffer: 1 << 30 })
}

function encode(pcm, file, kbps) {
  mkdirSync(dirname(file), { recursive: true })
  execFileSync('ffmpeg', ['-v', 'error', '-y', '-f', 'f32le', '-ac', String(CH), '-ar', String(RATE), '-i', '-', '-map_metadata', '-1', '-c:a', 'libmp3lame', '-b:a', `${kbps}k`, file], { input: pcm, maxBuffer: 1 << 30 })
}

const mp3s = (dir) => (existsSync(dir) ? readdirSync(dir).filter((f) => f.endsWith('.mp3')).sort() : [])
const stem = (f) => f.replace(/\.mp3$/, '')

// A loop with its own tail before it and head after it; the loop runs from WRAP for its length.
function wrapped(pcm) {
  const n = sec(pcm)
  return Buffer.concat([cut(pcm, n - WRAP, n), pcm, cut(pcm, 0, WRAP)])
}

// One-shots (and loops) laid end to end with a little silence between, and where each one is.
function sprite(parts) {
  const bufs = [silence(GAP)]
  let at = GAP
  const regions = {}
  for (const p of parts) {
    const pcm = p.loop ? wrapped(p.pcm) : p.pcm
    const len = sec(p.pcm)
    // A one-shot's region opens a touch early and closes a touch late, so a few milliseconds of
    // decoder delay never clips its attack or its tail (there's only silence either side).
    regions[p.name] = p.loop ? { start: r3(at + WRAP), length: r3(len), loop: true } : { start: r3(Math.max(0, at - 0.02)), length: r3(len + 0.08) }
    bufs.push(pcm, silence(GAP))
    at += sec(pcm) + GAP
  }
  return { pcm: Buffer.concat(bufs), regions }
}

function build(src) {
  rmSync(OUT, { recursive: true, force: true })
  const list = []
  const add = (file, extra = {}) => {
    const hash = createHash('sha256').update(readFileSync(join(OUT, file))).digest('hex').slice(0, 10)
    list.push({ file, hash, ...extra })
    console.log(file)
  }

  // Town music: the recordings as they are.
  for (const f of mp3s(join(src, 'town'))) {
    const pcm = decode(join(src, 'town', f))
    mkdirSync(join(OUT, 'music'), { recursive: true })
    copyFileSync(join(src, 'town', f), join(OUT, 'music', f))
    add(`music/${f}`, { length: r3(sec(pcm)) })
  }
  // The club's tracks loop all night; the rave's drop loops after its build-up.
  for (const f of mp3s(join(src, 'club'))) {
    const pcm = decode(join(src, 'club', f))
    encode(wrapped(pcm), join(OUT, 'club', f), 192)
    add(`club/${f}`, { loop: { start: WRAP, length: r3(sec(pcm)) } })
  }
  for (const f of mp3s(join(src, 'rave'))) {
    const pcm = decode(join(src, 'rave', f))
    const loop = f.includes('loop')
    encode(loop ? wrapped(pcm) : pcm, join(OUT, 'rave', f), 192)
    add(`rave/${f}`, loop ? { loop: { start: WRAP, length: r3(sec(pcm)) } } : { length: r3(sec(pcm)) })
  }
  // Weather: one sprite a season, "day-calm", "night-rain"...; thunder goes with the effects.
  const amb = mp3s(join(src, 'ambience'))
  for (const season of ['spring', 'summer', 'fall', 'winter']) {
    const parts = amb.filter((f) => f.startsWith(`${season}-`)).map((f) => ({ name: stem(f).slice(season.length + 1), pcm: decode(join(src, 'ambience', f)), loop: true }))
    if (!parts.length) continue
    const s = sprite(parts)
    encode(s.pcm, join(OUT, 'sprites', `weather-${season}.mp3`), 160)
    add(`sprites/weather-${season}.mp3`, { regions: s.regions })
  }
  // Every sound effect in one sprite (not the web's own sprite file: these are the same sounds,
  // one file each, so the parts are known exactly).
  const fx = [
    ...mp3s(join(src, 'sfx')).filter((f) => f !== 'sfx-sprite.mp3').map((f) => ({ name: stem(f), pcm: decode(join(src, 'sfx', f)) })),
    ...amb.filter((f) => f.startsWith('thunder-')).map((f) => ({ name: stem(f), pcm: decode(join(src, 'ambience', f)) })),
  ]
  const s = sprite(fx)
  encode(s.pcm, join(OUT, 'sprites', 'sfx.mp3'), 160)
  add('sprites/sfx.mp3', { regions: s.regions })
  const voice = sprite(mp3s(join(src, 'voice')).map((f) => ({ name: stem(f), pcm: decode(join(src, 'voice', f)) })))
  encode(voice.pcm, join(OUT, 'sprites', 'voice.mp3'), 96)
  add('sprites/voice.mp3', { regions: voice.regions })

  writeFileSync(LIST, JSON.stringify(list, null, 1) + '\n')
}

// The asset name a file uploads under; a changed file gets a new one.
const assetName = (e) => `audio:${e.file.replace(/\.mp3$/, '')}:${e.hash}`

function lua(v, indent = '') {
  if (typeof v === 'number') return String(v)
  if (typeof v === 'boolean') return String(v)
  if (typeof v === 'string') return JSON.stringify(v)
  const inner = indent + '\t'
  const keys = Object.keys(v)
  if (!keys.length) return '{}'
  const key = (k) => (/^[A-Za-z_][A-Za-z0-9_]*$/.test(k) ? k : `[${JSON.stringify(k)}]`)
  return `{\n${keys.map((k) => `${inner}${key(k)} = ${lua(v[k], inner)},`).join('\n')}\n${indent}}`
}

function ids() {
  const list = JSON.parse(readFileSync(LIST, 'utf8'))
  const assets = existsSync(ASSETS) ? JSON.parse(readFileSync(ASSETS, 'utf8')) : {}
  const out = { music: {}, club: {}, rave: {}, sprites: {} }
  let uploaded = 0
  for (const e of list) {
    const id = assets[assetName(e)] ?? 0
    if (id) uploaded++
    const [dir, f] = e.file.split('/')
    const name = stem(f)
    const entry = { id }
    if (e.length) entry.length = e.length
    if (e.loop) entry.loop = e.loop
    if (e.regions) entry.regions = e.regions
    out[dir][name] = entry
  }
  const head = [
    '--!strict',
    '-- GENERATED by tools/audio/build.mjs from audio/list.json and the uploaded ids in',
    '-- tools/models/assets.json. Do not edit: run `node tools/audio/build.mjs --ids` again.',
    '-- id 0: not uploaded yet (that sound stays silent). Times are in seconds. A loop plays from',
    '-- loop.start for loop.length, over and over; a sprite part plays from start for length.',
    '',
  ].join('\n')
  writeFileSync(LUAU, `${head}return ${lua(out)}\n`)
  console.log(`${list.length} audio files, ${uploaded} uploaded`)
}

const arg = process.argv[2]
if (!arg) {
  console.error('usage: node tools/audio/build.mjs <recordings folder> | --ids')
  process.exit(1)
}
if (arg !== '--ids') build(resolve(arg))
ids()
