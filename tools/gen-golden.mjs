// Regenerates tests/Golden.luau: what the web game's data.ts and race.ts return for a wide sweep of
// inputs. tests/parity.luau calls the Luau ports with the same inputs and expects the same answers.
// Usage: node tools/gen-golden.mjs <path to the Cartopia web repo>
import { execFileSync } from 'node:child_process'
import { mkdtempSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join, resolve } from 'node:path'
import { pathToFileURL } from 'node:url'

const web = resolve(process.argv[2] ?? '../cartopia')
const dir = mkdtempSync(join(tmpdir(), 'golden-'))
const load = async (name) => {
  const out = join(dir, `${name}.mjs`)
  execFileSync(join(web, 'node_modules/.bin/esbuild'), [join(web, `src/game/${name}.ts`), '--bundle', '--format=esm', '--platform=node', `--outfile=${out}`])
  return import(pathToFileURL(out).href)
}
const D = await load('data')
const R = await load('race')

// Each case: [function name, args, expected]. Args hold ids, not objects, so both sides can look
// them up. The adapters in tests/parity.luau must match these one for one.
const cases = []
const add = (fn, args, out) => cases.push({ fn, args, out })

// Buildings
for (const b of D.BUILDINGS) {
  add('upgradable', [b.id], D.upgradable(b))
  add('takesDriver', [b.id], D.takesDriver(b))
  for (let l = 1; l <= D.MAX_BUILDING_LEVEL; l++) {
    add('buildingStats', [b.id, l], {
      payout: D.upgradePayout(b, l), parts: D.upgradePartsPayout(b, l), xp: D.upgradeXp(b, l), seconds: D.upgradeJobSeconds(b, l),
      fuel: D.upgradeFuelCap(b, l), cost: D.buildingUpgradeCost(b, l), name: D.levelName(b, l),
    })
  }
}
add('buildingDef', ['from-the-future'], { parked: true, name: D.buildingDef('from-the-future').name })
for (const level of [undefined, 0, 1, 3.7, 42, -5, 'x']) add('buildingLevel', [level ?? null], D.buildingLevel({ level }))
for (const [level, jobLevel] of [[3, null], [4, 3], [2, 9], [5, 5]]) add('jobLevel', [level, jobLevel], D.jobLevel({ level, jobLevel: jobLevel ?? undefined }))
for (let l = 0; l <= 12; l++) add('houseResidents', [l], D.houseResidents(l))
for (let l = 0; l <= 11; l++) add('levelLift', [l], D.levelLift(l))

// Cars, upgrades and mods
const none = { engine: 0, turbo: 0, tires: 0, weight: 0 }
const ups = [none, { engine: 5, turbo: 5, tires: 5, weight: 5 }, { engine: 2, turbo: 0, tires: 4, weight: 1 }]
const modSets = [[], D.MODS.map((m) => m.id), ['flamepipes', 'chrome', 'nope', 'twintips'], D.MODS.filter((_, i) => i % 3 === 0).map((m) => m.id)]
for (const c of D.CARS) {
  add('restoreCost', [c.id], D.restoreCost(c))
  add('carSource', [c.id], D.carSource(c))
  for (let l = 0; l < D.MAX_UPGRADE; l++) add('upgradeCost', [c.id, l], D.upgradeCost(c, l))
  ups.forEach((u, ui) => modSets.forEach((m, mi) => add('performance', [c.id, ui, mi], D.performance(c, u, m))))
  modSets.forEach((m, mi) => add('fittedMods', [mi, c.body], D.fittedMods(m, c.body)))
  for (const b of ['pizza', 'tires', 'diner', 'burger']) add('driverPayout', [b, 2, c.id], D.driverPayout(D.buildingDef(b), 2, c))
}
add('carDef', ['future-car'], { parked: true, price: D.carDef('future-car').price, likes: D.carDef('future-car').likes.length })
add('ownedMods', [['twintips', 'nope', 'chrome'], ['chrome', 'flamepipes']], D.ownedMods({ ownedMods: ['twintips', 'nope', 'chrome'], mods: ['chrome', 'flamepipes'] }))
for (const m of D.MODS) add('modXp', [m.id], D.modXp(m.id))
add('garagePower', [], D.garagePower(D.CARS.slice(0, 9).map((c, i) => ({ model: c.id, upgrades: ups[i % 3], mods: modSets[i % 4] }))))

// Progression
for (let l = 1; l <= 80; l++) add('xpToNext', [l], D.xpToNext(l))
for (let n = 0; n <= 24; n++) add('plotPrice', [n], D.plotPrice(n))
for (let f = 0; f <= 60; f += 3) add('refillBucks', [f], D.refillBucks(f))

