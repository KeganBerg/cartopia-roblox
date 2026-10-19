// ---- The deep sky (Cartopia Roblox only): the Milky Way, nebulae, galaxies, planets, a black hole
// and a quasar, faded in with the night.
vec3 dirOf(float az, float el) { az = radians(az); el = radians(el); return vec3(cos(el) * sin(az), sin(el), cos(el) * cos(az)); }
// Where d lands on the flat of the sky round c (radians, roughly), and whether it's on c's side.
vec2 loc(vec3 d, vec3 c, out float on) {
  vec3 r = normalize(cross(c, vec3(0.0, 1.0, 0.0)));
  vec3 u = cross(r, c);
  float z = dot(d, c);
  on = step(0.6, z);
  return vec2(dot(d, r), dot(d, u)) / max(z, 0.05);
}
mat2 rot(float a) { float c = cos(a), s = sin(a); return mat2(c, -s, s, c); }
float fbm3(vec2 p) { float v = 0.0, a = 0.5; for (int i = 0; i < 5; i++) { v += a * noise(p); p = p * 2.03 + 11.7; a *= 0.5; } return v; }
vec3 nebula(vec3 d, vec3 c, float size, float seed, vec3 a, vec3 b) {
  float on; vec2 p = loc(d, c, on) / size;
  float r = length(p);
  if (on < 0.5 || r > 1.6) return vec3(0.0);
  float n = fbm3(p * 2.2 + seed);
  float wisp = fbm3(p * 5.0 - seed + n * 1.5);
  float shape = smoothstep(1.3, 0.1, r + (0.5 - n) * 0.9);
  float glow = pow(shape, 1.6) * (0.35 + wisp * 0.9);
  vec3 col = mix(a, b, smoothstep(0.35, 0.75, wisp + r * 0.3));
  // Dark dust threading through it.
  float dust = smoothstep(0.55, 0.7, fbm3(p * 3.4 + seed * 2.0));
  return col * glow * (1.0 - dust * 0.7) * 1.15;
}
vec3 galaxy(vec3 d, vec3 c, float size, float tilt, float turn, float squash, vec3 arm, vec3 core) {
  float on; vec2 p = loc(d, c, on) / size;
  if (on < 0.5 || dot(p, p) > 4.0) return vec3(0.0);
  p = rot(turn) * p;
  p.y /= squash;
  p = rot(tilt) * p;
  float r = length(p);
  float a = atan(p.y, p.x);
  float spiral = pow(0.5 + 0.5 * cos(2.0 * a - log(r + 0.02) * 4.2), 2.5);
  float disc = exp(-r * 3.2);
  float knots = 0.6 + 0.8 * noise(p * 14.0);
  vec3 col = arm * spiral * disc * knots * 1.6 + core * exp(-r * r * 60.0) * 1.8 + mix(core, arm, 0.5) * exp(-r * 6.0) * 0.35;
  return col;
}
// A planet's disc: true where it covers the sky, its colour in col.
float planet(vec3 d, vec3 c, float rad, vec3 light, int kind, out vec3 col) {
  float on; vec2 p = loc(d, c, on) / rad;
  float r2 = dot(p, p);
  col = vec3(0.0);
  if (on < 0.5) return 0.0;
  float cover = 0.0;
  if (r2 < 1.0) {
    vec3 n = vec3(p, sqrt(1.0 - r2));
    float lit = clamp(dot(n, normalize(light)), 0.0, 1.0);
    lit = 0.06 + 0.94 * smoothstep(0.0, 0.35, lit);
    vec3 base;
    if (kind == 0) {
      // A banded giant, cream and rust, with a storm.
      float band = sin(p.y * 13.0 + noise(p * 6.0) * 2.0);
      base = mix(vec3(0.93, 0.78, 0.55), vec3(0.78, 0.45, 0.25), 0.5 + 0.5 * band);
      base = mix(base, vec3(0.85, 0.3, 0.2), smoothstep(0.16, 0.05, length((p - vec2(0.3, -0.25)) * vec2(1.0, 1.8))));
    } else if (kind == 1) {
      // An ice world, teal with white swirls.
      base = mix(vec3(0.2, 0.62, 0.85), vec3(0.85, 0.97, 1.0), smoothstep(0.45, 0.8, fbm3(p * 3.0 + 4.0)));
    } else {
      // A rusty little world.
      base = mix(vec3(0.75, 0.32, 0.18), vec3(0.95, 0.6, 0.4), fbm3(p * 4.0 + 9.0));
    }
    col = base * lit;
    cover = smoothstep(1.0, 0.97, r2);
    // A thin bright rim of atmosphere.
    col += vec3(0.5, 0.7, 1.0) * smoothstep(0.85, 1.0, r2) * 0.4 * lit;
  }
  if (kind == 0) {
    // Its rings, tilted, hidden behind the ball on the far side.
    vec2 q = rot(0.35) * p;
    float e = length(vec2(q.x, q.y * 3.6));
    float ring = smoothstep(1.35, 1.4, e) * smoothstep(2.25, 2.15, e) * (0.65 + 0.35 * sin(e * 40.0));
    ring *= 1.0 - smoothstep(1.78, 1.85, e) * smoothstep(1.95, 1.88, e);
    float behind = step(r2, 1.0) * step(q.y, 0.0);
    float a = ring * (1.0 - behind);
    col = mix(col, vec3(0.95, 0.85, 0.65) * (0.35 + 0.65 * step(0.0, -q.x * 0.2 + 0.5)), a);
    cover = max(cover, a * 0.95);
  }
  return cover;
}
vec3 deepSky(vec3 d, inout vec3 col) {
  vec3 add = vec3(0.0);
  // The Milky Way: a broad river of light right across the sky, warm towards its heart, with dark
  // dust lanes down its middle.
  vec3 N = normalize(vec3(0.42, 0.5, -0.76));
  float b = dot(d, N);
  vec3 tq = normalize(cross(N, vec3(0.0, 1.0, 0.0)));
  float along = atan(dot(d, cross(N, tq)), dot(d, tq));
  vec2 mw = vec2(along * 3.0, b * 14.0);
  float body = exp(-b * b / 0.022) * (0.55 + 0.7 * fbm3(mw * 2.6));
  float heart = exp(-pow(along - 0.9, 2.0) / 0.5);
  float lane = smoothstep(0.45, 0.65, fbm3(mw * 2.2 + 5.0)) * exp(-b * b / 0.004);
  vec3 mwc = mix(vec3(0.35, 0.42, 0.95), vec3(1.0, 0.72, 0.5), heart);
  mwc = mix(mwc, vec3(0.85, 0.4, 0.95), smoothstep(0.55, 0.8, fbm3(mw * 0.8 + 2.0)) * 0.6);
  add += mwc * body * (1.0 - lane * 0.85) * (0.35 + heart * 0.45);
  // Its thick star clouds.
  vec3 sq = d * 520.0;
  vec3 sc = floor(sq);
  float sh = hash(sc.xy * 0.53 + sc.z * 1.91);
  add += vec3(0.9, 0.9, 1.0) * step(1.0 - 0.06 * body, sh) * smoothstep(0.45, 0.0, length(fract(sq) - 0.5)) * 0.9;
  // Bright coloured stars with a soft glow round them.
  vec3 cq = d * 90.0;
  vec3 cc = floor(cq);
  float ch = hash(cc.xy * 1.37 + cc.z * 2.71);
  float cs = step(0.985, ch) * exp(-dot(fract(cq) - 0.5, fract(cq) - 0.5) * 60.0);
  vec3 tint = mix(vec3(0.6, 0.75, 1.0), vec3(1.0, 0.7, 0.45), fract(ch * 91.3));
  add += tint * cs * 1.4;
  // Nebulae.
  add += nebula(d, dirOf(40.0, 32.0), 0.26, 3.0, vec3(0.95, 0.15, 0.6), vec3(0.2, 0.8, 1.0));
  add += nebula(d, dirOf(160.0, 22.0), 0.22, 7.0, vec3(1.0, 0.35, 0.12), vec3(1.0, 0.85, 0.4));
  add += nebula(d, dirOf(255.0, 45.0), 0.3, 13.0, vec3(0.2, 0.95, 0.65), vec3(0.4, 0.3, 1.0));
  add += nebula(d, dirOf(320.0, 16.0), 0.18, 21.0, vec3(0.65, 0.2, 1.0), vec3(1.0, 0.3, 0.45));
  add += nebula(d, dirOf(110.0, 62.0), 0.2, 31.0, vec3(0.1, 0.5, 1.0), vec3(0.9, 0.3, 0.9));
  // Galaxies: spirals at different tilts.
  add += galaxy(d, dirOf(85.0, 28.0), 0.1, 0.4, 0.6, 0.45, vec3(0.45, 0.65, 1.0), vec3(1.0, 0.9, 0.65));
  add += galaxy(d, dirOf(205.0, 52.0), 0.08, 1.3, -0.4, 0.8, vec3(0.9, 0.5, 1.0), vec3(1.0, 0.85, 0.7));
  add += galaxy(d, dirOf(300.0, 38.0), 0.09, 2.1, 1.1, 0.3, vec3(0.5, 0.9, 1.0), vec3(1.0, 0.95, 0.8));
  add += galaxy(d, dirOf(15.0, 70.0), 0.07, 0.0, 0.2, 0.6, vec3(1.0, 0.6, 0.5), vec3(1.0, 0.9, 0.7));
  // A quasar: a blazing point with two thin jets shooting out of it.
  {
    float on; vec2 p = loc(d, dirOf(130.0, 40.0), on);
    p = rot(0.7) * p;
    float jet = exp(-p.x * p.x / 0.0000045) * exp(-abs(p.y) / 0.07) * step(abs(p.y), 0.25);
    float knot = exp(-p.x * p.x / 0.00002) * exp(-pow(abs(p.y) - 0.11, 2.0) / 0.0002);
    float core = exp(-dot(p, p) / 0.00002) * 2.5 + exp(-length(p) / 0.012) * 0.6;
    add += on * (vec3(0.55, 0.75, 1.0) * (jet * 1.3 + knot * 0.8) + vec3(0.95, 0.95, 1.0) * core);
  }
  // A black hole: a glowing, tilted disc of hot gas round a perfectly black middle, with a thin
  // ring of light bent round its shadow.
  {
    float on; vec2 p = loc(d, dirOf(350.0, 27.0), on) / 0.04;
    if (on > 0.5 && dot(p, p) < 30.0) {
      vec2 q = rot(-0.25) * p;
      float r = length(p);
      float e = length(vec2(q.x, q.y * 4.0));
      float disc = smoothstep(1.2, 1.5, e) * smoothstep(4.2, 2.0, e);
      float beam = 0.55 + 0.45 * tanh(-q.x * 0.8);
      vec3 hot = mix(vec3(1.0, 0.35, 0.08), vec3(1.0, 0.92, 0.75), smoothstep(3.5, 1.4, e));
      float swirl = 0.7 + 0.3 * sin(atan(q.y * 4.0, q.x) * 6.0 + e * 5.0);
      float front = step(0.0, q.y) + step(1.0, r);
      // The disc's far side, bent up over the top and under the bottom of the shadow.
      float halo = smoothstep(0.25, 0.0, abs(r - 1.25)) * (0.6 + 0.4 * abs(p.y) / max(r, 0.01));
      float photon = exp(-pow(r - 1.04, 2.0) / 0.002);
      vec3 glow = hot * (disc * beam * swirl * 1.8 * min(front, 1.0) + halo * 0.9) + vec3(1.0, 0.9, 0.75) * photon * 1.2;
      float shadow = smoothstep(1.02, 0.95, r) * (1.0 - disc * step(0.0, q.y) * step(r, 1.0) * 0.0);
      col *= 1.0 - shadow;
      add *= 1.0 - shadow;
      add += glow * (1.0 - shadow * (1.0 - step(0.0, q.y) * disc));
    }
  }
  // Planets, drawn over everything behind them.
  vec3 pc;
  float pa = planet(d, dirOf(60.0, 18.0), 0.045, vec3(-0.7, 0.4, 0.6), 0, pc);
  col = mix(col, pc, pa); add *= 1.0 - pa;
  pa = planet(d, dirOf(235.0, 25.0), 0.028, vec3(0.8, 0.3, 0.5), 1, pc);
  col = mix(col, pc, pa); add *= 1.0 - pa;
  pa = planet(d, dirOf(185.0, 60.0), 0.016, vec3(0.2, -0.6, 0.7), 2, pc);
  col = mix(col, pc, pa); add *= 1.0 - pa;
  return add;
}
