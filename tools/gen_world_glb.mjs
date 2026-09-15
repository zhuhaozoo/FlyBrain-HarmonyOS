// 果蝇大脑 Demo —— 场景与果蝇模型生成脚本（零依赖，Node >= 18）
// 生成 entry/src/main/resources/rawfile/gltf/world.glb
// 内容：地面圆盘 + 环形石块 + 果蝇（thorax/abdomen/head/eyes/antennae/legs，
//       以及可运行时驱动的节点 fly / wing_left / wing_right）
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
function srgb2lin(hex) {
  const r = ((hex >> 16) & 255) / 255, g = ((hex >> 8) & 255) / 255, b = (hex & 255) / 255;
  const f = (c) => (c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4));
  return [f(r), f(g), f(b), 1];
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
    // 侧面法线（含锥度补偿的近似）
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
  MAT_EYE = 5, MAT_WING = 6, MAT_LEG = 7, MAT_FOOD = 8, MAT_SPOT = 9;
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
];

// ---------- 组装几何与节点 ----------
const meshes = [];   // {geometry, material}
const nodes = [];    // {name, mesh?, children?, translation?, rotation?, scale?}

function addMesh(geometry, material) {
  meshes.push({ geometry, material });
  return meshes.length - 1;
}
function addNode(node) { nodes.push(node); return nodes.length - 1; }

// 1) 地面：圆盘 r=5.5，顶部 y=0
{
  const g = bakeTransform(makeDisc(5.5, 56), { x: 0, y: 0, z: 0, w: 1 }, [1, 1, 1], [0, 0.001, 0]);
  const m = addMesh(g, MAT_GROUND);
  addNode({ name: 'ground', mesh: m });
}
// 2) 石块：共享一个椭球网格，节点缩放/摆放
{
  const g = makeEllipsoid(0.5, 0.30, 0.42, 0, 0, 0, 10, 14);
  const m = addMesh(g, MAT_STONE);
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
    });
  }
}

// 3) 果蝇（朝 +Z，根节点在地面）
const flyChildren = [];
{
  // 胸（椭球）
  let m = addMesh(makeEllipsoid(0.14, 0.13, 0.20, 0, 0.30, 0.02, 12, 18), MAT_THORAX);
  flyChildren.push(addNode({ name: 'thorax', mesh: m }));
  // 腹（椭球，向后延伸）
  m = addMesh(makeEllipsoid(0.115, 0.105, 0.23, 0, 0.285, -0.30, 12, 18), MAT_ABDOMEN);
  flyChildren.push(addNode({ name: 'abdomen', mesh: m }));
  // 头
  m = addMesh(makeEllipsoid(0.105, 0.105, 0.10, 0, 0.335, 0.245, 10, 16), MAT_HEAD);
  flyChildren.push(addNode({ name: 'head', mesh: m }));
  // 复眼 ×2（共享网格）
  m = addMesh(makeEllipsoid(0.052, 0.062, 0.070, 0, 0, 0, 8, 12), MAT_EYE);
  flyChildren.push(addNode({ name: 'eye_left', mesh: m, translation: [-0.062, 0.36, 0.285] }));
  flyChildren.push(addNode({ name: 'eye_right', mesh: m, translation: [0.062, 0.36, 0.285] }));
  // 触角 ×2（细圆柱，从头顶斜向前外）
  m = addMesh(makeCylinder(0.004, 0.007, 1, 6, true, true), MAT_LEG); // 单位长，靠节点缩放
  const antL = { start: [-0.03, 0.42, 0.30], end: [-0.10, 0.50, 0.42] };
  const antR = { start: [0.03, 0.42, 0.30], end: [0.10, 0.50, 0.42] };
  for (const [i, a] of [[0, antL], [1, antR]]) {
    const dir = [a.end[0] - a.start[0], a.end[1] - a.start[1], a.end[2] - a.start[2]];
    const len = Math.hypot(...dir);
    const q = quatBetween([0, 1, 0], dir);
    flyChildren.push(addNode({
      name: i === 0 ? 'antenna_left' : 'antenna_right', mesh: m,
      translation: [a.start[0], a.start[1], a.start[2]], rotation: [q.x, q.y, q.z, q.w], scale: [1, len, 1],
    }));
  }
  // 腿 ×6（单位长圆柱，节点缩放 + 对齐方向）
  m = addMesh(makeCylinder(0.010, 0.014, 1, 8, true, true), MAT_LEG);
  const legs = [
    // 前对 / 中对 / 后对：[sx(±1), startZ, outX, endZ]
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
const flyNode = addNode({ name: 'fly', children: flyChildren });

// 4) 食物 ×5 与聚光光斑（初始藏到地下 y=-10，运行时激活）
{
  const foodMesh = addMesh(makeEllipsoid(0.07, 0.07, 0.07, 0, 0, 0, 8, 12), MAT_FOOD);
  for (let i = 0; i < 5; i++) {
    addNode({ name: `food_${i}`, mesh: foodMesh, translation: [0, -10, 0] });
  }
  const spotMesh = addMesh(makeDisc(0.55, 40), MAT_SPOT);
  addNode({ name: 'lightspot', mesh: spotMesh, translation: [0, -10, 0] });
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

const gltfMeshes = [], gltfNodes = [], gltfScenesNodes = [];
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
// 顶层节点：ground/stones/fly/food/lightspot
for (let i = 0; i < nodes.length; i++) {
  const nm = nodes[i].name;
  if (nm === 'ground' || nm.startsWith('stone_') || nm === 'fly' ||
    nm.startsWith('food_') || nm === 'lightspot') {
    gltfScenesNodes.push(i);
  }
}

const buffer = Buffer.concat(bufferParts);
const gltf = {
  asset: { version: '2.0', generator: 'guoying gen_world_glb.mjs' },
  scene: 0,
  scenes: [{ name: 'world', nodes: gltfScenesNodes }],
  nodes: gltfNodes,
  meshes: gltfMeshes,
  materials: materials.map((m) => ({
    name: m.name,
    pbrMetallicRoughness: { baseColorFactor: m.baseColor, metallicFactor: 0.0, roughnessFactor: m.roughness },
    ...(m.emissive ? { emissiveFactor: m.emissive } : {}),
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
let tris = 0, verts = 0;
for (const m of check.meshes) { tris += m.primitives[0].indices ? 1 : 0; verts += 1; }
console.log(`world.glb OK: ${glb.length} bytes, meshes=${check.meshes.length}, nodes=${check.nodes.length}, ` +
  `materials=${check.materials.length}, topNodes=${gltfScenesNodes.length}`);
console.log('out:', OUT_FILE);
