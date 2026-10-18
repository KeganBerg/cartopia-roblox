// Bakes the web game's car skins (scene/skins.ts: animated patterns drawn by a shader inside the
// paint) into flat tiles Roblox can lay on a car, one pair per skin number:
//   skin<n>-base.png: the paint's colour under the skin, drawn on white paint (the game tints it
//                     the car's colour, so on any paint it comes out as the shader's mix);
//   skin<n>-glow.png: the skin's glow, its strength in the alpha;
//   skin<n>-glow2.png: the same glow a moment later.
// Each tile is one car-length (one web unit) across, seen straight on. Roblox has no shader, so the
// game brings the motion back by hand (Skins.luau): the two glows fade into each other for the
// pulses and twinkles, and slide with the camera as if they lay `depth` under the paint (the mean
// of the depths the skin's layers sit at, 0 for a skin drawn on the surface).
//
// node tools/models/skins.mjs <web repo>   (CHROMIUM=<path> picks the browser)
// The tiles are kept in tools/models/skins/ and go up with the other textures (build.mjs).
// Run it again when the web game's skins change.

import { readFileSync, writeFileSync, mkdirSync } from 'node:fs'
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
// The two moments the glow is drawn at.
const TIMES = [1.0, 2.6]

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
in vec2 vUv;
out vec4 o;
vec3 srgb(vec3 c) { c = clamp(c, 0.0, 1.0); return mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(0.0031308, c)); }
void main() {
  vec3 p = vec3(vUv, 0.0);
  vec3 col = vec3(1.0), glow = vec3(0.0);
  float rough = 0.5;
  skinShade(uId, p, vec3(0.0, 0.0, 1.0), vec3(0.0, 0.0, -1.0), uT, col, glow, rough);
  if (uMode == 0) { o = vec4(srgb(col), 1.0); return; }
  float a = clamp(max(glow.r, max(glow.g, glow.b)), 0.0, 1.0);
  o = vec4(a > 0.0 ? srgb(glow / max(a, 1e-4)) : vec3(0.0), a);
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
const tiles = await page.evaluate(({ VERT, FRAG, ids, SIZE, TIMES }) => {
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
  for (const id of ids) for (const [mode, t, file] of [[0, TIMES[0], 'base'], [1, TIMES[0], 'glow'], [1, TIMES[1], 'glow2']]) {
    gl.uniform1i(gl.getUniformLocation(prog, 'uId'), id)
    gl.uniform1i(gl.getUniformLocation(prog, 'uMode'), mode)
    gl.uniform1f(gl.getUniformLocation(prog, 'uT'), t)
    gl.clearColor(0, 0, 0, 0)
    gl.clear(gl.COLOR_BUFFER_BIT)
    gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4)
    out[`skin${id}-${file}.png`] = canvas.toDataURL('image/png').split(',')[1]
  }
  return out
}, { VERT, FRAG, ids, SIZE, TIMES })
await browser.close()

mkdirSync(OUT, { recursive: true })
for (const [file, b64] of Object.entries(tiles)) writeFileSync(join(OUT, file), Buffer.from(b64, 'base64'))
writeFileSync(join(OUT, 'skins.json'), JSON.stringify({ span: 1, skins: ids.map((n) => ({ n, depth: depthOf[n] ?? 0, base: `skin${n}-base.png`, glow: `skin${n}-glow.png`, glow2: `skin${n}-glow2.png` })) }, null, 1) + '\n')
console.log(`baked ${ids.length} skins into ${OUT}`)
