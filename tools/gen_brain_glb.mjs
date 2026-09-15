// M2：FlyWire 真实连接组坐标 → 3D 大脑点云 glb 生成脚本（零依赖 Node >= 18）
// 输入：tools/data/coordinates.csv（已解压）、tools/data/classification.csv（已解压）
// 输出：entry/src/main/resources/rawfile/gltf/brain.glb
// 结构：按 super_class 分 5 组（optic/sensory/central/motor/endocrine），
//       每个神经元一个小三角形，同组共享材质（自发光），节点可独立显隐。
// 运行：node tools/gen_brain_glb.mjs
//
// v2 修正（都是真机/解析验证出来的问题）：
//   1. emissiveFactor 原来被写进了 pbrMetallicRoughness 内部 —— 按 glTF 规范它属于
//      material 顶层，放错位置会被引擎直接忽略，"自发光"从来没生效过；
//   2. 原来所有三角形的法线都写死 (0,1,0)，配合平行光会让背光的一半神经元发黑。
//      现在每个神经元的小三角**朝向背离脑中心**（法线取径向），点云读起来才有体积感；
//   3. 顺带按位置做轻微尺寸/朝向扰动，避免"整齐的方阵"观感。
import { writeFileSync, readFileSync, mkdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const DIR = join(dirname(fileURLToPath(import.meta.url)), 'data');
const OUT_FILE = join(dirname(fileURLToPath(import.meta.url)),
  '..', 'entry', 'src', 'main', 'resources', 'rawfile', 'gltf', 'brain.glb');

// ---------- 读分类 ----------
console.log('reading classification...');
const clsLines = readFileSync(join(DIR, 'classification.csv'), 'utf8').split('\n');
const groupOf = new Map(); // root_id -> group index
const GROUPS = ['optic', 'sensory', 'central', 'motor', 'endocrine'];
let unknown = 0;
for (let i = 1; i < clsLines.length; i++) {
  const line = clsLines[i].trim();
  if (!line) continue;
  const c1 = line.indexOf(',');
  const c2 = line.indexOf(',', c1 + 1);
  const c3 = line.indexOf(',', c2 + 1);
  if (c1 < 0 || c2 < 0 || c3 < 0) continue;
  const id = line.slice(0, c1);
  const superClass = line.slice(c2 + 1, c3).trim();
  let g = GROUPS.indexOf(superClass);
  if (g < 0) {
    g = 2; // 未知归类为 central
    unknown++;
  }
  groupOf.set(id, g);
}
console.log(`classified neurons: ${groupOf.size}, unknown->central: ${unknown}`);

// ---------- 读坐标（每个 root_id 取第一行）----------
console.log('reading coordinates...');
const coordLines = readFileSync(join(DIR, 'coordinates.csv'), 'utf8').split('\n');
const posOf = new Map(); // root_id -> [x,y,z]
for (let i = 1; i < coordLines.length; i++) {
  const line = coordLines[i].trim();
  if (!line) continue;
  const c1 = line.indexOf(',');
  const id = line.slice(0, c1);
  if (posOf.has(id)) continue;
  const b1 = line.indexOf('[', c1);
  const b2 = line.indexOf(']', c1);
  if (b1 < 0 || b2 < 0) continue;
  const nums = line.slice(b1 + 1, b2).trim().split(/\s+/);
  if (nums.length !== 3) continue;
  posOf.set(id, [Number(nums[0]), Number(nums[1]), Number(nums[2])]);
}
console.log(`coordinate neurons: ${posOf.size}`);

// ---------- 合并 + 归一化 ----------
const byGroup = GROUPS.map(() => []); // each: [x,y,z]
let minX = 1e15, minY = 1e15, minZ = 1e15, maxX = -1e15, maxY = -1e15, maxZ = -1e15;
for (const [id, g] of groupOf) {
  const p = posOf.get(id);
  if (!p) continue;
  byGroup[g].push(p);
  if (p[0] < minX) minX = p[0]; if (p[0] > maxX) maxX = p[0];
  if (p[1] < minY) minY = p[1]; if (p[1] > maxY) maxY = p[1];
  if (p[2] < minZ) minZ = p[2]; if (p[2] > maxZ) maxZ = p[2];
}
const cx = (minX + maxX) / 2, cy = (minY + maxY) / 2, cz = (minZ + maxZ) / 2;
const half = Math.max(maxX - minX, maxY - minY, maxZ - minZ) / 2;
console.log(`bbox half=${half.toFixed(0)} center=(${cx.toFixed(0)},${cy.toFixed(0)},${cz.toFixed(0)})`);
byGroup.forEach((arr, g) => console.log(`group ${GROUPS[g]}: ${arr.length} neurons`));

// FAFB 体素坐标 → 场景：目标半径 ~1.6，保持真实比例，dorsal(大y) 朝上
const S = 1.6 / half;

// ---------- 小工具 ----------
const DEG = Math.PI / 180;
function srgb(hex) {
  const f = (c) => { const v = c / 255; return v <= 0.04045 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4); };
  return [f((hex >> 16) & 255), f((hex >> 8) & 255), f((hex & 255)), 1];
}
function cross3(a, b) {
  return [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]];
}
function norm3(a) {
  const L = Math.hypot(a[0], a[1], a[2]);
  return L < 1e-9 ? [0, 1, 0] : [a[0] / L, a[1] / L, a[2] / L];
}
// 确定性伪随机（保证每次生成结果可复现，便于 diff）
function makeRng(seed) {
  let s = seed >>> 0;
  return () => { s = (s * 1664525 + 1013904223) >>> 0; return s / 4294967296; };
}

