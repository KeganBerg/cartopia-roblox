# Cartopia (Roblox)

The Roblox version of [Cartopia](https://github.com/KeganBerg/Cartopia). The web game's rules and
economy (`src/game` in the web repo) are converted to Luau automatically, so the Roblox game runs
the same code as the web game and stays in step when it changes. The 3D models (every building,
car and street piece) are converted from the web game's own scene code too, so the town looks like
the web game's.

## What's here

| Path | What it is |
| --- | --- |
| `src/shared/Game/*.luau` | **Generated** from the web game's `src/game/data.ts`, `race.ts`, `store.ts` and everything they import (54 modules). Don't edit by hand; change the web game or the converter. |
| `src/shared/RaceFloors.luau` | The fastest legal finish time for each PI, **generated** from the web game's referee migration. |
| `src/server/Towns.luau` | Runs every player's town on the server with the web game's own store, and checks which actions clients may ask for. |
| `src/server/Saves.luau` | Player saves in a DataStore (`Towns_v1`), with session locking. |
| `src/server/init.server.luau` | Wires it up: loads and saves towns, ticks the town clock every second, autosaves every 5 minutes, and serves the remotes. |
| `src/shared/Models/` | `Catalog.luau`, `Scenery.luau` and `Meshes.luau` are **generated** by `tools/models`: every building (`id@level`), car and street piece as Roblox parts, and the countryside round the town (forest, farm, lake, each plot's wild meadow) with its meshes merged so it stays cheap to draw. `Builder.luau` builds them. |
| `src/server/TownView.luau` | Draws each player's town in `Workspace.Towns` from their save: land, lawn, roads (put together like the web's `RoadTile`), buildings and cars. |
| `src/client/Remote.luau` | The client's side: `Remote.act("buyCar", "pip", "#c62828")`, and a copy of the town in the client's store. |
| `src/client/` (rest) | The screens (HUD, shop, showroom, build mode, job bubbles), the web-style town camera (`TownCamera`), the shared day and night (`DayNight`), the countryside round the town (`Countryside`), the town's traffic and townspeople (`TownLife`), the race and crowd at a Speedway (`SpeedwayLife`) and the merged gas stations' and car washes' big centres at level 7-10, the Big Bison travel stop and the Bubble Car Spa, with their cars, brushes and customers (`CentreLife`, `Centres/`). |
| `src/client/Sounds/` | The music and sounds (see "Music and sounds" below). |
| `tools/transpile/` | The TypeScript-to-Luau converter (see below). |
| `tools/models/` | The model converter: renders the web game's models in Node, turns them into parts and meshes, and uploads the meshes to Roblox (`upload.mjs`). |
| `tools/emulate/` | Runs the real Luau outside Roblox (with Lune) and draws what it built, for previews without Studio. |

Layout (Rojo):

```
ReplicatedStorage.Shared       <- src/shared   rules shared by server and client
ServerScriptService.Server     <- src/server   towns, saves, remotes
StarterPlayer.StarterPlayerScripts.Client <- src/client   remotes, screens, camera, lighting
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

### Gem packs and car packs (Robux)

The Bank sells the web game's gem packs and car packs (`bucksPacks.ts`) as Roblox Developer
Products, one per pack, named exactly like the pack. `tools/products/sync.mjs` (run by
`.github/workflows/products.yml` when `tools/products/` changes) makes them, pricing each pack from
the web game's dollar price at Roblox's own Robux store rates (`prices.json`: "match-dollars", with
per-pack overrides; `null` stops selling a pack). The Open Cloud key needs the
`developer-product:read` and `developer-product:write` permissions for it.

The server (`src/server/Purchases.luau`) finds the products by name, opens Roblox's purchase prompt
from the `Bank` remote, and in `ProcessReceipt` pays the pack through the web store's own
`applyPurchases` (gems, plus coins and parts for the buyer's level, plus the car). Each PurchaseId
is written with the save in the same DataStore update, so a receipt Roblox sends twice pays once.
Car packs are one per account, and buying waits for the town's Crew House, as on the web.

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

## The 3D models

`node tools/models/build.mjs <web repo>` renders every building, car, street piece and lawn piece
with the web game's own components (`@react-three/test-renderer`, run by the web repo's vitest),
and converts what it drew: boxes, cylinders and balls become plain parts, everything else becomes a
mesh. Meshes are packed into one `.glb` per model (`build/meshes/`) and uploaded as Model assets by
`tools/models/upload.mjs`, which records their ids in `tools/models/assets.json`; the game loads
them with `InsertService` when the server starts. Until a mesh is uploaded the game draws a box in
its place. The publish workflow does all of this on every run (the Open Cloud key needs Assets read
and write for the upload).

Previews without Studio:

```
rojo build -o build/place.rbxl
lune run tools/emulate/town.luau build/place.rbxl build/town.json build/gui.json [shop|showroom]
node tools/emulate/render.mjs <web repo> build/town.json out.png build/gui.json
```

## Music and sounds

The web game synthesises its music and sounds as it plays; the Roblox game plays Kegan's
recordings of them. `node tools/audio/build.mjs <recordings folder>` (needs ffmpeg; the folder is
the project's `cartopia-roblox-music`) writes `audio/`: the 24 town songs and 18 club tracks one
file each, Rave Mode's build-up and drop, and three sprites (every sound effect, the tutorial's
voice lines, and a season's weather loops), listed in `audio/list.json`. Roblox caps audio uploads
a month, hence the sprites. The publish job uploads anything new (`tools/models/upload.mjs`, effects
first) and writes the ids into `src/shared/AudioAssets.luau` (`build.mjs --ids`); a sound not
uploaded yet stays silent.

In the game, `src/client/Sounds` plays them: `Sfx` (named like the web's `sfx.*` calls:
`Sfx.coin()`, `Sfx.crate.open("gold")`, `Sfx.rescue.reveal("rare")`), `Music` (three day and three
night songs a season, shuffled), `Ambience` (the town's sounds and weather; `Ambience.setWeather`,
`Ambience.thunder`), `Club` (the nightclub's track for the night), `Rave` (`Rave.start(dropAt)`),
`Voice` (`Voice.say("03-collect")`) and `Mixer` (the Menu's Music, Effects and Town sounds
settings, saved per account by `server/Prefs`). Sounds the store's actions make on the server
(`sfx.buy()` in store.ts) reach the player with the town's snapshot.

## Next steps

1. Check in Studio that the shared modules load (they use Roblox's string requires,
   `require("./data")`) and that a town loads, saves and reloads.
2. Races on the server, so race results can go on the allowed list; live racing; crews.
