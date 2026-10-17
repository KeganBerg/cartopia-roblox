# Cartopia (Roblox)

The Roblox version of [Cartopia](https://github.com/KeganBerg/Cartopia). The web game's rules and
economy (`src/game` in the web repo) are converted to Luau automatically, so the Roblox game runs
the same code as the web game and stays in step when it changes. The town, cars and UI are rebuilt
in Studio.

## What's here

| Path | What it is |
| --- | --- |
| `src/shared/Game/*.luau` | **Generated** from the web game's `src/game/data.ts`, `race.ts`, `store.ts` and everything they import (54 modules). Don't edit by hand; change the web game or the converter. |
| `src/shared/RaceFloors.luau` | The fastest legal finish time for each PI, **generated** from the web game's referee migration. |
| `src/server/Towns.luau` | Runs every player's town on the server with the web game's own store, and checks which actions clients may ask for. |
| `src/server/Saves.luau` | Player saves in a DataStore (`Towns_v1`), with session locking. |
| `src/server/init.server.luau` | Wires it up: loads and saves towns, ticks the town clock every second, autosaves every 5 minutes, and serves the remotes. |
| `src/client/Remote.luau` | The client's side: `Remote.act("buyCar", "pip", "#c62828")`, and a copy of the town in the client's store. |
| `tools/transpile/` | The TypeScript-to-Luau converter (see below). |

Layout (Rojo):

```
ReplicatedStorage.Shared       <- src/shared   rules shared by server and client
ServerScriptService.Server     <- src/server   towns, saves, remotes
StarterPlayer.StarterPlayerScripts.Client <- src/client   remotes now; camera, input, HUD later
```

## How the economy works

The server is the only place a town changes. Each player's state lives on the server; when a
client calls `Remote.act(action, ...)`, the server checks the action is on the allowed list in
`Towns.luau` with the right kinds of arguments, rate-limits it (20 at once, 10 a second), moves the
town clock on, and runs the web game's own action for it. The client then gets
`{ save, need, panel, toasts }` on the `Cartopia.Town` remote.

Actions whose results the web game takes from elsewhere (race results, crates, gem purchases,
gifts, arcade payouts) are not on the allowed list yet. They come back once the server works those
results out itself.

Remotes, in `ReplicatedStorage.Cartopia`:

- `Act` (RemoteFunction): `(action, ...args) -> ok, result` (or `false, reason`)
- `Town` (RemoteEvent): the player's town after every change

Saves are the web game's `SaveState`, so a save moves between the two games unchanged. Loading takes
a lock in the same `UpdateAsync` that reads the save; a lock not refreshed for 30 minutes counts as
abandoned. If another server still holds a player's lock after 5 tries, the player is kicked with a
"try again" message instead of getting a blank town that would overwrite theirs.

## The converter

`node tools/transpile/transpile.mjs <web repo>` converts the web game with
[TypeScriptToLua](https://typescripttolua.github.io/) (target Luau), with fixes for the places
where JavaScript and Luau disagree:

- Truthiness: `0`, `''` and `NaN` are false in JavaScript, so conditions, `!`, `||` and `&&` on
  numbers and strings go through `__truthy`.
- Setting a field to `null` in an object literal or spread (`{ ...car, jobEndsAt: null }`) really
  clears it (`__obj`).
- Bitwise operators, `Math.imul`, `Date`, `Intl.DateTimeFormat` (for the US East Coast day),
  `JSON`, `localeCompare` and `toLocaleString` have Luau versions in `tools/transpile/js.ts`.
- `for` loops with `continue` still run their `i++`.
- Browser-only parts (sound, timers, local storage, the 3D scene) are stubbed in
  `tools/transpile/stubs`.

The converter stops with an error when it finds something it can't convert, so a web change can't
quietly break the Roblox game.

## Tests

The tests run outside Studio with the standalone [Luau](https://github.com/luau-lang/luau/releases)
binaries, from the project root:

```sh
luau tests/run.luau                # about 6 seconds
luau -O2 tests/floors.luau         # a few minutes: recomputes all 250 referee floors
```

- `tests/parity.luau` replays 7,835 inputs recorded from the web game's rules
  (`tools/gen-golden.mjs` → `tests/Golden.luau`) and expects exactly the same answers.
- `tests/store.luau` plays a 60-step session (building, jobs, cars, upgrades, goals, land, a week
  away) through the web store and the converted one (`tools/store-script.mjs`,
  `tools/gen-store-golden.mjs` → `tests/StoreGolden.luau`) and compares every save.
- `tests/server.luau` checks the session locking, the allowed actions, and that towns stay separate
  and survive a save round trip.

### When the web game changes

With the web repo checked out next to this one and its packages installed (`npm ci`):

```sh
npm ci --prefix tools/transpile                 # once
node tools/transpile/transpile.mjs ../cartopia  # rewrites src/shared/Game and RaceFloors.luau
node tools/gen-golden.mjs ../cartopia
node tools/gen-store-golden.mjs ../cartopia
luau tests/run.luau
```

The publish workflow does this on its own (below).

## Publishing

`.github/workflows/publish.yml` publishes the live game on every push to `main`, and checks the web
game every 15 minutes. Each run converts the web game, re-records the golden data, runs the tests
and only publishes if they pass. Setup (Open Cloud key, ids) is in the workflow file's header.

A publish replaces the whole place with what Rojo builds, so anything made in Studio has to be
saved into this repo (as `.rbxm` models) or the next publish overwrites it.

## Next steps

1. Check in Studio that the shared modules load (they use Roblox's string requires,
   `require("./data")`) and that a town loads, saves and reloads.
2. The town: grid placement, roads, and building and car models in Studio, drawn from the client's
   copy of the town.
3. UI: HUD, shop, showroom, garage and race screens, calling `Remote.act`.
4. Races on the server, so race results can go on the allowed list.