// ---------- 构建几何 ----------
// 每个神经元一个小三角形：位置在神经元坐标，三角面**垂直于径向**（朝外），
// 三个顶点共享该径向法线 —— 点云因此读起来是"有体积的毛球"而不是"一面平沙"。
class Geometry {
  constructor() { this.positions = []; this.normals = []; this.indices = []; }
}
const meshes = [];
const TRI_SIZE = 0.030;   // 三角形外接半径（场景单位）

for (let g = 0; g < GROUPS.length; g++) {
  const geo = new Geometry();
  const pts = byGroup[g];
  const rng = makeRng(0x9e37 + g * 7919);
  for (let n = 0; n < pts.length; n++) {
    const x = (pts[n][0] - cx) * S;
    const y = (pts[n][1] - cy) * S;
    const z = (pts[n][2] - cz) * S;
    // 径向（背离脑中心）；退化时退回 +Y
    const nrm = norm3([x, y, z]);
    // 在垂直径向的平面内取正交基 u/v
    const up = Math.abs(nrm[1]) > 0.94 ? [1, 0, 0] : [0, 1, 0];
    const u = norm3(cross3(up, nrm));
    const v = norm3(cross3(nrm, u));
    const s = TRI_SIZE * (0.7 + rng() * 0.75);   // 尺寸扰动：避免整齐方阵
    const roll = rng() * Math.PI * 2;            // 面内自转
    const cs = Math.cos(roll), sn = Math.sin(roll);
    const ux = u[0] * cs + v[0] * sn, uy = u[1] * cs + v[1] * sn, uz = u[2] * cs + v[2] * sn;
    const vx = -u[0] * sn + v[0] * cs, vy = -u[1] * sn + v[1] * cs, vz = -u[2] * sn + v[2] * cs;
    // 等边三角形（重心在神经元位置）
    const pts3 = [
      [x + ux * s, y + uy * s, z + uz * s],
      [x - ux * s * 0.5 + vx * s * 0.866, y - uy * s * 0.5 + vy * s * 0.866, z - uz * s * 0.5 + vz * s * 0.866],
      [x - ux * s * 0.5 - vx * s * 0.866, y - uy * s * 0.5 - vy * s * 0.866, z - uz * s * 0.5 - vz * s * 0.866],
    ];
    const b = geo.positions.length / 3;
    for (const p of pts3) {
      geo.positions.push(p[0], p[1], p[2]);
      geo.normals.push(nrm[0], nrm[1], nrm[2]);
    }
    geo.indices.push(b, b + 1, b + 2);
  }
  meshes.push({ geo, group: g });
  console.log(`mesh ${GROUPS[g]}: verts=${geo.positions.length / 3}`);
}

