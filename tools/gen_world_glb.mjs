// 果蝇大脑 Demo —— 场景与果蝇模型生成脚本（零依赖，Node >= 18）
// 生成 entry/src/main/resources/rawfile/gltf/world.glb
//
// v1（M0）：地面圆盘 + 环形石块 + 果蝇（thorax/abdomen/head/eyes/antennae/legs/wings）
// v2（M4）：场景丰富化与玩法所需节点 —— 河流弧带 + 河岸卵石、树木 ×3（trunk/crown 二级摇摆）、
//          日月枢轴、星空、树冠果实、青蛙（含舌头）、各类特效节点（加号/风线/涟漪/路径点）、
//          以及果蝇的 head_pivot（进食低头用轴心）。
//
// 坐标约定：Y 向上，果蝇朝向 +Z，根节点位于地面接触点。
// 运行：node tools/gen_world_glb.mjs
import { writeFileSync, mkdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const OUT_FILE = join(dirname(fileURLToPath(import.meta.url)),
  '..', 'entry', 'src', 'main', 'resources', 'rawfile', 'gltf', 'world.glb');

// ---------- 数学工具 ----------
const DEG = Math.PI / 180;
function quatFromAxisAngle(ax, ay, az, angle) {
  const n = Math.hypot(ax, ay, az) || 1;
  const s = Math.sin(angle / 2);
  return { x: ax / n * s, y: ay / n * s, z: az / n * s, w: Math.cos(angle / 2) };
}
function quatMul(a, b) {
  return {
    x: a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y,
    y: a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x,
    z: a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w,
    w: a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z,
  };
}
function quatApply(q, v) {
  const tx = 2 * (q.y * v.z - q.z * v.y);
  const ty = 2 * (q.z * v.x - q.x * v.z);
  const tz = 2 * (q.x * v.y - q.y * v.x);
  return {
    x: v.x + q.w * tx + (q.y * tz - q.z * ty),
    y: v.y + q.w * ty + (q.z * tx - q.x * tz),
    z: v.z + q.w * tz + (q.x * ty - q.y * tx),
  };
}
function quatBetween(from, to) {
  const f = Math.hypot(...from), t = Math.hypot(...to);
  const a = [from[0] / f, from[1] / f, from[2] / f], b = [to[0] / t, to[1] / t, to[2] / t];
  const d = a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
  if (d > 0.99999) return { x: 0, y: 0, z: 0, w: 1 };
  if (d < -0.99999) { // 反向：任取垂直轴
    const ax = Math.abs(a[0]) < 0.9 ? [1, 0, 0] : [0, 1, 0];
    const axis = [a[1] * ax[2] - a[2] * ax[1], a[2] * ax[0] - a[0] * ax[2], a[0] * ax[1] - a[1] * ax[0]];
    return quatFromAxisAngle(...axis, Math.PI);
  }
  const c = [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]];
  return { x: c[0], y: c[1], z: c[2], w: 1 + d };
}
function quatY(angle) { return quatFromAxisAngle(0, 1, 0, angle); }
function quatX(angle) { return quatFromAxisAngle(1, 0, 0, angle); }
function quatZ(angle) { return quatFromAxisAngle(0, 0, 1, angle); }
function srgb2lin(hex) {
  const r = ((hex >> 16) & 255) / 255, g = ((hex >> 8) & 255) / 255, b = (hex & 255) / 255;
  const f = (c) => (c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4));
  return [f(r), f(g), f(b), 1];
}
function lin4(hex, alpha) {
  const c = srgb2lin(hex);
  return [c[0], c[1], c[2], alpha];
}
// 确定性伪随机（保证每次生成结果一致，便于 diff 与复现）
function makeRng(seed) {
  let s = seed >>> 0;
  return () => {
    s = (s * 1664525 + 1013904223) >>> 0;
    return s / 4294967296;
  };
}

// ---------- 几何构建 ----------
class Geometry {
  constructor() { this.positions = []; this.normals = []; this.indices = []; }
  addVertex(px, py, pz, nx, ny, nz) {
    this.positions.push(px, py, pz);
    this.normals.push(nx, ny, nz);
    return this.positions.length / 3 - 1;
  }
  addTri(a, b, c) { this.indices.push(a, b, c); }
  vertCount() { return this.positions.length / 3; }
}

// 单位球（经纬分段），随后按半径缩放：normal = position（单位球上即法线）
function makeSphere(latBands, lonBands) {
  const g = new Geometry();
  for (let i = 0; i <= latBands; i++) {
    const theta = i * Math.PI / latBands;
    for (let j = 0; j <= lonBands; j++) {
      const phi = j * 2 * Math.PI / lonBands;
      const x = Math.sin(theta) * Math.cos(phi);
      const y = Math.cos(theta);
      const z = Math.sin(theta) * Math.sin(phi);
      g.addVertex(x, y, z, x, y, z);
    }
  }
  for (let i = 0; i < latBands; i++) {
    for (let j = 0; j < lonBands; j++) {
      const a = i * (lonBands + 1) + j, b = a + lonBands + 1;
      g.addTri(a, b, a + 1); g.addTri(b, b + 1, a + 1);
    }
  }
  return g;
}

// 椭球：位置 = 单位球 * (a,b,c) + 平移；法线 ∝ (x/a², y/b², z/c²)
function makeEllipsoid(a, b, c, cx, cy, cz, lat = 14, lon = 20) {
  const g = makeSphere(lat, lon);
  for (let i = 0; i < g.vertCount(); i++) {
    const ix = i * 3;
    const px = g.positions[ix] * a, py = g.positions[ix + 1] * b, pz = g.positions[ix + 2] * c;
    const nRaw = [g.positions[ix] / a, g.positions[ix + 1] / b, g.positions[ix + 2] / c];
    const nl = Math.hypot(...nRaw) || 1;
    g.positions[ix] = px + cx; g.positions[ix + 1] = py + cy; g.positions[ix + 2] = pz + cz;
    g.normals[ix] = nRaw[0] / nl; g.normals[ix + 1] = nRaw[1] / nl; g.normals[ix + 2] = nRaw[2] / nl;
  }
  return g;
}

// ---------- v3 建模原语（用于提升模型精细度） ----------

// 剖面插值：pts 为 [[z, r], ...] 控制点，按 t 递增；用 smoothstep 段内插值避免折角。
// 返回函数 t → [r, z]
function makeProfile(pts) {
  return (t) => {
    const n = pts.length - 1;
    const x = Math.min(0.999999, Math.max(0, t)) * n;
    const i = Math.floor(x);
    const f = x - i;
    const s = f * f * (3 - 2 * f);
    return [
      pts[i][1] + (pts[i + 1][1] - pts[i][1]) * s,
      pts[i][0] + (pts[i + 1][0] - pts[i][0]) * s,
    ];
  };
}

// 旋转体（轴为 +Z）：profile(t) → [r, z]，t 从 0（前端）到 1（后端）。
// 法线由剖面切线推出：n2D = normalize(dr, -dz)，再绕 Z 旋成 3D。
function makeRevolutionZ(profile, seg = 24, lat = 20) {
  const g = new Geometry();
  const eps = 1e-3;
  const rings = [];
  for (let i = 0; i <= lat; i++) {
    const t = i / lat;
    const p = profile(t);
    // 端点半径允许收敛到 0（与 makeSphere 的极点同一做法）：整圈顶点重合，
    // 连接面退化为零面积三角形，表面仍是闭合的，不会露出内壁
    const r = Math.max(0, p[0]);
    const z = p[1];
    const pA = profile(Math.max(0, t - eps));
    const pB = profile(Math.min(1, t + eps));
    const dr = pB[0] - pA[0];
    const dz = pB[1] - pA[1];
    const nl = Math.hypot(dr, dz) || 1;
    const nr = dr / nl;
    const nz = -dz / nl;
    const ring = [];
    for (let j = 0; j <= seg; j++) {
      const phi = j * 2 * Math.PI / seg;
      const c = Math.cos(phi), s = Math.sin(phi);
      ring.push(g.addVertex(r * c, r * s, z, nr * c, nr * s, nz));
    }
    rings.push(ring);
  }
  for (let i = 0; i < lat; i++) {
    for (let j = 0; j < seg; j++) {
      const a = rings[i][j], b = rings[i][j + 1];
      const c = rings[i + 1][j], d = rings[i + 1][j + 1];
      g.addTri(a, c, d);
      g.addTri(a, d, b);
    }
  }
  return g;
}

