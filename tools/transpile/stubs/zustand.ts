/** @noSelfInFile */
// Stand-in for zustand: one plain store, no React. Typed like zustand so the game code keeps its
// types (TypeScriptToLua needs them to translate array and string methods). The Roblox server swaps
// each player's state in and out around every action (see src/server/Towns.luau).
export type SetState<T> = (this: void, partial: Partial<T> | ((s: T) => Partial<T>), replace?: boolean) => void
export type StoreApi<T> = { getState: (this: void) => T; setState: SetState<T>; subscribe: (this: void, fn: (s: T) => void) => () => void }
export type StateCreator<T> = (this: void, set: SetState<T>, get: (this: void) => T, api: StoreApi<T>) => T

function make<T>(fn: StateCreator<T>): StoreApi<T> {
  let state = {} as T
  const api: StoreApi<T> = {
    getState: () => state,
    setState: (partial, replace) => {
      const next = typeof partial === 'function' ? (partial as (s: T) => Partial<T>)(state) : partial
      state = replace ? (next as T) : { ...state, ...next }
    },
    subscribe: () => () => {},
  }
  state = fn(api.setState, api.getState, api)
  return api
}
export function create<T>(): (fn: StateCreator<T>) => StoreApi<T>
export function create<T>(fn: StateCreator<T>): StoreApi<T>
export function create<T>(fn?: StateCreator<T>): any {
  return fn ? make(fn) : (f: StateCreator<T>) => make(f)
}