// ---------- GLB 序列化 ----------
function floatArr(a) { return new Float32Array(a); }
function indexArr(a, big) { return big ? new Uint32Array(a) : new Uint16Array(a); }

const accessors = [], bufferViews = [], bufferParts = [];
let bufferOffset = 0;
const pad4 = (n) => (4 - (n % 4)) % 4;

function pushView(typedArr, target) {
  const padding = pad4(bufferOffset);
  if (padding) bufferParts.push(Buffer.alloc(padding));
  bufferOffset += padding;
  let total = 0;
  for (const p of bufferParts) total += p.length;
  bufferParts.push(Buffer.from(typedArr.buffer, typedArr.byteOffset, typedArr.byteLength));
  bufferViews.push({ buffer: 0, byteOffset: total, byteLength: typedArr.byteLength, target });
  bufferOffset = total + typedArr.byteLength;
  return bufferViews.length - 1;
}
function addAccessor(arr, type, comp, target, minMax) {
  const view = pushView(arr, target);
  const acc = { bufferView: view, componentType: comp, count: arr.length / (type === 'VEC3' ? 3 : 1), type };
  if (minMax) { acc.min = minMax.min; acc.max = minMax.max; }
  accessors.push(acc);
  return accessors.length - 1;
}

const gltfMeshes = [];
for (const m of meshes) {
  const pos = floatArr(m.geo.positions);
  const nor = floatArr(m.geo.normals);
  let mn = [1e9, 1e9, 1e9], mx = [-1e9, -1e9, -1e9];
  for (let i = 0; i < pos.length; i += 3) {
    for (let k = 0; k < 3; k++) {
      if (pos[i + k] < mn[k]) mn[k] = pos[i + k];
      if (pos[i + k] > mx[k]) mx[k] = pos[i + k];
    }
  }
  const big = pos.length / 3 > 65535;
  const idx = indexArr(m.geo.indices, big);
  const posAcc = addAccessor(pos, 'VEC3', 5126, 34962, { min: mn, max: mx });
  const norAcc = addAccessor(nor, 'VEC3', 5126, 34962);
  const idxAcc = addAccessor(idx, 'SCALAR', big ? 5125 : 5123, 34963);
  gltfMeshes.push({
    primitives: [{ attributes: { POSITION: posAcc, NORMAL: norAcc }, indices: idxAcc, material: m.group }],
  });
}

// 材质：emissiveFactor 必须在 material 顶层（曾经错放进 pbrMetallicRoughness 而被忽略）。
// 同时保留 baseColor，这样即使某些引擎弱化 emissive，靠平行光也还能看清。
const materials = [
  { name: 'optic', base: srgb(0x33bbff), emis: [0.20, 0.62, 1.00] },
  { name: 'sensory', base: srgb(0xff7733), emis: [1.00, 0.42, 0.14] },
  { name: 'central', base: srgb(0x9966ff), emis: [0.58, 0.36, 1.00] },
  { name: 'motor', base: srgb(0x44dd88), emis: [0.20, 0.90, 0.48] },
  { name: 'endocrine', base: srgb(0xffdd44), emis: [1.00, 0.88, 0.24] },
];