// 扫掠管：沿折线 path 生成带半径变化的管（腿/树枝/触角/舌头共用）
function makeTube(path, radii, seg = 10, capStart = true, capEnd = true) {
  const g = new Geometry();
  const n = path.length;
  const dirs = [];
  for (let i = 0; i < n; i++) {
    const a = path[Math.max(0, i - 1)];
    const b = path[Math.min(n - 1, i + 1)];
    const d = [b[0] - a[0], b[1] - a[1], b[2] - a[2]];
    const L = Math.hypot(...d) || 1;
    dirs.push([d[0] / L, d[1] / L, d[2] / L]);
  }
  const rings = [];
  for (let i = 0; i < n; i++) {
    const d = dirs[i];
    const up = Math.abs(d[1]) > 0.9 ? [0, 0, 1] : [0, 1, 0];
    const u = norm3(cross3(up, d));
    const v = norm3(cross3(d, u));
    const r = radii[i];
    const ring = [];
    for (let j = 0; j <= seg; j++) {
      const phi = j * 2 * Math.PI / seg;
      const c = Math.cos(phi), s = Math.sin(phi);
      const nx = u[0] * c + v[0] * s, ny = u[1] * c + v[1] * s, nz = u[2] * c + v[2] * s;
      ring.push(g.addVertex(
        path[i][0] + nx * r, path[i][1] + ny * r, path[i][2] + nz * r, nx, ny, nz));
    }
    rings.push(ring);
  }
  for (let i = 0; i < n - 1; i++) {
    for (let j = 0; j < seg; j++) {
      const a = rings[i][j], b = rings[i][j + 1];
      const c = rings[i + 1][j], d = rings[i + 1][j + 1];
      g.addTri(a, d, c);
      g.addTri(a, b, d);
    }
  }
  if (capStart) {
    const c0 = g.addVertex(path[0][0], path[0][1], path[0][2], -dirs[0][0], -dirs[0][1], -dirs[0][2]);
    for (let j = 0; j < seg; j++) {
      g.addTri(c0, rings[0][j + 1], rings[0][j]);
    }
  }
  if (capEnd) {
    const k = n - 1;
    const c1 = g.addVertex(path[k][0], path[k][1], path[k][2], dirs[k][0], dirs[k][1], dirs[k][2]);
    for (let j = 0; j < seg; j++) {
      g.addTri(c1, rings[k][j], rings[k][j + 1]);
    }
  }
  return g;
}

// 平面着色：把索引网格展开为逐面顶点 + 面法线（低多边形岩石用它最好看）。
// 注意：必须同时 addVertex 与 addTri —— 只加顶点会导致 mesh 索引为空，
// 引擎会静默丢弃该节点（曾因此白折腾一轮：岩石/鹅卵石全都没了）。
function flatShade(g) {
  const out = new Geometry();
  for (let i = 0; i < g.indices.length; i += 3) {
    const ia = g.indices[i], ib = g.indices[i + 1], ic = g.indices[i + 2];
    const a = [g.positions[ia * 3], g.positions[ia * 3 + 1], g.positions[ia * 3 + 2]];
    const b = [g.positions[ib * 3], g.positions[ib * 3 + 1], g.positions[ib * 3 + 2]];
    const c = [g.positions[ic * 3], g.positions[ic * 3 + 1], g.positions[ic * 3 + 2]];
    const cr = cross3([b[0] - a[0], b[1] - a[1], b[2] - a[2]],
      [c[0] - a[0], c[1] - a[1], c[2] - a[2]]);
    // 跳过退化三角形（球的极点处三顶点重合）：既省面数，也避免产生零法线
    if (Math.hypot(cr[0], cr[1], cr[2]) < 1e-12) {
      continue;
    }
    const n = norm3(cr);
    const base = out.vertCount();
    for (const p of [a, b, c]) {
      out.addVertex(p[0], p[1], p[2], n[0], n[1], n[2]);
    }
    out.addTri(base, base + 1, base + 2);
  }
  return out;
}

// 低多边形岩石：低分段球 + 低频隆起 + 平面着色 → 有棱角感的石头
function makeRock(rx, ry, rz, lump, seed) {
  const g = makeSphere(6, 9);
  for (let i = 0; i < g.vertCount(); i++) {
    const ix = i * 3;
    const x = g.positions[ix], y = g.positions[ix + 1], z = g.positions[ix + 2];
    const f = 1 + lump * (
      Math.sin(x * 3.1 + seed) * 0.5 +
      Math.sin(y * 4.3 + seed * 1.7) * 0.3 +
      Math.sin(z * 2.7 + seed * 2.3) * 0.35);
    g.positions[ix] = x * rx * f;
    g.positions[ix + 1] = y * ry * f;
    g.positions[ix + 2] = z * rz * f;
  }
  return flatShade(g);
}

// 扫掠机翼：沿 +X 伸展的扁平透镜形，带后掠与弦长/厚度渐变。
// mirror=true 时镜像到 -X（左右翼各一份网格，避免用负缩放翻转面朝向）。
function makeWingLens(len, chordRoot, chordTip, sweepBack, thickRoot, thickTip,
  tSeg = 12, aSeg = 12, mirror = false) {
  const g = new Geometry();
  const sx = mirror ? -1 : 1;
  const eps = 1e-3;
  const P = (t, th) => {
    const tc = Math.min(1, Math.max(0, t));
    const chord = chordRoot + (chordTip - chordRoot) * tc;
    const thick = thickRoot + (thickTip - thickRoot) * tc;
    const c = Math.cos(th), s = Math.sin(th);
    return [
      sx * tc * len,
      0.5 * thick * s,
      -sweepBack * tc + 0.5 * chord * c,
    ];
  };
  const normAt = (t, th) => {
    const p0 = P(t + eps, th), p1 = P(t - eps, th);
    const q0 = P(t, th + eps), q1 = P(t, th - eps);
    const dt = [p0[0] - p1[0], p0[1] - p1[1], p0[2] - p1[2]];
    const dth = [q0[0] - q1[0], q0[1] - q1[1], q0[2] - q1[2]];
    const n = cross3(dth, dt);
    return norm3([n[0] * sx, n[1] * sx, n[2] * sx]);
  };
  const rings = [];
  for (let i = 0; i <= tSeg; i++) {
    const t = i / tSeg;
    const ring = [];
    for (let j = 0; j <= aSeg; j++) {
      const th = j * 2 * Math.PI / aSeg;
      const p = P(t, th);
      const n = normAt(t, th);
      ring.push(g.addVertex(p[0], p[1], p[2], n[0], n[1], n[2]));
    }
    rings.push(ring);
  }
  for (let i = 0; i < tSeg; i++) {
    for (let j = 0; j < aSeg; j++) {
      const a = rings[i][j], b = rings[i][j + 1];
      const c = rings[i + 1][j], d = rings[i + 1][j + 1];
      g.addTri(a, c, d);
      g.addTri(a, d, b);
    }
  }
  return g;
}

function cross3(a, b) {
  return [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]];
}
function norm3(a) {
  const L = Math.hypot(a[0], a[1], a[2]) || 1;
  return [a[0] / L, a[1] / L, a[2] / L];
}

// 长方体（中心在原点），带正确面法线
function makeBox(w, h, d) {
  const g = new Geometry();
  const hw = w / 2, hh = h / 2, hd = d / 2;
  const faces = [
    { n: [1, 0, 0], v: [[hw, -hh, -hd], [hw, hh, -hd], [hw, hh, hd], [hw, -hh, hd]] },
    { n: [-1, 0, 0], v: [[-hw, -hh, hd], [-hw, hh, hd], [-hw, hh, -hd], [-hw, -hh, -hd]] },
    { n: [0, 1, 0], v: [[-hw, hh, -hd], [-hw, hh, hd], [hw, hh, hd], [hw, hh, -hd]] },
    { n: [0, -1, 0], v: [[-hw, -hh, hd], [-hw, -hh, -hd], [hw, -hh, -hd], [hw, -hh, hd]] },
    { n: [0, 0, 1], v: [[hw, -hh, hd], [hw, hh, hd], [-hw, hh, hd], [-hw, -hh, hd]] },
    { n: [0, 0, -1], v: [[-hw, -hh, -hd], [-hw, hh, -hd], [hw, hh, -hd], [hw, -hh, -hd]] },
  ];
  for (const f of faces) {
    const base = g.vertCount();
    for (const p of f.v) g.addVertex(p[0], p[1], p[2], f.n[0], f.n[1], f.n[2]);
    g.addTri(base, base + 1, base + 2); g.addTri(base, base + 2, base + 3);
  }
  return g;
}

// 圆柱：沿 +Y，高 h，中心在原点；可选端盖
function makeCylinder(rTop, rBot, h, seg = 14, capTop = true, capBot = true) {
  const g = new Geometry();
  const hh = h / 2;
  for (let j = 0; j <= seg; j++) {
    const phi = j * 2 * Math.PI / seg;
    const cx = Math.cos(phi), cz = Math.sin(phi);
    const slope = (rTop - rBot) / h;
    const nl = Math.hypot(1, slope);
    g.addVertex(rTop * cx, hh, rTop * cz, cx / nl, slope / nl, cz / nl);
    g.addVertex(rBot * cx, -hh, rBot * cz, cx / nl, slope / nl, cz / nl);
  }
  for (let j = 0; j < seg; j++) {
    const a = j * 2;
    g.addTri(a, a + 2, a + 3); g.addTri(a, a + 3, a + 1);
  }
  if (capTop) {
    const c = g.addVertex(0, hh, 0, 0, 1, 0);
    for (let j = 0; j < seg; j++) {
      const a = j * 2;
      g.addTri(c, a + 2, a);
    }
  }
  if (capBot) {
    const c = g.addVertex(0, -hh, 0, 0, -1, 0);
    for (let j = 0; j < seg; j++) {
      const a = j * 2;
      g.addTri(c, a, a + 2);
    }
  }
  return g;
}

// 底部贴地的圆柱（y ∈ [0, h]），水平中心在原点 —— 树干的自然模型
function makeCylinderUp(rTop, rBot, h, seg = 12) {
  return bakeTransform(makeCylinder(rTop, rBot, h, seg), { x: 0, y: 0, z: 0, w: 1 }, [1, 1, 1], [0, h / 2, 0]);
}

// 圆盘（朝 +Y）
function makeDisc(r, seg = 48) {
  const g = new Geometry();
  const c = g.addVertex(0, 0, 0, 0, 1, 0);
  for (let j = 0; j <= seg; j++) {
    const phi = j * 2 * Math.PI / seg;
    g.addVertex(r * Math.cos(phi), 0, r * Math.sin(phi), 0, 1, 0);
  }
  for (let j = 0; j < seg; j++) g.addTri(c, j + 2, j + 1);
  return g;
}

