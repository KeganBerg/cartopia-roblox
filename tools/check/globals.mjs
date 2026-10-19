// Catches the mistakes in the game's own scripts that only show up as errors in the live game:
// a name used before its `local` line, or misspelt, reads as an unknown global (nil there), and a
// syntax error stops the whole script. Runs luau-analyze over every hand-written script (not the
// converted src/shared/Game) and fails on either; Roblox's own globals are allowed.
//
//   node tools/check/globals.mjs        (luau-analyze on PATH, as publish.yml installs it)

import { execFileSync } from 'node:child_process'
import { readdirSync, statSync } from 'node:fs'
import { join, relative } from 'node:path'

const ROOT = join(import.meta.dirname, '../..')

const ROBLOX = new Set([
  'game', 'workspace', 'script', 'plugin', 'shared', 'Enum', 'Instance', 'Vector3', 'Vector2',
  'Vector3int16', 'Vector2int16', 'CFrame', 'Color3', 'BrickColor', 'UDim', 'UDim2', 'Rect',
  'Ray', 'Region3', 'Region3int16', 'NumberSequence', 'NumberSequenceKeypoint', 'ColorSequence',
  'ColorSequenceKeypoint', 'NumberRange', 'TweenInfo', 'DateTime', 'Random', 'Font', 'Faces',
  'Axes', 'PhysicalProperties', 'RaycastParams', 'OverlapParams', 'PathWaypoint', 'SharedTable',
  'Content', 'CatalogSearchParams', 'DockWidgetPluginGuiInfo', 'task', 'warn', 'tick', 'time',
  'wait', 'delay', 'spawn', 'elapsedTime', 'settings', 'UserSettings', 'stats', 'version',
  // `_, x = f()` assigns the throwaway global, which Roblox allows.
  '_',
])

function scripts(dir, out = []) {
  for (const name of readdirSync(dir)) {
    const p = join(dir, name)
    if (statSync(p).isDirectory()) {
      if (relative(ROOT, p) !== join('src', 'shared', 'Game')) scripts(p, out)
    } else if (name.endsWith('.luau') || name.endsWith('.lua')) {
      out.push(p)
    }
  }
  return out
}

const files = scripts(join(ROOT, 'src'))
let text
try {
  text = execFileSync('luau-analyze', files, { encoding: 'utf8', maxBuffer: 1 << 28, stdio: ['ignore', 'pipe', 'pipe'] })
} catch (e) {
  // It exits non-zero whenever it finds anything (the Roblox types it can't see, mostly).
  text = `${e.stdout ?? ''}${e.stderr ?? ''}`
}

const bad = []
for (const line of text.split('\n')) {
  const unknown = line.match(/^(.*?\(\d+,\d+\)): TypeError: Unknown global '([^']+)'/)
  if (unknown && !ROBLOX.has(unknown[2])) bad.push(`${unknown[1]}: unknown global '${unknown[2]}' (used before its local line, or misspelt?)`)
  else if (/: SyntaxError: /.test(line)) bad.push(line)
}
for (const b of bad) console.log(b.replace(ROOT + '/', ''))
console.log(`globals: ${files.length} scripts, ${bad.length} problems`)
process.exit(bad.length ? 1 : 0)