// Grand Prix and campaign
for (const s of D.GP_SERIES) for (let r = 0; r < D.GP_ROUNDS; r++) for (let c = 0; c < 4; c++) add('gp', [s.id, r, c], { pi: D.gpRivalPi(s, r, c), reward: D.gpReward(s, r) })
D.CAMPAIGN.forEach((ch, ci) => {
  for (let i = 0; i < D.CAMPAIGN_RACES; i++) {
    add('campaign', [ci, i], { pi: D.campaignRivalPi(ch, i), first: D.campaignReward(ch, i, true), again: D.campaignReward(ch, i, false), shift: D.campaignShift(ci, i), skills: D.campaignRivalSkills(ci, i) })
  }
})
for (const [a, b] of [[10, 11], [10, 10], [9.6, 10], [9.71, 10], [9.39, 10], [9.4, 10], [5, 1e9]]) add('campaignStars', [a, b], D.campaignStars(a, b))

// Skills
const racers = [{ gear: 0, dist: 0 }, { gear: 1, dist: 10 }, { gear: 2, dist: 50 }, { gear: 3, dist: 200 }]
for (const sk of [...Object.keys(D.SKILLS), null]) {
  for (const me of racers) for (const them of racers) for (const t of [1, 3]) {
    add('skills', [sk, me, them, t], { boost: D.skillBoost(sk ?? undefined, me, them), drag: D.skillDrag(sk ?? undefined, them, t), live: D.liveSkillBoost(sk ?? undefined, me, them, t) })
  }
}

// Calendar: UTC keys, seasons, East Coast event days (both DST switches and year ends).
const times = [
  Date.UTC(2026, 9, 11, 14, 32), Date.UTC(2026, 9, 1, 3, 59), Date.UTC(2026, 9, 1, 4, 0), Date.UTC(2026, 10, 1, 3, 59), Date.UTC(2026, 10, 1, 4, 0),
  Date.UTC(2026, 10, 1, 5, 59), Date.UTC(2026, 10, 1, 6, 0), Date.UTC(2026, 2, 8, 6, 59), Date.UTC(2026, 2, 8, 7, 0), Date.UTC(2027, 0, 1, 0, 0),
  Date.UTC(2026, 11, 31, 23, 59), Date.UTC(2027, 0, 3, 12), Date.UTC(2027, 0, 4, 12), Date.UTC(2024, 11, 30), Date.UTC(2028, 1, 29, 8),
  Date.UTC(2026, 9, 5), Date.UTC(2026, 10, 16), Date.UTC(2027, 9, 31, 12), Date.UTC(2020, 11, 31, 23),
]
for (const t of times) {
  add('calendar', [t], {
    day: D.dayKey(t), week: D.weekKey(t), nextDay: D.msToNextDay(t), nextWeek: D.msToNextWeek(t), season: D.seasonNumber(t),
    event: D.activeEvent(t)?.id ?? null, eventEnds: D.eventEndsAt(D.EVENTS[0], t),
  })
}
for (let n = 1; n <= 4; n++) add('seasonOf', [n], D.seasonOf(n))
add('seasonCars', [], D.seasonCars())

// Tasks: same draw for the same key on every device.
const ownSets = [[], ['rescue'], ['rescue', 'gas']]
for (const period of ['daily', 'weekly']) {
  const pool = period === 'daily' ? D.DAILY_TASKS : D.WEEKLY_TASKS
  for (let d = 0; d < 40; d++) {
    const t = Date.UTC(2026, 9, 1) + d * 86400000
    const key = period === 'daily' ? D.dayKey(t) : D.weekKey(t)
    for (const level of [1, 2, 5, 30]) {
      ownSets.forEach((own, oi) => add('drawTasks', [period, key, level, oi], D.drawTasks(pool, key, level, (id) => own.includes(id))))
    }
  }
}

// Deals
for (let d = 0; d < 60; d++) {
  const day = D.dayKey(Date.UTC(2026, 9, 1) + d * 86400000)
  add('dealsFor', [day], D.dealsFor(day).map((x) => x.id))
}
for (const d of D.DEALS) add('dealOffer', [d.id], { offer: D.dealOffer(d), save: D.dealSave(d) })

// Paint and skins
const cars = [{ color: '#c62828' }, { color: '#c62828', finish: 'matte', stripe: '#fafafa' }]
for (const p of D.PAINTS) for (const f of D.FINISHES) for (const st of D.STRIPES) cars.forEach((car, ci) => add('paintJobCost', [ci, p.color, f.id, st], D.paintJobCost(car, { color: p.color, finish: f.id, stripe: st })))
for (const s of [{ level: 1 }, { level: 10, claimedSets: ['daily'] }, { level: 30, claimedSets: ['muscle', 'daily'], skins: ['static', 'nope'] }]) {
  add('ownedSkins', [s], D.ownedSkins(s))
  add('ownedModSkins', [s], D.ownedModSkins({ level: s.level, claimedSets: s.claimedSets, modSkins: s.skins }))
}
for (let t = 1; t <= 30; t++) add('seasonSkin', [t], { car: D.seasonSkin(t)?.id ?? null, mod: D.seasonModSkin(t)?.id ?? null })

