// Stand-ins for the browser APIs the web game's src/game modules use, written in plain TypeScript
declare const os: { time(this: void): number }
declare const math: { random(this: void): number }
declare const BIT32_LIB: {
  band(a: number, b: number): number
  bor(a: number, b: number): number
  bxor(a: number, b: number): number
  bnot(a: number): number
  lshift(a: number, n: number): number
  rshift(a: number, n: number): number
  arshift(a: number, n: number): number
}

// (BIT32_LIB is Luau's bit32 library: TypeScriptToLua won't take that name, so it's renamed after.)
// JavaScript's bitwise operators, which TypeScriptToLua's Luau output can't express: transpile.mjs
// rewrites each `a ^ b`, `a >>> b`... into one of these. bit32 works on unsigned 32-bit numbers;
// JavaScript's operators (all but >>>) give signed ones.
const signed = (n: number) => (n >= 2147483648 ? n - 4294967296 : n)
export const __band = (a: number, b: number) => signed(BIT32_LIB.band(a, b))
export const __bor = (a: number, b: number) => signed(BIT32_LIB.bor(a, b))
export const __bxor = (a: number, b: number) => signed(BIT32_LIB.bxor(a, b))
export const __bnot = (a: number) => signed(BIT32_LIB.bnot(a))
export const __shl = (a: number, n: number) => signed(BIT32_LIB.lshift(a, BIT32_LIB.band(n, 31)))
export const __shr = (a: number, n: number) => signed(BIT32_LIB.arshift(a, BIT32_LIB.band(n, 31)))
export const __ushr = (a: number, n: number) => BIT32_LIB.rshift(a, BIT32_LIB.band(n, 31))
// so TypeScriptToLua can turn them into Luau along with everything else. tools/transpile.mjs points
// each module's Date, Intl and Math.imul at these. Times are UTC milliseconds, like JavaScript's.

const DAY = 86400000

// Days since 1970-01-01 for a UTC date (month 1-12), and back (Howard Hinnant's algorithms).
function daysFromCivil(y: number, m: number, d: number) {
  y = m <= 2 ? y - 1 : y
  const era = Math.floor(y / 400)
  const yoe = y - era * 400
  const doy = Math.floor((153 * ((m + 9) % 12) + 2) / 5) + d - 1
  const doe = yoe * 365 + Math.floor(yoe / 4) - Math.floor(yoe / 100) + doy
  return era * 146097 + doe - 719468
}
function civilFromDays(z: number): [number, number, number] {
  z += 719468
  const era = Math.floor(z / 146097)
  const doe = z - era * 146097
  const yoe = Math.floor((doe - Math.floor(doe / 1460) + Math.floor(doe / 36524) - Math.floor(doe / 146096)) / 365)
  const doy = doe - (365 * yoe + Math.floor(yoe / 4) - Math.floor(yoe / 100))
  const mp = Math.floor((5 * doy + 2) / 153)
  const d = doy - Math.floor((153 * mp + 2) / 5) + 1
  const m = mp < 10 ? mp + 3 : mp - 9
  return [yoe + era * 400 + (m <= 2 ? 1 : 0), m, d]
}
const pad = (n: number, w: number) => {
  let s = `${n}`
  while (s.length < w) s = `0${s}`
  return s
}

// The clock: the Roblox entry scripts swap in DateTime for millisecond accuracy.
let clock = () => os.time() * 1000
export function setClock(fn: () => number) {
  clock = fn
}

