// Bakes the web game's car skins (scene/skins.ts: animated patterns drawn by a shader inside the
// paint) into flat tiles Roblox can lay on a car, one pair per skin number:
//   skin<n>-base.png: the paint's colour under the skin, drawn on white paint (the game tints it
//                     the car's colour, so on any paint it comes out as the shader's mix);
//   skin<n>-glow.png: the skin's glow, its strength in the alpha.
// Each tile is one car-length (one web unit) across, seen straight on and frozen at one moment
// (Roblox has no shader, so the layers' parallax and pulses are lost).
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

const FRAG = `#version 300 es
precision highp float;
precision highp int;
${glsl}
uniform int uId;
uniform int uMode;
in vec2 vUv;
out vec4 o;
vec3 srgb(vec3 c) { c = clamp(c, 0.0, 1.0); return mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(0.0031308, c)); }
void main() {
  vec3 p = vec3(vUv, 0.0);
  vec3 col = vec3(1.0), glow = vec3(0.0);
  float rough = 0.5;
  skinShade(uId, p, vec3(0.0, 0.0, 1.0), vec3(0.0, 0.0, -1.0), 1.0, col, glow, rough);
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
const tiles = await page.evaluate(({ VERT, FRAG, ids, SIZE }) => {
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
  for (const id of ids) for (const mode of [0, 1]) {
    gl.uniform1i(gl.getUniformLocation(prog, 'uId'), id)
    gl.uniform1i(gl.getUniformLocation(prog, 'uMode'), mode)
    gl.clearColor(0, 0, 0, 0)
    gl.clear(gl.COLOR_BUFFER_BIT)
    gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4)
    out[`skin${id}-${mode ? 'glow' : 'base'}.png`] = canvas.toDataURL('image/png').split(',')[1]
  }
  return out
}, { VERT, FRAG, ids, SIZE })
await browser.close()

mkdirSync(OUT, { recursive: true })
for (const [file, b64] of Object.entries(tiles)) writeFileSync(join(OUT, file), Buffer.from(b64, 'base64'))
writeFileSync(join(OUT, 'skins.json'), JSON.stringify({ span: 1, skins: ids.map((n) => ({ n, base: `skin${n}-base.png`, glow: `skin${n}-glow.png` })) }, null, 1) + '\n')
console.log(`baked ${ids.length} skins into ${OUT}`)
