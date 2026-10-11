# Cartopia (Roblox)

The Roblox version of [Cartopia](https://github.com/KeganBerg/Cartopia), ported from the web game
rather than decompiled: the game rules are rewritten in Luau, and the town, cars and UI will be
rebuilt in Studio.

## What's here so far

Step 1 of the port: the shared game rules, tested against the web game.

| File | What it is |
| --- | --- |
| `src/shared/Catalog.luau` | Every building, car, mod, goal, skin, deal and price table. **Generated** from the web game's `src/game/data.ts`; don't edit it by hand. |
| `src/shared/Data.luau` | The rules over that catalog (upgrades, payouts, performance index, campaign, tasks, seasons, deals, paint...), hand-ported from `data.ts`. |
| `src/shared/Race.luau` | Drag race physics, launch, shifting, boost, AI timing, garage dyno and the referee's time floors, ported from `race.ts`. |
| `src/shared/RaceFloors.luau` | The fastest legal finish time for each PI. **Generated** from the web game's referee migration. |
| `src/shared/Clock.luau` | The 20-minute town day/night clock, from `clock.ts`. |
| `src/shared/Util.luau` | JavaScript-compatible rounding, UTC calendar math and list helpers. |
| `src/shared/Types.luau` | Types for the catalog tables. |
| `src/server`, `src/client` | Entry scripts (placeholders for now). |

All of `src/shared` replicates to `ReplicatedStorage.Shared`, so the server and clients use the
same rules. Everything is `--!strict` and type-checks clean with `luau-analyze`.

### Differences from the web code

- Lists are 1-based. Ids, building levels, gears (0 = first) and campaign race numbers keep the web
  game's numbering, so saves and ids carry over.
- `Data.drawTasks(period, key, level, owned)` takes `"daily"` or `"weekly"` instead of the task list,
  and a task's count comes from `Data.taskCount` (the web version keeps it as a function on each task).
- `Race.shiftQuality` returns two values, `quality, label`, instead of an object.
- `Race.raceFloor` reads `RaceFloors` first; working one out takes about a second
  (`Race.computeRaceFloor`).
- Times are milliseconds since the epoch, as on the web. The entry scripts point `Util.setClock` at
  `DateTime` so they're accurate to the millisecond.
- The East Coast date for events is worked out from US daylight-saving rules instead of `Intl`.

## Layout (Rojo)

```
ReplicatedStorage.Shared       <- src/shared   rules shared by server and client
ServerScriptService.Server     <- src/server   economy, saves (DataStores), races, traffic
StarterPlayer.StarterPlayerScripts.Client <- src/client   camera, input, HUD, effects
```

## Working on it

Install the tools with [Rokit](https://github.com/rojo-rbx/rokit) (`rokit install`), then:

```sh
rojo serve                         # live-sync into Studio with the Rojo plugin
rojo build -o Cartopia.rbxlx       # or build a place file to open in Studio
```

### Tests

The tests run outside Studio with the standalone [Luau](https://github.com/luau-lang/luau/releases)
binaries, from the project root:

```sh
luau tests/run.luau                # about 4 seconds
luau -O2 tests/floors.luau         # about a minute: recomputes all 250 referee floors
luau-analyze src/shared/*.luau     # type check
```

`tests/parity.luau` replays about 4,000 inputs recorded from the web game (`tests/Golden.luau`)
through the Luau ports and expects exactly the same answers, down to the last decimal.

### When the web game's data changes

With the web repo checked out next to this one and its packages installed (`npm ci`):

```sh
node tools/gen-catalog.mjs ../cartopia   # rewrites Catalog.luau and RaceFloors.luau
node tools/gen-golden.mjs ../cartopia    # rewrites tests/Golden.luau
luau tests/run.luau
```

New rules (functions) in `data.ts` or `race.ts` still need porting by hand; add a case for each to
`gen-golden.mjs` and an adapter in `tests/parity.luau`.

## Next steps

1. Check in Studio that the shared modules load. They use Roblox's string requires
   (`require("./Catalog")`); if that errors, switch them to `require(script.Parent.Catalog)`.
2. Server economy and saves: player profiles in DataStores (ProfileStore), and remotes for jobs,
   buying, upgrades and races, with the server checking every change.
3. The town: grid placement, roads, and building and car models in Studio.
4. UI: HUD, shop, showroom, garage and race screens.
5. Port the rest of `src/game` (traffic sim, crates, rivals, quests, weather) the same way.