export class JsDate {
  private t: number
  constructor(t?: number) {
    this.t = t ?? clock()
  }
  static now() {
    return clock()
  }
  static UTC(year: number, month = 0, day = 1, hours = 0, minutes = 0, seconds = 0, ms = 0) {
    const y = year + Math.floor(month / 12)
    const m = ((month % 12) + 12) % 12
    return (daysFromCivil(y, m + 1, 1) + day - 1) * DAY + hours * 3600000 + minutes * 60000 + seconds * 1000 + ms
  }
  // Only the ISO forms the game writes: YYYY-MM-DD with an optional THH:MM[:SS][Z].
  static parse(s: string) {
    const [date, time] = s.split('T')
    const [y, m, d] = date.split('-').map((x) => Number(x))
    let ms = daysFromCivil(y, m, d) * DAY
    if (time) {
      const [h, mi, sec] = time.replace('Z', '').split(':').map((x) => Number(x))
      ms += (h || 0) * 3600000 + (mi || 0) * 60000 + (sec || 0) * 1000
    }
    return ms
  }
  getTime() {
    return this.t
  }
  valueOf() {
    return this.t
  }
  private ymd() {
    return civilFromDays(Math.floor(this.t / DAY))
  }
  getUTCFullYear() {
    return this.ymd()[0]
  }
  getUTCMonth() {
    return this.ymd()[1] - 1
  }
  getUTCDate() {
    return this.ymd()[2]
  }
  getUTCDay() {
    return (((Math.floor(this.t / DAY) + 4) % 7) + 7) % 7
  }
  getUTCHours() {
    return Math.floor((((this.t % DAY) + DAY) % DAY) / 3600000)
  }
  toISOString() {
    const [y, m, d] = this.ymd()
    const ms = ((this.t % DAY) + DAY) % DAY
    const h = Math.floor(ms / 3600000)
    const mi = Math.floor((ms % 3600000) / 60000)
    const s = Math.floor((ms % 60000) / 1000)
    return `${pad(y, 4)}-${pad(m, 2)}-${pad(d, 2)}T${pad(h, 2)}:${pad(mi, 2)}:${pad(s, 2)}.${pad(ms % 1000, 3)}Z`
  }
}

// US Eastern time, the only zone the game names: EST (UTC-5), and EDT (UTC-4) from 2am on the second
// Sunday in March to 2am on the first Sunday in November.
function easternOffset(t: number) {
  const y = civilFromDays(Math.floor(t / DAY))[0]
  const sunday = (month: number, n: number) => {
    const first = daysFromCivil(y, month, 1)
    return first + ((7 - ((first + 4) % 7)) % 7) + (n - 1) * 7
  }
  const start = sunday(3, 2) * DAY + 7 * 3600000
  const end = sunday(11, 1) * DAY + 6 * 3600000
  return t >= start && t < end ? -4 : -5
}

type PartOptions = { timeZone?: string; month?: string; day?: string }
class DateTimeFormat {
  private zone: string
  constructor(_locale?: string, opts?: PartOptions) {
    this.zone = opts?.timeZone ?? 'UTC'
  }
  formatToParts(d: JsDate) {
    const t = d.getTime()
    const local = new JsDate(this.zone === 'America/New_York' ? t + easternOffset(t) * 3600000 : t)
    return [
      { type: 'month', value: pad(local.getUTCMonth() + 1, 2) },
      { type: 'literal', value: '/' },
      { type: 'day', value: pad(local.getUTCDate(), 2) },
    ]
  }
  // Servers run on UTC; per-player zones would come from the client.
  resolvedOptions() {
    return { timeZone: this.zone }
  }
}
export const JsIntl = { DateTimeFormat }

// JavaScript's Math.imul: the low 32 bits of a * b, as a signed 32-bit number.
// Array(n).fill(v)
export function __arrayOf<T>(n: number, v: T): T[] {
  const out: T[] = []
  for (let i = 0; i < n; i++) out.push(v)
  return out
}

export function imul(a: number, b: number) {
  const ah = (a >>> 16) & 0xffff
  const al = a & 0xffff
  const bh = (b >>> 16) & 0xffff
  const bl = b & 0xffff
  return (al * bl + ((((ah * bl + al * bh) & 0xffff) * 65536) >>> 0)) | 0
}

// Number formatting with thousands separators, like toLocaleString('en-US') on whole numbers.
export function localeString(n: number) {
  const neg = n < 0
  let s = `${Math.round(Math.abs(n))}`
  let out = ''
  while (s.length > 3) {
    out = `,${s.slice(s.length - 3)}${out}`
    s = s.slice(0, s.length - 3)
  }
  return (neg ? '-' : '') + s + out
}

// JavaScript truthiness: 0, '', NaN, null, undefined and false are false. In Lua only nil and false
// are, so transpile.mjs wraps every condition whose type could be a number or string in this.
export const __truthy = (v: unknown) => v !== undefined && v !== null && v !== false && v !== 0 && v !== '' && v === v

