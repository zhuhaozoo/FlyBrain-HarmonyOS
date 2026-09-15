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
  MAT_PATH_DOT = 26;
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
];

// ---------- 组装几何与节点 ----------
const meshes = [];   // {geometry, material}
const nodes = [];    // {name, mesh?, children?, translation?, rotation?, scale?}
const topNodes = []; // 顶层节点索引（scene.nodes）

function addMesh(geometry, material) {
  meshes.push({ geometry, material });
  return meshes.length - 1;
}
function addNode(node, top = false) {
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

// ==== 2) 场内石块 ====
{
  const m = addMesh(makeEllipsoid(0.5, 0.30, 0.42, 0, 0, 0, 10, 14), MAT_STONE);
  const stonePos = [
    [2.7, 0.9, 0.75], [3.6, -1.7, 0.95], [-3.1, 1.4, 0.85],
    [-4.1, -1.1, 0.7], [1.3, -3.4, 0.65], [-1.8, 3.3, 0.9],
    [4.4, 2.2, 0.8], [-3.9, 3.8, 0.6],
  ]; // [x, z, scale]
  for (let i = 0; i < stonePos.length; i++) {
    const s = stonePos[i];
    addNode({
      name: `stone_${i}`, mesh: m,
      translation: [s[0], 0.30 * s[2] * 0.55, s[1]], scale: [s[2], s[2] * 1.6, s[2]],
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
  const water = bakeTransform(makeArcBand(RIVER_RIN, RIVER_ROUT, RIVER_A0, RIVER_A1, 30),
    { x: 0, y: 0, z: 0, w: 1 }, [1, 1, 1], [0, 0.012, 0]);
  addNode({ name: 'river', mesh: addMesh(water, MAT_WATER) }, true);

  // 两侧鹅卵石（外白灰椭球，随机缩放）
  const rng = makeRng(0x51ee01);
  const stoneMesh = addMesh(makeEllipsoid(0.16, 0.10, 0.13, 0, 0, 0, 8, 12), MAT_BANK_STONE);
  const bankSpecs = [
    { r: RIVER_RIN - 0.12, n: 8 },
    { r: RIVER_ROUT + 0.12, n: 8 },
  ];
  let k = 0;
  for (const spec of bankSpecs) {
    for (let i = 0; i < spec.n; i++) {
      const t = (i + 0.5) / spec.n;
      const a = RIVER_A0 + (RIVER_A1 - RIVER_A0) * t;
      const jitterR = spec.r + (rng() - 0.5) * 0.18;
      const s = 0.7 + rng() * 0.8;
      addNode({
        name: `river_bank_stone_${k}`, mesh: stoneMesh,
        translation: [jitterR * Math.cos(a), 0.05 * s, jitterR * Math.sin(a)],
        rotation: quatY(rng() * Math.PI * 2),
        scale: [s, s, s],
      }, true);
      k++;
    }
  }
}

// ==== 4) 树木 ×3：tree_i（根）→ trunk（一级摇摆）→ crown（二级摇摆） ====
// 位置在场地边缘外一圈；其中 0 号树挨着河岸。
const TREE_SPECS = [
  { x: 5.0 * Math.cos(14 * DEG), z: 5.0 * Math.sin(14 * DEG), h: 1.30, s: 1.0 },
  { x: 5.6 * Math.cos(150 * DEG), z: 5.6 * Math.sin(150 * DEG), h: 1.10, s: 0.9 },
  { x: 5.3 * Math.cos(250 * DEG), z: 5.3 * Math.sin(250 * DEG), h: 1.22, s: 0.95 },
];
{
  const crownDark = addMesh(makeEllipsoid(0.46, 0.36, 0.46, 0, 0, 0, 12, 16), MAT_CROWN_DARK);
  const crownLight = addMesh(makeEllipsoid(0.34, 0.28, 0.34, 0, 0, 0, 12, 16), MAT_CROWN_LIGHT);
  const fruitMesh = addMesh(makeEllipsoid(0.055, 0.055, 0.055, 0, 0, 0, 8, 10), MAT_FRUIT);
  const rng = makeRng(0x7ee501);

  let fruitIdx = 0;
  for (let ti = 0; ti < TREE_SPECS.length; ti++) {
    const spec = TREE_SPECS[ti];
    // 树干网格按实际高度烘焙 ⇒ 节点无需缩放，子节点（树冠）的位移就是真实米数
    const trunkMesh = addMesh(makeCylinderUp(0.055, 0.095, spec.h, 12), MAT_TRUNK);
    // 树冠：2 深 1 浅错位堆叠
    const crownChildren = [
      addNode({ name: `crown_${ti}_dark_a`, mesh: crownDark, translation: [0, 0.30, 0], scale: [spec.s, spec.s, spec.s] }),
      addNode({ name: `crown_${ti}_dark_b`, mesh: crownDark, translation: [0.22 * spec.s, 0.52, -0.14 * spec.s], scale: [0.82 * spec.s, 0.78 * spec.s, 0.82 * spec.s] }),
      addNode({ name: `crown_${ti}_light`, mesh: crownLight, translation: [-0.18 * spec.s, 0.62, 0.16 * spec.s], scale: [spec.s, spec.s, spec.s] }),
    ];
    // 果实 ×3 挂在树冠表面（兼作食物彩蛋）
    for (let f = 0; f < 3; f++) {
      const a = rng() * Math.PI * 2;
      crownChildren.push(addNode({
        name: `fruit_${fruitIdx}`, mesh: fruitMesh,
        translation: [0.42 * spec.s * Math.cos(a), 0.28 + 0.34 * rng(), 0.42 * spec.s * Math.sin(a)],
      }));
      fruitIdx++;
    }
    // 层级：tree_i（根部）→ trunk（一级摇摆，网格底贴地 ⇒ 绕根部摆）→ crown（二级摇摆）
    const crown = addNode({ name: `crown_${ti}`, translation: [0, spec.h, 0], children: crownChildren });
    const trunk = addNode({ name: `trunk_${ti}`, mesh: trunkMesh, children: [crown] });
    addNode({ name: `tree_${ti}`, translation: [spec.x, 0, spec.z], children: [trunk] }, true);
  }
}

// ==== 5) 太阳 / 月亮枢轴（绕 Z 轴匀速旋转，天然实现东升西落） ====
{
  const sunMesh = addMesh(makeEllipsoid(0.55, 0.55, 0.55, 0, 0, 0, 12, 16), MAT_SUN);
  const moonMesh = addMesh(makeEllipsoid(0.40, 0.40, 0.40, 0, 0, 0, 12, 16), MAT_MOON);
  // 圆盘替身：用小球而非平面圆盘，避免正/背面剔除导致某个角度看不见
  const sun = addNode({ name: 'sun', mesh: sunMesh, translation: [9, 0, 0] });
  addNode({ name: 'sun_pivot', children: [sun] }, true);
  const moon = addNode({ name: 'moon', mesh: moonMesh, translation: [9, 0, 0] });
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

// ==== 7) 青蛙（含可伸缩舌头） ====
// 蹲坐在河流内侧岸边；朝向场地中心（由生成期烘焙的 yaw 承担）
const FROG_R = 4.55, FROG_A = 64 * DEG;
{
  const fx = FROG_R * Math.cos(FROG_A), fz = FROG_R * Math.sin(FROG_A);
  // 朝向原点：本地 +Z 需指向 (fx,fz) 的反方向
  const yaw = Math.atan2(-fx, -fz);
  const qFrog = quatY(yaw);

  const bodyMesh = addMesh(makeEllipsoid(0.34, 0.26, 0.42, 0, 0.26, 0, 12, 16), MAT_FROG_BODY);
  const eyeMesh = addMesh(makeEllipsoid(0.095, 0.105, 0.095, 0, 0, 0, 8, 12), MAT_FROG_EYE);
  const pupilMesh = addMesh(makeEllipsoid(0.045, 0.05, 0.045, 0, 0, 0, 6, 10), MAT_LEG);
  const legMesh = addMesh(makeCylinder(0.045, 0.06, 1, 8, true, true), MAT_FROG_BODY);
  const tongueMesh = addMesh(makeTongueUnit(0.05), MAT_FROG_TONGUE);

  const frogChildren = [];
  frogChildren.push(addNode({ name: 'frog_body', mesh: bodyMesh }));
  // 眼球 + 瞳孔（瞳孔是独立节点，便于"转向果蝇"时只动瞳孔）
  frogChildren.push(addNode({ name: 'frog_eye_l', mesh: eyeMesh, translation: [-0.17, 0.50, 0.16] }));
  frogChildren.push(addNode({ name: 'frog_eye_r', mesh: eyeMesh, translation: [0.17, 0.50, 0.16] }));
  frogChildren.push(addNode({ name: 'frog_pupil_l', mesh: pupilMesh, translation: [-0.20, 0.53, 0.235] }));
  frogChildren.push(addNode({ name: 'frog_pupil_r', mesh: pupilMesh, translation: [0.14, 0.53, 0.235] }));
  // 四条折腿（前二后二）
  const legSpecs = [
    { sx: -1, z: 0.30 }, { sx: 1, z: 0.30 }, { sx: -1, z: -0.26 }, { sx: 1, z: -0.26 },
  ];
  for (let i = 0; i < legSpecs.length; i++) {
    const L = legSpecs[i];
    const start = [L.sx * 0.24, 0.20, L.z];
    const end = [L.sx * 0.40, 0.0, L.z + (L.z > 0 ? 0.12 : -0.10)];
    const dir = [end[0] - start[0], end[1] - start[1], end[2] - start[2]];
    const len = Math.hypot(...dir);
    frogChildren.push(addNode({
      name: `frog_leg_${i}`, mesh: legMesh,
      translation: start, rotation: quatBetween([0, 1, 0], dir), scale: [1, len, 1],
    }));
  }
  // 舌头：挂在与嘴同高的位置，沿本地 +Z 伸缩（base 固定、末端伸出）
  frogChildren.push(addNode({ name: 'frog_tongue', mesh: tongueMesh, translation: [0, 0.26, 0.34] }));

  addNode({ name: 'frog', translation: [fx, 0, fz], rotation: qFrog, children: frogChildren }, true);
}

// ==== 8) 果蝇（朝 +Z，根节点在地面） ====
const flyChildren = [];
// 头部轴心（颈部）：head/复眼/触角都挂在这下面，进食时整体低头
const HEAD_PIVOT = [0, 0.345, 0.19];
{
  let m = addMesh(makeEllipsoid(0.14, 0.13, 0.20, 0, 0.30, 0.02, 12, 18), MAT_THORAX);
  flyChildren.push(addNode({ name: 'thorax', mesh: m }));
  m = addMesh(makeEllipsoid(0.115, 0.105, 0.23, 0, 0.285, -0.30, 12, 18), MAT_ABDOMEN);
  flyChildren.push(addNode({ name: 'abdomen', mesh: m }));

  // —— 头部组（相对 head_pivot 的偏移）——
  const headChildren = [];
  m = addMesh(makeEllipsoid(0.105, 0.105, 0.10, 0, 0.335, 0.245, 10, 16), MAT_HEAD);
  headChildren.push(addNode({ name: 'head', mesh: m, translation: [0, 0.335 - HEAD_PIVOT[1], 0.245 - HEAD_PIVOT[2]] }));
  m = addMesh(makeEllipsoid(0.052, 0.062, 0.070, 0, 0, 0, 8, 12), MAT_EYE);
  headChildren.push(addNode({ name: 'eye_left', mesh: m, translation: [-0.062, 0.36 - HEAD_PIVOT[1], 0.285 - HEAD_PIVOT[2]] }));
  headChildren.push(addNode({ name: 'eye_right', mesh: m, translation: [0.062, 0.36 - HEAD_PIVOT[1], 0.285 - HEAD_PIVOT[2]] }));
  m = addMesh(makeCylinder(0.004, 0.007, 1, 6, true, true), MAT_LEG);
  const antL = { start: [-0.03, 0.42, 0.30], end: [-0.10, 0.50, 0.42] };
  const antR = { start: [0.03, 0.42, 0.30], end: [0.10, 0.50, 0.42] };
  for (const [i, a] of [[0, antL], [1, antR]]) {
    const dir = [a.end[0] - a.start[0], a.end[1] - a.start[1], a.end[2] - a.start[2]];
    const len = Math.hypot(...dir);
    const q = quatBetween([0, 1, 0], dir);
    headChildren.push(addNode({
      name: i === 0 ? 'antenna_left' : 'antenna_right', mesh: m,
      translation: [a.start[0] - HEAD_PIVOT[0], a.start[1] - HEAD_PIVOT[1], a.start[2] - HEAD_PIVOT[2]],
      rotation: [q.x, q.y, q.z, q.w], scale: [1, len, 1],
    }));
  }
  flyChildren.push(addNode({ name: 'head_pivot', translation: HEAD_PIVOT, children: headChildren }));

  // 腿 ×6
  m = addMesh(makeCylinder(0.010, 0.014, 1, 8, true, true), MAT_LEG);
  const legs = [
    { sz: 0.12, ox: 0.15, ez: 0.16 }, { sz: 0.00, ox: 0.19, ez: 0.02 }, { sz: -0.10, ox: 0.15, ez: -0.14 },
  ];
  for (const side of [-1, 1]) {
    for (const L of legs) {
      const start = [side * 0.10, 0.24, L.sz];
      const end = [side * L.ox, 0.0, L.ez];
      const dir = [end[0] - start[0], end[1] - start[1], end[2] - start[2]];
      const len = Math.hypot(...dir);
      const q = quatBetween([0, 1, 0], dir);
      flyChildren.push(addNode({
        name: `leg_${side < 0 ? 'l' : 'r'}_${L.sz}`, mesh: m,
        translation: [start[0], start[1], start[2]], rotation: [q.x, q.y, q.z, q.w], scale: [1, len, 1],
      }));
    }
  }
  // 翅膀：轴心节点（运行时绕 Z 轴摆动）+ 叶片子节点
  const wingMesh = addMesh(bakeTransform(makeBox(0.34, 0.006, 0.115), { x: 0, y: 0, z: 0, w: 1 }, [1, 1, 1], [0, 0, 0]), MAT_WING);
  const wingLBlade = addNode({ name: 'wing_blade_l', mesh: wingMesh, translation: [-0.17, 0, 0] });
  const wingRBlade = addNode({ name: 'wing_blade_r', mesh: wingMesh, translation: [0.17, 0, 0] });
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
const check = JSON.parse(jsonChunk.toString('utf8'));
let bufLen = check.buffers[0].byteLength;
for (const a of check.accessors) {
  const v = check.bufferViews[a.bufferView];
  if (v.byteOffset + v.byteLength > bufLen) throw new Error('bufferView overflow');
}
// 节点树结构打印 + 必备节点名检查（运行时靠 DFS 按名字查找，名字写错会静默失效）
const names = new Set(check.nodes.map((n) => n.name));
const REQUIRED = [
  'ground', 'ground_inner', 'river', 'river_bank_stone_0', 'river_bank_stone_15',
  'tree_0', 'tree_1', 'tree_2', 'trunk_0', 'crown_0', 'fruit_0', 'fruit_8',
  'sun_pivot', 'sun', 'moon_pivot', 'moon', 'stars', 'star_0', 'star_29',
  'frog', 'frog_body', 'frog_tongue', 'frog_eye_l', 'frog_eye_r',
  'fly', 'head_pivot', 'head', 'wing_left', 'wing_right',
  'food_0', 'food_4', 'lightspot',
  'plus_fx_0', 'plus_fx_2', 'wind_line_0', 'wind_line_5', 'ripple_0', 'ripple_2',
  'path_dot_0', 'path_dot_5',
];
const missing = REQUIRED.filter((n) => !names.has(n));
if (missing.length > 0) throw new Error('缺少必备节点: ' + missing.join(', '));

// 节点名必须唯一：运行时靠 DFS 按名字查找，重名会导致取到错误的节点
const seen = new Map();
for (const n of check.nodes) {
  if (seen.has(n.name)) throw new Error(`节点名重复: ${n.name}`);
  seen.set(n.name, true);
}
// 三角形总数（面数预算红线 < 8 万）
let triTotal = 0;
for (const m of check.meshes) {
  const prim = m.primitives[0];
  triTotal += check.accessors[prim.indices].count / 3;
}
const budget = 80000;
if (triTotal > budget) throw new Error(`三角面 ${triTotal} 超出预算 ${budget}`);

console.log(`world.glb OK: ${glb.length} bytes, meshes=${check.meshes.length}, nodes=${check.nodes.length}, ` +
  `materials=${check.materials.length}, topNodes=${topNodes.length}, triangles=${triTotal}`);
console.log('out:', OUT_FILE);