// 环形扇带（朝 +Y）：河流与涟漪共用。角度用 atan2(z, x) 度量
function makeArcBand(rIn, rOut, a0, a1, seg = 28) {
  const g = new Geometry();
  for (let j = 0; j <= seg; j++) {
    const a = a0 + (a1 - a0) * j / seg;
    const c = Math.cos(a), s = Math.sin(a);
    g.addVertex(rIn * c, 0, rIn * s, 0, 1, 0);
    g.addVertex(rOut * c, 0, rOut * s, 0, 1, 0);
  }
  for (let j = 0; j < seg; j++) {
    const a = j * 2;
    // 绕序保证法线朝 +Y（正对上方观察者）
    g.addTri(a, a + 3, a + 1);
    g.addTri(a, a + 2, a + 3);
  }
  return g;
}

// “＋”形特效（两片交叉薄板，位于 XY 平面）
function makePlus(s) {
  const g = new Geometry();
  const parts = [
    makeBox(s, s * 0.28, s * 0.14),
    makeBox(s * 0.28, s, s * 0.14),
  ];
  for (const src of parts) {
    const base = g.vertCount();
    for (let i = 0; i < src.vertCount(); i++) {
      g.addVertex(src.positions[i * 3], src.positions[i * 3 + 1], src.positions[i * 3 + 2],
        src.normals[i * 3], src.normals[i * 3 + 1], src.normals[i * 3 + 2]);
    }
    for (let i = 0; i < src.indices.length; i += 3) {
      g.addTri(base + src.indices[i], base + src.indices[i + 1], base + src.indices[i + 2]);
    }
  }
  return g;
}

// 沿 +Z 的单位长圆柱（底面在 z=0，末端在 z=1）—— 青蛙舌头（运行时 scale.z 伸缩）
function makeTongueUnit(r) {
  const g = makeCylinder(r, r * 0.85, 1, 8, true, true);
  return bakeTransform(g, quatBetween([0, 1, 0], [0, 0, 1]), [1, 1, 1], [0, 0, 0.5]);
}

// 对几何做四元数旋转 + 缩放 + 平移（用于在生成期烘焙静态变换）
function bakeTransform(g, q, s, t) {
  for (let i = 0; i < g.vertCount(); i++) {
    const ix = i * 3;
    const p = quatApply(q, { x: g.positions[ix] * s[0], y: g.positions[ix + 1] * s[1], z: g.positions[ix + 2] * s[2] });
    const n = quatApply(q, { x: g.normals[ix], y: g.normals[ix + 1], z: g.normals[ix + 2] });
    g.positions[ix] = p.x + t[0]; g.positions[ix + 1] = p.y + t[1]; g.positions[ix + 2] = p.z + t[2];
    g.normals[ix] = n.x; g.normals[ix + 1] = n.y; g.normals[ix + 2] = n.z;
  }
  return g;
}

// ---------- 材质 ----------
const MAT_GROUND = 0, MAT_STONE = 1, MAT_THORAX = 2, MAT_ABDOMEN = 3, MAT_HEAD = 4,
  MAT_EYE = 5, MAT_WING = 6, MAT_LEG = 7, MAT_FOOD = 8, MAT_SPOT = 9,
  MAT_GROUND_INNER = 10, MAT_WATER = 11, MAT_BANK_STONE = 12, MAT_TRUNK = 13,
  MAT_CROWN_DARK = 14, MAT_CROWN_LIGHT = 15, MAT_FRUIT = 16, MAT_SUN = 17,
  MAT_MOON = 18, MAT_STAR = 19, MAT_FROG_BODY = 20, MAT_FROG_EYE = 21,
  MAT_FROG_TONGUE = 22, MAT_FX_PLUS = 23, MAT_FX_WIND = 24, MAT_FX_RIPPLE = 25,
  MAT_PATH_DOT = 26, MAT_ABDOMEN_BAND = 27, MAT_RIVER_BED = 28, MAT_WATER_SHALLOW = 29;
const materials = [
  { name: 'ground', baseColor: srgb2lin(0x5f8f4c), roughness: 0.95 },
  { name: 'stone', baseColor: srgb2lin(0x8f8d85), roughness: 0.9 },
  { name: 'thorax', baseColor: srgb2lin(0xb98a4e), roughness: 0.7 },
  { name: 'abdomen', baseColor: srgb2lin(0x7a5228), roughness: 0.7 },
  { name: 'head', baseColor: srgb2lin(0xc59a63), roughness: 0.7 },
  { name: 'eye', baseColor: srgb2lin(0xb03028), roughness: 0.25 },
  { name: 'wing', baseColor: srgb2lin(0xe8e4da), roughness: 0.4 },
  { name: 'leg', baseColor: srgb2lin(0x3a2a1a), roughness: 0.8 },
  { name: 'food', baseColor: srgb2lin(0xc23a2e), roughness: 0.4 },
  { name: 'spot', baseColor: srgb2lin(0xffe28a), roughness: 1.0, emissive: [1.0, 0.9, 0.45] },
  // ---- v2 新增 ----
  { name: 'ground_inner', baseColor: srgb2lin(0x7d9a54), roughness: 0.95 },
  { name: 'water', baseColor: lin4(0x3f7fd9, 0.75), roughness: 0.15, alphaMode: 'BLEND' },
  { name: 'bank_stone', baseColor: srgb2lin(0xcfcabb), roughness: 0.9 },
  { name: 'trunk', baseColor: srgb2lin(0x6b4a2c), roughness: 0.85 },
  { name: 'crown_dark', baseColor: srgb2lin(0x2f6b33), roughness: 0.9 },
  { name: 'crown_light', baseColor: srgb2lin(0x4f8f42), roughness: 0.9 },
  { name: 'fruit', baseColor: srgb2lin(0xd0402f), roughness: 0.5 },
  { name: 'sun', baseColor: srgb2lin(0xffd27a), roughness: 1.0, emissive: [1.0, 0.78, 0.35] },
  { name: 'moon', baseColor: srgb2lin(0xe8eeff), roughness: 1.0, emissive: [0.72, 0.78, 0.95] },
  { name: 'star', baseColor: srgb2lin(0xffffff), roughness: 1.0, emissive: [0.95, 0.95, 1.0] },
  { name: 'frog_body', baseColor: srgb2lin(0x4a7c3f), roughness: 0.7 },
  { name: 'frog_eye', baseColor: srgb2lin(0xf2e9c8), roughness: 0.3 },
  { name: 'frog_tongue', baseColor: srgb2lin(0xd9536a), roughness: 0.6 },
  { name: 'fx_plus', baseColor: srgb2lin(0x7fe08a), roughness: 1.0, emissive: [0.45, 0.95, 0.5] },
  { name: 'fx_wind', baseColor: lin4(0xffffff, 0.34), roughness: 1.0, alphaMode: 'BLEND' },
  { name: 'fx_ripple', baseColor: lin4(0xffffff, 0.5), roughness: 1.0, alphaMode: 'BLEND' },
  { name: 'path_dot', baseColor: lin4(0xfff3c4, 0.85), roughness: 1.0, emissive: [0.6, 0.55, 0.3] },
  { name: 'abdomen_band', baseColor: srgb2lin(0x5a3a1c), roughness: 0.8 },
  { name: 'river_bed', baseColor: srgb2lin(0x6b6350), roughness: 0.95 },
  { name: 'water_shallow', baseColor: lin4(0x6fa8e0, 0.55), roughness: 0.2, alphaMode: 'BLEND' },
];

// 天空穹顶配色（9 段，索引即 sky_i 的编号）。必须与 entry/.../FlyConfig.ets 的 skyPhases 一致：
// 相位落在 [skyPhases[i], skyPhases[i+1]) 时显示 sky_i。
const SKY_PHASES = [0, 0.06, 0.12, 0.45, 0.60, 0.66, 0.70, 0.74, 0.90, 1.0];
const SKY_HEX = [0x8FA6D8, 0x9CB6DC, 0x87CEEB, 0x87CEEB, 0xC9A98F, 0xFF9A5A, 0xA5705E, 0x0B1026, 0x0B1026];
const MAT_SKY_BASE = materials.length;   // = 30
for (let i = 0; i < SKY_HEX.length; i++) {
  const base = srgb2lin(SKY_HEX[i]);
  materials.push({
    name: `sky_${i}`,
    baseColor: base,
    roughness: 1.0,
    // 自发光让天空不受平行光强弱影响（夜晚该暗是靠颜色本身变深，而不是被灯照黑）；
    // 同时保留 baseColor，万一某些引擎弱化 emissive，也还能看出正确颜色。
    // 系数取 0.85：实测偏低时天空会显得发灰、认不出是蓝天。
    emissive: [base[0] * 0.85, base[1] * 0.85, base[2] * 0.85],
  });
}

// ---------- 组装几何与节点 ----------
const meshes = [];   // {geometry, material}
const nodes = [];    // {name, mesh?, children?, translation?, rotation?, scale?}
const topNodes = []; // 顶层节点索引（scene.nodes）

function addMesh(geometry, material) {
  meshes.push({ geometry, material });
  return meshes.length - 1;
}
function addNode(node, top = false) {
  // rotation 统一成 {x,y,z,w}：调用方可能直接传 [x,y,z,w] 数组，
  // 而序列化是按 .x/.y/.z/.w 读的 —— 传数组会被写成 [null,null,null,null]（非法 glTF）
  if (node.rotation && Array.isArray(node.rotation)) {
    const r = node.rotation;
    node.rotation = { x: r[0], y: r[1], z: r[2], w: r[3] };
  }
  nodes.push(node);
  const idx = nodes.length - 1;
  if (top) topNodes.push(idx);
  return idx;
}