const gltfNodes = gltfMeshes.map((m, i) => ({ name: `brain_${GROUPS[i]}`, mesh: i }));
const buffer = Buffer.concat(bufferParts);
const gltf = {
  asset: { version: '2.0', generator: 'guoying gen_brain_glb.mjs v2 (data: FlyWire FAFB v783)' },
  scene: 0,
  scenes: [{ name: 'brain', nodes: gltfNodes.map((_, i) => i) }],
  nodes: gltfNodes,
  meshes: gltfMeshes,
  materials: materials.map((m) => ({
    name: m.name,
    doubleSided: true,
    emissiveFactor: m.emis,                                  // ← 顶层，不是 pbrMetallicRoughness 内
    pbrMetallicRoughness: { baseColorFactor: m.base, metallicFactor: 0, roughnessFactor: 0.85 },
  })),
  accessors,
  bufferViews,
  buffers: [{ byteLength: buffer.length }],
};

const padB = (b, byte) => { const p = pad4(b.length); return p ? Buffer.concat([b, Buffer.alloc(p, byte)]) : b; };
const jsonChunk = padB(Buffer.from(JSON.stringify(gltf), 'utf8'), 0x20);
const binChunk = padB(buffer, 0x00);
const total = 12 + 8 + jsonChunk.length + 8 + binChunk.length;
const header = Buffer.alloc(12);
header.writeUInt32LE(0x46546C67, 0); header.writeUInt32LE(2, 4); header.writeUInt32LE(total, 8);
const jh = Buffer.alloc(8); jh.writeUInt32LE(jsonChunk.length, 0); jh.writeUInt32LE(0x4E4F534A, 4);
const bh = Buffer.alloc(8); bh.writeUInt32LE(binChunk.length, 0); bh.writeUInt32LE(0x004E4942, 4);

mkdirSync(dirname(OUT_FILE), { recursive: true });
const glb = Buffer.concat([header, jh, jsonChunk, bh, binChunk]);
writeFileSync(OUT_FILE, glb);

// ---------- 自校验（与 gen_world_glb.mjs 同一套规矩：宁可脚本崩，也不产出残废资源）----------
const check = JSON.parse(jsonChunk.toString('utf8'));
const bufLen = check.buffers[0].byteLength;
for (const a of check.accessors) {
  const v = check.bufferViews[a.bufferView];
  if (v.byteOffset + v.byteLength > bufLen) throw new Error('bufferView overflow');
  if (a.count <= 0) throw new Error('存在 count=0 的 accessor');
}
for (let i = 0; i < check.meshes.length; i++) {
  const prim = check.meshes[i].primitives[0];
  const idxAcc = check.accessors[prim.indices];
  const posAcc = check.accessors[prim.attributes.POSITION];
  const norAcc = check.accessors[prim.attributes.NORMAL];
  if (!idxAcc || idxAcc.count < 3) throw new Error(`mesh[${i}] 索引为空`);
  if (!posAcc || posAcc.count < 3) throw new Error(`mesh[${i}] 顶点不足`);
  if (!norAcc || norAcc.count !== posAcc.count) throw new Error(`mesh[${i}] 法线缺失或数量不符`);
}
for (const m of check.materials) {
  if (!m.emissiveFactor) throw new Error(`材质 ${m.name} 缺 emissiveFactor（检查是否又写进了 pbrMetallicRoughness）`);
  if (!m.doubleSided) throw new Error(`材质 ${m.name} 未开 doubleSided`);
}
const NEURON_TOTAL = byGroup.reduce((a, arr) => a + arr.length, 0);
let triTotal = 0;
for (const m of check.meshes) triTotal += check.accessors[m.primitives[0].indices].count / 3;
if (triTotal !== NEURON_TOTAL) {
  throw new Error(`三角形数 ${triTotal} 与神经元数 ${NEURON_TOTAL} 不一致（应当一神经元一面）`);
}
if (NEURON_TOTAL < 139000) throw new Error(`神经元总数 ${NEURON_TOTAL} 偏低，数据可能没读全`);

console.log(`brain.glb OK: ${total} bytes, groups=${GROUPS.length}, neurons=${NEURON_TOTAL}, triangles=${triTotal}`);
console.log('out:', OUT_FILE);
