/** @noSelfInFile */
// Stand-in for zustand's persist: saving is the Roblox server's job (DataStores), so it passes through.
import type { StateCreator } from './__zustand'
export const persist = <T>(init: StateCreator<T>, _opts?: unknown): StateCreator<T> => init