// ==== 1) 地面：外圈草地 + 内圈活动区（同心圆盘叠放） ====
{
  const outer = bakeTransform(makeDisc(5.5, 56), { x: 0, y: 0, z: 0, w: 1 }, [1, 1, 1], [0, 0.001, 0]);
  addNode({ name: 'ground', mesh: addMesh(outer, MAT_GROUND) }, true);
  const inner = bakeTransform(makeDisc(3.3, 44), { x: 0, y: 0, z: 0, w: 1 }, [1, 1, 1], [0, 0.004, 0]);
  addNode({ name: 'ground_inner', mesh: addMesh(inner, MAT_GROUND_INNER) }, true);
}

// ==== 2) 场内石块（v3：3 种带棱角的低多边形岩石，随机朝向与比例，半埋入地面） ====
{
  const rockMeshes = [
    addMesh(makeRock(0.50, 0.32, 0.44, 0.22, 1.7), MAT_STONE),
    addMesh(makeRock(0.44, 0.38, 0.50, 0.26, 4.1), MAT_STONE),
    addMesh(makeRock(0.58, 0.26, 0.40, 0.18, 8.3), MAT_STONE),
  ];
  const stonePos = [
    [2.7, 0.9, 0.75], [3.6, -1.7, 0.95], [-3.1, 1.4, 0.85],
    [-4.1, -1.1, 0.7], [1.3, -3.4, 0.65], [-1.8, 3.3, 0.9],
    [4.4, 2.2, 0.8], [-3.9, 3.8, 0.6],
  ]; // [x, z, scale]
  const rng = makeRng(0x5709ee);
  for (let i = 0; i < stonePos.length; i++) {
    const s = stonePos[i];
    addNode({
      name: `stone_${i}`, mesh: rockMeshes[i % rockMeshes.length],
      translation: [s[0], 0.20 * s[2], s[1]],
      rotation: quatMul(quatY(rng() * Math.PI * 2), quatZ((rng() - 0.5) * 0.35)),
      scale: [s[2] * (0.9 + rng() * 0.25), s[2] * (0.75 + rng() * 0.4), s[2] * (0.9 + rng() * 0.25)],
    }, true);
  }
}

// ==== 3) 河流弧带 + 河岸卵石 ====
// 弧带位于场地东侧（+X/+Z 方向），径向 4.9~6.6。
// 说明：设计稿给的是 5.2~6.8 且水面 y=-0.02；这里把内半径收到 4.9、水面抬到
// 地面上方（y=0.012），否则地面圆盘会遮住水面、且果蝇（活动半径 4.6）永远够不到岸边。
const RIVER_A0 = 20 * DEG, RIVER_A1 = 108 * DEG;
const RIVER_RIN = 4.9, RIVER_ROUT = 6.6;
{
  // v3：河床（泥土带）+ 浅水圈 + 主水面，三层叠出河道的纵深感
  const bed = bakeTransform(
    makeArcBand(RIVER_RIN - 0.32, RIVER_ROUT + 0.48, RIVER_A0 - 0.045, RIVER_A1 + 0.045, 36),
    { x: 0, y: 0, z: 0, w: 1 }, [1, 1, 1], [0, 0.004, 0]);
  addNode({ name: 'river_bed', mesh: addMesh(bed, MAT_RIVER_BED) }, true);

  const shallow = bakeTransform(
    makeArcBand(RIVER_RIN, RIVER_RIN + 0.34, RIVER_A0, RIVER_A1, 30),
    { x: 0, y: 0, z: 0, w: 1 }, [1, 1, 1], [0, 0.009, 0]);
  addNode({ name: 'river_shallow', mesh: addMesh(shallow, MAT_WATER_SHALLOW) }, true);

  // 主水面：高度与 EnvironmentController.riverY 一致（乘波时会整体起伏）
  const water = bakeTransform(makeArcBand(RIVER_RIN, RIVER_ROUT, RIVER_A0, RIVER_A1, 32),
    { x: 0, y: 0, z: 0, w: 1 }, [1, 1, 1], [0, 0.012, 0]);
  addNode({ name: 'river', mesh: addMesh(water, MAT_WATER) }, true);

  // 两侧鹅卵石：贴岸分布，大小/朝向/比例随机，用低多边形岩石更自然
  const rng = makeRng(0x51ee01);
  const pebbleMeshes = [
    addMesh(makeRock(0.17, 0.11, 0.14, 0.16, 2.9), MAT_BANK_STONE),
    addMesh(makeRock(0.13, 0.10, 0.16, 0.20, 6.4), MAT_BANK_STONE),
  ];
  const bankSpecs = [
    { r: RIVER_RIN - 0.14, n: 8 },
    { r: RIVER_ROUT + 0.14, n: 8 },
  ];
  let k = 0;
  for (const spec of bankSpecs) {
    for (let i = 0; i < spec.n; i++) {
      const t = (i + 0.5) / spec.n;
      const a = RIVER_A0 + (RIVER_A1 - RIVER_A0) * t;
      const jitterR = spec.r + (rng() - 0.5) * 0.20;
      const s = 0.65 + rng() * 0.85;
      addNode({
        name: `river_bank_stone_${k}`, mesh: pebbleMeshes[k % pebbleMeshes.length],
        translation: [jitterR * Math.cos(a), 0.035 * s, jitterR * Math.sin(a)],
        rotation: quatMul(quatY(rng() * Math.PI * 2), quatZ((rng() - 0.5) * 0.4)),
        scale: [s * (0.85 + rng() * 0.3), s * (0.7 + rng() * 0.4), s * (0.85 + rng() * 0.3)],
      }, true);
      k++;
    }
  }
}

// ==== 4) 树木 ×3：tree_i（根）→ trunk（一级摇摆）→ crown（二级摇摆） ====
// v3：树干改扫掠管（带锥度与轻微倾斜）+ 3 根烘进树干的枝条；树冠改 6 层错落叶球。
// 位置在场地边缘外一圈；其中 0 号树挨着河岸。
const TREE_SPECS = [
  { x: 5.0 * Math.cos(14 * DEG), z: 5.0 * Math.sin(14 * DEG), h: 1.30, s: 1.00, lean: 0.10 },
  { x: 5.6 * Math.cos(150 * DEG), z: 5.6 * Math.sin(150 * DEG), h: 1.10, s: 0.90, lean: -0.08 },
  { x: 5.3 * Math.cos(250 * DEG), z: 5.3 * Math.sin(250 * DEG), h: 1.22, s: 0.95, lean: 0.05 },
];
{
  const crownDark = addMesh(makeEllipsoid(0.40, 0.32, 0.40, 0, 0, 0, 14, 18), MAT_CROWN_DARK);
  const crownLight = addMesh(makeEllipsoid(0.31, 0.26, 0.31, 0, 0, 0, 14, 18), MAT_CROWN_LIGHT);
  const fruitMesh = addMesh(makeEllipsoid(0.055, 0.055, 0.055, 0, 0, 0, 10, 12), MAT_FRUIT);
  const rng = makeRng(0x7ee501);

  let fruitIdx = 0;
  const fruitPending = [];   // 果实的绝对坐标，稍后作为顶层节点挂上（见下方说明）
  for (let ti = 0; ti < TREE_SPECS.length; ti++) {
    const spec = TREE_SPECS[ti];
    const h = spec.h, lean = spec.lean;
    // 树干：底部贴地、向上渐细并轻微倾斜（高度烘焙进网格 ⇒ 节点无 scale，
    // 否则作为子节点的树冠会被一起缩放 —— 见易错总结第 27 条）
    const trunkMesh = addMesh(makeTube(
      [[0, 0, 0], [lean * 0.45, h * 0.5, 0], [lean, h, 0]],
      [0.115, 0.072, 0.040], 12, true, true), MAT_TRUNK);

    // 枝条 ×3：挂在树干下随树干一起摆
    const branchChildren = [];
    const branches = [
      { from: [0.02, h * 0.60, 0.00], to: [0.34 * spec.s, h * 1.02, 0.16 * spec.s] },
      { from: [-0.02, h * 0.68, 0.03], to: [-0.30 * spec.s, h * 1.08, -0.18 * spec.s] },
      { from: [0.00, h * 0.74, -0.02], to: [0.10 * spec.s, h * 1.16, -0.30 * spec.s] },
    ];
    for (let bi = 0; bi < branches.length; bi++) {
      const b = branches[bi];
      const path = [[0, 0, 0],
        [(b.to[0] - b.from[0]) * 0.5, (b.to[1] - b.from[1]) * 0.5, (b.to[2] - b.from[2]) * 0.5],
        [b.to[0] - b.from[0], b.to[1] - b.from[1], b.to[2] - b.from[2]]];
      branchChildren.push(addNode({
        name: `branch_${ti}_${bi}`,
        mesh: addMesh(makeTube(path, [0.048, 0.030, 0.016], 8, true, true), MAT_TRUNK),
        translation: b.from,
      }));
    }

    // 树冠：6 个错落叶球（深绿底 + 浅绿受光面），每棵树用不同随机相位
    const crownChildren = [];
    for (let ci = 0; ci < 6; ci++) {
      const ang = ci * Math.PI * 2 / 6 + rng() * 0.8;
      const rad = (0.14 + rng() * 0.20) * spec.s;
      const y = (0.16 + rng() * 0.44) * spec.s;
      const sc = (0.62 + rng() * 0.5) * spec.s;
      const light = ci % 2 === 1;
      crownChildren.push(addNode({
        name: `crown_${ti}_blob_${ci}`,
        mesh: light ? crownLight : crownDark,
        translation: [rad * Math.cos(ang), y, rad * Math.sin(ang)],
        scale: [sc, sc * (0.82 + rng() * 0.3), sc],
        rotation: quatY(rng() * Math.PI),
      }));
    }
    // 果实 ×3：**记为顶层节点**（绝对坐标 = 树根 + 树冠偏移 + 冠内偏移）。
    // 之所以不挂在树冠下：果实成熟后要自己落到地面被果蝇吃掉，
    // 挂在树冠里会被树的摇摆带着走、也无法脱离树干。
    for (let f = 0; f < 3; f++) {
      const a = rng() * Math.PI * 2;
      const fx = 0.40 * spec.s * Math.cos(a);
      const fy = (0.24 + 0.40 * rng()) * spec.s;
      const fz = 0.40 * spec.s * Math.sin(a);
      fruitPending.push({
        name: `fruit_${fruitIdx}`,
        pos: [spec.x + lean + fx, h + fy, spec.z + fz],
      });
      fruitIdx++;
    }

    // 层级：tree_i（根部）→ trunk（一级摇摆，绕根部）→ crown（二级摇摆）
    // 枝条的坐标是相对"树根"写的，所以必须挂在 trunk 下（crown 已被抬到 y=h，不能复用这份坐标）
    const crown = addNode({ name: `crown_${ti}`, translation: [lean, h, 0], children: crownChildren });
    const trunk = addNode({
      name: `trunk_${ti}`, mesh: trunkMesh, children: [crown].concat(branchChildren),
    });
    addNode({ name: `tree_${ti}`, translation: [spec.x, 0, spec.z], children: [trunk] }, true);
  }
  // 果实作为顶层节点补挂（位置即世界坐标，行为层据此判断"落地点"）
  for (const fp of fruitPending) {
    addNode({ name: fp.name, mesh: fruitMesh, translation: fp.pos }, true);
  }
}

