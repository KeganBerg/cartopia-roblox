// The session tools/gen-store-golden.mjs plays through the web store. Each step waits `wait` ms on
// the pinned clock, then calls the store action `do` with `args`. An arg like { def: 'pizza', i: 1 }
// is the second pizza place's uid, { car: 0 } the first car's, { goal: 0 } the first active goal.
export const START = Date.UTC(2026, 9, 17, 12)
export const SEED = 42

const MIN = 60_000
const businesses = [{ def: 'pizza', i: 0 }, { def: 'pizza', i: 1 }, { def: 'pizza', i: 2 }]
const workday = (wait) => [
  { do: 'tick', args: [{ now: true }], wait },
  { do: 'collectAll', args: [true] },
  ...businesses.map((b) => ({ do: 'tapBuilding', args: [b] })),
]

export const SCRIPT = [
  { do: 'tick', args: [{ now: true }] },
  { do: 'tapBuilding', args: [{ def: 'pizza', i: 0 }] },
  { do: 'tapBuilding', args: [{ def: 'pizza', i: 0 }], wait: 5 * MIN },
  { do: 'tick', args: [{ now: true }], wait: 20 * MIN },
  { do: 'tapBuilding', args: [{ def: 'pizza', i: 0 }] },
  { do: 'tapBuilding', args: [{ def: 'pizza', i: 1 }] },
  { do: 'tapBuilding', args: [{ def: 'pizza', i: 2 }] },
  { do: 'placeBuilding', args: ['rescue', 12, 12] },
  { do: 'placeBuilding', args: ['rescue', 11, 12] },
  { do: 'placeBuilding', args: ['pizza', 13, 14] },
  { do: 'paintRoad', args: [20, 11] },
  { do: 'paintRoad', args: [21, 11] },
  { do: 'bulldoze', args: [21, 11] },
  { do: 'bulldoze', args: [17, 9] },
  { do: 'buyCar', args: ['pip', '#c62828'] },
  { do: 'buyCar', args: ['lambo', '#c62828'] },
  { do: 'upgradeCar', args: [{ car: 0 }, 'engine'] },
  { do: 'upgradeCar', args: [{ car: 0 }, 'engine'] },
  { do: 'upgradeCar', args: [{ car: 1 }, 'tires'] },
  { do: 'assignCar', args: [{ def: 'pizza', i: 0 }, { car: 0 }] },
  { do: 'upgradeBuilding', args: [{ def: 'pizza', i: 1 }] },
  ...workday(30 * MIN),
  ...workday(30 * MIN),
  { do: 'claimGoal', args: [{ goal: 0 }] },
  { do: 'claimGoal', args: [{ goal: 1 }] },
  { do: 'refillFuel' },
  ...workday(45 * MIN),
  { do: 'buyPlot', args: [3, 1] },
  { do: 'sellCar', args: [{ car: 2 }] },
  ...workday(60 * MIN),
  ...workday(3 * 60 * MIN),
  { do: 'claimGoal', args: [{ goal: 0 }] },
  { do: 'upgradeBuilding', args: [{ def: 'pizza', i: 0 }] },
  { do: 'upgradeBuilding', args: [{ def: 'gas', i: 0 }] },
  ...workday(24 * 60 * MIN),
  { do: 'tick', args: [{ now: true }], wait: 7 * 24 * 60 * MIN },
]
