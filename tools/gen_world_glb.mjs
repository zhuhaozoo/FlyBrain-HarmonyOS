// 果蝇大脑 Demo —— 场景与果蝇模型生成脚本（零依赖，Node >= 18）
// 生成 entry/src/main/resources/rawfile/gltf/world.glb
//
// v1（M0）：地面圆盘 + 环形石块 + 果蝇（thorax/abdomen/head/eyes/antennae/legs/wings）
// v2（M4）：场景丰富化与玩法所需节点 —— 河流弧带 + 河岸卵石、树木 ×3（trunk/crown 二级摇摆）、
//          日月枢轴、星空、树冠果实、青蛙（含舌头）、各类特效节点（加号/风线/涟漪/路径点）、
//          以及果蝇的 head_pivot（进食低头用轴心）。
// v3（M4.5）：建模精细度升级（旋转体剖面/折腿/扫掠翼/低多边形岩石）。
// v4（建模优化）：
//   1) 场景树木/岩石/草丛改用 Quaternius「Ultimate Stylized Nature」CC0 素材的几何
//      （tools/assets/*.glb）。贴图不入包：解码 PNG 取平均色作材质色，并按 alpha
//      裁剪叶片卡片三角形；几何按契约重建为 tree_i → trunk_i → crown_i 层级，
//      运行时节点名与摇摆轴心与 v3 完全一致。
//   2) 果蝇/青蛙减面：旋转体/椭球/扫掠管分段下调，静态装饰件（刚毛/背板环/单眼/
//      平衡棒/蛙鼻孔/蛙蹼）合并为单节点单网格，契约节点全部保留。
//   3) 天空穹顶降分段；序列化数值收敛（JSON 变小）。
//
// 坐标约定：Y 向上，果蝇朝向 +Z，根节点位于地面接触点。
// 运行：node tools/gen_world_glb.mjs
import { writeFileSync, readFileSync, mkdirSync, readdirSync } from 'node:fs';
import { inflateSync } from 'node:zlib';
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