// ==== 5) 太阳 / 月亮枢轴（绕 Z 轴匀速旋转，天然实现东升西落） ====
{
  const sunMesh = addMesh(makeEllipsoid(0.55, 0.55, 0.55, 0, 0, 0, 12, 16), MAT_SUN);
  const moonMesh = addMesh(makeEllipsoid(0.40, 0.40, 0.40, 0, 0, 0, 12, 16), MAT_MOON);
  // 圆盘替身：用小球而非平面圆盘，避免正/背面剔除导致某个角度看不见。
  // 注意命名：不能叫 'sun' —— 运行时会用 createLight({name:'sun'}) 创建平行光，
  // 同名会让按名字查找取到灯而不是这个球体。
  const sun = addNode({ name: 'sun_disc', mesh: sunMesh, translation: [9, 0, 0] });
  addNode({ name: 'sun_pivot', children: [sun] }, true);
  const moon = addNode({ name: 'moon_disc', mesh: moonMesh, translation: [9, 0, 0] });
  addNode({ name: 'moon_pivot', rotation: quatFromAxisAngle(0, 0, 1, Math.PI), children: [moon] }, true);
}

// ==== 6) 星空（穹顶半球，夜晚显隐 + 缓慢自转） ====
{
  const starMesh = addMesh(makeEllipsoid(0.055, 0.055, 0.055, 0, 0, 0, 5, 6), MAT_STAR);
  const rng = makeRng(0x57a200);
  const starChildren = [];
  for (let i = 0; i < 30; i++) {
    // 半球均匀取点：y > 0.15，半径 12
    const u = rng() * 2 - 1;
    const phi = rng() * Math.PI * 2;
    const y = 0.15 + (1 - 0.15) * rng();
    const rHoriz = Math.sqrt(Math.max(0, 1 - y * y));
    const s = 0.7 + rng() * 0.9;
    starChildren.push(addNode({
      name: `star_${i}`, mesh: starMesh,
      translation: [12 * rHoriz * Math.cos(phi), 12 * y, 12 * rHoriz * Math.sin(phi)],
      scale: [s, s, s],
    }));
  }
  addNode({ name: 'stars', children: starChildren }, true);
}

// ==== 6.5) 天空穹顶 ×9（昼夜用）====
// 为什么是"多个穹顶 + 切换可见"而不是"一个穹顶 + 运行时改色"：
// camera.clearColor 在真机上不生效（M0 已知）；而运行时改材质要走 MaterialProperty，
// 写入口径不确定，写错会直接变成编译错误卡住构建。可见性切换只用 Node.visible —— 最稳，
// 且同一时刻只有一个穹顶可见，绘制开销可忽略。
// 半径 35：要大于相机最远距离（22）才能保证相机始终在球内、也不会被剔除。
const SKY_RADIUS = 35;
{
  // 球面，法线朝内（观察者在球内）。
  // 关键：**两个绕序都输出**。只输出单向时，若引擎对背面剔除的处理与预期不同，
  // 从球内看就会被整片剔除、直接露出组件底色（实测就是这样：天空一直是灰的）。
  // 双向输出后无论引擎是否真正支持 doubleSided，球内都必然可见；
  // 若引擎支持 doubleSided，背向的那一面会被剔除，不会与正面打架。
  const makeSkyDome = (R, lat = 8, lon = 16) => {
    const g = new Geometry();
    const id = [];
    for (let i = 0; i <= lat; i++) {
      const theta = i * Math.PI / lat;
      for (let j = 0; j <= lon; j++) {
        const phi = j * 2 * Math.PI / lon;
        const x = Math.sin(theta) * Math.cos(phi);
        const y = Math.cos(theta);
        const z = Math.sin(theta) * Math.sin(phi);
        id.push(g.addVertex(x * R, y * R, z * R, -x, -y, -z));
      }
    }
    for (let i = 0; i < lat; i++) {
      for (let j = 0; j < lon; j++) {
        const a = id[i * (lon + 1) + j];
        const a1 = id[i * (lon + 1) + j + 1];
        const b = id[(i + 1) * (lon + 1) + j];
        const b1 = id[(i + 1) * (lon + 1) + j + 1];
        g.addTri(a, a1, b);
        g.addTri(b, a1, b1);
        g.addTri(a, b, a1);
        g.addTri(b, b1, a1);
      }
    }
    return g;
  };
  // 注意：glTF 没有节点级 visible 属性（不在规范里），所以显隐只能由运行时设定。
  // 场景加载后 SceneManager 会先把 sky_* 全部隐藏，再由 EnvironmentController 每帧
  // 只打开当前时段对应的那一个。
  for (let i = 0; i < SKY_HEX.length; i++) {
    const mesh = addMesh(makeSkyDome(SKY_RADIUS), MAT_SKY_BASE + i);
    addNode({ name: `sky_${i}`, mesh }, true);
  }
}

