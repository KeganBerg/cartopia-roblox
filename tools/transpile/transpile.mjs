// Turns the web game's game-rule modules (src/game/*.ts) into Luau with TypeScriptToLua, so the
// Roblox version runs the very same rules instead of a hand-written copy that drifts.
// Usage: node tools/transpile/transpile.mjs <path to the Cartopia web repo>
//
// The web code is copied to a scratch folder and lightly rewritten first (REWRITES below): browser
// APIs point at js.ts, and the few constructs TypeScriptToLua can't handle are swapped for
// equivalents. Output goes to src/shared/Game, one ModuleScript per module, plus lualib.
import { execFileSync } from 'node:child_process'
import { cpSync, existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, statSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { dirname, join, relative, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { createRequire } from 'node:module'

const ts = createRequire(import.meta.url)('typescript')

const here = dirname(fileURLToPath(import.meta.url))
const root = resolve(here, '../..')
const web = resolve(process.argv[2] ?? '../cartopia')
const out = join(root, 'src/shared/Game')

// TypeScriptToLua 1.37 bug: for Luau it turns `c ? a : b` into an if-expression even when a branch
// needs statements run first (a spread, an optional chain...), so those run whatever `c` is. Patch
// it to fall back to the safe if-statement form in that case. Idempotent.
{
  const file = join(here, 'node_modules/typescript-to-lua/dist/transformation/visitors/conditional.js')
  const bug = `        // Luau's ternary operator doesn't have these issues
        return lua.createConditionalExpression(context.transformExpression(expression.condition), context.transformExpression(expression.whenTrue), context.transformExpression(expression.whenFalse), expression);`
  const fix = `        // Luau's ternary operator doesn't have these issues (patched by tools/transpile: only when no branch needs preceding statements)
        const c = (0, preceding_statements_1.transformInPrecedingStatementScope)(context, () => context.transformExpression(expression.condition));
        const t = (0, preceding_statements_1.transformInPrecedingStatementScope)(context, () => context.transformExpression(expression.whenTrue));
        const f = (0, preceding_statements_1.transformInPrecedingStatementScope)(context, () => context.transformExpression(expression.whenFalse));
        if (t.precedingStatements.length > 0 || f.precedingStatements.length > 0) return transformProtectedConditionalExpression(context, expression, c, t, f);
        context.addPrecedingStatements(c.precedingStatements);
        return lua.createConditionalExpression(c.result, t.result, f.result, expression);`
  const src = readFileSync(file, 'utf8')
  if (src.includes(bug)) writeFileSync(file, src.replace(bug, fix))
  else if (!src.includes('patched by tools/transpile')) throw new Error('TypeScriptToLua changed: re-check the conditional patch')
}

// TypeScriptToLua 1.37 bug: it prints a Luau if-expression bare where it is an operand, so
// `(c ? a : b) && x` comes out as `if c then a else b and x`, which Luau reads as
// `if c then a else (b and x)`. Patch the printer to always bracket one there. Idempotent.
{
  const file = join(here, 'node_modules/typescript-to-lua/dist/LuaPrinter.js')
  const bug = `            return lua.isFunctionExpression(expression) || lua.isTableExpression(expression);`
  const fix = `            return lua.isFunctionExpression(expression) || lua.isTableExpression(expression) || lua.isConditionalExpression(expression); // patched by tools/transpile`
  const src = readFileSync(file, 'utf8')
  if (src.includes(bug)) writeFileSync(file, src.replace(bug, fix))
  else if (!src.includes('patched by tools/transpile')) throw new Error('TypeScriptToLua changed: re-check the printer patch')
}

// Lua tables can't hold nil, so `{ ...old, need: null }` would keep old.need. __TS__Obj (what
// `__obj` calls) builds such literals and remembers which keys it set to nil, in a weak table, and
// the patched __TS__ObjectAssign (Object.assign and TypeScriptToLua's own spreads) clears those keys
// too, so "set to null" survives being spread into another object, like zustand's set() does.
const LUALIB_PATCH = `local __TS__NilKeys = setmetatable({}, { __mode = "k" })
local __TS__SPREAD = {}

local function __TS__CopyInto(target, source, nils)
    for key, value in pairs(source) do
        target[key] = value
        if nils then nils[key] = nil end
    end
    local sourceNils = __TS__NilKeys[source]
    if sourceNils then
        for key in pairs(sourceNils) do
            target[key] = nil
            if nils then nils[key] = true end
        end
    end
end

local function __TS__Obj(_shape, ...)
    local t, nils = {}, {}
    local n = select("#", ...)
    local parts = { ... }
    for i = 1, n, 2 do
        local key, value = parts[i], parts[i + 1]
        if key == __TS__SPREAD then
            if type(value) == "table" then __TS__CopyInto(t, value, nils) end
        else
            t[key] = value
            nils[key] = if value == nil then true else nil
        end
    end
    if next(nils) then __TS__NilKeys[t] = nils end
    return t
end

local function __TS__ObjectAssign(target, ...)
    local n = select("#", ...)
    local sources = { ... }
    local nils = __TS__NilKeys[target]
    for i = 1, n do
        local source = sources[i]
        if type(source) == "table" then
            if __TS__NilKeys[source] and not nils then
                nils = {}
                __TS__NilKeys[target] = nils
            end
            __TS__CopyInto(target, source, nils)
        end
    end
    return target
end
`
function patchLualib(src) {
  const start = src.indexOf('local function __TS__ObjectAssign(target, ...)')
  if (start < 0) throw new Error('lualib changed: __TS__ObjectAssign not found')
  const end = src.indexOf('\nend\n', start) + 5
  src = src.slice(0, start) + LUALIB_PATCH + src.slice(end)
  // Roblox's _G is a plain shared table, not the globals, so the Promise and async helpers'
  // _G.pcall and _G.coroutine came back nil there (any async function failed in the live game).
  src = src.replace('local ____pcall = _G.pcall', 'local ____pcall = pcall').replace('local ____coroutine = _G.coroutine or ({})', 'local ____coroutine = coroutine')
  if (/_G\./.test(src)) throw new Error('lualib changed: it reads _G, which Roblox does not fill')
  return src.replace(/\nreturn \{\n/, '\nreturn {\n  __TS__Obj = __TS__Obj,\n  __TS__SPREAD = __TS__SPREAD,\n')
}

// The modules the Roblox game uses; whatever they import comes along too.
export const ENTRIES = JSON.parse(readFileSync(join(here, 'entries.json'), 'utf8'))

const work = mkdtempSync(join(tmpdir(), 'transpile-'))
cpSync(join(web, 'src'), join(work, 'src'), { recursive: true })
cpSync(join(here, 'js.ts'), join(work, 'src/__js.ts'))
// Browser-only modules the game code imports, swapped for small stand-ins (stubs/).
const STUBS = {
  'stubs/zustand.ts': 'src/__zustand.ts',
  'stubs/zustand-middleware.ts': 'src/__zustand_middleware.ts',
  'stubs/sound.ts': 'src/lib/sound.ts',
  'stubs/prefs.ts': 'src/lib/prefs.ts',
  'stubs/boostTrail.ts': 'src/scene/boostTrail.ts',
  'stubs/three.ts': 'src/__three.ts',
}
for (const [from, to] of Object.entries(STUBS)) cpSync(join(here, from), join(work, to))
// The same stand-ins after transpiling, where Luau can do what TypeScript can't (catch any sfx.* call).
const LUAU_STUBS = {
  // Every sfx.* call goes to `heard` when something has set it (the server's Towns collects them
  // for the player's client to play, see client/Sounds/Sfx), and is silent otherwise.
  lib_sound: [
    'local M = { heard = nil :: ((string, ...any) -> ())? }',
    'M.sfx = setmetatable({}, { __index = function(_, name)',
    '\treturn function(...)',
    '\t\tif M.heard then',
    '\t\t\tM.heard(name, ...)',
    '\t\tend',
    '\tend',
    'end })',
    'return M',
    '',
  ].join('\n'),
}

// Regular expressions the game uses, each swapped for a function call that does the same job
// (TypeScriptToLua has no regex support). A new regex fails the build until it's added here.
const REGEX = [
  [/\.replace\(\/\[\^A-Z0-9 \]\/g, ''\)/g, ".split('').filter((c) => (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c === ' ').join('')"],
  [/const HEX = \/\^#\[0-9a-f\]\{6\}\$\//, "const HEX = { test: (s: string) => s.length === 7 && s[0] === '#' && s.slice(1).split('').every((c) => (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f')) }"],
]
const REWRITES = [
  ...REGEX,
  // Lua lists can't hold nil: STRIPES' "no stripe" entry becomes false.
  [/export const STRIPES = \[null,/, 'export const STRIPES: (string | null)[] = [false as unknown as null,'],
  // Likewise merge.ts's missing quarters of a 4x4: a nil would shorten the list, and every() then
  // passed a single merged square as a whole 4x4 block on offer.
  [/alike\(g\.anchor, q\.anchor\) \? q : null/, 'alike(g.anchor, q.anchor) ? q : (false as unknown as null)'],
  [/Math\.imul\(/g, '__imul('],
  [/Math\.hypot\(/g, '__hypot('],
  // Float32Arrays (kart tracks) keep their 0-based indexes and single precision (js.ts __zeros).
  [/new Float32Array\((?=[^()]*\)(?!\.fill))/g, '__zeros('],
  [/new Array\(([^()]*)\)\.fill\(([^()]*)\)/g, '__arrayOf($1, $2)'],
  [/(?<![\w.])Array\(([^()]*)\)\.fill\(([^()]*)\)/g, '__arrayOf($1, $2)'],
  // Typed arrays are plain lists here (they start at zero, or at what .fill() gives).
  [/new (?:Float32|Float64|Int32|Int8|Uint8)Array\(([^()]*)\)\.fill\(([^()]*)\)/g, '__arrayOf($1, $2)'],
  [/new (?:Float32|Float64|Int32|Int8|Uint8)Array\(([^()]*)\)/g, '__arrayOf($1, 0)'],
  // Math functions passed around as values (a default `rand = Math.random`) need a real function.
  [/Math\.random(?!\s*\()/g, '(() => __random())'],
  [/Math\.random\(\)/g, '__random()'],
  [/Math\.(floor|ceil|round|abs|sqrt|sign)(?!\s*\()/g, '((x: number) => Math.$1(x))'],
  [/(?<!new )Intl\.DateTimeFormat\(/g, 'new Intl.DateTimeFormat('],
  [/([\w.?]+)\.toLocaleString\(\)/g, '__localeString($1)'],
  // Passing a named function straight to map/filter trips TypeScriptToLua's `this` checks.
  [/\(Boolean\)/g, "((x: any) => !!x)"],
  [/\.(map|filter|some|every|forEach|find)\(([A-Za-z_]\w*)\)/g, '.$1((x: any) => $2(x))'],
  // The arcade's device bests are parsed JSON (untyped); give the list its type so .map converts.
  [/Array\.isArray\(b\.park\) \? b\.park\.map\(/, 'Array.isArray(b.park) ? (b.park as unknown[]).map('],
  // Town traffic keeps a following distance that grows with speed (about 0.7s behind the car in
  // front) instead of riding its bumper; queued at a light it still closes up to GAP.
  [/\n(\s*)cap\(a\.gap - room\)\n/, '\n$1cap(a.gap - room)\n$1limit = Math.min(limit, Math.max(0, a.gap - room) / HEADWAY)\n'],
  [/\nconst GAP = ([\d.]+) \/\/ bumper to bumper when queued\n/, '\nconst GAP = $1 // bumper to bumper when queued\nconst HEADWAY = 0.7 // seconds kept behind the car in front (tools/transpile)\n'],
]
// Rewrites that must find their spot: the build fails if the web's code moves out from under them.
const REQUIRED = [['scene/traffic/sim.ts', 'a.gap - room) / HEADWAY'], ['scene/traffic/sim.ts', 'const HEADWAY = ']]

function walk(dir) {
  return readdirSync(dir).flatMap((f) => {
    const p = join(dir, f)
    return statSync(p).isDirectory() ? walk(p) : p.endsWith('.ts') || p.endsWith('.tsx') ? [p] : []
  })
}
// Text rewrites first, on every file.
for (const file of walk(join(work, 'src'))) {
  if (file.endsWith('__js.ts')) continue
  let src = readFileSync(file, 'utf8')
  for (const [from, to] of REWRITES) src = src.replace(from, to)
  for (const [path, mark] of REQUIRED) {
    if (file.replace(/\\/g, '/').endsWith(path) && !src.includes(mark)) throw new Error(`${path}: a tools/transpile rewrite no longer applies (${mark})`)
  }
  const toRoot = relative(dirname(file), join(work, 'src')).replace(/\\/g, '/') || '.'
  src = src.replace(/from 'zustand'/g, `from '${toRoot}/__zustand'`).replace(/from 'zustand\/middleware'/g, `from '${toRoot}/__zustand_middleware'`)
  src = src.replace(/from 'three'/g, `from '${toRoot}/__three'`).replace(/from 'three\/examples\/jsm\/utils\/BufferGeometryUtils\.js'/g, `from '${toRoot}/__three'`)
  writeFileSync(file, src)
}

// Then two rewrites that need the type checker, on every module the entries reach:
//  - Bitwise operators become calls to js.ts helpers (TypeScriptToLua's Luau output uses Lua 5.3
//    operators, which Luau doesn't have). `h ^= x` becomes `h = __bxor(h, x)`.
//  - JavaScript truthiness: in Lua, 0 and '' count as true. Every condition, !, && and || whose
//    operand could be a number or string goes through __truthy, and `a || b` keeps its value
//    semantics (`a` if truthy, else `b`).
const K = ts.SyntaxKind
const BITWISE = new Map([
  [K.AmpersandToken, '__band'], [K.BarToken, '__bor'], [K.CaretToken, '__bxor'],
  [K.LessThanLessThanToken, '__shl'], [K.GreaterThanGreaterThanToken, '__shr'], [K.GreaterThanGreaterThanGreaterThanToken, '__ushr'],
  [K.AmpersandEqualsToken, '__band'], [K.BarEqualsToken, '__bor'], [K.CaretEqualsToken, '__bxor'],
  [K.LessThanLessThanEqualsToken, '__shl'], [K.GreaterThanGreaterThanEqualsToken, '__shr'], [K.GreaterThanGreaterThanGreaterThanEqualsToken, '__ushr'],
])
const COMPOUND = new Set([K.AmpersandEqualsToken, K.BarEqualsToken, K.CaretEqualsToken, K.LessThanLessThanEqualsToken, K.GreaterThanGreaterThanEqualsToken, K.GreaterThanGreaterThanGreaterThanEqualsToken])
const F = ts.TypeFlags
const LOOSE = F.Number | F.NumberLiteral | F.String | F.StringLiteral | F.TemplateLiteral | F.BigInt | F.BigIntLiteral | F.Any | F.Unknown | F.Enum | F.EnumLiteral | F.TypeParameter | F.Index | F.IndexedAccess | F.StringMapping
// Callbacks whose return value these array methods test for truthiness.
const PREDICATES = new Set(['filter', 'some', 'every', 'find', 'findIndex', 'findLast', 'findLastIndex'])

const program = ts.createProgram({
  rootNames: [...ENTRIES.map((e) => join(work, 'src', e)), join(work, 'src/__js.ts')],
  options: { target: ts.ScriptTarget.ESNext, module: ts.ModuleKind.ESNext, moduleResolution: ts.ModuleResolutionKind.Bundler, lib: ['lib.esnext.d.ts'], types: [], strict: false, skipLibCheck: true, jsx: ts.JsxEmit.React, noEmit: true },
})
const checker = program.getTypeChecker()
const loose = (node) => {
  const t = checker.getTypeAtLocation(node)
  const parts = t.isUnion() ? t.types : [t]
  return parts.some((p) => (p.flags & LOOSE) !== 0)
}
const simple = (e) => ts.isIdentifier(e) || e.kind === K.ThisKeyword || ts.isLiteralExpression(e) ||
  ((ts.isPropertyAccessExpression(e)) && !e.questionDotToken && simple(e.expression))

// Luau allows 200 upvalues per function, and the game store's big closure uses more imported names
// than that. So named imports (`import { a } from './x'`) become namespace imports, and each use of
// `a` becomes `__ns_x.a`: one upvalue per module instead of one per name.
function namespaceImports(sf, f) {
  const aliases = new Map() // import specifier symbol -> [namespace name, exported name]
  const spaces = []
  for (const st of sf.statements) {
    if (!ts.isImportDeclaration(st) || !st.importClause || st.importClause.isTypeOnly) continue
    const nb = st.importClause.namedBindings
    if (!nb || !ts.isNamedImports(nb)) continue
    const ns = f.createUniqueName(`__ns_${st.moduleSpecifier.text.replace(/[^A-Za-z0-9]/g, '_')}`)
    let any = false
    for (const el of nb.elements) {
      if (el.isTypeOnly) continue
      const sym = checker.getSymbolAtLocation(el.name)
      if (sym) {
        aliases.set(sym, [ns, (el.propertyName ?? el.name).text])
        any = true
      }
    }
    if (any) spaces.push([st, ns])
  }
  return { aliases, spaces }
}

// Object literals that need __obj: any spread, or any value that could be null or undefined.
const NULLISH = F.Null | F.Undefined | F.Void | F.Any | F.Unknown
function needsObj(lit) {
  if (lit.properties.some((p) => ts.isMethodDeclaration(p) || ts.isGetAccessor(p) || ts.isSetAccessor(p))) return false
  // Wrapping hides the literal's contextual type, which would leave callback parameters untyped.
  const fn = (p) => ts.isPropertyAssignment(p) && (ts.isArrowFunction(p.initializer) || ts.isFunctionExpression(p.initializer))
  if (lit.properties.some(fn)) return false
  return lit.properties.some((p) => {
    if (ts.isSpreadAssignment(p)) return true
    const value = ts.isShorthandPropertyAssignment(p) ? p.name : p.initializer
    if (value.kind === K.NullKeyword || (ts.isIdentifier(value) && value.text === 'undefined')) return true
    const t = checker.getTypeAtLocation(value)
    return (t.isUnion() ? t.types : [t]).some((x) => (x.flags & NULLISH) !== 0)
  })
}

// Whether a loop body has a `continue` for that loop (not one for a loop nested inside it).
let loopCount = 0
function continues(body) {
  let hit = false
  const walk = (n) => {
    if (hit || ts.isFunctionLike(n) || ts.isIterationStatement(n, false)) return
    if (ts.isContinueStatement(n)) {
      if (n.label) throw new Error(`labelled continue at ${n.getSourceFile().fileName}:${n.getStart()}`)
      hit = true
      return
    }
    ts.forEachChild(n, walk)
  }
  walk(body)
  return hit
}

function rewrite(sf) {
  const used = new Set()
  const f = ts.factory
  const { aliases, spaces } = namespaceImports(sf, f)
  const spaceOf = new Map(spaces)
  const call = (name, args) => {
    used.add(name)
    return f.createCallExpression(f.createIdentifier(name), undefined, args)
  }
  const paren = (e) => f.createParenthesizedExpression(e)
  // `orig` is the untransformed node (for its type); `e` the rewritten one.
  // Without strict mode TypeScript types `a && b` as b's type, so `list.length && x < 1` looks like a
  // boolean though it can be 0: a condition built from && and || is loose if any operand is.
  const looseCond = (o) => {
    while (ts.isParenthesizedExpression(o)) o = o.expression
    if (ts.isBinaryExpression(o) && (o.operatorToken.kind === K.AmpersandAmpersandToken || o.operatorToken.kind === K.BarBarToken)) return looseCond(o.left) || looseCond(o.right)
    return loose(o)
  }
  const cond = (orig, e) => (orig && looseCond(orig) ? call('__truthy', [e]) : e)
  // a || b, a && b with a loose left side, without evaluating `a` twice.
  const logical = (orig, left, right, isOr) => {
    if (!loose(orig.left)) return null
    const pick = (v) => (isOr ? f.createConditionalExpression(call('__truthy', [v]), undefined, v, undefined, right) : f.createConditionalExpression(call('__truthy', [v]), undefined, right, undefined, v))
    if (simple(orig.left)) return paren(pick(left))
    const v = f.createUniqueName('v')
    const fn = f.createArrowFunction(undefined, undefined, [f.createParameterDeclaration(undefined, undefined, v)], undefined, undefined, paren(pick(v)))
    return f.createCallExpression(paren(fn), undefined, [left])
  }
  let changed = false
  const thisVoid = () => f.createParameterDeclaration(undefined, undefined, 'this', undefined, f.createKeywordTypeNode(K.VoidKeyword))
  const hasThis = (params) => params.length > 0 && ts.isIdentifier(params[0].name) && params[0].name.text === 'this'
  const visit = (ctx) => (node) => {
    const orig = node
    // Function types (`tick: (now: number) => void`) get an explicit `this: void`: TypeScriptToLua
    // otherwise gives the functions they describe a self parameter, even under @noSelfInFile.
    if (ts.isFunctionTypeNode(node) && !hasThis(node.parameters)) {
      changed = true
      const inner = ts.visitEachChild(node, visit(ctx), ctx)
      return f.updateFunctionTypeNode(inner, inner.typeParameters, f.createNodeArray([thisVoid(), ...inner.parameters]), inner.type)
    }
    if (ts.isMethodSignature(node) && !hasThis(node.parameters)) {
      changed = true
      const inner = ts.visitEachChild(node, visit(ctx), ctx)
      return f.updateMethodSignature(inner, inner.modifiers, inner.name, inner.questionToken, inner.typeParameters, f.createNodeArray([thisVoid(), ...inner.parameters]), inner.type)
    }
    if (ts.isImportDeclaration(node) && spaceOf.has(node)) {
      // Keep the type-only names (and the module's side effects) and add the namespace import.
      return [
        node,
        f.createImportDeclaration(undefined, f.createImportClause(false, undefined, f.createNamespaceImport(spaceOf.get(node))), node.moduleSpecifier),
      ]
    }
    if (ts.isIdentifier(node) && aliases.size && !ts.isImportSpecifier(node.parent) && !(ts.isPropertyAccessExpression(node.parent) && node.parent.name === node) &&
      !(ts.isPropertyAssignment(node.parent) && node.parent.name === node) && !ts.isTypeReferenceNode(node.parent) && !ts.isQualifiedName(node.parent)) {
      const sym = checker.getSymbolAtLocation(node)
      const hit = sym && aliases.get(sym)
      if (hit) return f.createPropertyAccessExpression(hit[0], hit[1])
    }
    if (ts.isShorthandPropertyAssignment(node) && aliases.size) {
      const sym = checker.getShorthandAssignmentValueSymbol(node)
      const hit = sym && aliases.get(sym)
      if (hit) return f.createPropertyAssignment(node.name.text, f.createPropertyAccessExpression(hit[0], hit[1]))
    }
    // Predicate callbacks: wrap what they return.
    if (ts.isCallExpression(node) && ts.isPropertyAccessExpression(node.expression) && PREDICATES.has(node.expression.name.text) && node.arguments.length) {
      const cb = node.arguments[0]
      if ((ts.isArrowFunction(cb) || ts.isFunctionExpression(cb))) {
        const sig = checker.getSignatureFromDeclaration(cb)
        const ret = sig && checker.getReturnTypeOfSignature(sig)
        const parts = ret ? (ret.isUnion() ? ret.types : [ret]) : []
        if (parts.some((p) => (p.flags & LOOSE) !== 0)) {
          const visited = ts.visitEachChild(node, visit(ctx), ctx)
          const newCb = visited.arguments[0]
          let body
          if (ts.isBlock(newCb.body)) {
            const wrapReturns = (n) => {
              if (ts.isFunctionLike(n) && n !== newCb) return n
              if (ts.isReturnStatement(n) && n.expression) return f.updateReturnStatement(n, call('__truthy', [n.expression]))
              return ts.visitEachChild(n, wrapReturns, ctx)
            }
            body = ts.visitEachChild(newCb.body, wrapReturns, ctx)
          } else body = call('__truthy', [newCb.body])
          const cb2 = ts.isArrowFunction(newCb)
            ? f.updateArrowFunction(newCb, newCb.modifiers, newCb.typeParameters, newCb.parameters, newCb.type, newCb.equalsGreaterThanToken, body)
            : f.updateFunctionExpression(newCb, newCb.modifiers, newCb.asteriskToken, newCb.name, newCb.typeParameters, newCb.parameters, newCb.type, body)
          return f.updateCallExpression(visited, visited.expression, visited.typeArguments, [cb2, ...visited.arguments.slice(1)])
        }
      }
    }
    node = ts.visitEachChild(node, visit(ctx), ctx)
    if (ts.isCallExpression(node) && ts.isPropertyAccessExpression(node.expression) && node.expression.name.text === 'localeCompare') {
      return call('__localeCompare', [node.expression.expression, node.arguments[0]])
    }
    if (ts.isBinaryExpression(node) && BITWISE.has(node.operatorToken.kind)) {
      const value = call(BITWISE.get(node.operatorToken.kind), [node.left, node.right])
      return paren(COMPOUND.has(node.operatorToken.kind) ? f.createAssignment(node.left, value) : value)
    }
    if (ts.isPrefixUnaryExpression(node) && node.operator === K.TildeToken) return paren(call('__bnot', [node.operand]))
    if (ts.isPrefixUnaryExpression(node) && node.operator === K.ExclamationToken) return f.updatePrefixUnaryExpression(node, cond(orig.operand, node.operand))
    if (ts.isBinaryExpression(node) && (node.operatorToken.kind === K.BarBarToken || node.operatorToken.kind === K.AmpersandAmpersandToken)) {
      return logical(orig, node.left, node.right, node.operatorToken.kind === K.BarBarToken) ?? node
    }
    if (ts.isBinaryExpression(node) && (node.operatorToken.kind === K.BarBarEqualsToken || node.operatorToken.kind === K.AmpersandAmpersandEqualsToken) && loose(orig.left)) {
      throw new Error(`${sf.fileName}: ||= / &&= on a number or string isn't handled yet`)
    }
    if (ts.isObjectLiteralExpression(node) && needsObj(orig)) {
      used.add('__obj')
      used.add('__SPREAD')
      const parts = []
      node.properties.forEach((p) => {
        if (ts.isSpreadAssignment(p)) parts.push(f.createIdentifier('__SPREAD'), p.expression)
        else if (ts.isShorthandPropertyAssignment(p)) parts.push(f.createStringLiteral(p.name.text), p.objectAssignmentInitializer ?? f.createIdentifier(p.name.text))
        else {
          const name = p.name
          const key = ts.isComputedPropertyName(name) ? name.expression : ts.isIdentifier(name) || ts.isPrivateIdentifier(name) ? f.createStringLiteral(name.text) : name
          parts.push(key, p.initializer)
        }
      })
      // `false as true && (() => literal)`: types the result as the literal without ever building it.
      const shape = f.createBinaryExpression(f.createAsExpression(f.createFalse(), f.createLiteralTypeNode(f.createTrue())), K.AmpersandAmpersandToken,
        f.createParenthesizedExpression(f.createArrowFunction(undefined, undefined, [], undefined, undefined, f.createParenthesizedExpression(node))))
      return f.createCallExpression(f.createIdentifier('__obj'), undefined, [shape, ...parts])
    }
    if (ts.isConditionalExpression(node)) return f.updateConditionalExpression(node, cond(orig.condition, node.condition), node.questionToken, node.whenTrue, node.colonToken, node.whenFalse)
    if (ts.isIfStatement(node)) return f.updateIfStatement(node, cond(orig.expression, node.expression), node.thenStatement, node.elseStatement)
    if (ts.isWhileStatement(node)) return f.updateWhileStatement(node, cond(orig.expression, node.expression), node.statement)
    if (ts.isDoStatement(node)) return f.updateDoStatement(node, node.statement, cond(orig.expression, node.expression))
    // Luau's `continue` skips what TypeScriptToLua puts at the end of the loop body: a for loop's
    // incrementor. Such loops become `init; while (true) { if (!first) inc; if (!cond) break; body }`.
    if (ts.isForStatement(node) && node.incrementor && continues(orig.statement)) {
      const first = f.createIdentifier(`____first${++loopCount}`)
      const head = []
      if (node.initializer) head.push(ts.isVariableDeclarationList(node.initializer) ? f.createVariableStatement(undefined, node.initializer) : f.createExpressionStatement(node.initializer))
      head.push(f.createVariableStatement(undefined, f.createVariableDeclarationList([f.createVariableDeclaration(first, undefined, undefined, f.createTrue())], ts.NodeFlags.Let)))
      const body = [f.createIfStatement(first, f.createExpressionStatement(f.createAssignment(first, f.createFalse())), f.createExpressionStatement(node.incrementor))]
      if (node.condition) body.push(f.createIfStatement(f.createLogicalNot(paren(cond(orig.condition, node.condition))), f.createBreakStatement()))
      body.push(...(ts.isBlock(node.statement) ? node.statement.statements : [node.statement]))
      return f.createBlock([...head, f.createWhileStatement(f.createTrue(), f.createBlock(body, true))], true)
    }
    if (ts.isForStatement(node) && node.condition) return f.updateForStatement(node, node.initializer, cond(orig.condition, node.condition), node.incrementor, node.statement)
    return node
  }
  const result = ts.transform(sf, [(ctx) => (n) => ts.visitNode(n, visit(ctx))])
  if (!used.size && !spaces.length && !changed) return { src: null, used }
  return { src: ts.createPrinter().printFile(result.transformed[0]), used }
}

const jsPath = join(work, 'src/__js.ts')
for (const sf of program.getSourceFiles()) {
  const file = sf.fileName
  if (!file.startsWith(join(work, 'src'))) continue
  const { src: rewritten, used } = rewrite(sf)
  let src = rewritten ?? readFileSync(file, 'utf8')
  if (file === jsPath) {
    writeFileSync(file, src)
    continue
  }
  const names = []
  if (/\bDate\b/.test(src)) names.push('JsDate as Date')
  if (/\bIntl\b/.test(src)) names.push('JsIntl as Intl')
  if (/\bJSON\b/.test(src)) names.push('JsJSON as JSON')
  if (src.includes('__imul(')) names.push('imul as __imul')
  if (src.includes('__hypot(')) names.push('hypot as __hypot')
  if (src.includes('__arrayOf(')) names.push('__arrayOf')
  if (src.includes('__zeros(')) names.push('__zeros')
  if (src.includes('__localeString(')) names.push('localeString as __localeString')
  if (src.includes('__random(')) names.push('__random')
  for (const g of ['setTimeout', 'clearTimeout', 'setInterval', 'clearInterval', 'console', 'localStorage']) if (new RegExp(`\\b${g}\\b`).test(src)) names.push(g)
  names.push(...used)
  if (names.length) {
    let rel = relative(dirname(file), join(work, 'src/__js')).replace(/\\/g, '/')
    if (!rel.startsWith('.')) rel = `./${rel}`
    src = `import { ${names.join(', ')} } from '${rel}'\n${src}`
  }
  // No `self` parameters anywhere, so Luau code calls actions as plain functions: state.tick(now).
  if (!src.startsWith('/** @noSelfInFile */')) src = `/** @noSelfInFile */\n${src}`
  writeFileSync(file, src)
}

writeFileSync(join(work, 'tsconfig.json'), JSON.stringify({
  compilerOptions: {
    target: 'ESNext', lib: ['ESNext'], module: 'ESNext', moduleResolution: 'bundler', strict: false, skipLibCheck: true,
    noImplicitAny: false, rootDir: 'src', outDir: 'out', types: [], noEmitOnError: false, jsx: 'react',
  },
  tstl: { luaTarget: 'Luau', noImplicitSelf: true, luaLibImport: 'require-minimal', noHeader: true },
  files: ENTRIES.map((e) => `src/${e}`),
}, null, 2))

let log = ''
try {
  log = execFileSync(join(here, 'node_modules/.bin/tstl'), ['-p', 'tsconfig.json'], { cwd: work, encoding: 'utf8' })
} catch (e) {
  log = `${e.stdout}${e.stderr}`
}
// Type errors are expected (the shims don't cover every DOM type); TypeScriptToLua's own errors mean
// something wasn't translated, so they stop the build.
const tstlErrors = log.split('\n').filter((l) => l.includes('error TSTL'))
if (tstlErrors.length) {
  console.error(tstlErrors.join('\n'))
  process.exit(1)
}

// Lay the output out flat in src/shared/Game, with requires Roblox and the Luau CLI both resolve.
const flat = (p) => p.replace(/\.lua$/, '').split('/').join('_').replace(/^game_/, '')
rmSync(out, { recursive: true, force: true })
mkdirSync(out, { recursive: true })
const lua = walk2(join(work, 'out'))
function walk2(dir) {
  return readdirSync(dir).flatMap((f) => {
    const p = join(dir, f)
    return statSync(p).isDirectory() ? walk2(p) : p.endsWith('.lua') ? [p] : []
  })
}
for (const file of lua) {
  const rel = relative(join(work, 'out'), file).replace(/\\/g, '/')
  const name = rel === 'lualib_bundle.lua' ? 'lualib_bundle' : flat(rel)
  let src = readFileSync(file, 'utf8').replace(/\bBIT32_LIB[.:]/g, 'bit32.')
  src = src.replace(/require\("([^"]+)"\)/g, (_, m) => `require("./${m === 'lualib_bundle' ? 'lualib_bundle' : flat(m.split('.').join('/'))}")`)
  const header = name === 'lualib_bundle'
    ? '--!nocheck\n-- TypeScriptToLua runtime (MIT licence). GENERATED: do not edit.\n'
    : `--!nocheck\n-- GENERATED by tools/transpile from the web game's src/${rel.replace(/\.lua$/, '.ts')}. Do not edit:\n-- change the web game and re-run the transpiler.\n`
  if (LUAU_STUBS[name]) src = LUAU_STUBS[name]
  if (name === 'lualib_bundle') src = patchLualib(src)
  if (name === '__js') src = src.replace(/(?:____exports\.__obj = function|function ____exports\.__obj)\([\s\S]*?\nend\n/, '____exports.__obj = ____lualib.__TS__Obj\n').replace(/____exports\.__SPREAD = \{\}/, '____exports.__SPREAD = ____lualib.__TS__SPREAD')
  writeFileSync(join(out, `${name}.luau`), header + src)
}
rmSync(work, { recursive: true, force: true })

// An array or string method called as a plain field (`list.find(...)`) means TypeScriptToLua didn't
// know the value's type (an `any`), so it wasn't translated and would fail at runtime.
const METHOD = /(?<![\w])(?!string\.|table\.|math\.|bit32\.|os\.|____lualib\.|____exports\.\w+\()[\w.]+\.(filter|map|find|findIndex|some|every|includes|push|pop|shift|unshift|slice|forEach|reduce|indexOf|join|concat|sort|splice|flat|flatMap|fill|startsWith|endsWith|split|replace|replaceAll|trim|toUpperCase|toLowerCase|padStart|padEnd|charAt|charCodeAt|repeat|at|toFixed|toString)\(/
const untranslated = []
for (const f of readdirSync(out)) {
  if (f === 'lualib_bundle.luau') continue
  readFileSync(join(out, f), 'utf8').split('\n').forEach((line, i) => {
    // (A class's own method named like one, `function Traffic.prototype.at(`, is its definition.)
    if (METHOD.test(line) && !line.trimStart().startsWith('--') && !/^\s*function [\w.]+\(/.test(line)) untranslated.push(`${f}:${i + 1}: ${line.trim().slice(0, 120)}`)
  })
}
if (untranslated.length) {
  console.error(`Untranslated method calls (an untyped value in the web code?):\n${untranslated.join('\n')}`)
  process.exit(1)
}
console.log(`wrote ${lua.length} modules to ${relative(root, out)}`)

// The referee's fastest allowed finish time per PI, from the newest migration that sets
// public.race_floor() (the web repo's race.test.ts checks it against race.ts). Computing one in
// Luau takes about a second, so Race.raceFloor reads this table first.
const migrations = join(web, 'supabase/migrations')
const sql = readdirSync(migrations).sort().map((f) => readFileSync(join(migrations, f), 'utf8')).filter((s) => s.includes('$floors$')).pop()
const floors = JSON.parse(/\$floors\$(.*)\$floors\$/s.exec(sql)[1])
const rows = []
for (let i = 0; i < floors.length; i += 10) rows.push('\t' + floors.slice(i, i + 10).join(', ') + ',')
const floorsDest = join(root, 'src/shared/RaceFloors.luau')
writeFileSync(floorsDest, [
  '--!strict',
  '-- GENERATED by tools/gen-catalog.mjs from the web game\'s race_floor() migration. Index = PI.',
  '-- The fastest finish time (seconds) the race referee accepts for a car with that PI.',
  '',
  'return {',
  ...rows,
  '}',
  '',
].join('\n'))
console.log(`wrote ${relative(root, floorsDest)}`)