// 对几何整体缩放（uniform 时法线不动；非均匀按逆转置修正后归一化）
function scaleGeometry(g, sx, sy = sx, sz = sx) {
  const uniform = sx === sy && sy === sz;
  for (let i = 0; i < g.vertCount(); i++) {
    g.positions[i * 3] *= sx;
    g.positions[i * 3 + 1] *= sy;
    g.positions[i * 3 + 2] *= sz;
    if (!uniform) {
      const n = norm3([g.normals[i * 3] / sx, g.normals[i * 3 + 1] / sy, g.normals[i * 3 + 2] / sz]);
      g.normals[i * 3] = n[0];
      g.normals[i * 3 + 1] = n[1];
      g.normals[i * 3 + 2] = n[2];
    }
  }
  return g;
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
  // quatBetween 返回的是**未归一化**四元数（既有 makeTube 管线依赖其现状，勿改），
  // 而 bakeTransform 用的 quatApply 只对单位四元数成立 —— 不归一化会把圆柱拉成斜的：
  // 原来算出来是 z∈[-0.54,1.55]、y∈±0.6 的斜拉伸体（舌头比青蛙身体还长）。
  // 归一化后才是"底面在 z=0、沿 +Z 长 1"的单位舌头（运行时 scale.z 伸长）。
  // 见易错总结第 38 条（quatBetween 未归一化）。
  const q = quatBetween([0, 1, 0], [0, 0, 1]);
  const ql = Math.hypot(q.x, q.y, q.z, q.w) || 1;
  const qn = { x: q.x / ql, y: q.y / ql, z: q.z / ql, w: q.w / ql };
  return bakeTransform(g, qn, [1, 1, 1], [0, 0, 0.5]);
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

// ---------- CC0 素材导入库（Quaternius「Ultimate Stylized Nature」等，CC0 1.0） ----------
// 从 tools/assets/*.glb 提取网格几何（POSITION/NORMAL/TEXCOORD_0 + indices），
// 应用节点 TRS 得到世界坐标。贴图不入包（引擎纹理管线未验证 + 体积代价大），
// 只用来做两件事：取平均色作材质底色、按 alpha 裁剪"透明卡片"三角形。
// 卡片式叶片/草叶是单面片，留下来的三角形同时输出正反两个绕序
// （引擎背面剔除行为已踩过坑 —— 见易错总结第 30 条，双绕序最稳）。

function mat4Identity() { return [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]; }
function mat4FromTRS(t, q, s) {
  const x = q.x, y = q.y, z = q.z, w = q.w;
  const x2 = x + x, y2 = y + y, z2 = z + z;
  const xx = x * x2, xy = x * y2, xz = x * z2, yy = y * y2, yz = y * z2, zz = z * z2;
  const wx = w * x2, wy = w * y2, wz = w * z2;
  return [
    (1 - (yy + zz)) * s[0], (xy + wz) * s[0], (xz - wy) * s[0], 0,
    (xy - wz) * s[1], (1 - (xx + zz)) * s[1], (yz + wx) * s[1], 0,
    (xz + wy) * s[2], (yz - wx) * s[2], (1 - (xx + yy)) * s[2], 0,
    t[0], t[1], t[2], 1,
  ];
}
function mat4Mul(a, b) { // 列主序 a×b
  const o = new Array(16);
  for (let c = 0; c < 4; c++) {
    for (let r = 0; r < 4; r++) {
      o[c * 4 + r] = a[r] * b[c * 4] + a[4 + r] * b[c * 4 + 1] + a[8 + r] * b[c * 4 + 2] + a[12 + r] * b[c * 4 + 3];
    }
  }
  return o;
}
function mat4Point(m, p) {
  return [
    m[0] * p[0] + m[4] * p[1] + m[8] * p[2] + m[12],
    m[1] * p[0] + m[5] * p[1] + m[9] * p[2] + m[13],
    m[2] * p[0] + m[6] * p[1] + m[10] * p[2] + m[14],
  ];
}

// 最小 PNG 解码：仅支持 8-bit、非隔行、灰度/RGB/RGBA/调色板（FBX2glTF 导出的贴图足够）。
// 失败返回 null —— 调用方回退到"不裁剪 + 默认配色"，不能让素材问题卡死生成。
function decodePng(bytes) {
  try {
    if (bytes.length < 24 || bytes.readUInt32BE(0) !== 0x89504e47) return null;
    let off = 8, w = 0, h = 0, depth = 0, colorType = 0, palette = null, trns = null;
    const idat = [];
    while (off + 8 <= bytes.length) {
      const len = bytes.readUInt32BE(off);
      const type = bytes.toString('ascii', off + 4, off + 8);
      const data = bytes.subarray(off + 8, off + 8 + len);
      if (type === 'IHDR') {
        w = data.readUInt32BE(0); h = data.readUInt32BE(4);
        depth = data[8]; colorType = data[9];
        if (data[12] !== 0) return null; // 隔行不支持
      } else if (type === 'PLTE') palette = data;
      else if (type === 'tRNS') trns = data;
      else if (type === 'IDAT') idat.push(data);
      else if (type === 'IEND') break;
      off += 12 + len;
    }
    if (depth !== 8 || !w || !h) return null;
    // colorType：0=灰度 2=RGB 3=调色板 6=RGBA
    const ch = colorType === 6 ? 4 : colorType === 2 ? 3 : (colorType === 3 || colorType === 0) ? 1 : 0;
    if (!ch) return null;
    const raw = inflateSync(Buffer.concat(idat));
    const stride = w * ch;
    if (raw.length < h * (stride + 1)) return null;
    const out = new Uint8Array(w * h * ch);
    let pos = 0;
    for (let y = 0; y < h; y++) {
      const filter = raw[pos++];
      const cur = out.subarray(y * stride, (y + 1) * stride);
      cur.set(raw.subarray(pos, pos + stride));
      pos += stride;
      const prev = y > 0 ? out.subarray((y - 1) * stride, y * stride) : null;
      for (let x = 0; x < stride; x++) {
        const a = x >= ch ? cur[x - ch] : 0;
        const b = prev ? prev[x] : 0;
        const c = (prev && x >= ch) ? prev[x - ch] : 0;
        let v = cur[x];
        if (filter === 1) v += a;
        else if (filter === 2) v += b;
        else if (filter === 3) v += (a + b) >> 1;
        else if (filter === 4) {
          const p = a + b - c;
          const pa = Math.abs(p - a), pb = Math.abs(p - b), pc = Math.abs(p - c);
          v += (pa <= pb && pa <= pc) ? a : (pb <= pc ? b : c);
        }
        cur[x] = v & 255;
      }
    }
    return { w, h, ch, data: out, palette, trns };
  } catch {
    return null;
  }
}

// 取归一化 UV 处像素 [r,g,b,a]（glTF 的 UV 原点在左上）
function pngSample(img, u, v) {
  const x = Math.min(img.w - 1, Math.max(0, Math.floor(u * img.w)));
  const y = Math.min(img.h - 1, Math.max(0, Math.floor(v * img.h)));
  const i = (y * img.w + x) * img.ch;
  if (img.ch === 4) return [img.data[i], img.data[i + 1], img.data[i + 2], img.data[i + 3]];
  if (img.ch === 3) return [img.data[i], img.data[i + 1], img.data[i + 2], 255];
  if (img.palette) {
    const pi = img.data[i] * 3;
    const a = img.trns && img.data[i] < img.trns.length ? img.trns[img.data[i]] : 255;
    return [img.palette[pi], img.palette[pi + 1], img.palette[pi + 2], a];
  }
  const g = img.data[i];
  return [g, g, g, 255];
}

function loadGlb(path) {
  const buf = readFileSync(path);
  if (buf.length < 20 || buf.readUInt32LE(0) !== 0x46546C67) throw new Error(`${path} 不是合法 glb`);
  const jsonLen = buf.readUInt32LE(12);
  const json = JSON.parse(buf.slice(20, 20 + jsonLen).toString('utf8'));
  const binStart = 20 + jsonLen + 8;
  const bin = buf.subarray(binStart, binStart + buf.readUInt32LE(binStart - 8));
  return { json, bin };
}

function readAccessor(g, idx) {
  const acc = g.json.accessors[idx];
  const bv = g.json.bufferViews[acc.bufferView];
  const start = (bv.byteOffset ?? 0) + (acc.byteOffset ?? 0);
  const Ctor = { 5126: Float32Array, 5125: Uint32Array, 5123: Uint16Array, 5121: Uint8Array }[acc.componentType];
  const nComp = { SCALAR: 1, VEC2: 2, VEC3: 3, VEC4: 4 }[acc.type];
  return new Ctor(g.bin.buffer, g.bin.byteOffset + start, acc.count * nComp);
}

// 提取指定名字节点（含子树）的全部 primitive，应用世界变换后返回
// [{ matName, pos[], nor[], uv[]|null, idx[] }]
function extractNodePrims(g, nodeName) {
  const byName = new Map(g.json.nodes.map((n, i) => [n.name, i]));
  const rootIdx = byName.get(nodeName);
  if (rootIdx === undefined) throw new Error(`素材缺少节点 ${nodeName}`);
  const out = [];
  const walk = (idx, parentM) => {
    const n = g.json.nodes[idx];
    // glTF 的 rotation 是 [x,y,z,w] 数组，统一转成对象再进矩阵（生成脚本 addNode 的同款坑）
    const rq = Array.isArray(n.rotation)
      ? { x: n.rotation[0], y: n.rotation[1], z: n.rotation[2], w: n.rotation[3] }
      : (n.rotation ?? { x: 0, y: 0, z: 0, w: 1 });
    const m = mat4Mul(parentM, mat4FromTRS(n.translation ?? [0, 0, 0], rq, n.scale ?? [1, 1, 1]));
    if (n.mesh !== undefined) {
      for (const prim of g.json.meshes[n.mesh].primitives) {
        const pos = readAccessor(g, prim.attributes.POSITION);
        const norAcc = prim.attributes.NORMAL !== undefined ? readAccessor(g, prim.attributes.NORMAL) : null;
        const uvAcc = prim.attributes.TEXCOORD_0 !== undefined ? readAccessor(g, prim.attributes.TEXCOORD_0) : null;
        const idxArr = readAccessor(g, prim.indices);
        const p = [], nn = [], uv = [], ii = [];
        for (let i = 0; i < pos.length; i += 3) {
          const wp = mat4Point(m, [pos[i], pos[i + 1], pos[i + 2]]);
          p.push(wp[0], wp[1], wp[2]);
          if (norAcc) {
            const wn = [
              m[0] * norAcc[i] + m[4] * norAcc[i + 1] + m[8] * norAcc[i + 2],
              m[1] * norAcc[i] + m[5] * norAcc[i + 1] + m[9] * norAcc[i + 2],
              m[2] * norAcc[i] + m[6] * norAcc[i + 1] + m[10] * norAcc[i + 2],
            ];
            const l = Math.hypot(wn[0], wn[1], wn[2]) || 1;
            nn.push(wn[0] / l, wn[1] / l, wn[2] / l);
          }
        }
        if (uvAcc) for (let i = 0; i < uvAcc.length; i++) uv.push(uvAcc[i]);
        for (let i = 0; i < idxArr.length; i++) ii.push(idxArr[i]);
        out.push({
          matName: g.json.materials[prim.material].name,
          pos: p, nor: nn, uv: uvAcc ? uv : null, idx: ii,
        });
      }
    }
    for (const c of n.children ?? []) walk(c, m);
  };
  walk(rootIdx, mat4Identity());
  return out;
}

// 多个 primitive 合成一个（索引按顶点偏移接续）。uv 只在全部 primitive 都有且长度一致时保留
function mergePrims(prims) {
  const pos = [], nor = [], idx = [];
  let uv = null;
  if (prims.every((p) => p.uv && p.uv.length === prims[0].uv.length)) {
    uv = [];
  }
  for (const p of prims) {
    const base = pos.length / 3;
    for (let i = 0; i < p.pos.length; i++) pos.push(p.pos[i]);
    for (let i = 0; i < p.nor.length; i++) nor.push(p.nor[i]);
    if (uv) for (let i = 0; i < p.uv.length; i++) uv.push(p.uv[i]);
    for (let i = 0; i < p.idx.length; i++) idx.push(p.idx[i] + base);
  }
  return { pos, nor, uv, idx };
}

// 按贴图 alpha 裁掉透明卡片三角形；保留下来的三角形输出正反两个绕序并重排顶点
function pruneLeafCards(prim, img, alphaThreshold = 0.35) {
  if (!img || !prim.uv) return { ...prim, doubled: false, dropped: 0 };
  const pos = [], nor = [], uv = [], idx = [];
  const remap = new Map();
  const vid = (v) => {
    let id = remap.get(v);
    if (id === undefined) {
      id = pos.length / 3;
      remap.set(v, id);
      pos.push(prim.pos[v * 3], prim.pos[v * 3 + 1], prim.pos[v * 3 + 2]);
      nor.push(prim.nor[v * 3], prim.nor[v * 3 + 1], prim.nor[v * 3 + 2]);
      uv.push(prim.uv[v * 2], prim.uv[v * 2 + 1]);
    }
    return id;
  };
  let dropped = 0;
  for (let i = 0; i < prim.idx.length; i += 3) {
    const a = prim.idx[i], b = prim.idx[i + 1], c = prim.idx[i + 2];
    const u = (prim.uv[a * 2] + prim.uv[b * 2] + prim.uv[c * 2]) / 3;
    const v = (prim.uv[a * 2 + 1] + prim.uv[b * 2 + 1] + prim.uv[c * 2 + 1]) / 3;
    if (pngSample(img, u, v)[3] / 255 < alphaThreshold) { dropped++; continue; }
    const a2 = vid(a), b2 = vid(b), c2 = vid(c);
    idx.push(a2, b2, c2, c2, b2, a2);
  }
  return { pos, nor, uv, idx, doubled: true, dropped };
}

// 贴图平均色 → 0..255 的 [r,g,b]（sRGB 空间抽样平均）。alpha 加权可压掉透明区杂色
function sampleTexColor(img, stride = 4, alphaWeighted = false) {
  if (!img) return null;
  let r = 0, g = 0, b = 0, wsum = 0, n = 0;
  for (let y = 0; y < img.h; y += stride) {
    for (let x = 0; x < img.w; x += stride) {
      const px = pngSample(img, x / img.w, y / img.h);
      const a = alphaWeighted ? px[3] / 255 : 1;
      if (a <= 0.01) continue;
      r += px[0] * a; g += px[1] * a; b += px[2] * a; wsum += a; n++;
    }
  }
  if (!n) return null;
  return [Math.round(r / wsum), Math.round(g / wsum), Math.round(b / wsum)];
}

// 一组 prim 归一化：底面 y=0、xz 居中、高度缩放到 targetH
function normalizePrims(prims, targetH) {
  let minX = 1e9, minY = 1e9, minZ = 1e9, maxX = -1e9, maxY = -1e9, maxZ = -1e9;
  for (const p of prims) {
    for (let i = 0; i < p.pos.length; i += 3) {
      minX = Math.min(minX, p.pos[i]); maxX = Math.max(maxX, p.pos[i]);
      minY = Math.min(minY, p.pos[i + 1]); maxY = Math.max(maxY, p.pos[i + 1]);
      minZ = Math.min(minZ, p.pos[i + 2]); maxZ = Math.max(maxZ, p.pos[i + 2]);
    }
  }
  const h = Math.max(1e-6, maxY - minY);
  const s = targetH / h;
  const cx = (minX + maxX) / 2, cz = (minZ + maxZ) / 2;
  for (const p of prims) {
    for (let i = 0; i < p.pos.length; i += 3) {
      p.pos[i] = (p.pos[i] - cx) * s;
      p.pos[i + 1] = (p.pos[i + 1] - minY) * s;
      p.pos[i + 2] = (p.pos[i + 2] - cz) * s;
    }
  }
  return { height: h * s, radius: Math.max(maxX - minX, maxZ - minZ) * s / 2 };
}

// 导入结果 → 生成脚本的 Geometry（可接 addMesh）
function primsToGeometry(p) {
  const g = new Geometry();
  for (let i = 0; i < p.pos.length; i += 3) {
    g.addVertex(p.pos[i], p.pos[i + 1], p.pos[i + 2], p.nor[i], p.nor[i + 1], p.nor[i + 2]);
  }
  for (let i = 0; i < p.idx.length; i += 3) g.addTri(p.idx[i], p.idx[i + 1], p.idx[i + 2]);
  return g;
}

// 把若干 Geometry 拼成一个（静态装饰件合并节点用，材质必须一致）
function mergeGeometryList(list) {
  const out = new Geometry();
  for (const g of list) {
    const base = out.vertCount();
    for (let i = 0; i < g.vertCount(); i++) {
      out.addVertex(g.positions[i * 3], g.positions[i * 3 + 1], g.positions[i * 3 + 2],
        g.normals[i * 3], g.normals[i * 3 + 1], g.normals[i * 3 + 2]);
    }
    // 注意 addTri 一次吃三个索引：逐元素调用会把索引数撑大 3 倍且全指向顶点 0
    for (let i = 0; i < g.indices.length; i += 3) {
      out.addTri(base + g.indices[i], base + g.indices[i + 1], base + g.indices[i + 2]);
    }
  }
  return out;
}

function srgb255ToLin(rgb, alpha = 1) {
  return srgb2lin((rgb[0] << 16) | (rgb[1] << 8) | rgb[2]).map((c, i) => i < 3 ? c : alpha);
}
function shadeRgb(rgb, k) {
  return rgb.map((c) => Math.max(0, Math.min(255, Math.round(c * k))));
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
  // v6：腹部底色整体调亮（0x7a5228 → 0x9a7440）。真果蝇腹部是"黄褐色底 + 每节后缘黑带"，
  // 原来是整体深棕 + 深色环，配上粗腹很容易被看成蜜蜂；调亮后浅黄背板/深色带的层次才出得来。
  { name: 'abdomen', baseColor: srgb2lin(0x9a7440), roughness: 0.7 },
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

// ---- CC0 素材载入（贴图只用于取色与透明裁剪，不入包） ----
// 素材来源与许可见 tools/assets/LICENSE-README.md（Quaternius，CC0 1.0 公有领域）
const ASSET_DIR = join(dirname(fileURLToPath(import.meta.url)), 'assets');
const ASSET_STATS = [];

// 树：NormalTree_4 当主树（河畔），NormalTree_5 ×2 作配角（旋转错开避免克隆感）。
// 选小体量变体是刻意的：贴图卡片裁剪后仍是不小的面数开销，预算要让给观感而不是复数。
const TREE_VARIANTS = ['NormalTree_4', 'NormalTree_5', 'NormalTree_5'];
function loadTreeVariant(glb, nodeName, targetH) {
  const prims = extractNodePrims(glb, nodeName);
  // 注意：材质名是 "...Leaves"，正则不能写 /Leaf/（"Leaves" 不含子串 "Leaf"）
  const bark = mergePrims(prims.filter((p) => /Bark/i.test(p.matName)));
  const leafRaw = mergePrims(prims.filter((p) => /Leav/i.test(p.matName)));
  if (!bark.pos.length || !leafRaw.pos.length) throw new Error(`${nodeName} 缺少树干或树叶几何`);
  // 叶片贴图按名字从 glb 里定位（"Leaves"），解码失败则不裁剪（回退路径，见 pruneLeafCards）
  const leafImgInfo = glb.json.images.find((im) => /Leav/i.test(im.name ?? ''));
  const leafImg = leafImgInfo ? decodePng(readLeafImage(glb, leafImgInfo)) : null;
  const leaf = pruneLeafCards(leafRaw, leafImg);
  const info = normalizePrims([bark, leaf], targetH);
  ASSET_STATS.push(`tree ${nodeName}: barkTris=${bark.idx.length / 3} leafTris=${leaf.idx.length / 3}` +
    ` (裁剪 ${leaf.dropped} 张透明卡片)`);
  return { bark, leaf, h: info.height, radius: info.radius };
}
// 树的贴图嵌在 glb 的 bufferView 里，取字节再交给 PNG 解码
function readLeafImage(glb, imgInfo) {
  const bv = glb.json.bufferViews[imgInfo.bufferView];
  return glb.bin.subarray(bv.byteOffset ?? 0, (bv.byteOffset ?? 0) + bv.byteLength);
}

const qnTreeGlb = loadGlb(join(ASSET_DIR, 'qn_trees.glb'));
// 叶色/树干色取自贴图（alpha 加权，压掉透明区杂色）；解码失败则退回项目既有配色。
// 法线贴图按 "_Normal" 后缀排除（不能裸写 /Normal/：所有贴图名都带 "NormalTree" 前缀）
const qnLeafImgInfo = qnTreeGlb.json.images.find((im) => /Leav/i.test(im.name ?? ''));
const qnBarkImgInfo = qnTreeGlb.json.images.find((im) => /Bark/i.test(im.name ?? '') && !/_Normal/i.test(im.name ?? ''));
const qnLeafRgb = sampleTexColor(decodePng(qnLeafImgInfo ? readLeafImage(qnTreeGlb, qnLeafImgInfo) : null), 4, true)
  ?? [0x4f, 0x8f, 0x42];
const qnBarkRgb = sampleTexColor(decodePng(qnBarkImgInfo ? readLeafImage(qnTreeGlb, qnBarkImgInfo) : null), 4)
  ?? [0x6b, 0x4a, 0x2c];
const trees = TREE_VARIANTS.map((v, i) => loadTreeVariant(qnTreeGlb, v, [1.88, 1.60, 1.45][i]));

const MAT_QN_BARK = materials.length;
materials.push({ name: 'qn_bark', baseColor: srgb255ToLin(qnBarkRgb), roughness: 0.9 });
const MAT_QN_LEAF = materials.length;
materials.push({ name: 'qn_leaf', baseColor: srgb255ToLin(qnLeafRgb), roughness: 0.9 });
const MAT_QN_LEAF_LIGHT = materials.length;
materials.push({ name: 'qn_leaf_light', baseColor: srgb255ToLin(shadeRgb(qnLeafRgb, 1.18)), roughness: 0.9 });
const MAT_QN_LEAF_DARK = materials.length;
materials.push({ name: 'qn_leaf_dark', baseColor: srgb255ToLin(shadeRgb(qnLeafRgb, 0.8)), roughness: 0.9 });
// 同一变体的两棵树用不同明暗的叶色 + 差异化高度/旋转，避免"同一棵树复制三遍"的观感
const TREE_LEAF_MATS = [MAT_QN_LEAF, MAT_QN_LEAF_LIGHT, MAT_QN_LEAF_DARK];

// 岩石 ×3 变体（场内石与河岸卵石共用，节点缩放区分大小——这些节点没有子节点，可安全缩放）
function loadRock(file, targetH) {
  const g = loadGlb(join(ASSET_DIR, file));
  const meshNode = g.json.nodes.find((n) => n.mesh !== undefined && n.name !== 'RootNode');
  const prim = mergePrims(extractNodePrims(g, meshNode.name));
  const info = normalizePrims([prim], targetH); // 归一化到单位高，大小交给节点 scale
  ASSET_STATS.push(`rock ${file}: tris=${prim.idx.length / 3} r=${info.radius.toFixed(3)}`);
  prim.radius = info.radius; // 水平外接半径（单位高归一化后）：供 blocker 碰撞圆换算
  return prim;
}
const rockGeoms = [
  loadRock('qn_rock.glb', 1.0),
  loadRock('qn_rock_large.glb', 1.0),
  loadRock('qn_rocks.glb', 1.0),
];

// 草丛 ×2 变体（纯装饰，静态节点；叶片卡片同样做透明裁剪 + 双绕序）
const qnGrassGlb = loadGlb(join(ASSET_DIR, 'qn_grass.glb'));
const qnGrassImgInfo = qnGrassGlb.json.images.find((im) => /Grass/i.test(im.name ?? ''));
const qnGrassImg = decodePng(qnGrassImgInfo ? readLeafImage(qnGrassGlb, qnGrassImgInfo) : null);
const qnGrassRgb = sampleTexColor(qnGrassImg, 4, true) ?? [0x5d, 0x8f, 0x3f];
function loadGrass(nodeName, targetH) {
  const prim = mergePrims(extractNodePrims(qnGrassGlb, nodeName));
  const pruned = pruneLeafCards(prim, qnGrassImg, 0.3);
  normalizePrims([pruned], targetH);
  ASSET_STATS.push(`grass ${nodeName}: tris=${pruned.idx.length / 3} (裁剪 ${pruned.dropped} 张透明卡片)`);
  return pruned;
}
const grassLarge = loadGrass('Grass_Large_Extruded', 1.0);
const grassSmall = loadGrass('Grass_Small', 1.0);

const MAT_QN_GRASS = materials.length;
materials.push({ name: 'qn_grass', baseColor: srgb255ToLin(qnGrassRgb), roughness: 0.95 });

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

// ---- 碰撞标记节点（运行时"果蝇步行不可穿越"的圆形阻挡区） ----
// 无网格、无子节点，只有两个可读通道：translation = 圆心(x,z)、scale.x = 阻挡半径。
// 为什么这么做见易错总结第 35 条（静态几何没地方放"半径"这类数值）。
// 全局统一编号 blocker_0..N-1：运行时段号连续收集（找不到就停），所以**不要跳号**。
// 一律挂成顶层节点：不能挂在会摇动的 tree_i/trunk_i 下面，否则碰撞圆跟着树一起摆。
let blockerCount = 0;
function addBlocker(x, z, r) {
  addNode({ name: `blocker_${blockerCount}`, translation: [x, 0, z], scale: [r, 1, r] }, true);
  blockerCount++;
}

// 树干"贴地部分"（最低 ratio 高度内）的水平圆心与半径。
// 树的碰撞圆只取树干：枝条与树冠不算阻挡（果蝇本该能从树冠下走过），
// 同时补偿"bark 包围盒中心 ≠ 树干轴心"的偏移（枝条通常不对称）。
function trunkBaseCircle(geom, h, ratio = 0.12) {
  const pos = geom.positions;
  const yMax = h * ratio;
  let minX = 1e9, maxX = -1e9, minZ = 1e9, maxZ = -1e9;
  for (let i = 0; i < pos.length; i += 3) {
    if (pos[i + 1] > yMax) continue;
    minX = Math.min(minX, pos[i]); maxX = Math.max(maxX, pos[i]);
    minZ = Math.min(minZ, pos[i + 2]); maxZ = Math.max(maxZ, pos[i + 2]);
  }
  if (minX > maxX) return { cx: 0, cz: 0, r: 0.08 };   // 没有贴地顶点：退化为细树干
  const cx = (minX + maxX) / 2;
  const cz = (minZ + maxZ) / 2;
  let r = 0.06;
  for (let i = 0; i < pos.length; i += 3) {
    if (pos[i + 1] > yMax) continue;
    r = Math.max(r, Math.hypot(pos[i] - cx, pos[i + 2] - cz));
  }
  return { cx, cz, r };
}

// ==== 1) 地面：外圈草地 + 内圈活动区（同心圆盘叠放） ====
// v5（M5P1.1）：地盘 5.5 → 7.4。树木在 5.0~5.6、落果最远 ~5.75，原来 5.5 的地盘
// 盖不住树根、果蝇（步行 6.0）也会走到草地边缘之外。
// v6（本次升级）：全部径向尺寸 ×1.5（地盘 7.4 → 11.0），地面圆盘分段同步加密，
// 否则 11 半径下 52 段的边缘会明显看出多边形折角。
//
// 注意 尺度成对约定：下面这台面上的每个半径都必须与运行时字段同批修改，否则会出现
// "果蝇走水面 / 够不到果实 / 天空被裁" 这类看起来像 bug 的现象。对照表：
//   ARENA_R 11.0        ↔ FlyConfig.flyArenaRadius 10.8（步行 arenaRadius 9.0）
//   RIVER_SAMPLES/RIVER_HALF ↔ FlyConfig.riverPts/riverHalfWidth
//   FROG_R/FROG_A       ↔ FlyConfig.frogX/frogZ
//   SKY_RADIUS 56       ↔ SceneManager.maxRadius 34 + panLimit 13.5
const ARENA_R = 11.0;        // 地面圆盘半径（原 7.4）
const ARENA_INNER_R = 6.6;   // 内圈活动区半径（原 4.4）
// 青蛙出生点（7) 青蛙段与 4.6) 配景段都要用，所以在这里先声明）
// v7：出生点移到蜿蜒河道北岸（旧 6.8∠64° 已远离新河道）。运行时 FlyConfig.frogX/frogZ 成对。
const FROG_R = 5.46, FROG_A = 52.8 * DEG;

// v7：蜿蜒河道 —— 自西向东蜿蜒穿过场心的 S 形（用户需求："河流从中间蜿蜒插过"）。
// 中心线控制点 + Catmull-Rom 采样；运行时 FlyConfig.riverPts 必须与 RIVER_SAMPLES
// 逐点一致、riverHalfWidth 对应 RIVER_HALF（尺度成对常量，易错总结第 37 条）。
const RIVER_CTRL = [
  [-11.0, 2.0], [-7.0, -1.6], [-3.2, -2.6], [-0.2, -0.8],
  [2.0, 1.8], [4.6, 3.2], [7.4, 2.6], [11.0, 0.8],
];
const RIVER_HALF = 0.7;      // 河道半宽（水面宽 1.4）
function catmullSample(pts, perSeg) {
  const out = [];
  for (let i = 0; i < pts.length - 1; i++) {
    const p0 = pts[Math.max(0, i - 1)], p1 = pts[i], p2 = pts[i + 1],
      p3 = pts[Math.min(pts.length - 1, i + 2)];
    const n = i === pts.length - 2 ? perSeg + 1 : perSeg;
    for (let j = 0; j < n; j++) {
      const t = j / perSeg, t2 = t * t, t3 = t2 * t;
      out.push([
        0.5 * (2 * p1[0] + (-p0[0] + p2[0]) * t + (2 * p0[0] - 5 * p1[0] + 4 * p2[0] - p3[0]) * t2 + (-p0[0] + 3 * p1[0] - 3 * p2[0] + p3[0]) * t3),
        0.5 * (2 * p1[1] + (-p0[1] + p2[1]) * t + (2 * p0[1] - 5 * p1[1] + 4 * p2[1] - p3[1]) * t2 + (-p0[1] + 3 * p1[1] - 3 * p2[1] + p3[1]) * t3),
      ]);
    }
  }
  out.push(pts[pts.length - 1].slice());
  return out;
}
const RIVER_SAMPLES = catmullSample(RIVER_CTRL, 3);
// 点到河道中心折线的最近距离/最近点/指向该点一侧的法向
function riverNearest(x, z) {
  let bd = Infinity, bx = 0, bz = 0, bi = 0, rcx = 0, rcz = 0;
  for (let i = 0; i < RIVER_SAMPLES.length - 1; i++) {
    const ax = RIVER_SAMPLES[i][0], az = RIVER_SAMPLES[i][1];
    const bx2 = RIVER_SAMPLES[i + 1][0], bz2 = RIVER_SAMPLES[i + 1][1];
    const dx = bx2 - ax, dz = bz2 - az;
    const l2 = dx * dx + dz * dz;
    let t = l2 > 1e-9 ? ((x - ax) * dx + (z - az) * dz) / l2 : 0;
    t = Math.max(0, Math.min(1, t));
    const cx = ax + dx * t, cz = az + dz * t;
    const d = Math.hypot(x - cx, z - cz);
    if (d < bd) { bd = d; bx = cx; bz = cz; bi = i; rcx = cx; rcz = cz; }
  }
  const dx = RIVER_SAMPLES[bi + 1][0] - RIVER_SAMPLES[bi][0];
  const dz = RIVER_SAMPLES[bi + 1][1] - RIVER_SAMPLES[bi][1];
  const l = Math.hypot(dx, dz) || 1;
  let nx = -dz / l, nz = dx / l;
  if ((x - bx) * nx + (z - bz) * nz < 0) { nx = -nx; nz = -nz; }
  return { d: bd, cx: rcx, cz: rcz, nx, nz };
}
const riverDist = (x, z) => riverNearest(x, z).d;
{
  const outer = bakeTransform(makeDisc(ARENA_R, 72), { x: 0, y: 0, z: 0, w: 1 }, [1, 1, 1], [0, 0.001, 0]);
  addNode({ name: 'ground', mesh: addMesh(outer, MAT_GROUND) }, true);
  const inner = bakeTransform(makeDisc(ARENA_INNER_R, 56), { x: 0, y: 0, z: 0, w: 1 }, [1, 1, 1], [0, 0.006, 0]);
  addNode({ name: 'ground_inner', mesh: addMesh(inner, MAT_GROUND_INNER) }, true);
}

// ==== 2) 场内石块（v4：Quaternius CC0 岩石几何 ×3 变体，随机朝向与比例，半埋入地面） ====
// 导入时已把岩石归一化为"底面 y=0、高 1"，节点 scale（无子节点，可安全缩放）负责实际大小
// v6：8 块 → 14 块（r 2.6~8.9 重新铺开），让放大后的场地不显空。
// 铺位约束由文件末尾的"石块铺位自检"把关（那里所有尺度常量都已定义）：
// 不进河流弧带、离树根与青蛙出生点 ≥1.2、不出草地边缘。
const STONE_POS = [
  [3.4, -3.4, 0.80], [5.8, -2.6, 0.95], [-4.6, 0.6, 0.85],
  [-5.8, 4.3, 0.80], [0.8, -6.4, 0.62], [4.6, -5.2, 0.85],
  [-6.8, -4.6, 0.72], [-2.9, -5.4, 0.60], [6.4, 5.6, 0.88],
  [3.0, 6.4, 0.70], [-1.4, 4.9, 0.78], [5.8, 0.2, 0.66],
  [-6.2, 2.6, 0.90], [8.0, -0.9, 0.60],
]; // [x, z, scale]（v7：避开蜿蜒河道重新铺位）
{
  const rockMeshes = rockGeoms.map((g) => addMesh(primsToGeometry(g), MAT_STONE));
  const stonePos = STONE_POS;
  const rng = makeRng(0x5709ee);
  for (let i = 0; i < stonePos.length; i++) {
    const s = stonePos[i];
    const k = s[2] * 0.62;
    // 随机量与顺序保持原样（改顺序会改变全部石头的造型）
    const rot = quatMul(quatY(rng() * Math.PI * 2), quatZ((rng() - 0.5) * 0.35));
    const sx = k * (0.9 + rng() * 0.25);
    const sy = k * (0.75 + rng() * 0.4);
    const sz = k * (0.9 + rng() * 0.25);
    addNode({
      name: `stone_${i}`, mesh: rockMeshes[i % rockMeshes.length],
      translation: [s[0], -0.06 * k, s[1]],
      rotation: rot, scale: [sx, sy, sz],
    }, true);
    // 碰撞圆（半径 = 该变体归一化后的水平外接半径 × 水平缩放的最大值，绕 Y 旋转后仍在圆内，
    //   略偏保守：果蝇会保持一点点距离，视觉上不会贴进石缝）
    addBlocker(s[0], s[1], rockGeoms[i % rockGeoms.length].radius * Math.max(sx, sz));
  }
}

// ==== 3) 蜿蜒河道（水面/河床/浅水缘）+ 两岸卵石 ====
// v7：河道由 RIVER_SAMPLES 折线扫掠成带状三角条带，替代旧的圆弧带。
// 三层：河床（最宽、泥土色、y=0.004）→ 浅水缘（略宽于水面、0.009）→ 主水面（0.012，
// 与 EnvironmentController.riverY 一致）。宽度沿程 0.85~1.25 倍起伏，让河道有粗细变化。
function riverRibbon(innerOff, outerOff, y) {
  const n = RIVER_SAMPLES.length;
  const g = new Geometry();
  const left = [], right = [];
  for (let i = 0; i < n; i++) {
    const p = RIVER_SAMPLES[i];
    const q = RIVER_SAMPLES[Math.min(n - 1, i + 1)];
    const q0 = RIVER_SAMPLES[Math.max(0, i - 1)];
    const dx = q[0] - q0[0], dz = q[1] - q0[1];
    const l = Math.hypot(dx, dz) || 1;
    const nx = -dz / l, nz = dx / l;
    const wobble = 1 + 0.18 * Math.sin(i * 1.7) * Math.sin(i * 0.9);
    const li = innerOff * wobble, lo = outerOff * wobble;
    left.push([p[0] + nx * li, p[1] + nz * li]);
    right.push([p[0] + nx * lo, p[1] + nz * lo]);
  }
  for (let i = 0; i < n; i++) {
    g.addVertex(left[i][0], y, left[i][1], 0, 1, 0);
    g.addVertex(right[i][0], y, right[i][1], 0, 1, 0);
  }
  for (let i = 0; i < n - 1; i++) {
    const a0 = i * 2, b0 = i * 2 + 1, a1 = i * 2 + 2, b1 = i * 2 + 3;
    // 双绕序输出（易错总结第 30 条：水面从上/下看都必须可见）
    g.addTri(a0, a1, b1); g.addTri(a0, b1, b0);
    g.addTri(a0, b1, a1); g.addTri(a0, b0, b1);
  }
  return g;
}
{
  // v7.1：各层高差拉开（原来河床 0.004 与内圈地面 0.004 共面 → 转视角时岸边整片闪烁）。
  // EnvironmentController.riverY 必须与主水面高度一致（成对常量）。
  addNode({ name: 'river_bed', mesh: addMesh(riverRibbon(-(RIVER_HALF + 0.45), RIVER_HALF + 0.45, 0.014), MAT_RIVER_BED) }, true);
  addNode({ name: 'river_shallow', mesh: addMesh(riverRibbon(-(RIVER_HALF + 0.14), RIVER_HALF + 0.14, 0.021), MAT_WATER_SHALLOW) }, true);
  addNode({ name: 'river', mesh: addMesh(riverRibbon(-RIVER_HALF, RIVER_HALF, 0.028), MAT_WATER) }, true);

  // 两岸鹅卵石 ×16（每岸 8 个，沿程均匀 + 抖动；阻挡圆照旧走 blocker 通道，总数不变）
  //
  // v7.2 关键约束：卵石阻挡圆必须让出「可行走沙滩带」。
  // 运行时贴地个体会被河域推岸推到水面外沿（RIVER_HALF + 0.05 = 0.75，FlyBrain.applyBoundary），
  // 若卵石内缘压在这条线上，果蝇一上岸就落进卵石阻挡圆：推水岸与推石头两个约束方向相反，
  // 位置来回弹 + 朝向反复被扭 → 表现为"走到河滩上就被卡住"（真机反馈②）。
  // 所以卵石内缘统一排在 BEACH_LINE 之外（=水面外沿再留 0.35 的可走沙滩带）；
  // 半径大的卵石整体外挪，内缘仍在同一位置，视觉上照样贴着岸边。
  const BEACH_LINE = RIVER_HALF + 0.35;
  const rng = makeRng(0x51ee01);
  const pebbleMeshes = rockGeoms.map((g2) => addMesh(primsToGeometry(g2), MAT_BANK_STONE));
  let k = 0;
  for (const bank of [-1, 1]) {
    const ring = [];
    const nBank = 8;
    for (let i = 0; i < nBank; i++) {
      const t = (i + 0.5) / nBank;
      const si = Math.min(RIVER_SAMPLES.length - 1, Math.round(t * (RIVER_SAMPLES.length - 1)));
      const p = RIVER_SAMPLES[si];
      const q = RIVER_SAMPLES[Math.min(RIVER_SAMPLES.length - 1, si + 1)];
      const q0 = RIVER_SAMPLES[Math.max(0, si - 1)];
      const dx = q[0] - q0[0], dz = q[1] - q0[1];
      const l = Math.hypot(dx, dz) || 1;
      let nx = -dz / l, nz = dx / l;
      if (bank < 0) { nx = -nx; nz = -nz; }
      const s2 = 0.65 + rng() * 0.85;
      const kk = s2 * 0.22;
      const rot = quatMul(quatY(rng() * Math.PI * 2), quatZ((rng() - 0.5) * 0.4));
      const sx = kk * (0.85 + rng() * 0.3);
      const sy = kk * (0.7 + rng() * 0.4);
      const sz = kk * (0.85 + rng() * 0.3);
      // 阻挡半径先算出来，再据此决定离河道多远（内缘必须 ≥ BEACH_LINE）。
      // 0.06 是余量：下面第一摆用的法向取自该采样点的局部折线段，与"到整条折线的最近距离"
      // 有偏差（河道弯曲处），所以再用真实最近点校正一次，最后按真实距离断言。
      const br = rockGeoms[k % rockGeoms.length].radius * Math.max(sx, sz);
      const offWant = RIVER_HALF + 0.20 + (rng() - 0.5) * 0.3;
      const off = Math.max(offWant, BEACH_LINE + br + 0.06);
      let px = p[0] + nx * off, pz = p[1] + nz * off;
      const rnFix = riverNearest(px, pz);
      if (rnFix.d - br < BEACH_LINE) {
        const off2 = BEACH_LINE + br + 0.06;
        px = rnFix.cx + rnFix.nx * off2;
        pz = rnFix.cz + rnFix.nz * off2;
      }
      addNode({
        name: `river_bank_stone_${k}`, mesh: pebbleMeshes[k % pebbleMeshes.length],
        translation: [px, -0.03 * kk, pz],
        rotation: rot, scale: [sx, sy, sz],
      }, true);
      addBlocker(px, pz, br);
      ring.push({ t, x: px, z: pz, r: br, inner: riverDist(px, pz) - br });
      k++;
    }
    ring.sort((a, b) => a.t - b.t);
    let minClear = Infinity, wide = 0, minInner = Infinity;
    for (let i = 0; i < ring.length; i++) {
      const p = ring[i], q = ring[(i + 1) % ring.length];
      const clear = Math.hypot(p.x - q.x, p.z - q.z) - (p.r + q.r);
      minClear = Math.min(minClear, clear);
      minInner = Math.min(minInner, p.inner);
      if (clear > 0.6) wide++;
    }
    ASSET_STATS.push(`bank ${bank < 0 ? '左岸' : '右岸'}: n=8 最小净宽=${minClear.toFixed(2)} ` +
      `宽敞缺口=${wide} 卵石内缘距河道中心=${minInner.toFixed(2)}`);
    if (minClear < 0.45) {
      throw new Error(`河岸最小净宽 ${minClear.toFixed(2)} < 0.45（果蝇过不去）`);
    }
    if (minInner < BEACH_LINE - 1e-6) {
      throw new Error(`河岸卵石内缘 ${minInner.toFixed(2)} < ${BEACH_LINE}：压住可行走沙滩带，` +
        `果蝇会被"推水岸"与"推石头"两个约束顶着卡住`);
    }
  }
}

// ==== 4) 树木 ×3：tree_i（根）→ trunk_i（一级摇摆）→ crown_i（二级摇摆） ====
// v4：几何来自 Quaternius CC0 素材（NormalTree_4 主树 + NormalTree_5 ×2），
// 树干/树叶是两份独立网格，高度烘焙、底部贴地。crown 的摆动轴心放在树冠基部（0.52h），
// 树叶顶点已相对该轴心平移；朝向差异（yaw）烘焙进几何，tree_i 不带旋转。
// trunk_i 下挂子节点 ⇒ 不允许 scale（易错总结第 27 条），一切尺寸烘焙进顶点。
const TREE_SPECS = [
  // v6：树距 5.0/5.6/5.3 → 7.5/8.4/7.95（≤8.4，必须留在步行软边界 9.0 之内，
  //   否则果蝇够不到树冠落下的果实，会围着软边界转圈）。高度见 loadTreeVariant 的 targetH。
  // v7：树挪到蜿蜒河道两岸之外（距河道中心线 ≥3.2，树距 ≤8.4 保持落果可达）
  { x: -4.6, z: -6.2, yaw: 0.0 },
  { x: 7.6, z: -3.4, yaw: 2.1 },
  { x: -7.5, z: 3.2, yaw: 4.2 },
];
{
  const fruitMesh = addMesh(makeEllipsoid(0.055, 0.055, 0.055, 0, 0, 0, 8, 10), MAT_FRUIT);
  const rng = makeRng(0x7ee501);

  let fruitIdx = 0;
  const fruitPending = [];   // 果实的绝对坐标，作为顶层节点挂上（落地逻辑在运行时）
  for (let ti = 0; ti < TREE_SPECS.length; ti++) {
    const spec = TREE_SPECS[ti];
    const t = trees[ti];
    const h = t.h;
    // 树叶顶点改写成"相对摆动轴心"的坐标（轴心 = 树冠基部）
    const pivotY = h * 0.52;
    for (let i = 1; i < t.leaf.pos.length; i += 3) t.leaf.pos[i] -= pivotY;
    const crownG = bakeTransform(primsToGeometry(t.leaf), quatY(spec.yaw), [1, 1, 1], [0, 0, 0]);
    const trunkG = bakeTransform(primsToGeometry(t.bark), quatY(spec.yaw), [1, 1, 1], [0, 0, 0]);

    const crown = addNode({
      name: `crown_${ti}`, translation: [0, pivotY, 0],
      mesh: addMesh(crownG, TREE_LEAF_MATS[ti]),
    });
    const trunk = addNode({
      name: `trunk_${ti}`, mesh: addMesh(trunkG, MAT_QN_BARK), children: [crown],
    });
    addNode({ name: `tree_${ti}`, translation: [spec.x, 0, spec.z], children: [trunk] }, true);
    // 树干阻挡圆：只取贴地那一段树干（枝条/树冠不算阻挡），
    // 圆心补偿到树干轴心（trunkBaseCircle 从烘焙后的顶点算），挂在顶层不受树摆影响
    const base = trunkBaseCircle(trunkG, h);
    addBlocker(spec.x + base.cx, spec.z + base.cz, base.r);
    ASSET_STATS.push(`tree_${ti} trunk base: r=${base.r.toFixed(3)} off=(${base.cx.toFixed(2)},${base.cz.toFixed(2)})`);

    // 果实 ×3：**记为顶层节点**（绝对坐标，从树根沿 a 方向距离 = 树距 + 冠内偏移）。
    // 不挂在树冠下：果实成熟后要自己落到地面被果蝇吃掉，不能被树的摇摆带着走。
    // 可达性保护（M5P1.1，v6 随场地放大同步）：落点距离必须钳在果蝇步行可达范围
    // （软边界 9.0 内，取 8.6），且河流弧上（20°~108°）往里收到内岸以内 ——
    // 否则果实落在够不到的地方，果蝇会围着树转圈。
    for (let f = 0; f < 3; f++) {
      const a = rng() * Math.PI * 2;
      const fr = t.radius * (0.35 + rng() * 0.45);
      const fy = pivotY + (h * 0.92 - pivotY) * (0.25 + rng() * 0.75);
      const treeR = Math.hypot(spec.x, spec.z);
      const rMax = 8.6;
      let dist = Math.min(treeR + fr, rMax);
      let fx = dist * Math.cos(a);
      let fz = dist * Math.sin(a);
      // v7：河道改蜿蜒折线 —— 落点若压进水带，沿法向推到近岸外侧
      if (riverDist(fx, fz) < RIVER_HALF + 0.35) {
        const nr = riverNearest(fx, fz);
        fx = nr.cx + nr.nx * (RIVER_HALF + 0.5);
        fz = nr.cz + nr.nz * (RIVER_HALF + 0.5);
      }
      fruitPending.push({
        name: `fruit_${fruitIdx}`,
        pos: [fx, fy, fz],
      });
      fruitIdx++;
    }
  }
  // 果实作为顶层节点补挂（位置即世界坐标，行为层据此判断"落地点"）
  for (const fp of fruitPending) {
    addNode({ name: fp.name, mesh: fruitMesh, translation: fp.pos }, true);
  }
}

// ==== 4.5) 草丛 ×28（v4 新增纯装饰：Quaternius CC0 草，静态节点，不参与任何驱动） ====
// v6：14 → 28 个、半径范围 1.1~4.2 → 1.6~6.3（场地放大后草丛密度不能变稀）。
// 所有实例共享下面 2 个网格，三角面不随实例数增长。
// 位置避开树根（≥0.9）与河流内岸（≥0.5），否则草会插在水里或穿进树干。
{
  const grassMeshes = [
    addMesh(primsToGeometry(grassLarge), MAT_QN_GRASS),
    addMesh(primsToGeometry(grassSmall), MAT_QN_GRASS),
  ];
  // v7：河岸湿生草用更鲜绿的材质（普通草地草保持原色），把"水线"在视觉上衬托出来
  const MAT_QN_GRASS_FRESH = materials.length;
  materials.push({
    name: 'qn_grass_fresh',
    baseColor: qnGrassRgb.map((c, i) => Math.min(1, c * (i < 3 ? 1.45 : 1))),
    roughness: 0.9,
  });
  const grassMeshesFresh = [
    addMesh(primsToGeometry(grassLarge), MAT_QN_GRASS_FRESH),
    addMesh(primsToGeometry(grassSmall), MAT_QN_GRASS_FRESH),
  ];
  const rng = makeRng(0x9a3301);
  for (let i = 0; i < 28; i++) {
    let gx, gz, ok = false;
    for (let tries = 0; tries < 30 && !ok; tries++) {
      const a = rng() * Math.PI * 2;
      const r = 1.6 + rng() * 4.7;
      gx = r * Math.cos(a); gz = r * Math.sin(a);
      ok = TREE_SPECS.every((t) => Math.hypot(t.x - gx, t.z - gz) > 0.9)
        && riverDist(gx, gz) > RIVER_HALF + 0.5;
    }
    if (!ok) continue;   // 30 次都撞上：宁可少长一丛，也不插到河里/树里
    const s = 0.16 + rng() * 0.14;
    addNode({
      name: `grass_${i}`, mesh: grassMeshes[i % grassMeshes.length],
      translation: [gx, 0, gz],
      rotation: quatY(rng() * Math.PI * 2),
      scale: [s * (0.85 + rng() * 0.3), s * (0.85 + rng() * 0.3), s * (0.85 + rng() * 0.3)],
    }, true);
  }
  // v7：河岸草甸 —— 沿蜿蜒河道两岸加密的湿生草丛（用户反馈"河边的草很粗糙"：
  // 密度也是重点；两岸各 13 丛，紧贴水线外侧成带状，远处草地保持疏朗）
  let placedRip = 0;
  for (let i = 0; i < 40; i++) {
    const bank = i % 2 === 0 ? 1 : -1;
    const t = (Math.floor(i / 2) + 0.5) / 20 + (rng() - 0.5) * 0.03;
    const si = Math.min(RIVER_SAMPLES.length - 1, Math.max(0, Math.round(t * (RIVER_SAMPLES.length - 1))));
    const p = RIVER_SAMPLES[si];
    const q = RIVER_SAMPLES[Math.min(RIVER_SAMPLES.length - 1, si + 1)];
    const q0 = RIVER_SAMPLES[Math.max(0, si - 1)];
    const dx = q[0] - q0[0], dz = q[1] - q0[1];
    const l = Math.hypot(dx, dz) || 1;
    let nx = -dz / l, nz = dx / l;
    if (bank < 0) { nx = -nx; nz = -nz; }
    const off = RIVER_HALF + 0.30 + rng() * 0.85;
    const gx = p[0] + nx * off, gz = p[1] + nz * off;
    if (Math.hypot(gx, gz) > ARENA_R - 0.6) continue;
    if (!TREE_SPECS.every((t2) => Math.hypot(t2.x - gx, t2.z - gz) > 0.9)) continue;
    const s = 0.14 + rng() * 0.13;
    addNode({
      name: `grass_river_${i}`, mesh: grassMeshesFresh[i % grassMeshesFresh.length],
      translation: [gx, 0, gz], rotation: quatY(rng() * Math.PI * 2),
      scale: [s * (0.85 + rng() * 0.3), s * (0.85 + rng() * 0.3), s * (0.85 + rng() * 0.3)],
    }, true);
    placedRip++;
  }
  ASSET_STATS.push(`grass riparian: ${placedRip}/40`);
}

// ==== 4.6) 静态配景（v6 新增：Kenney「Nature Kit」CC0 素材）====
// 素材来源与许可见 tools/assets/LICENSE-README.md（Kenney，CC0 1.0 公有领域）。
// 这批素材是"无贴图、纯材质色"的低多边形模型（每个 32~200 面），导入时：
//   1) **整只模型一起归一化**（底面贴地、xz 居中、高度缩放到 spec.h）——必须整只算一次包围盒，
//      否则花瓣/茎/伞盖各算各的，会被缩放散架；
//   2) 三角面输出**双绕序**（易错总结第 30 条：薄片类几何从背面看会被整片剔除，
//      素材里有大量草叶/花瓣薄片，单面绕序在真机上会看到"空洞"）；
//   3) 每个实例的变换在生成期烘焙进顶点，按（变体 × 材质）合并成 1 个 props_* 节点 + 1 个网格。
// **只作装饰**：不参与碰撞、不注册进 registerExtra（每帧零驱动成本）——
// 果蝇可以从花丛/蘑菇间穿过，这是刻意的（放大后的场地到处立"隐形墙"会更糟）。
const MAT_PROP_PURPLE = materials.length;
materials.push({ name: 'prop_purple', baseColor: srgb2lin(0x9b5fd0), roughness: 0.7 });
const MAT_PROP_RED = materials.length;
materials.push({ name: 'prop_red', baseColor: srgb2lin(0xc9423a), roughness: 0.7 });
const MAT_PROP_YELLOW = materials.length;
materials.push({ name: 'prop_yellow', baseColor: srgb2lin(0xe8c24a), roughness: 0.7 });
const MAT_PROP_TAN = materials.length;
materials.push({ name: 'prop_tan', baseColor: srgb2lin(0xc09a63), roughness: 0.8 });
const MAT_PROP_STEM = materials.length;
materials.push({ name: 'prop_stem', baseColor: srgb2lin(0xe4dcc8), roughness: 0.85 });
const MAT_PROP_WOOD = materials.length;
materials.push({ name: 'prop_wood', baseColor: srgb2lin(0xb08a58), roughness: 0.85 });

// 变体表：素材文件名 → 归一化高度 + 材质名映射（Kenney 的材质名是 grass / colorRed / woodBark …）。
// h 按"真果蝇 3mm、场地约 10 个果蝇身长"的比例取：花 0.26、蘑菇 0.17、灌木 0.34~0.42、芦苇 0.52。
const PROP_VARIANTS = [
  { id: 'flower_purple', file: 'kn_flower_purpleA.glb', h: 0.26, n: 4, rMin: 2.0, rMax: 8.0,
    mats: { grass: MAT_QN_GRASS, colorPurple: MAT_PROP_PURPLE } },
  { id: 'flower_red', file: 'kn_flower_redA.glb', h: 0.26, n: 4, rMin: 2.0, rMax: 8.0,
    mats: { grass: MAT_QN_GRASS, colorRed: MAT_PROP_RED } },
  { id: 'flower_yellow', file: 'kn_flower_yellowA.glb', h: 0.26, n: 4, rMin: 2.0, rMax: 8.2,
    mats: { grass: MAT_QN_GRASS, colorYellow: MAT_PROP_YELLOW } },
  { id: 'mushroom_red', file: 'kn_mushroom_red.glb', h: 0.17, n: 3, rMin: 2.2, rMax: 8.4,
    mats: { _defaultMat: MAT_PROP_STEM, colorRed: MAT_PROP_RED } },
  { id: 'mushroom_tan', file: 'kn_mushroom_tan.glb', h: 0.17, n: 3, rMin: 2.2, rMax: 8.4,
    mats: { _defaultMat: MAT_PROP_STEM, colorTan: MAT_PROP_TAN } },
  { id: 'mushroom_group', file: 'kn_mushroom_group.glb', h: 0.24, n: 2, rMin: 3.0, rMax: 8.0,
    mats: { _defaultMat: MAT_PROP_STEM, colorRed: MAT_PROP_RED } },
  { id: 'bush', file: 'kn_bush.glb', h: 0.34, n: 3, rMin: 3.0, rMax: 8.6, mats: { grass: MAT_QN_GRASS } },
  { id: 'bush_detailed', file: 'kn_bush_detailed.glb', h: 0.42, n: 3, rMin: 3.0, rMax: 8.4,
    mats: { grass: MAT_QN_GRASS } },
  { id: 'log', file: 'kn_log.glb', h: 0.22, n: 2, rMin: 3.5, rMax: 8.0, minGap: 1.0,
    mats: { woodBark: MAT_QN_BARK, woodInner: MAT_PROP_WOOD } },
  { id: 'stump', file: 'kn_stump.glb', h: 0.24, n: 2, rMin: 3.5, rMax: 8.2, minGap: 1.0,
    mats: { woodBark: MAT_QN_BARK, woodInner: MAT_PROP_WOOD } },
  { id: 'reed', file: 'kn_reed.glb', h: 0.52, n: 10, manual: true, mats: { grass: MAT_QN_GRASS } },
  { id: 'lily', file: 'kn_lily.glb', h: 0.06, n: 4, manual: true,
    mats: { leafsGreen: MAT_QN_LEAF, leafsDark: MAT_QN_LEAF_DARK, colorRed: MAT_PROP_RED } },
];
{
  const rng = makeRng(0x6b0b01);   // 独立种子：配景的随机量与既有元素完全无关
  const buckets = new Map();       // `${id}|${matName}` → { id, matName, mat, geoms }
  const placed = [];               // 已放置实例的 [x, z]，用于互不重叠
  const cloneGeom = (g) => {
    const c = new Geometry();
    c.positions = g.positions.slice();
    c.normals = g.normals.slice();
    c.indices = g.indices.slice();
    return c;
  };
  const doubleWind = (g) => {      // 每个三角形补一份反向绕序（薄片几何双面可见）
    const n = g.indices.length;
    for (let i = 0; i < n; i += 3) g.addTri(g.indices[i + 2], g.indices[i + 1], g.indices[i]);
    return g;
  };
  const loadVariant = (spec) => {
    const g = loadGlb(join(ASSET_DIR, spec.file));
    const rootName = g.json.nodes[g.json.scenes[0].nodes[0]].name;
    const prims = extractNodePrims(g, rootName);
    normalizePrims(prims, spec.h);          // 整只一起归一化（关键：不能按材质分组归一化）
    const byMat = new Map();
    for (const p of prims) {
      if (spec.mats[p.matName] === undefined) throw new Error(`${spec.file} 出现未映射的材质 ${p.matName}`);
      if (!byMat.has(p.matName)) byMat.set(p.matName, []);
      byMat.get(p.matName).push(p);
    }
    const parts = [];
    for (const [matName, list] of byMat) {
      parts.push({ matName, mat: spec.mats[matName], geom: doubleWind(primsToGeometry(mergePrims(list))) });
    }
    ASSET_STATS.push(`prop ${spec.id}: tris=${parts.reduce((s, p) => s + p.geom.indices.length / 3, 0)}` +
      ` 材质=${parts.map((p) => p.matName).join('/')}`);
    return parts;
  };
  const variants = new Map();
  const counts = new Map();        // 各变体实际落位数量（拒绝采样连续失败会少放，这里打印出来核对）
  for (const spec of PROP_VARIANTS) variants.set(spec.id, loadVariant(spec));
  const put = (id, x, z, y, yaw, s) => {
    for (const part of variants.get(id)) {
      const key = `${id}|${part.matName}`;
      if (!buckets.has(key)) buckets.set(key, { id, matName: part.matName, mat: part.mat, geoms: [] });
      buckets.get(key).geoms.push(bakeTransform(cloneGeom(part.geom), quatY(yaw), [s, s, s], [x, y, z]));
    }
    placed.push([x, z]);
    counts.set(id, (counts.get(id) ?? 0) + 1);
  };
  // 落点检查：不进河流弧带、离树根/石块/青蛙出生点/已放配景足够远、不出草地边缘
  const freeSpot = (x, z, minGap) => {
    const r = Math.hypot(x, z);
    const a = Math.atan2(z, x);
    if (r < 1.2 || r > ARENA_R - 1.4) return false;
    if (riverDist(x, z) < RIVER_HALF + 0.5) return false;
    for (const t of TREE_SPECS) if (Math.hypot(t.x - x, t.z - z) < 1.0) return false;
    for (const sp of STONE_POS) if (Math.hypot(sp[0] - x, sp[1] - z) < 0.95) return false;
    if (Math.hypot(FROG_R * Math.cos(FROG_A) - x, FROG_R * Math.sin(FROG_A) - z) < 1.1) return false;
    for (const p of placed) if (Math.hypot(p[0] - x, p[1] - z) < minGap) return false;
    return true;
  };
  for (const spec of PROP_VARIANTS) {
    if (spec.n === undefined || spec.manual === true) continue;   // reed/lily 由下面的专用循环摆
    for (let i = 0; i < spec.n; i++) {
      for (let tries = 0; tries < 40; tries++) {
        const a = rng() * Math.PI * 2;
        const r = spec.rMin + rng() * (spec.rMax - spec.rMin);
        const x = r * Math.cos(a), z = r * Math.sin(a);
        if (!freeSpot(x, z, spec.minGap ?? 0.55)) continue;
        put(spec.id, x, z, 0, rng() * Math.PI * 2, 0.85 + rng() * 0.4);
        break;
      }
    }
  }
  // 芦苇：沿蜿蜒河道两岸的水线处（v7：折线取点）—— 靠水才有那味儿
  for (let i = 0; i < 8; i++) {
    const bank = i % 2 === 0 ? 1 : -1;
    const t = (i + 0.5) / 8;
    const si = Math.min(RIVER_SAMPLES.length - 1, Math.max(0, Math.round(t * (RIVER_SAMPLES.length - 1))));
    const p = RIVER_SAMPLES[si];
    const q = RIVER_SAMPLES[Math.min(RIVER_SAMPLES.length - 1, si + 1)];
    const q0 = RIVER_SAMPLES[Math.max(0, si - 1)];
    const dx = q[0] - q0[0], dz = q[1] - q0[1];
    const l = Math.hypot(dx, dz) || 1;
    let nx = -dz / l, nz = dx / l;
    if (bank < 0) { nx = -nx; nz = -nz; }
    const off = RIVER_HALF + 0.08 + rng() * 0.25;
    put('reed', p[0] + nx * off, p[1] + nz * off, 0, rng() * Math.PI * 2, 0.45 + rng() * 0.35);
  }
  // 睡莲：贴在河面上（水面 y = 0.012，睡莲抬到 0.03 免得被水面盖住）
  for (let i = 0; i < 4; i++) {
    const t = (i + 0.5) / 4;
    const si = Math.min(RIVER_SAMPLES.length - 1, Math.round(t * (RIVER_SAMPLES.length - 1)));
    const p = RIVER_SAMPLES[si];
    const q = RIVER_SAMPLES[Math.min(RIVER_SAMPLES.length - 1, si + 1)];
    const q0 = RIVER_SAMPLES[Math.max(0, si - 1)];
    const dx = q[0] - q0[0], dz = q[1] - q0[1];
    const l = Math.hypot(dx, dz) || 1;
    const nx = -dz / l, nz = dx / l;
    const off = (rng() - 0.5) * RIVER_HALF * 0.9;
    put('lily', p[0] + nx * off, p[1] + nz * off, 0.036, rng() * Math.PI * 2, 0.9 + rng() * 0.5);
  }
  for (const b of buckets.values()) {
    addNode({
      name: `props_${b.id}_${b.matName.replace(/[^A-Za-z]/g, '')}`,
      mesh: addMesh(mergeGeometryList(b.geoms), b.mat),
    }, true);
  }
  ASSET_STATS.push('props 落位: ' + PROP_VARIANTS
    .map((s) => `${s.id}=${counts.get(s.id) ?? 0}/${s.n ?? 0}`).join(' '));
}

// ==== 5) 太阳 / 月亮枢轴（绕 Z 轴匀速旋转，天然实现东升西落） ====
// v6：轨道半径 9 → 13.5、球径 ×1.5（场地放大后日月的视张角不能变小）。
// 轨道半径必须与运行时 FlyConfig.sunOrbitRadius 一致。
const SUN_ORBIT = 13.5;
{
  const sunMesh = addMesh(makeEllipsoid(0.82, 0.82, 0.82, 0, 0, 0, 10, 14), MAT_SUN);
  const moonMesh = addMesh(makeEllipsoid(0.60, 0.60, 0.60, 0, 0, 0, 10, 14), MAT_MOON);
  // 圆盘替身：用小球而非平面圆盘，避免正/背面剔除导致某个角度看不见。
  // 注意命名：不能叫 'sun' —— 运行时会用 createLight({name:'sun'}) 创建平行光，
  // 同名会让按名字查找取到灯而不是这个球体。
  const sun = addNode({ name: 'sun_disc', mesh: sunMesh, translation: [SUN_ORBIT, 0, 0] });
  addNode({ name: 'sun_pivot', children: [sun] }, true);
  const moon = addNode({ name: 'moon_disc', mesh: moonMesh, translation: [SUN_ORBIT, 0, 0] });
  addNode({ name: 'moon_pivot', rotation: quatFromAxisAngle(0, 0, 1, Math.PI), children: [moon] }, true);
}

// ==== 6) 星空（穹顶半球，夜晚显隐 + 缓慢自转） ====
// v6：30 颗 / 球半径 12 → 40 颗 / 球半径 18（场地放大后星星不能显得又少又近）。
{
  const starMesh = addMesh(makeEllipsoid(0.055, 0.055, 0.055, 0, 0, 0, 5, 6), MAT_STAR);
  const rng = makeRng(0x57a200);
  const starChildren = [];
  for (let i = 0; i < 40; i++) {
    // 半球均匀取点：y > 0.15，半径 18
    const u = rng() * 2 - 1;
    const phi = rng() * Math.PI * 2;
    const y = 0.15 + (1 - 0.15) * rng();
    const rHoriz = Math.sqrt(Math.max(0, 1 - y * y));
    const s = 0.7 + rng() * 0.9;
    starChildren.push(addNode({
      name: `star_${i}`, mesh: starMesh,
      translation: [18 * rHoriz * Math.cos(phi), 18 * y, 18 * rHoriz * Math.sin(phi)],
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
// 半径 56：必须大于"相机最远距离（SceneManager.maxRadius 34）+ 平移上限（panLimit 13.5）
// = 47.5"，否则拉到最远/平移到底时相机跑到球外，天空会被裁掉。
const SKY_RADIUS = 56;
{
  // 球面，法线朝内（观察者在球内）。
  // 关键：**两个绕序都输出**。只输出单向时，若引擎对背面剔除的处理与预期不同，
  // 从球内看就会被整片剔除、直接露出组件底色（实测就是这样：天空一直是灰的）。
  // 双向输出后无论引擎是否真正支持 doubleSided，球内都必然可见；
  // 若引擎支持 doubleSided，背向的那一面会被剔除，不会与正面打架。
  // v4：分段 8×16 → 4×10。穹顶是纯色球壳，低分段在 35 半径下肉眼无差别，
  //   9 个穹顶合计从 4.6k 面降到 1.4k 面。
  const makeSkyDome = (R, lat = 4, lon = 10) => {
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
// v6：出生点 4.55∠64° → 6.8∠64°（场地放大后它在内岸附近原地蹲着会显得贴到河边，
//   这里整体外推到跑道中段）。运行时 FlyConfig.frogX/frogZ 必须与 FROG_R/FROG_A 一致
//   （常量在 1) 地面段的尺度块里声明，配景段也要用它做避让）。
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
  // v4 减面：旋转体 26×22 → 20×15
  const bodyMesh = addMesh(
    squashY(bakeTransform(makeRevolutionZ(bodyProfile, 20, 15),
      { x: 0, y: 0, z: 0, w: 1 }, [1, 1, 1], [0, 0.215, 0]), 0.78), MAT_FROG_BODY);
  // 咽喉囊（下颌处浅色鼓包）
  const throatMesh = addMesh(makeEllipsoid(0.145, 0.075, 0.150, 0, 0.115, 0.145, 10, 12), MAT_FROG_EYE);
  // 眼球（凸出于头顶）
  const eyeMesh = addMesh(makeEllipsoid(0.088, 0.092, 0.088, 0, 0, 0, 10, 12), MAT_FROG_EYE);
  // 瞳孔：竖向椭圆（蛙类特征）
  const pupilMesh = addMesh(makeEllipsoid(0.030, 0.052, 0.030, 0, 0, 0, 7, 9), MAT_LEG);
  // 腿：用扫掠管做两段折腿
  const tongueMesh = addMesh(makeTongueUnit(0.05), MAT_FROG_TONGUE);

  const frogChildren = [];
  frogChildren.push(addNode({ name: 'frog_body', mesh: bodyMesh }));
  frogChildren.push(addNode({ name: 'frog_throat', mesh: throatMesh }));
  // 眼球 + 瞳孔（瞳孔是独立节点：控制器在蓄力时前移、眨眼时隐藏）
  frogChildren.push(addNode({ name: 'frog_eye_l', mesh: eyeMesh, translation: [-0.145, 0.315, 0.145] }));
  frogChildren.push(addNode({ name: 'frog_eye_r', mesh: eyeMesh, translation: [0.145, 0.315, 0.145] }));
  frogChildren.push(addNode({ name: 'frog_pupil_l', mesh: pupilMesh, translation: [-0.150, 0.330, 0.212] }));
  frogChildren.push(addNode({ name: 'frog_pupil_r', mesh: pupilMesh, translation: [0.140, 0.330, 0.212] }));
  // 鼻孔 ×2 → 合并为单节点（纯装饰，运行时不单独驱动）
  frogChildren.push(addNode({
    name: 'frog_nostrils',
    mesh: addMesh(mergeGeometryList([
      bakeTransform(makeEllipsoid(0.014, 0.014, 0.014, 0, 0, 0, 6, 7), { x: 0, y: 0, z: 0, w: 1 }, [1, 1, 1], [-0.048, 0.185, 0.268]),
      bakeTransform(makeEllipsoid(0.014, 0.014, 0.014, 0, 0, 0, 6, 7), { x: 0, y: 0, z: 0, w: 1 }, [1, 1, 1], [0.048, 0.185, 0.268]),
    ]), MAT_LEG),
  }));

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
      name: `frog_leg_front_${i}`, mesh: addMesh(makeTube(path, [0.055, 0.036, 0.030], 6, true, true), MAT_FROG_BODY),
      translation: L.base,
    }));
  }
  // 后肢 ×2（粗壮、折叠成 Z 形，是青蛙的辨识特征）
  const hindLegs = [
    { sx: -1, base: [-0.190, 0.215, -0.190], kneeA: [-0.330, 0.185, -0.330], kneeB: [-0.300, 0.070, -0.080], foot: [-0.320, 0.010, -0.330] },
    { sx: 1, base: [0.190, 0.215, -0.190], kneeA: [0.330, 0.185, -0.330], kneeB: [0.300, 0.070, -0.080], foot: [0.320, 0.010, -0.330] },
  ];
  const webGeoms = [];
  for (let i = 0; i < hindLegs.length; i++) {
    const L = hindLegs[i];
    const path = [[0, 0, 0],
      [L.kneeA[0] - L.base[0], L.kneeA[1] - L.base[1], L.kneeA[2] - L.base[2]],
      [L.kneeB[0] - L.base[0], L.kneeB[1] - L.base[1], L.kneeB[2] - L.base[2]],
      [L.foot[0] - L.base[0], L.foot[1] - L.base[1], L.foot[2] - L.base[2]]];
    frogChildren.push(addNode({
      name: `frog_leg_hind_${i}`, mesh: addMesh(makeTube(path, [0.075, 0.052, 0.040, 0.032], 6, true, true), MAT_FROG_BODY),
      translation: L.base,
    }));
    // 蹼足：烘焙旋转与平移，稍后合并为单节点
    webGeoms.push(bakeTransform(makeBox(0.16, 0.014, 0.13),
      quatY(L.sx > 0 ? -0.35 : 0.35), [1, 1, 1], [L.foot[0], 0.008, L.foot[2]]));
  }
  frogChildren.push(addNode({ name: 'frog_webs', mesh: addMesh(mergeGeometryList(webGeoms), MAT_FROG_BODY) }));

  // 舌头：挂在与嘴同高的位置，沿本地 +Z 伸缩（底面固定在 z=0，运行时 scale.z 伸长）
  frogChildren.push(addNode({ name: 'frog_tongue', mesh: tongueMesh, translation: [0, 0.150, 0.300] }));

  addNode({ name: 'frog', translation: [fx, 0, fz], rotation: qFrog, children: frogChildren }, true);
}

// ==== 8) 果蝇 ×6（M5 多智能体；朝 +Z，根节点在地面） ====
// v3：躯干/头改用旋转体剖面，腹部加背板环，复眼加大外扩，单眼/平衡棒/背刚毛，两段折腿，扫掠透镜翅。
// v4 减面：旋转体/椭球分段整体下调，装饰件合并节点。
// v5（M5）：同一套网格烘焙 6 份节点树（fly_0..fly_5），网格索引跨果蝇共享（数据只存一份）；
//   全部放在原点，运行时按数量决定上场几只、并把初始位置铺在出生圈上（见 FlyAgents）。
// v5.1（用户反馈"像蜜蜂、偏大"）：整体缩小到 0.6 倍；腹部额外收窄 0.85（蜜蜂感主要来自
//   粗壮的条纹大腹）；翅膀只缩 0.75 —— 相对更长，接近果蝇"小身大翅"的真实比例。
// v6 新增：腹部浅黄背板材质（真果蝇腹部是"浅黄底 + 每节后缘一道黑带"，
// 而不是整体深棕；配合下面的 5 节背板把"蜜蜂感"去掉）。追加到材质表末尾，不影响既有索引。
const MAT_ABDOMEN_LIGHT = materials.length;
materials.push({ name: 'abdomen_light', baseColor: srgb2lin(0xd8b476), roughness: 0.7 });

// ==== 8) 果蝇 ×6：NeuroMechFly v1.0 高精度重建模型（Apache-2.0）====
// 来源：NeLy-EPFL/NeuroMechFly（真实果蝇 CT 重建，65 个分部件网格共 33.4 万三角面，
// 含独立口器 Haustellum/Rostrum、复眼、触角、平衡棒、五节跗节腿、左右翅）。
// STL 为米制局部坐标；nmf.sdf 的 link pose（毫米，旋转恒 0）给出拼装平移。
// 世界系 x=向前、y=向左、z=向上 → 场景系 = (-y, z-hGround, x-xMid) * K：
// 前向 +z、贴地 y=0、右 +x（与既有渲染契约一致：左翅在 -x，绕 z 拍动、绕 y 收展）。
// 运行时契约不变：fly_i / wing_left_i / wing_right_i / head_pivot_i；
// 翅根铰点、头枢轴直接取自 SDF 的 LWing/RWing/Head link 原点（真实关节位置）。
const NMF_DIR = join(dirname(fileURLToPath(import.meta.url)), 'assets', 'nmf_stl');
const FLY_BODY_LEN = 0.42;   // 目标体长（FlyConfig.bodyRadius/eatRadius/相机偏移等按此成对）

function nmfParseSTL(path) {
  const buf = readFileSync(path);
  const count = buf.readUInt32LE(80);
  if (84 + count * 50 !== buf.length) {
    throw new Error(`STL 尺寸校验失败 ${path}: ${buf.length} vs ${84 + count * 50}`);
  }
  const tris = new Float32Array(count * 9);
  for (let i = 0; i < count; i++) {
    const o = 84 + i * 50 + 12;
    for (let v = 0; v < 9; v++) tris[i * 9 + v] = buf.readFloatLE(o + v * 4);
  }
  return tris;   // 米制局部坐标（三角汤）
}

function nmfParseLinks(path) {
  const s = readFileSync(path, 'utf8');
  const map = new Map();
  for (const m of s.matchAll(/<link name="([^"]+)">\s*<pose>([^<]*)<\/pose>/g)) {
    const v = m[2].trim().split(/\s+/).map(Number);
    // SDF rpy（R = Rz(y)Ry(p)Rx(r)）—— 解包保留以兼容任意导出；但注意 nmf.sdf 的
    // link 旋转恒为 0：**link pose 只是零关节角绑定布局，站姿不在这份数据里**
    // （v7.1 曾误以为换 locomotion_optimization.sdf 就带真实站姿，实测两份 SDF 的
    // link pose 几乎逐数相同、腿垂直下挂，见易错总结第 38 条）。
    const r = v[3], p = v[4], y = v[5];
    const cr = Math.cos(r), sr = Math.sin(r), cp = Math.cos(p), sp = Math.sin(p),
      cy = Math.cos(y), sy = Math.sin(y);
    map.set(m[1], {
      p: [v[0], v[1], v[2]],
      rpy: [r, p, y],
      R: [cy * cp, cy * sp * sr - sy * cr, cy * sp * cr + sy * sr,
        sy * cp, sy * sp * sr + cy * cr, sy * sp * cr - cy * sr, -sp, cp * sr, cp * cr],
    });
  }
  return map;
}

// 三角汤 → 焊接顶点 + 平均法线（平滑着色；量化 0.0005mm 合并 STL 重复顶点）
function nmfGeometry(soup) {
  const geom = new Geometry();
  const keyOf = (x, y, z) => `${x.toFixed(4)}|${y.toFixed(4)}|${z.toFixed(4)}`;
  const vmap = new Map();   // key → { idx, nx, ny, nz, n }
  const addTriIdx = [];
  for (let i = 0; i < soup.length; i += 9) {
    const ax = soup[i], ay = soup[i + 1], az = soup[i + 2];
    const bx = soup[i + 3], by = soup[i + 4], bz = soup[i + 5];
    const cx = soup[i + 6], cy = soup[i + 7], cz = soup[i + 8];
    // 面法线
    const ux = bx - ax, uy = by - ay, uz = bz - az;
    const vx = cx - ax, vy = cy - ay, vz = cz - az;
    let nx = uy * vz - uz * vy, ny = uz * vx - ux * vz, nz = ux * vy - uy * vx;
    const nl = Math.hypot(nx, ny, nz) || 1;
    nx /= nl; ny /= nl; nz /= nl;
    const tri = [];
    for (const [px, py, pz] of [[ax, ay, az], [bx, by, bz], [cx, cy, cz]]) {
      const k = keyOf(px, py, pz);
      let rec = vmap.get(k);
      if (!rec) {
        rec = { idx: geom.addVertex(px, py, pz, 0, 0, 0), nx: 0, ny: 0, nz: 0, n: 0 };
        vmap.set(k, rec);
      }
      rec.nx += nx; rec.ny += ny; rec.nz += nz; rec.n++;
      tri.push(rec.idx);
    }
    addTriIdx.push(tri);
  }
  for (const rec of vmap.values()) {
    const l = Math.hypot(rec.nx, rec.ny, rec.nz) || 1;
    geom.normals[rec.idx * 3] = rec.nx / l;
    geom.normals[rec.idx * 3 + 1] = rec.ny / l;
    geom.normals[rec.idx * 3 + 2] = rec.nz / l;
  }
  for (const [a, b, c] of addTriIdx) geom.addTri(a, b, c);
  return geom;
}

{
  // v7.2：站姿修正。回到 nmf.sdf（rpy 恒 0 的纯净零位）；真实站姿由下方"关节链 FK"
  // 在生成期摆出并烘进节段顶点。nmf_loco.sdf 并不含站姿（其模型名甚至仍是
  // neuromechfly_noLimits，link pose 与 nmf.sdf 几乎逐数相同——六条腿垂直下挂）。
  const nmfLinks = nmfParseLinks(join(NMF_DIR, 'nmf.sdf'));
  const stlFiles = readdirSync(NMF_DIR).filter((f) => f.endsWith('.stl'));
  // —— 装配（毫米）：v = R(rpy)·(local×1000) + linkPos；体长基准 bbox（排除翅膀）——
  const assembled = new Map();   // name → Float32Array（世界毫米）
  for (const f of stlFiles) {
    const name = f.replace(/\.stl$/, '');
    const L = nmfLinks.get(name);
    if (!L) throw new Error(`nmf.sdf 缺少部件 pose: ${name}`);
    const tris = nmfParseSTL(join(NMF_DIR, f));
    const v = new Float32Array(tris.length);
    for (let i = 0; i < tris.length; i += 3) {
      const lx = tris[i] * 1000, ly = tris[i + 1] * 1000, lz = tris[i + 2] * 1000;
      v[i] = L.R[0] * lx + L.R[1] * ly + L.R[2] * lz + L.p[0];
      v[i + 1] = L.R[3] * lx + L.R[4] * ly + L.R[5] * lz + L.p[1];
      v[i + 2] = L.R[6] * lx + L.R[7] * ly + L.R[8] * lz + L.p[2];
    }
    assembled.set(name, v);
  }
  // —— 非腿部件的姿势（头部俯仰/腹端下卷/双翅收拢贴背/平衡棒）：沿用 v7.1 从
  // nmf_loco.sdf 读 rpy 的做法，绕各自 link 原点旋转烘顶点。nmf.sdf 是零位布局，
  // 零位的翅膀是水平展开的，不烘焙这层姿势双翅就会摊平。
  // 腿部姿势不取自 nmf_loco（它的腿 rpy 近零、也非真实站姿），由下方关节链 FK 摆出。
  const poseLinks = nmfParseLinks(join(NMF_DIR, 'nmf_loco.sdf'));
  const legRe = /^(?:L|R)[FMH](?:Coxa|Femur|Tibia|Tarsus\d)$/;
  for (const [name, v] of assembled) {
    if (legRe.test(name)) continue;
    const L = poseLinks.get(name);
    if (!L) continue;
    if (Math.hypot(L.rpy[0], L.rpy[1], L.rpy[2]) < 1e-9) continue;
    for (let i = 0; i < v.length; i += 3) {
      const d = [v[i] - L.p[0], v[i + 1] - L.p[1], v[i + 2] - L.p[2]];
      const r = [
        L.R[0] * d[0] + L.R[1] * d[1] + L.R[2] * d[2],
        L.R[3] * d[0] + L.R[4] * d[1] + L.R[5] * d[2],
        L.R[6] * d[0] + L.R[7] * d[1] + L.R[8] * d[2],
      ];
      v[i] = L.p[0] + r[0]; v[i + 1] = L.p[1] + r[1]; v[i + 2] = L.p[2] + r[2];
    }
  }
  // 体长基准 = 口器前端到腹末（排除向后收拢的翅膀，否则翅膀会把比例撑大）
  const bMin = [1e9, 1e9, 1e9], bMax = [-1e9, -1e9, -1e9];
  for (const [name, v] of assembled) {
    if (name === 'LWing' || name === 'RWing') continue;
    for (let i = 0; i < v.length; i += 3) {
      if (v[i] < bMin[0]) bMin[0] = v[i]; if (v[i] > bMax[0]) bMax[0] = v[i];
    }
  }
  const lenMM = bMax[0] - bMin[0];
  const K = FLY_BODY_LEN / lenMM;

  // —— v7.2 关节链站姿（FK）：零位六腿垂直下挂 → 真果蝇三角站姿 ——
  // 每节段给一个目标朝向，用最短弧旋转 quatBetween(零位方向→目标) 得到各关节的
  // 世界旋转，再把旋转烘进节段顶点（枢轴保持零旋转）。烘顶点而非让枢轴带基准旋转：
  // ① 贴地基准必须在摆姿后重算，果蝇才能真的站在地面上；
  // ② 运行时基准 = 模型静止姿态，动画偏移直接叠加，不依赖读取引擎里的模型四元数。
  const v3sub = (a, b) => [a[0] - b[0], a[1] - b[1], a[2] - b[2]];
  const v3add = (a, b) => [a[0] + b[0], a[1] + b[1], a[2] + b[2]];
  const v3norm = (v) => { const l = Math.hypot(v[0], v[1], v[2]) || 1; return [v[0] / l, v[1] / l, v[2] / l]; };
  const qApply3 = (q, v) => { const r = quatApply(q, { x: v[0], y: v[1], z: v[2] }); return [r.x, r.y, r.z]; };
  const quatConj = (q) => ({ x: -q.x, y: -q.y, z: -q.z, w: q.w });
  // 注意：quatBetween 返回的是未归一化四元数（既有 makeTube 管线依赖其现状，勿改），
  // 而 quatApply 的旋转公式只对单位四元数成立 —— 必须先归一化，否则方向会被带偏
  const quatNorm = (q) => { const l = Math.hypot(q.x, q.y, q.z, q.w) || 1; return { x: q.x / l, y: q.y / l, z: q.z / l, w: q.w / l }; };
  // 目标朝向（左腿；[基节, 股节, 胫节, 跗节]；场景系 x 右 / y 上 / z 前，
  // x 分量为负 = 向体侧外张）：前腿前伸、中腿外张、后腿后蹬、胫节陡下、跗节近地
  const STANCE_DIRS = {
    F: [[-0.22, -0.91, 0.36], [-0.28, -0.75, 0.60], [-0.22, -0.92, -0.32], [-0.18, -0.25, 0.95]],
    M: [[-0.45, -0.87, 0.20], [-0.62, -0.74, -0.10], [-0.30, -0.93, 0.05], [-0.93, -0.18, 0.10]],
    H: [[-0.25, -0.92, -0.30], [-0.35, -0.80, -0.49], [-0.22, -0.96, 0.17], [-0.60, -0.15, -0.79]],
  };
  const STANCE_JOINTS = {};   // 'LF' → 摆姿后 4 关节（世界毫米），供建节点树用
  const STANCE_TIPS = {};     // 'LF' → 摆姿后脚尖（世界毫米），供日志/自检
  for (const sd of ['L', 'R']) {
    const mir = sd === 'R';
    for (const pair of ['F', 'M', 'H']) {
      // STANCE_DIRS 是场景系（x 右 / y 上 / z 前），FK 在 NMF 世界系（x 前 / y 左 / z 上）
      // 里做 —— 换算：世界 = [场景z(前), -场景x(右→左), 场景y(上)]；右腿先镜像场景 x
      const targets = STANCE_DIRS[pair].map((d) => {
        const s = mir ? [-d[0], d[1], d[2]] : d;
        return v3norm([s[2], -s[0], s[1]]);
      });
      const J = [`${sd}${pair}Coxa`, `${sd}${pair}Femur`, `${sd}${pair}Tibia`, `${sd}${pair}Tarsus1`]
        .map((n) => nmfLinks.get(n).p);
      // 零位方向：相邻关节连线；跗节取 5 节跗骨网格里离跗节关节最远的顶点当脚尖
      const tip = (() => {
        let best = J[3], bd = -1;
        for (let t = 1; t <= 5; t++) {
          const v = assembled.get(`${sd}${pair}Tarsus${t}`);
          for (let i = 0; i < v.length; i += 3) {
            const d = (v[i] - J[3][0]) ** 2 + (v[i + 1] - J[3][1]) ** 2 + (v[i + 2] - J[3][2]) ** 2;
            if (d > bd) { bd = d; best = [v[i], v[i + 1], v[i + 2]]; }
          }
        }
        return best;
      })();
      const zero = [v3norm(v3sub(J[1], J[0])), v3norm(v3sub(J[2], J[1])),
        v3norm(v3sub(J[3], J[2])), v3norm(v3sub(tip, J[3]))];
      const qW = zero.map((z, k) => quatNorm(quatBetween(z, targets[k])));
      // 前向运动学：逐节摆出关节新位置（第 k 关节绕第 k-1 关节转 qW[k-1]）
      const Jp = [J[0]];
      for (let k = 1; k < 4; k++) Jp.push(v3add(Jp[k - 1], qApply3(qW[k - 1], v3sub(J[k], J[k - 1]))));
      const bakeSeg = (name, k) => {
        const v = assembled.get(name);
        for (let i = 0; i < v.length; i += 3) {
          const p = v3add(Jp[k], qApply3(qW[k], v3sub([v[i], v[i + 1], v[i + 2]], J[k])));
          v[i] = p[0]; v[i + 1] = p[1]; v[i + 2] = p[2];
        }
      };
      bakeSeg(`${sd}${pair}Coxa`, 0); bakeSeg(`${sd}${pair}Femur`, 1); bakeSeg(`${sd}${pair}Tibia`, 2);
      for (let t = 1; t <= 5; t++) bakeSeg(`${sd}${pair}Tarsus${t}`, 3);
      // 自校验：摆姿后前三个节段方向必须命中目标（跗节方向由 qW 定义，天然命中）
      for (let k = 0; k < 3; k++) {
        const d = v3norm(v3sub(Jp[k + 1], Jp[k]));
        const dot = d[0] * targets[k][0] + d[1] * targets[k][1] + d[2] * targets[k][2];
        if (dot < 0.999) throw new Error(`${sd}${pair} 第${k}节摆姿未命中目标 (dot=${dot.toFixed(4)})`);
      }
      STANCE_JOINTS[`${sd}${pair}`] = Jp;
      STANCE_TIPS[`${sd}${pair}`] = v3add(Jp[3], qApply3(qW[3], v3sub(tip, J[3])));
    }
  }
  // 摆姿后重算全包络：贴地（nMin[2]）与前后居中（xMid）必须来自摆姿后的真实包围盒，
  // 否则按零位垂腿算出的地面会让摆姿后的果蝇悬空
  const nMin = [1e9, 1e9, 1e9], nMax = [-1e9, -1e9, -1e9];
  for (const v of assembled.values()) {
    for (let i = 0; i < v.length; i += 3) {
      if (v[i] < nMin[0]) nMin[0] = v[i]; if (v[i] > nMax[0]) nMax[0] = v[i];
      if (v[i + 1] < nMin[1]) nMin[1] = v[i + 1]; if (v[i + 1] > nMax[1]) nMax[1] = v[i + 1];
      if (v[i + 2] < nMin[2]) nMin[2] = v[i + 2]; if (v[i + 2] > nMax[2]) nMax[2] = v[i + 2];
    }
  }
  for (const [k, tip] of Object.entries(STANCE_TIPS)) {
    console.log(`stance ${k}: coxaY=${(STANCE_JOINTS[k][0][2] - nMin[2]).toFixed(2)}mm ` +
      `footY=${(tip[2] - nMin[2]).toFixed(2)}mm tip=[${tip.map((v) => v.toFixed(2))}]`);
  }
  const xMid = (nMin[0] + nMax[0]) / 2;
  // 世界毫米 → 场景：右 = -y、上 = z-hGround、前 = x-xMid，整体缩放 K
  const T = (x, y, z) => [-y * K, (z - nMin[2]) * K, (x - xMid) * K];
  const partScene = (name) => {
    const v = assembled.get(name);
    const out = new Float32Array(v.length);
    for (let i = 0; i < v.length; i += 3) {
      const p = T(v[i], v[i + 1], v[i + 2]);
      out[i] = p[0]; out[i + 1] = p[1]; out[i + 2] = p[2];
    }
    return nmfGeometry(out);
  };
  const mergeParts = (names) => mergeGeometryList(names.map(partScene));

  // —— 网格库（全部果蝇共享）——
  const FM = {};
  FM.thorax = addMesh(partScene('Thorax'), MAT_THORAX);
  // 腹部 5 段：浅黄底板与深色节带交替（真果蝇腹部花纹）
  const abdSpec = [['A1A2', MAT_ABDOMEN_LIGHT], ['A3', MAT_ABDOMEN_BAND], ['A4', MAT_ABDOMEN_LIGHT],
    ['A5', MAT_ABDOMEN_BAND], ['A6', MAT_ABDOMEN]];
  FM.abd = abdSpec.map(([n, m]) => addMesh(partScene(n), m));
  FM.head = addMesh(partScene('Head'), MAT_HEAD);
  FM.eyeL = addMesh(partScene('LEye'), MAT_EYE);
  FM.eyeR = addMesh(partScene('REye'), MAT_EYE);
  FM.antL = addMesh(partScene('LAntenna'), MAT_LEG);
  FM.antR = addMesh(partScene('RAntenna'), MAT_LEG);
  FM.mouth = addMesh(mergeParts(['Haustellum', 'Rostrum']), MAT_LEG);   // 口器（喙 + 唇瓣）
  FM.halteres = addMesh(mergeParts(['LHaltere', 'RHaltere']), MAT_HEAD);
  FM.wingL = addMesh(partScene('LWing'), MAT_WING);
  FM.wingR = addMesh(partScene('RWing'), MAT_WING);
  // 腿：四节段各自成网格（基节/股节/胫节 + 5 节跗骨合并），共享给 6 只果蝇。
  // 顶点已经是摆姿后的世界坐标（上方关节链 FK 烘焙），运行时枢轴零旋转 = 基准站姿。
  FM.legs = {};
  for (const sd of ['L', 'R']) {
    for (const pair of ['F', 'M', 'H']) {
      FM.legs[`${sd}${pair}`] = {
        coxa: addMesh(partScene(`${sd}${pair}Coxa`), MAT_LEG),
        femur: addMesh(partScene(`${sd}${pair}Femur`), MAT_LEG),
        tibia: addMesh(partScene(`${sd}${pair}Tibia`), MAT_LEG),
        tarsus: addMesh(mergeParts([1, 2, 3, 4, 5].map((t) => `${sd}${pair}Tarsus${t}`)), MAT_LEG),
      };
    }
  }

  // —— 枢轴（SDF link 原点 → 场景坐标）——
  const nm = (n) => nmfLinks.get(n).p;
  const WING_L_PIVOT = T(nm('LWing')[0], nm('LWing')[1], nm('LWing')[2]);
  const WING_R_PIVOT = T(nm('RWing')[0], nm('RWing')[1], nm('RWing')[2]);
  const HEAD_PIVOT = T(nm('Head')[0], nm('Head')[1], nm('Head')[2]);

  // —— 按后缀构建节点树（s ∈ 0..5）；装配网格是世界坐标，挂在枢轴下的部件
  //    平移取 -pivot（使最终位置回到装配位）——
  const buildFly = (s) => {
    const c = [];
    c.push(addNode({ name: `thorax_${s}`, mesh: FM.thorax }));
    for (let i = 0; i < FM.abd.length; i++) {
      c.push(addNode({ name: `abdomen_${i}_${s}`, mesh: FM.abd[i] }));
    }
    c.push(addNode({ name: `halteres_${s}`, mesh: FM.halteres }));
    // 六条腿：基节/股节/胫节/跗节四级枢轴关节链（v7.2）。基准站姿已烘进网格
    //（枢轴零旋转），运行时在枢轴上叠加相对旋转实现三角步态/飞行收腿/死亡蜷腿
    //（FlyRenderer.applyLegs）。网格顶点存的是摆姿后世界坐标，
    // 所以每个网格的平移补偿 = 其枢轴的绝对位置取负。
    const neg = (p) => [-p[0], -p[1], -p[2]];
    const rel = (a, b) => [a[0] - b[0], a[1] - b[1], a[2] - b[2]];
    const legDefs = [
      ['fl', 'LF'], ['fr', 'RF'], ['ml', 'LM'], ['mr', 'RM'], ['hl', 'LH'], ['hr', 'RH'],
    ];
    for (const [sn, key] of legDefs) {
      const seg = FM.legs[key];
      const J = STANCE_JOINTS[key].map((p) => T(p[0], p[1], p[2]));   // 摆姿后枢轴（场景系）
      const tarsusPivot = addNode({
        name: `leg_${sn}_tarsus_pivot_${s}`, translation: rel(J[3], J[2]),
        children: [addNode({ name: `leg_${sn}_tarsus_${s}`, mesh: seg.tarsus, translation: neg(J[3]) })],
      });
      const tibiaPivot = addNode({
        name: `leg_${sn}_tibia_pivot_${s}`, translation: rel(J[2], J[1]),
        children: [addNode({ name: `leg_${sn}_tibia_${s}`, mesh: seg.tibia, translation: neg(J[2]) }), tarsusPivot],
      });
      const femurPivot = addNode({
        name: `leg_${sn}_femur_pivot_${s}`, translation: rel(J[1], J[0]),
        children: [addNode({ name: `leg_${sn}_femur_${s}`, mesh: seg.femur, translation: neg(J[1]) }), tibiaPivot],
      });
      c.push(addNode({
        name: `leg_${sn}_pivot_${s}`, translation: J[0],
        children: [addNode({ name: `leg_${sn}_coxa_${s}`, mesh: seg.coxa, translation: neg(J[0]) }), femurPivot],
      }));
    }

    const headChildren = [];
    headChildren.push(addNode({ name: `head_${s}`, mesh: FM.head, translation: neg(HEAD_PIVOT) }));
    headChildren.push(addNode({ name: `eye_left_${s}`, mesh: FM.eyeL, translation: neg(HEAD_PIVOT) }));
    headChildren.push(addNode({ name: `eye_right_${s}`, mesh: FM.eyeR, translation: neg(HEAD_PIVOT) }));
    headChildren.push(addNode({ name: `antenna_left_${s}`, mesh: FM.antL, translation: neg(HEAD_PIVOT) }));
    headChildren.push(addNode({ name: `antenna_right_${s}`, mesh: FM.antR, translation: neg(HEAD_PIVOT) }));
    const mp = T(nm('Rostrum')[0], nm('Rostrum')[1], nm('Rostrum')[2]);
    headChildren.push(addNode({
      name: `mouth_pivot_${s}`, translation: [mp[0] - HEAD_PIVOT[0], mp[1] - HEAD_PIVOT[1], mp[2] - HEAD_PIVOT[2]],
      children: [addNode({ name: `proboscis_${s}`, mesh: FM.mouth, translation: neg(mp) })],
    }));
    c.push(addNode({ name: `head_pivot_${s}`, translation: HEAD_PIVOT, children: headChildren }));

    const wingLBlade = addNode({ name: `wing_blade_l_${s}`, mesh: FM.wingL, translation: neg(WING_L_PIVOT) });
    const wingRBlade = addNode({ name: `wing_blade_r_${s}`, mesh: FM.wingR, translation: neg(WING_R_PIVOT) });
    c.push(addNode({ name: `wing_left_${s}`, translation: WING_L_PIVOT, children: [wingLBlade] }));
    c.push(addNode({ name: `wing_right_${s}`, translation: WING_R_PIVOT, children: [wingRBlade] }));

    return addNode({ name: `fly_${s}`, children: c }, true);
  };
  for (let s = 0; s < 6; s++) {
    buildFly(s);
  }
  console.log(`NMF fly: bodyLenMM=${lenMM.toFixed(2)} K=${K.toFixed(4)} parts=${stlFiles.length} stance=FK关节链(基/股/胫/跗)` +
    `headPivot=[${HEAD_PIVOT.map((v) => v.toFixed(3))}] wingL=[${WING_L_PIVOT.map((v) => v.toFixed(3))}]`);
}

// ==== 9) 食物 ×5 与聚光光斑（初始藏到地下 y=-10，运行时激活） ====
{
  const foodMesh = addMesh(makeEllipsoid(0.07, 0.07, 0.07, 0, 0, 0, 8, 12), MAT_FOOD);
  for (let i = 0; i < 5; i++) {
    addNode({ name: `food_${i}`, mesh: foodMesh, translation: [0, -10, 0] }, true);
  }
  const spotMesh = addMesh(makeDisc(0.82, 48), MAT_SPOT);
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
// v4：JSON 数值收敛——变换/颜色按 1e-4~1e-6 精度取整，肉眼无差别但 JSON 明显变小
const r4 = (x) => Math.round(x * 1e4) / 1e4;
const r6 = (x) => Math.round(x * 1e6) / 1e6;
for (const mesh of meshes) {
  const g = mesh.geometry;
  const posArr = new Float32Array(g.positions);
  const norArr = new Float32Array(g.normals);
  const idxArr = g.vertCount() > 65535 ? new Uint32Array(g.indices) : new Uint16Array(g.indices);
  // 索引必须全部有限且落在顶点范围内：合并/烘焙类代码若把索引写坏
  // （如 NaN、越界），在这里当场爆掉，而不是等真机上渲染成垃圾
  for (let i = 0; i < g.indices.length; i++) {
    const v = g.indices[i];
    if (!Number.isFinite(v) || v < 0 || v >= g.vertCount()) {
      throw new Error(`mesh[${meshes.indexOf(mesh)}] 索引[${i}]=${v} 非法（顶点数 ${g.vertCount()}）`);
    }
  }
  let minX = 1e9, minY = 1e9, minZ = 1e9, maxX = -1e9, maxY = -1e9, maxZ = -1e9;
  for (let i = 0; i < posArr.length; i += 3) {
    minX = Math.min(minX, posArr[i]); maxX = Math.max(maxX, posArr[i]);
    minY = Math.min(minY, posArr[i + 1]); maxY = Math.max(maxY, posArr[i + 1]);
    minZ = Math.min(minZ, posArr[i + 2]); maxZ = Math.max(maxZ, posArr[i + 2]);
  }
  const posAcc = addAccessor(posArr, 'VEC3', 5126, posArr.length / 3, 34962,
    { min: [r4(minX), r4(minY), r4(minZ)], max: [r4(maxX), r4(maxY), r4(maxZ)] });
  const norAcc = addAccessor(norArr, 'VEC3', 5126, norArr.length / 3, 34962);
  const idxAcc = addAccessor(idxArr, 'SCALAR', idxArr instanceof Uint32Array ? 5125 : 5123, idxArr.length, 34963);
  gltfMeshes.push({ primitives: [{ attributes: { POSITION: posAcc, NORMAL: norAcc }, indices: idxAcc, material: mesh.material }] });
}

for (const node of nodes) {
  const n = { name: node.name };
  if (node.mesh !== undefined) n.mesh = node.mesh;
  if (node.children) n.children = node.children;
  if (node.translation) n.translation = node.translation.map(r4);
  if (node.rotation) n.rotation = [node.rotation.x, node.rotation.y, node.rotation.z, node.rotation.w].map(r6);
  if (node.scale) n.scale = node.scale.map(r4);
  gltfNodes.push(n);
}

const buffer = Buffer.concat(bufferParts);
const gltf = {
  asset: { version: '2.0', generator: 'guoying gen_world_glb.mjs v4 (asset-import + slim)' },
  scene: 0,
  scenes: [{ name: 'world', nodes: topNodes }],
  nodes: gltfNodes,
  meshes: gltfMeshes,
  materials: materials.map((m) => ({
    name: m.name,
    pbrMetallicRoughness: {
      baseColorFactor: m.baseColor.map(r4), metallicFactor: 0.0, roughnessFactor: r4(m.roughness),
    },
    ...(m.emissive ? { emissiveFactor: m.emissive.map(r4) } : {}),
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
  'stone_0', 'stone_13',
  // 石块碰撞标记（无网格：translation=圆心、scale.x=阻挡半径，供行为层防穿模）
  // 0..13 场内石块(14) / 14..29 河岸卵石(16) / 30..32 树干(3，只算贴地树干，不含枝条与树冠)
  'blocker_0', 'blocker_13', 'blocker_29', 'blocker_32',
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
  // 果蝇 ×6（NeuroMechFly 高精度重建；运行时按名字查找 fly_i / wing / head_pivot）
  'fly_0', 'fly_1', 'fly_2', 'fly_3', 'fly_4', 'fly_5',
  'thorax_0', 'head_pivot_0', 'head_0', 'eye_left_0', 'eye_right_0',
  'antenna_left_0', 'antenna_right_0', 'proboscis_0', 'mouth_pivot_0',
  'head_pivot_5', 'wing_left_5', 'wing_right_5', 'wing_left_0', 'wing_right_0',
  // 腿关节链（v7.2）：基节/股节/胫节/跗节四级枢轴 + 节段网格，抽 4 条腿点名
  'leg_fl_pivot_0', 'leg_fl_femur_pivot_0', 'leg_fl_tibia_pivot_0', 'leg_fl_tarsus_pivot_0',
  'leg_fl_coxa_0', 'leg_mr_tibia_pivot_3', 'leg_hr_tarsus_pivot_5', 'leg_ml_femur_2',
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

// 7.4) 石块铺位自检（尺度放大后最容易出的错：石块压到河里/树根上/青蛙出生点上）
for (const sp of STONE_POS) {
  const sx = sp[0], sz = sp[1];
  const r = Math.hypot(sx, sz);
  const a = Math.atan2(sz, sx);
  if (r > ARENA_R - 1.0) throw new Error(`石块(${sx},${sz}) 超出草地边缘 r=${r.toFixed(2)}`);
  if (riverDist(sx, sz) < RIVER_HALF + 0.35) {
    throw new Error(`石块(${sx},${sz}) 落在蜿蜒河道内（dist=${riverDist(sx, sz).toFixed(2)}）`);
  }
  for (const t of TREE_SPECS) {
    if (Math.hypot(t.x - sx, t.z - sz) < 1.2) throw new Error(`石块(${sx},${sz}) 压住树根`);
  }
  if (Math.hypot(FROG_R * Math.cos(FROG_A) - sx, FROG_R * Math.sin(FROG_A) - sz) < 1.2) {
    throw new Error(`石块(${sx},${sz}) 压住青蛙出生点`);
  }
}

// 7.5) 碰撞标记节点数量（运行时按 blocker_0..N-1 连续收集，跳号会导致后面的全部失效）：
// 石块 14 + 河岸卵石 16 + 树干 3 = 33 —— 改了场景元素要同步这里与 REQUIRED 清单
const BLOCKER_EXPECT = { stones: 14, pebbles: 16, trees: 3 };
const blockerExpect = BLOCKER_EXPECT.stones + BLOCKER_EXPECT.pebbles + BLOCKER_EXPECT.trees;
if (blockerCount !== blockerExpect) {
  throw new Error(`blocker 数量 ${blockerCount} ≠ ${blockerExpect}` +
    `（石块 ${BLOCKER_EXPECT.stones} + 卵石 ${BLOCKER_EXPECT.pebbles} + 树干 ${BLOCKER_EXPECT.trees}）`);
}

// 8) 三角面数：上下限都要卡（只卡上限会漏掉"几何整体缺失"这种事故）
let triTotal = 0;
for (const m of check.meshes) {
  triTotal += check.accessors[m.primitives[0].indices].count / 3;
}
// v7（NeuroMechFly 高精度果蝇）：部件 33.4 万三角面（6 只共享网格），预算上调到 42 万
const TRI_MIN = 8000, TRI_MAX = 420000;
if (triTotal < TRI_MIN) {
  throw new Error(`三角面 ${triTotal} 低于下限 ${TRI_MIN}，可能有 mesh 缺少几何`);
}
if (triTotal > TRI_MAX) {
  throw new Error(`三角面 ${triTotal} 超出预算 ${TRI_MAX}`);
}

console.log(`world.glb OK: ${glb.length} bytes, meshes=${check.meshes.length}, nodes=${check.nodes.length}, ` +
  `materials=${check.materials.length}, topNodes=${topNodes.length}, triangles=${triTotal}`);
for (const line of ASSET_STATS) console.log('  ' + line);
console.log('out:', OUT_FILE);