// ==== 7) 青蛙（含可伸缩舌头） ====
// v3：身体改旋转体剖面（臀宽头窄）+ 纵向压缩，加咽喉囊、突出大眼、鼻孔、
//     两段折腿与后肢蹼足。蹲坐在河流内侧岸边；朝向场地中心（生成期烘焙 yaw）。
const FROG_R = 4.55, FROG_A = 64 * DEG;
{
  const fx = FROG_R * Math.cos(FROG_A), fz = FROG_R * Math.sin(FROG_A);
  // 朝向原点：本地 +Z 需指向 (fx,fz) 的反方向
  const yaw = Math.atan2(-fx, -fz);
  const qFrog = quatY(yaw);

  // 纵向压扁（青蛙又宽又扁）：位置 y*=k，法线 ny/=k 再归一化（对角缩放的逆转置）
  const squashY = (g, k) => {
    for (let i = 0; i < g.vertCount(); i++) {
      const ix = i * 3;
      g.positions[ix + 1] *= k;
      g.normals[ix + 1] /= k;
      const nl = Math.hypot(g.normals[ix], g.normals[ix + 1], g.normals[ix + 2]) || 1;
      g.normals[ix] /= nl; g.normals[ix + 1] /= nl; g.normals[ix + 2] /= nl;
    }
    return g;
  };

  // 身体：吻端（+Z）→ 臀部（-Z），臀宽头窄
  const bodyProfile = makeProfile([
    [0.30, 0.000], [0.27, 0.075], [0.21, 0.140], [0.12, 0.195],
    [0.00, 0.232], [-0.14, 0.238], [-0.28, 0.190], [-0.40, 0.080], [-0.44, 0.000],
  ]);
  const bodyMesh = addMesh(
    squashY(bakeTransform(makeRevolutionZ(bodyProfile, 26, 22),
      { x: 0, y: 0, z: 0, w: 1 }, [1, 1, 1], [0, 0.215, 0]), 0.78), MAT_FROG_BODY);
  // 咽喉囊（下颌处浅色鼓包）
  const throatMesh = addMesh(makeEllipsoid(0.145, 0.075, 0.150, 0, 0.115, 0.145, 14, 18), MAT_FROG_EYE);
  // 眼球（凸出于头顶）
  const eyeMesh = addMesh(makeEllipsoid(0.088, 0.092, 0.088, 0, 0, 0, 14, 18), MAT_FROG_EYE);
  // 瞳孔：竖向椭圆（蛙类特征）
  const pupilMesh = addMesh(makeEllipsoid(0.030, 0.052, 0.030, 0, 0, 0, 10, 12), MAT_LEG);
  // 腿：用扫掠管做两段折腿
  const tongueMesh = addMesh(makeTongueUnit(0.05), MAT_FROG_TONGUE);
  // 蹼足：一片扁三角
  const webMesh = addMesh(makeBox(0.16, 0.014, 0.13), MAT_FROG_BODY);

  const frogChildren = [];
  frogChildren.push(addNode({ name: 'frog_body', mesh: bodyMesh }));
  frogChildren.push(addNode({ name: 'frog_throat', mesh: throatMesh }));
  // 眼球 + 瞳孔（瞳孔是独立节点：控制器在蓄力时前移、眨眼时隐藏）
  frogChildren.push(addNode({ name: 'frog_eye_l', mesh: eyeMesh, translation: [-0.145, 0.315, 0.145] }));
  frogChildren.push(addNode({ name: 'frog_eye_r', mesh: eyeMesh, translation: [0.145, 0.315, 0.145] }));
  frogChildren.push(addNode({ name: 'frog_pupil_l', mesh: pupilMesh, translation: [-0.150, 0.330, 0.212] }));
  frogChildren.push(addNode({ name: 'frog_pupil_r', mesh: pupilMesh, translation: [0.140, 0.330, 0.212] }));
  // 鼻孔 ×2
  const nostrilMesh = addMesh(makeEllipsoid(0.014, 0.014, 0.014, 0, 0, 0, 8, 10), MAT_LEG);
  frogChildren.push(addNode({ name: 'frog_nostril_l', mesh: nostrilMesh, translation: [-0.048, 0.185, 0.268] }));
  frogChildren.push(addNode({ name: 'frog_nostril_r', mesh: nostrilMesh, translation: [0.048, 0.185, 0.268] }));

  // 前肢 ×2（较短，支撑上身）：基节 → 腕 → 掌
  const frontLegs = [
    { sx: -1, base: [-0.185, 0.170, 0.150], mid: [-0.235, 0.075, 0.205], foot: [-0.250, 0.010, 0.255] },
    { sx: 1, base: [0.185, 0.170, 0.150], mid: [0.235, 0.075, 0.205], foot: [0.250, 0.010, 0.255] },
  ];
  for (let i = 0; i < frontLegs.length; i++) {
    const L = frontLegs[i];
    const path = [[0, 0, 0],
      [L.mid[0] - L.base[0], L.mid[1] - L.base[1], L.mid[2] - L.base[2]],
      [L.foot[0] - L.base[0], L.foot[1] - L.base[1], L.foot[2] - L.base[2]]];
    frogChildren.push(addNode({
      name: `frog_leg_front_${i}`, mesh: addMesh(makeTube(path, [0.055, 0.036, 0.030], 9, true, true), MAT_FROG_BODY),
      translation: L.base,
    }));
  }
  // 后肢 ×2（粗壮、折叠成 Z 形，是青蛙的辨识特征）
  const hindLegs = [
    { sx: -1, base: [-0.190, 0.215, -0.190], kneeA: [-0.330, 0.185, -0.330], kneeB: [-0.300, 0.070, -0.080], foot: [-0.320, 0.010, -0.330] },
    { sx: 1, base: [0.190, 0.215, -0.190], kneeA: [0.330, 0.185, -0.330], kneeB: [0.300, 0.070, -0.080], foot: [0.320, 0.010, -0.330] },
  ];
  for (let i = 0; i < hindLegs.length; i++) {
    const L = hindLegs[i];
    const path = [[0, 0, 0],
      [L.kneeA[0] - L.base[0], L.kneeA[1] - L.base[1], L.kneeA[2] - L.base[2]],
      [L.kneeB[0] - L.base[0], L.kneeB[1] - L.base[1], L.kneeB[2] - L.base[2]],
      [L.foot[0] - L.base[0], L.foot[1] - L.base[1], L.foot[2] - L.base[2]]];
    frogChildren.push(addNode({
      name: `frog_leg_hind_${i}`, mesh: addMesh(makeTube(path, [0.075, 0.052, 0.040, 0.032], 10, true, true), MAT_FROG_BODY),
      translation: L.base,
    }));
    // 蹼足
    frogChildren.push(addNode({
      name: `frog_web_${i}`, mesh: webMesh,
      translation: [L.foot[0], 0.008, L.foot[2]],
      rotation: quatY(L.sx > 0 ? -0.35 : 0.35),
    }));
  }

  // 舌头：挂在与嘴同高的位置，沿本地 +Z 伸缩（底面固定在 z=0，运行时 scale.z 伸长）
  frogChildren.push(addNode({ name: 'frog_tongue', mesh: tongueMesh, translation: [0, 0.150, 0.300] }));

  addNode({ name: 'frog', translation: [fx, 0, fz], rotation: qFrog, children: frogChildren }, true);
}

