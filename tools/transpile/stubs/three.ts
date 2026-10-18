// The two pieces of three.js the game code uses (game/kart.ts builds its tracks with them):
// Vector3, and a closed centripetal CatmullRomCurve3 with getLength / getSpacedPoints, worked out
// the same way three.js does (arc lengths from 200 divisions, then evenly spaced points).

export class Vector3 {
  x: number; y: number; z: number
  constructor(x = 0, y = 0, z = 0) { this.x = x; this.y = y; this.z = z }
  distanceTo(v: Vector3) { return Math.sqrt((this.x - v.x) ** 2 + (this.y - v.y) ** 2 + (this.z - v.z) ** 2) }
}

// A cubic for one coordinate, as three.js's CubicPoly.initNonuniformCatmullRom.
function poly(x0: number, x1: number, x2: number, x3: number, dt0: number, dt1: number, dt2: number) {
  let t1 = (x1 - x0) / dt0 - (x2 - x0) / (dt0 + dt1) + (x2 - x1) / dt1
  let t2 = (x2 - x1) / dt1 - (x3 - x1) / (dt1 + dt2) + (x3 - x2) / dt2
  t1 *= dt1; t2 *= dt1
  const c0 = x1, c1 = t1, c2 = -3 * x1 + 3 * x2 - 2 * t1 - t2, c3 = 2 * x1 - 2 * x2 + t1 + t2
  return (t: number) => c0 + c1 * t + c2 * t * t + c3 * t * t * t
}

const DIVISIONS = 200

export class CatmullRomCurve3 {
  points: Vector3[]
  closed: boolean
  lengths: number[] | null = null
  constructor(points: Vector3[], closed = false, _type = 'centripetal') { this.points = points; this.closed = closed }

  getPoint(t: number): Vector3 {
    const points = this.points, l = points.length
    const p = (l - (this.closed ? 0 : 1)) * t
    let intPoint = Math.floor(p)
    let weight = p - intPoint
    if (this.closed) intPoint += intPoint > 0 ? 0 : (Math.floor(Math.abs(intPoint) / l) + 1) * l
    else if (weight === 0 && intPoint === l - 1) { intPoint = l - 2; weight = 1 }
    const at = (i: number) => points[((i % l) + l) % l]
    let p0: Vector3, p3: Vector3
    if (this.closed || intPoint > 0) p0 = at(intPoint - 1)
    else p0 = new Vector3(2 * points[0].x - points[1].x, 2 * points[0].y - points[1].y, 2 * points[0].z - points[1].z)
    const p1 = at(intPoint), p2 = at(intPoint + 1)
    if (this.closed || intPoint + 2 < l) p3 = at(intPoint + 2)
    else p3 = new Vector3(2 * points[l - 1].x - points[l - 2].x, 2 * points[l - 1].y - points[l - 2].y, 2 * points[l - 1].z - points[l - 2].z)
    // Centripetal: knot spacing is the square root of each chord's length.
    const d2 = (a: Vector3, b: Vector3) => (a.x - b.x) ** 2 + (a.y - b.y) ** 2 + (a.z - b.z) ** 2
    let dt0 = Math.pow(d2(p0, p1), 0.25), dt1 = Math.pow(d2(p1, p2), 0.25), dt2 = Math.pow(d2(p2, p3), 0.25)
    if (dt1 < 1e-4) dt1 = 1.0
    if (dt0 < 1e-4) dt0 = dt1
    if (dt2 < 1e-4) dt2 = dt1
    return new Vector3(
      poly(p0.x, p1.x, p2.x, p3.x, dt0, dt1, dt2)(weight),
      poly(p0.y, p1.y, p2.y, p3.y, dt0, dt1, dt2)(weight),
      poly(p0.z, p1.z, p2.z, p3.z, dt0, dt1, dt2)(weight),
    )
  }

  getLengths(): number[] {
    if (this.lengths) return this.lengths
    const cache: number[] = [0]
    let last = this.getPoint(0), sum = 0
    for (let p = 1; p <= DIVISIONS; p++) {
      const current = this.getPoint(p / DIVISIONS)
      sum += current.distanceTo(last)
      cache.push(sum)
      last = current
    }
    this.lengths = cache
    return cache
  }

  getLength(): number { const l = this.getLengths(); return l[l.length - 1] }

  getUtoTmapping(u: number): number {
    const arcLengths = this.getLengths()
    const il = arcLengths.length
    const targetArcLength = u * arcLengths[il - 1]
    let low = 0, high = il - 1, i = 0
    while (low <= high) {
      i = Math.floor(low + (high - low) / 2)
      const comparison = arcLengths[i] - targetArcLength
      if (comparison < 0) low = i + 1
      else if (comparison > 0) high = i - 1
      else { high = i; break }
    }
    i = high
    if (arcLengths[i] === targetArcLength) return i / (il - 1)
    const lengthBefore = arcLengths[i]
    const segmentLength = arcLengths[i + 1] - lengthBefore
    const segmentFraction = (targetArcLength - lengthBefore) / segmentLength
    return (i + segmentFraction) / (il - 1)
  }

  getPointAt(u: number): Vector3 { return this.getPoint(this.getUtoTmapping(u)) }

  getSpacedPoints(divisions = 5): Vector3[] {
    const points: Vector3[] = []
    for (let d = 0; d <= divisions; d++) points.push(this.getPointAt(d / divisions))
    return points
  }
}