// Timers only drive toasts and sounds in game code, which mean nothing on the server, so they never fire.
export const setTimeout = (_fn: unknown, _ms?: number) => 0
export const clearTimeout = (_id?: unknown) => {}
export const setInterval = (_fn: unknown, _ms?: number) => 0
export const clearInterval = (_id?: unknown) => {}
export const console = { log: (..._a: unknown[]) => {}, warn: (..._a: unknown[]) => {}, error: (..._a: unknown[]) => {} }

// JSON. The game only stringifies to compare two values, so object keys are written sorted (the web
// writes them in insertion order); parse reads back what stringify writes.
const quote = (str: string) => {
  let out = '"'
  for (let i = 0; i < str.length; i++) {
    const c = str.charAt(i)
    out += c === '"' ? '\\"' : c === '\\' ? '\\\\' : c === '\n' ? '\\n' : c
  }
  return out + '"'
}
function stringify(v: unknown): string | undefined {
  if (v === null || v === undefined) return v === null ? 'null' : undefined
  if (typeof v === 'boolean') return v ? 'true' : 'false'
  if (typeof v === 'number') return v === v && v !== Infinity && v !== -Infinity ? `${v}` : 'null'
  if (typeof v === 'string') return quote(v)
  if (typeof v === 'function') return undefined
  if (Array.isArray(v)) return `[${v.map((x) => stringify(x) ?? 'null').join(',')}]`
  const o = v as Record<string, unknown>
  const parts: string[] = []
  for (const k of Object.keys(o).sort()) {
    const x = stringify(o[k])
    if (x !== undefined) parts.push(`${quote(k)}:${x}`)
  }
  return `{${parts.join(',')}}`
}
function parse(text: string): unknown {
  let i = 0
  const ws = () => {
    while (i < text.length && ' \t\n\r'.includes(text.charAt(i))) i++
  }
  const value = (): unknown => {
    ws()
    const c = text.charAt(i)
    if (c === '{') {
      i++
      const o: Record<string, unknown> = {}
      ws()
      if (text.charAt(i) === '}') return (i++, o)
      for (;;) {
        ws()
        const k = value() as string
        ws()
        i++ // :
        o[k] = value()
        ws()
        if (text.charAt(i++) === '}') return o
      }
    }
    if (c === '[') {
      i++
      const a: unknown[] = []
      ws()
      if (text.charAt(i) === ']') return (i++, a)
      for (;;) {
        a.push(value())
        ws()
        if (text.charAt(i++) === ']') return a
      }
    }
    if (c === '"') {
      let out = ''
      i++
      while (text.charAt(i) !== '"') {
        let ch = text.charAt(i++)
        if (ch === '\\') {
          ch = text.charAt(i++)
          if (ch === 'n') ch = '\n'
          else if (ch === 't') ch = '\t'
        }
        out += ch
      }
      i++
      return out
    }
    for (const [word, v] of [['true', true], ['false', false], ['null', null]] as const) {
      if (text.slice(i, i + word.length) === word) return (i += word.length, v)
    }
    const start = i
    while (i < text.length && '+-0123456789.eE'.includes(text.charAt(i))) i++
    if (i === start) throw new Error('bad JSON')
    return Number(text.slice(start, i))
  }
  return value()
}
export const JsJSON = { stringify, parse }
// No browser storage on the server: reads come back empty and writes are dropped.
export const localStorage = {
  getItem: (_k: string): string | null => null,
  setItem: (_k: string, _v: string) => {},
  removeItem: (_k: string) => {},
}

// String ordering for sorts. JavaScript's localeCompare follows the locale's collation; this compares
// character codes, which only differs for accented letters and mixed case.
export const __localeCompare = (a: string, b: string) => (a < b ? -1 : a > b ? 1 : 0)

// Math.random, swappable so tests can replay the web game's exact rolls.
let rng = () => math.random()
export const __random = () => rng()
export function setRandom(fn: () => number) {
  rng = fn
}

// Object literals with a spread or a possibly-null value: transpile.mjs turns `{ ...a, k: v }` into
// `__obj(shape, __SPREAD, a, 'k', v)`, because a Lua table can't hold a key whose value is nil, and
// JavaScript relies on `{ ...old, need: null }` clearing `need`. The real __obj is Luau code in the
// patched lualib (transpile.mjs, LUALIB_PATCH); `shape` is never evaluated, it only carries the type.
export const __SPREAD = {}
export function __obj<T>(_shape: false | (() => T), ..._parts: unknown[]): T {
  return undefined as unknown as T
}