// ==== 8) 果蝇（朝 +Z，根节点在地面） ====
// v3：躯干/头改用旋转体剖面（腰部收窄、腹部蛋形收尾），腹部加 4 道背板环，
//     复眼加大并外扩，加单眼 ×3、平衡棒 ×2、背刚毛 ×8，腿改两段折腿，翅膀改扫掠透镜形。
const flyChildren = [];
// 头部轴心（颈部）：head/复眼/触角都挂在这下面，进食时整体低头
const HEAD_PIVOT = [0, 0.345, 0.19];
{
  // —— 胸部（旋转体，前端接到颈部、后端收成腰）——
  const thoraxProfile = makeProfile([
    [0.17, 0.058], [0.10, 0.104], [0.02, 0.126], [-0.04, 0.110], [-0.09, 0.068], [-0.105, 0.030],
  ]);
  let m = addMesh(bakeTransform(makeRevolutionZ(thoraxProfile, 26, 20),
    { x: 0, y: 0, z: 0, w: 1 }, [1, 1, 1], [0, 0.300, 0]), MAT_THORAX);
  flyChildren.push(addNode({ name: 'thorax', mesh: m }));
  // 小盾片（胸部背面的小鼓包）
  m = addMesh(makeEllipsoid(0.052, 0.030, 0.046, 0, 0.396, -0.072, 12, 16), MAT_THORAX);
  flyChildren.push(addNode({ name: 'scutellum', mesh: m }));
  // 平衡棒 ×2（果蝇标志性器官：翅膀退化成的小棒）
  m = addMesh(makeEllipsoid(0.030, 0.012, 0.012, 0, 0, 0, 8, 10), MAT_HEAD);
  flyChildren.push(addNode({ name: 'haltere_l', mesh: m, translation: [-0.072, 0.330, -0.062], rotation: quatY(-0.5) }));
  flyChildren.push(addNode({ name: 'haltere_r', mesh: m, translation: [0.072, 0.330, -0.062], rotation: quatY(0.5) }));
  // 背刚毛 ×8（细锥，插在胸部背面）
  {
    const bristleMesh = addMesh(makeTube([[0, 0, 0], [0, 0.030, -0.008], [0, 0.052, -0.016]],
      [0.0060, 0.0035, 0.0010], 6, true, true), MAT_LEG);
    const spots = [
      [-0.045, 0.386, 0.055], [0.045, 0.386, 0.055],
      [-0.062, 0.386, -0.005], [0.062, 0.386, -0.005],
      [-0.040, 0.392, -0.055], [0.040, 0.392, -0.055],
      [-0.016, 0.400, -0.010], [0.016, 0.400, -0.010],
    ];
    for (let i = 0; i < spots.length; i++) {
      const s = spots[i];
      const tilt = quatMul(quatZ(s[0] < 0 ? 0.35 : -0.35), quatX(-0.28));
      flyChildren.push(addNode({
        name: `bristle_${i}`, mesh: bristleMesh, translation: s,
        rotation: [tilt.x, tilt.y, tilt.z, tilt.w],
      }));
    }
  }
  // —— 腹部（蛋形旋转体：腰细 → 中段饱满 → 尾端收尖）——
  const abdomenProfile = makeProfile([
    [-0.060, 0.000], [-0.075, 0.062], [-0.140, 0.114], [-0.260, 0.126],
    [-0.380, 0.108], [-0.480, 0.062], [-0.545, 0.000],
  ]);
  m = addMesh(bakeTransform(makeRevolutionZ(abdomenProfile, 26, 22),
    { x: 0, y: 0, z: 0, w: 1 }, [1, 1, 1], [0, 0.288, 0]), MAT_ABDOMEN);
  flyChildren.push(addNode({ name: 'abdomen', mesh: m }));
  // 腹部背板环 ×4（略凸起的深色环，做出"分节"观感）
  {
    const bands = [[-0.160, 0.116], [-0.250, 0.126], [-0.340, 0.113], [-0.430, 0.086]];
    const bandMesh = addMesh(bakeTransform(makeRevolutionZ(makeProfile([
      [-0.013, 0.000], [-0.008, 0.055], [0.000, 0.093], [0.008, 0.055], [0.013, 0.000],
    ]), 24, 8), { x: 0, y: 0, z: 0, w: 1 }, [1, 1, 1], [0, 0, 0]), MAT_ABDOMEN_BAND);
    for (let i = 0; i < bands.length; i++) {
      const r = bands[i][1];
      flyChildren.push(addNode({
        name: `abdomen_band_${i}`, mesh: bandMesh,
        translation: [0, 0.288, bands[i][0]],
        scale: [(r + 0.004) / 0.093, (r + 0.004) / 0.093, 1],
      }));
    }
  }

  // —— 头部（旋转体）+ 复眼 + 单眼 + 触角 ——
  const headChildren = [];
  const headProfile = makeProfile([
    [0.345, 0.000], [0.322, 0.052], [0.285, 0.084], [0.240, 0.094], [0.195, 0.080], [0.165, 0.000],
  ]);
  m = addMesh(bakeTransform(makeRevolutionZ(headProfile, 24, 18),
    { x: 0, y: 0, z: 0, w: 1 }, [1, 1, 1], [0, 0.335, 0]), MAT_HEAD);
  headChildren.push(addNode({ name: 'head', mesh: m, translation: [0, 0.335 - HEAD_PIVOT[1], 0 - HEAD_PIVOT[2]] }));
  // 复眼：贴在头两侧、略向外斜（比 v2 更大，占据头部大半）
  m = addMesh(makeEllipsoid(0.044, 0.066, 0.068, 0, 0, 0, 14, 18), MAT_EYE);
  const eyeTiltL = quatMul(quatZ(0.30), quatY(-0.22));
  headChildren.push(addNode({
    name: 'eye_left', mesh: m,
    translation: [-0.058 - HEAD_PIVOT[0], 0.352 - HEAD_PIVOT[1], 0.262 - HEAD_PIVOT[2]],
    rotation: [eyeTiltL.x, eyeTiltL.y, eyeTiltL.z, eyeTiltL.w],
  }));
  const eyeTiltR = quatMul(quatZ(-0.30), quatY(0.22));
  headChildren.push(addNode({
    name: 'eye_right', mesh: m,
    translation: [0.058 - HEAD_PIVOT[0], 0.352 - HEAD_PIVOT[1], 0.262 - HEAD_PIVOT[2]],
    rotation: [eyeTiltR.x, eyeTiltR.y, eyeTiltR.z, eyeTiltR.w],
  }));
  // 单眼 ×3（头顶的三个小亮点）
  m = addMesh(makeEllipsoid(0.014, 0.014, 0.014, 0, 0, 0, 8, 10), MAT_EYE);
  const ocelli = [[0, 0.404, 0.286], [-0.030, 0.398, 0.272], [0.030, 0.398, 0.272]];
  for (let i = 0; i < ocelli.length; i++) {
    const o = ocelli[i];
    headChildren.push(addNode({
      name: `ocellus_${i}`, mesh: m,
      translation: [o[0] - HEAD_PIVOT[0], o[1] - HEAD_PIVOT[1], o[2] - HEAD_PIVOT[2]],
    }));
  }
  // 触角：两段细管 + 末端小棒（避免单根直棍的塑料感）
  {
    const antSpecs = [
      { name: 'antenna_left', base: [-0.028, 0.406, 0.318], mid: [-0.052, 0.436, 0.372], tip: [-0.070, 0.446, 0.412] },
      { name: 'antenna_right', base: [0.028, 0.406, 0.318], mid: [0.052, 0.436, 0.372], tip: [0.070, 0.446, 0.412] },
    ];
    for (const a of antSpecs) {
      const path = [[0, 0, 0],
        [a.mid[0] - a.base[0], a.mid[1] - a.base[1], a.mid[2] - a.base[2]],
        [a.tip[0] - a.base[0], a.tip[1] - a.base[1], a.tip[2] - a.base[2]]];
      headChildren.push(addNode({
        name: a.name, mesh: addMesh(makeTube(path, [0.0085, 0.0055, 0.0042], 8, true, true), MAT_LEG),
        translation: [a.base[0] - HEAD_PIVOT[0], a.base[1] - HEAD_PIVOT[1], a.base[2] - HEAD_PIVOT[2]],
      }));
      headChildren.push(addNode({
        name: `${a.name}_club`, mesh: addMesh(makeEllipsoid(0.014, 0.013, 0.020, 0, 0, 0, 8, 10), MAT_LEG),
        translation: [a.tip[0] - HEAD_PIVOT[0], a.tip[1] - HEAD_PIVOT[1], a.tip[2] - HEAD_PIVOT[2]],
      }));
    }
  }
  // 口器（喙）：头下方一小段，进食低头时更自然
  headChildren.push(addNode({
    name: 'proboscis', mesh: addMesh(makeEllipsoid(0.030, 0.038, 0.030, 0, 0, 0, 10, 12), MAT_LEG),
    translation: [0 - HEAD_PIVOT[0], 0.300 - HEAD_PIVOT[1], 0.286 - HEAD_PIVOT[2]],
  }));
  flyChildren.push(addNode({ name: 'head_pivot', translation: HEAD_PIVOT, children: headChildren }));

  // —— 腿 ×6：两段折腿（基节→膝→足），单网格扫掠出折角 ——
  const legSpecs = [
    { sz: 0.13, ez: 0.20, ox: 0.19 },   // 前足（朝前）
    { sz: 0.00, ez: 0.02, ox: 0.23 },   // 中足
    { sz: -0.10, ez: -0.17, ox: 0.20 }, // 后足
  ];
  for (const side of [-1, 1]) {
    for (let li = 0; li < legSpecs.length; li++) {
      const L = legSpecs[li];
      const base = [side * 0.098, 0.238, L.sz];
      const knee = [side * (L.ox * 0.62), 0.115, L.sz + L.ez * 0.45];
      const foot = [side * L.ox, 0.0, L.ez];
      const path = [[0, 0, 0],
        [knee[0] - base[0], knee[1] - base[1], knee[2] - base[2]],
        [foot[0] - base[0], foot[1] - base[1], foot[2] - base[2]]];
      flyChildren.push(addNode({
        name: `leg_${side < 0 ? 'l' : 'r'}_${li}`,
        mesh: addMesh(makeTube(path, [0.0180, 0.0105, 0.0070], 9, true, true), MAT_LEG),
        translation: base,
      }));
    }
  }

  // —— 翅膀：扫掠透镜形（根部宽、翼尖窄并后掠）；左右各一份网格（不用负缩放，避免翻面）——
  const wingR = addMesh(makeWingLens(0.36, 0.150, 0.058, 0.080, 0.0075, 0.0030, 14, 12, false), MAT_WING);
  const wingL = addMesh(makeWingLens(0.36, 0.150, 0.058, 0.080, 0.0075, 0.0030, 14, 12, true), MAT_WING);
  const wingLBlade = addNode({ name: 'wing_blade_l', mesh: wingL, translation: [0, 0, 0] });
  const wingRBlade = addNode({ name: 'wing_blade_r', mesh: wingR, translation: [0, 0, 0] });
  const wl = addNode({ name: 'wing_left', translation: [-0.09, 0.405, -0.03], children: [wingLBlade] });
  const wr = addNode({ name: 'wing_right', translation: [0.09, 0.405, -0.03], children: [wingRBlade] });
  flyChildren.push(wl, wr);
}
const flyNode = addNode({ name: 'fly', children: flyChildren }, true);

// ==== 9) 食物 ×5 与聚光光斑（初始藏到地下 y=-10，运行时激活） ====
{
  const foodMesh = addMesh(makeEllipsoid(0.07, 0.07, 0.07, 0, 0, 0, 8, 12), MAT_FOOD);
  for (let i = 0; i < 5; i++) {
    addNode({ name: `food_${i}`, mesh: foodMesh, translation: [0, -10, 0] }, true);
  }
  const spotMesh = addMesh(makeDisc(0.55, 40), MAT_SPOT);
  addNode({ name: 'lightspot', mesh: spotMesh, translation: [0, -10, 0] }, true);
}

// ==== 10) 特效节点（全部初始隐藏在地下，事件期间才激活） ====
{
  // 进食完成 "+" ×3
  const plusMesh = addMesh(makePlus(0.20), MAT_FX_PLUS);
  for (let i = 0; i < 3; i++) {
    addNode({ name: `plus_fx_${i}`, mesh: plusMesh, translation: [0, -10, 0] }, true);
  }
  // 风线 ×6（细长扁条，沿 +X 长 0.8）
  const windMesh = addMesh(makeBox(0.8, 0.012, 0.05), MAT_FX_WIND);
  for (let i = 0; i < 6; i++) {
    addNode({ name: `wind_line_${i}`, mesh: windMesh, translation: [0, -10, 0] }, true);
  }
  // 河面涟漪 ×3（环带）
  const rippleMesh = addMesh(makeArcBand(0.42, 0.52, 0, Math.PI * 2, 24), MAT_FX_RIPPLE);
  for (let i = 0; i < 3; i++) {
    addNode({ name: `ripple_${i}`, mesh: rippleMesh, translation: [0, -10, 0] }, true);
  }
  // 觅食路径点 ×6
  const dotMesh = addMesh(makeEllipsoid(0.045, 0.045, 0.045, 0, 0, 0, 6, 8), MAT_PATH_DOT);
  for (let i = 0; i < 6; i++) {
    addNode({ name: `path_dot_${i}`, mesh: dotMesh, translation: [0, -10, 0] }, true);
  }
}

// ---------- GLTF/GLB 序列化 ----------
const accessors = [], bufferViews = [];
let bufferParts = [], bufferOffset = 0;

function pad4(n) { return (4 - (n % 4)) % 4; }
function pushView(typedArr, target) {
  const bytes = Buffer.from(typedArr.buffer, typedArr.byteOffset, typedArr.byteLength);
  const padding = pad4(bufferOffset);
  if (padding) bufferParts.push(Buffer.alloc(padding));
  bufferOffset += padding;
  const aligned = (Buffer.concat(bufferParts).length); // offset AFTER padding
  bufferParts.push(bytes);
  const view = { buffer: 0, byteOffset: aligned, byteLength: bytes.length, target };
  bufferViews.push(view);
  bufferOffset = aligned + bytes.length;
  return bufferViews.length - 1;
}
function addAccessor(typedArr, type, componentType, count, target, minMax) {
  const view = pushView(typedArr, target);
  const acc = { bufferView: view, componentType, count, type };
  if (minMax) { acc.min = minMax.min; acc.max = minMax.max; }
  accessors.push(acc);
  return accessors.length - 1;
}