// Collection sets
const owned = D.CARS.filter((_, i) => i % 2 === 0).map((c) => ({ model: c.id }))
for (const set of D.CAR_SETS) add('setOwned', [set.id], D.setOwned(set, owned))
add('readySets', [], D.readySets({ cars: D.CARS.map((c) => ({ model: c.id })), claimedSets: ['daily'] }).map((s) => s.id))

// Visitors and services
for (const kind of Object.keys(D.VISITORS)) for (const level of [1, 7, 40]) for (const roll of [0, 0.049, 0.5]) add('visitorPrize', [kind, level, roll], D.visitorPrize(kind, level, roll))
for (let l = 1; l <= 20; l += 4) add('services', [l], { tires: D.servicePay(l, 'tires'), gas: D.servicePay(l, 'gas'), can: D.gasCanCost(l), flat: D.flatFixCost(l) })

// Race physics
for (let pi = 10; pi <= 250; pi += 5) add('dynoPull', [pi], R.dynoPull(pi))
for (const pi of [1, 7, 60, 133, 250]) add('computeRaceFloor', [pi], R.raceFloor(pi))
for (const [lo, hi] of [[undefined, undefined], [0.8, 0.9]]) for (const rpm of [0.5, 0.65, 0.7, 0.78, 0.85, 0.93, 0.95]) add('shiftQuality', [rpm, lo ?? null, hi ?? null], R.shiftQuality(rpm, lo, hi))
// Full scripted races: launch, shift points, boost timing and skill, run frame by frame.
for (const pi of [20, 60, 140]) {
  for (const [react, shiftAt, fireGear, skill] of [[0.1, 0.9, 2, 'launch'], [-1, 0.7, 1, null], [0.4, 0.97, 3, 'torque'], [0.8, 0.8, null, 'nitro']]) {
    const r = R.freshRacer(false)
    const dt = 1 / 60
    let t = 0
    const calls = []
    while (r.finished === null && t < 60) {
      t += dt
      if (!r.launched && t >= (react < 0 ? R.JUMP_START_DELAY : react)) calls.push(R.launchRacer(r, react))
      if (r.launched && r.gear < 3 && r.rpm >= shiftAt) R.shiftRacer(r, R.shiftQuality(r.rpm).q)
      if (fireGear !== null && r.gear >= fireGear) R.fireBoost(r)
      R.stepRacer(r, pi, dt, t, D.skillBoost(skill ?? undefined, r, { gear: 0, dist: 0 }))
    }
    add('scriptedRace', [pi, react, shiftAt, fireGear, skill], { finished: r.finished, speed: r.speed, streak: r.streak, boostUsed: r.boostUsed, calls })
  }
}

// ---- Write it out as a Luau table ----
const ident = /^[A-Za-z_][A-Za-z0-9_]*$/
const str = (s) => '"' + s.replace(/\\/g, '\\\\').replace(/"/g, '\\"').replace(/\n/g, '\\n') + '"'
function lua(v) {
  if (v === null || v === undefined) return 'NULL'
  if (typeof v === 'string') return str(v)
  if (typeof v === 'number') return Number.isFinite(v) ? String(v) : v > 0 ? 'math.huge' : '-math.huge'
  if (typeof v === 'boolean') return String(v)
  if (Array.isArray(v)) return `{ ${v.map(lua).join(', ')} }`
  const e = Object.entries(v).filter(([, x]) => x !== undefined)
  return `{ ${e.map(([k, x]) => `${ident.test(k) ? k : `[${str(k)}]`} = ${lua(x)}`).join(', ')} }`
}
const lines = [
  '--!nocheck',
  '-- GENERATED by tools/gen-golden.mjs from the web game. What its data.ts and race.ts return for each',
  '-- input; tests/parity.luau checks the Luau ports against it. NULL stands for JavaScript null.',
  '',
  'local NULL = require("./Null")',
  '',
  'return {',
  ...cases.map((c) => `\t{ fn = ${str(c.fn)}, args = ${lua(c.args)}, out = ${lua(c.out)} },`),
  '}',
  '',
]
writeFileSync(new URL('../tests/Golden.luau', import.meta.url), lines.join('\n'))
console.log(`wrote ${cases.length} cases`)
