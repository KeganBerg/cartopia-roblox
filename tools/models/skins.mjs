// Bakes the web game's car skins (scene/skins.ts: animated patterns drawn by a shader inside the
// paint) into flat tiles Roblox can lay on a car, for each skin number:
//   skin<n>-base.png:  what the skin does to the paint under it, as a layer over the plain paint:
//                      the colour and see-through that, laid over any paint, best match the shader
//                      run on that paint (fitted over a spread of paints, in screen colours);
//   skin<n>-glow<k>.png: the skin's glow at moment k (FRAMES of them), its strength in the alpha.
// Each tile is one car-length (one web unit) across, seen straight on. Roblox has no shader, so the
// game brings the motion back by hand (client/SkinMotion): the glow plays through its moments,
// fading from one to the next, and slides with the camera as if it lay `depth` under the paint (the
// mean of the depths the skin's layers sit at, 0 for a skin drawn on the surface).
// It also draws each skin's picker swatch (data.ts SkinDef.swatch, CSS) as swatch-<id>.png.
//
// node tools/models/skins.mjs <web repo>   (CHROMIUM=<path> picks the browser)
// The tiles are kept in tools/models/skins/ and go up with the other textures (build.mjs).
// Run it again when the web game's skins change.

import { readFileSync, writeFileSync, mkdirSync, readdirSync, rmSync } from 'node:fs'
import { join, resolve, dirname } from 'node:path'
import { createRequire } from 'node:module'
import { fileURLToPath } from 'node:url'

const HERE = dirname(fileURLToPath(import.meta.url))
const WEB = resolve(process.argv[2] ?? '../web')
const OUT = join(HERE, 'skins')
const SIZE = 512

const src = readFileSync(join(WEB, 'src/scene/skins.ts'), 'utf8')
const start = src.indexOf('export const SKIN_GLSL = /* glsl */ `')
const glsl = src.slice(src.indexOf('`', start) + 1, src.indexOf('\n`', start))
const ids = [...new Set([...glsl.matchAll(/\bid == (\d+)\b/g)].map((m) => +m[1]))].sort((a, b) => a - b)
// The moments the glow is drawn at, half a second apart (SkinMotion plays them at that pace).
const FRAMES = 4
const TIMES = Array.from({ length: FRAMES }, (_, k) => 1.0 + k * 0.5)
// Paints (screen colours) the base layer is fitted over.
const PAINTS = [[0, 0, 0], [1, 1, 1], [0.5, 0.5, 0.5], [0.85, 0.15, 0.15], [0.15, 0.7, 0.25], [0.15, 0.35, 0.9], [0.95, 0.8, 0.2], [0.6, 0.2, 0.7]]

// The pickers' swatches: every body and mod skin (and Custom Colour) in data.ts, by id.
const dataTs = readFileSync(join(WEB, 'src/game/data.ts'), 'utf8')
const defs = dataTs.slice(dataTs.indexOf('export const SKINS'), dataTs.indexOf('export const TRACK_SKINS'))
const swatches = [...defs.matchAll(/\{\s*id: '(\w+)', n: \d+,[\s\S]*?swatch: '([^']*)'/g)].map((m) => ({ id: m[1], css: m[2] }))

// How deep each skin's layers lie: the depths its skAt calls ask for (a loop's taken at its middle
// pass, i = 1), averaged.
const depthOf = {}
const blocks = glsl.split(/\bif \(id == (\d+)\)/)
for (let i = 1; i < blocks.length; i += 2) {
  const ds = [...blocks[i + 1].matchAll(/skAt\(p, n, v, ([^)]*?)\)/g)].map((m) => {
    const x = m[1].replace(/\bfi\b/g, '1').replace(/\bi\b/g, '1')
    return /^[\d.\s+\-*?:=()]+$/.test(x) ? Function(`return (${x})`)() : 0.06
  })
  depthOf[blocks[i]] = ds.length ? Math.round((ds.reduce((a, b) => a + b, 0) / ds.length) * 1000) / 1000 : 0
}