const gltfMeshes = [], gltfNodes = [];
for (const mesh of meshes) {
  const g = mesh.geometry;
  const posArr = new Float32Array(g.positions);
  const norArr = new Float32Array(g.normals);
  const idxArr = g.vertCount() > 65535 ? new Uint32Array(g.indices) : new Uint16Array(g.indices);
  let minX = 1e9, minY = 1e9, minZ = 1e9, maxX = -1e9, maxY = -1e9, maxZ = -1e9;
  for (let i = 0; i < posArr.length; i += 3) {
    minX = Math.min(minX, posArr[i]); maxX = Math.max(maxX, posArr[i]);
    minY = Math.min(minY, posArr[i + 1]); maxY = Math.max(maxY, posArr[i + 1]);
    minZ = Math.min(minZ, posArr[i + 2]); maxZ = Math.max(maxZ, posArr[i + 2]);
  }
  const posAcc = addAccessor(posArr, 'VEC3', 5126, posArr.length / 3, 34962, { min: [minX, minY, minZ], max: [maxX, maxY, maxZ] });
  const norAcc = addAccessor(norArr, 'VEC3', 5126, norArr.length / 3, 34962);
  const idxAcc = addAccessor(idxArr, 'SCALAR', idxArr instanceof Uint32Array ? 5125 : 5123, idxArr.length, 34963);
  gltfMeshes.push({ primitives: [{ attributes: { POSITION: posAcc, NORMAL: norAcc }, indices: idxAcc, material: mesh.material }] });
}

for (const node of nodes) {
  const n = { name: node.name };
  if (node.mesh !== undefined) n.mesh = node.mesh;
  if (node.children) n.children = node.children;
  if (node.translation) n.translation = node.translation;
  if (node.rotation) n.rotation = [node.rotation.x, node.rotation.y, node.rotation.z, node.rotation.w];
  if (node.scale) n.scale = node.scale;
  gltfNodes.push(n);
}

const buffer = Buffer.concat(bufferParts);
const gltf = {
  asset: { version: '2.0', generator: 'guoying gen_world_glb.mjs v2 (M4)' },
  scene: 0,
  scenes: [{ name: 'world', nodes: topNodes }],
  nodes: gltfNodes,
  meshes: gltfMeshes,
  materials: materials.map((m) => ({
    name: m.name,
    pbrMetallicRoughness: { baseColorFactor: m.baseColor, metallicFactor: 0.0, roughnessFactor: m.roughness },
    ...(m.emissive ? { emissiveFactor: m.emissive } : {}),
    ...(m.alphaMode ? { alphaMode: m.alphaMode } : {}),
  })),
  accessors,
  bufferViews,
  buffers: [{ byteLength: buffer.length }],
};

function padBuffer(b, byte) {
  const p = pad4(b.length);
  return p ? Buffer.concat([b, Buffer.alloc(p, byte)]) : b;
}
const jsonChunk = padBuffer(Buffer.from(JSON.stringify(gltf), 'utf8'), 0x20);
const binChunk = padBuffer(buffer, 0x00);
const total = 12 + 8 + jsonChunk.length + 8 + binChunk.length;
const header = Buffer.alloc(12);
header.writeUInt32LE(0x46546C67, 0); // 'glTF'
header.writeUInt32LE(2, 4);
header.writeUInt32LE(total, 8);
const jsonHeader = Buffer.alloc(8);
jsonHeader.writeUInt32LE(jsonChunk.length, 0);
jsonHeader.writeUInt32LE(0x4E4F534A, 4); // 'JSON'
const binHeader = Buffer.alloc(8);
binHeader.writeUInt32LE(binChunk.length, 0);
binHeader.writeUInt32LE(0x004E4942, 4); // 'BIN\0'

const glb = Buffer.concat([header, jsonHeader, jsonChunk, binHeader, binChunk]);
mkdirSync(dirname(OUT_FILE), { recursive: true });
writeFileSync(OUT_FILE, glb);

// ---------- 自校验 ----------
// 这份校验的意义：下面每一条都是真实踩过的坑。宁可生成脚本直接崩，
// 也不要产出一个"看起来 OK、装到真机上才发现少了一半东西"的 glb。
const check = JSON.parse(jsonChunk.toString('utf8'));
const bufLen = check.buffers[0].byteLength;

// 1) bufferView 不得越界
for (const a of check.accessors) {
  const v = check.bufferViews[a.bufferView];
  if (v.byteOffset + v.byteLength > bufLen) throw new Error('bufferView overflow');
}

// 2) 任何 accessor 的 count 都不能为 0（count=0 的索引 accessor 会让引擎静默丢弃该节点）
for (let i = 0; i < check.accessors.length; i++) {
  if (check.accessors[i].count <= 0) {
    throw new Error(`accessor[${i}] 的 count=${check.accessors[i].count}，非法`);
  }
}

// 3) 每个 mesh 都必须有非空索引与顶点（曾因 flatShade 忘记 addTri 而丢掉全部岩石/鹅卵石）
for (let i = 0; i < check.meshes.length; i++) {
  const prim = check.meshes[i].primitives[0];
  const matName = check.materials[prim.material] ? check.materials[prim.material].name : '?';
  const idxAcc = check.accessors[prim.indices];
  const posAcc = check.accessors[prim.attributes.POSITION];
  if (!idxAcc || idxAcc.count < 3) {
    throw new Error(`mesh[${i}](${matName}) 索引为空：count=${idxAcc ? idxAcc.count : 'none'}`);
  }
  if (!posAcc || posAcc.count < 3) {
    throw new Error(`mesh[${i}](${matName}) 顶点不足：count=${posAcc ? posAcc.count : 'none'}`);
  }
}

// 4) 节点变换必须是有限数值（传四元数数组会被写成 [null,null,null,null] 这种非法值）
for (const n of check.nodes) {
  for (const key of ['translation', 'rotation', 'scale']) {
    const v = n[key];
    if (!v) continue;
    for (const x of v) {
      if (typeof x !== 'number' || !Number.isFinite(x)) {
        throw new Error(`节点 ${n.name} 的 ${key} 含非法值: ${JSON.stringify(v)}`);
      }
    }
  }
}

// 5) 必备节点名检查（运行时靠 DFS 按名字查找，名字写错会静默失效）
// 这份清单 = 运行时契约：改模型时**不要**改这些名字，否则功能会无声失效
const names = new Set(check.nodes.map((n) => n.name));
const REQUIRED = [
  // 场景
  'ground', 'ground_inner', 'river', 'river_bed', 'river_shallow',
  'river_bank_stone_0', 'river_bank_stone_15',
  'stone_0', 'stone_7',
  // 树木（trunk/crown 是摇摆驱动点）
  'tree_0', 'tree_1', 'tree_2', 'trunk_0', 'trunk_1', 'trunk_2',
  'crown_0', 'crown_1', 'crown_2', 'fruit_0', 'fruit_8',
  // 昼夜
  'sun_pivot', 'sun_disc', 'moon_pivot', 'moon_disc', 'stars', 'star_0', 'star_29',
  // 天空穹顶（按时段切换可见）
  'sky_0', 'sky_4', 'sky_8',
  // 青蛙（tongue 伸缩、pupil 蓄力前移与眨眼）
  'frog', 'frog_body', 'frog_tongue', 'frog_eye_l', 'frog_eye_r',
  'frog_pupil_l', 'frog_pupil_r',
  // 果蝇（head_pivot 进食低头、wing 拍动）
  'fly', 'head_pivot', 'head', 'wing_left', 'wing_right',
  'wing_blade_l', 'wing_blade_r', 'eye_left', 'eye_right', 'antenna_left', 'antenna_right',
  // 交互与特效
  'food_0', 'food_4', 'lightspot',
  'plus_fx_0', 'plus_fx_2', 'wind_line_0', 'wind_line_5', 'ripple_0', 'ripple_2',
  'path_dot_0', 'path_dot_5',
];
const missing = REQUIRED.filter((n) => !names.has(n));
if (missing.length > 0) throw new Error('缺少必备节点: ' + missing.join(', '));

// 6) 节点名必须唯一：重名会让按名字查找取到错误的节点
const seen = new Map();
for (const n of check.nodes) {
  if (seen.has(n.name)) throw new Error(`节点名重复: ${n.name}`);
  seen.set(n.name, true);
}

// 7) 场景根节点必须全部有效且引用的节点都存在
for (const idx of check.scenes[0].nodes) {
  if (typeof idx !== 'number' || idx < 0 || idx >= check.nodes.length) {
    throw new Error(`scene.nodes 引用了不存在的节点下标: ${idx}`);
  }
}
if (check.scenes[0].nodes.length !== topNodes.length) {
  throw new Error(`scene.nodes 数量(${check.scenes[0].nodes.length}) 与顶层节点登记数(${topNodes.length}) 不一致`);
}

// 8) 三角面数：上下限都要卡（只卡上限会漏掉"几何整体缺失"这种事故）
let triTotal = 0;
for (const m of check.meshes) {
  triTotal += check.accessors[m.primitives[0].indices].count / 3;
}
const TRI_MIN = 8000, TRI_MAX = 80000;
if (triTotal < TRI_MIN) {
  throw new Error(`三角面 ${triTotal} 低于下限 ${TRI_MIN}，可能有 mesh 缺少几何`);
}
if (triTotal > TRI_MAX) {
  throw new Error(`三角面 ${triTotal} 超出预算 ${TRI_MAX}`);
}

console.log(`world.glb OK: ${glb.length} bytes, meshes=${check.meshes.length}, nodes=${check.nodes.length}, ` +
  `materials=${check.materials.length}, topNodes=${topNodes.length}, triangles=${triTotal}`);
console.log('out:', OUT_FILE);