const FRAG = `#version 300 es
precision highp float;
precision highp int;
${glsl}
uniform int uId;
uniform int uMode;
uniform float uT;
uniform vec3 uBase;
in vec2 vUv;
const float EDGE = 0.3;
out vec4 o;
vec3 srgb(vec3 c) { c = clamp(c, 0.0, 1.0); return mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(0.0031308, c)); }
vec3 shade(vec2 at) {
  vec3 col = uBase, glow = vec3(0.0);
  float rough = 0.5;
  skinShade(uId, vec3(at, 0.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 0.0, -1.0), uT, col, glow, rough);
  return uMode == 0 ? col : glow;
}
// The pattern isn't periodic, so laid side by side the tiles would show seams: near the far edges
// each tile fades into the pattern one tile back, which is what the next tile starts with.
void main() {
  vec2 w = smoothstep(1.0 - EDGE, 1.0, vUv);
  vec3 c = mix(mix(shade(vUv), shade(vUv - vec2(1.0, 0.0)), w.x), mix(shade(vUv - vec2(0.0, 1.0)), shade(vUv - vec2(1.0)), w.x), w.y);
  if (uMode == 0) { o = vec4(srgb(c), 1.0); return; }
  float a = clamp(max(c.r, max(c.g, c.b)), 0.0, 1.0);
  o = vec4(a > 0.0 ? srgb(c / max(a, 1e-4)) : vec3(0.0), a);
}`
const VERT = `#version 300 es
in vec2 aPos;
out vec2 vUv;
void main() { vUv = aPos * 0.5 + 0.5; gl_Position = vec4(aPos, 0.0, 1.0); }`

const req = createRequire(join(WEB, 'package.json'))
const { chromium } = req('playwright')
const browser = await chromium.launch({ ...(process.env.CHROMIUM ? { executablePath: process.env.CHROMIUM } : {}), args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'] })
const page = await browser.newPage()
page.on('console', (m) => m.type() === 'error' && console.error(m.text()))
const tiles = await page.evaluate(({ VERT, FRAG, ids, SIZE, TIMES, PAINTS }) => {
  const canvas = document.createElement('canvas')
  canvas.width = canvas.height = SIZE
  const gl = canvas.getContext('webgl2', { premultipliedAlpha: false, preserveDrawingBuffer: true, antialias: false })
  const shader = (type, text) => {
    const s = gl.createShader(type)
    gl.shaderSource(s, text)
    gl.compileShader(s)
    if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) throw new Error(gl.getShaderInfoLog(s))
    return s
  }
  const prog = gl.createProgram()
  gl.attachShader(prog, shader(gl.VERTEX_SHADER, VERT))
  gl.attachShader(prog, shader(gl.FRAGMENT_SHADER, FRAG))
  gl.linkProgram(prog)
  if (!gl.getProgramParameter(prog, gl.LINK_STATUS)) throw new Error(gl.getProgramInfoLog(prog))
  gl.useProgram(prog)
  const buf = gl.createBuffer()
  gl.bindBuffer(gl.ARRAY_BUFFER, buf)
  gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 1, -1, -1, 1, 1, 1]), gl.STATIC_DRAW)
  const at = gl.getAttribLocation(prog, 'aPos')
  gl.enableVertexAttribArray(at)
  gl.vertexAttribPointer(at, 2, gl.FLOAT, false, 0, 0)
  const out = {}
  const draw = (id, mode, t, base) => {
    gl.uniform1i(gl.getUniformLocation(prog, 'uId'), id)
    gl.uniform1i(gl.getUniformLocation(prog, 'uMode'), mode)
    gl.uniform1f(gl.getUniformLocation(prog, 'uT'), t)
    gl.uniform3fv(gl.getUniformLocation(prog, 'uBase'), base.map((c) => (c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4)))
    gl.clearColor(0, 0, 0, 0)
    gl.clear(gl.COLOR_BUFFER_BIT)
    gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4)
  }
  const flat = document.createElement('canvas')
  flat.width = flat.height = SIZE
  const ctx = flat.getContext('2d')
  for (const id of ids) {
    // The base: the shader's paint on each test paint, then per pixel the layer (colour c,
    // opacity a) for which (1 - a) * paint + a * c comes closest to it on all of them.
    const shots = PAINTS.map((paint) => {
      draw(id, 0, TIMES[0], paint)
      const px = new Uint8Array(SIZE * SIZE * 4)
      gl.readPixels(0, 0, SIZE, SIZE, gl.RGBA, gl.UNSIGNED_BYTE, px)
      return px
    })
    const img = ctx.createImageData(SIZE, SIZE)
    const K = PAINTS.length
    for (let y = 0; y < SIZE; y++) for (let x = 0; x < SIZE; x++) {
      const i = ((SIZE - 1 - y) * SIZE + x) * 4, o = (y * SIZE + x) * 4
      // out - paint = d - a * paint per channel: a shared, d per channel (d = a * c).
      let sxy = 0, sxx = 0
      const yb = [0, 0, 0], xb = [0, 0, 0]
      for (let c = 0; c < 3; c++) {
        for (let k = 0; k < K; k++) { yb[c] += shots[k][i + c] / 255 - PAINTS[k][c]; xb[c] += PAINTS[k][c] }
        yb[c] /= K; xb[c] /= K
        for (let k = 0; k < K; k++) {
          const dx = PAINTS[k][c] - xb[c], dy = shots[k][i + c] / 255 - PAINTS[k][c] - yb[c]
          sxy += dx * dy; sxx += dx * dx
        }
      }
      const a = Math.min(1, Math.max(0, -sxy / sxx))
      for (let c = 0; c < 3; c++) img.data[o + c] = a > 0.004 ? Math.round(255 * Math.min(1, Math.max(0, (yb[c] + a * xb[c]) / a))) : 0
      img.data[o + 3] = Math.round(255 * a)
    }
    ctx.putImageData(img, 0, 0)
    out[`skin${id}-base.png`] = flat.toDataURL('image/png').split(',')[1]
    TIMES.forEach((t, k) => {
      draw(id, 1, t, [1, 1, 1])
      out[`skin${id}-glow${k + 1}.png`] = canvas.toDataURL('image/png').split(',')[1]
    })
  }
  return out
}, { VERT, FRAG, ids, SIZE, TIMES, PAINTS })

// The swatches: each skin's CSS on a picker chip (36 px, drawn three times as sharp). The CSS's own
// background size stands, as on the web (its inline shorthand beats .skin-chip's cover).
const chips = await browser.newPage({ deviceScaleFactor: 3 })
await chips.setContent(`<body style="margin:0;background:transparent">${swatches.map((w, i) => `<div id="w${i}" style="width:36px;height:36px;background:${w.css.replace(/"/g, "'")}"></div>`).join('')}</body>`)
const pics = {}
for (const [i, w] of swatches.entries()) pics[`swatch-${w.id}.png`] = await chips.locator(`#w${i}`).screenshot({ omitBackground: true })
await browser.close()

mkdirSync(OUT, { recursive: true })
for (const f of readdirSync(OUT)) if (f.endsWith('.png')) rmSync(join(OUT, f))
for (const [file, b64] of Object.entries(tiles)) writeFileSync(join(OUT, file), Buffer.from(b64, 'base64'))
for (const [file, png] of Object.entries(pics)) writeFileSync(join(OUT, file), png)
writeFileSync(join(OUT, 'skins.json'), JSON.stringify({
  span: 1,
  step: TIMES[1] - TIMES[0],
  skins: ids.map((n) => ({ n, depth: depthOf[n] ?? 0, base: `skin${n}-base.png`, glows: TIMES.map((_, k) => `skin${n}-glow${k + 1}.png`) })),
  swatches: swatches.map((w) => ({ id: w.id, file: `swatch-${w.id}.png` })),
}, null, 1) + '\n')
console.log(`baked ${ids.length} skins and ${swatches.length} swatches into ${OUT}`)
