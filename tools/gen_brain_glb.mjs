// M2：FlyWire 真实连接组坐标 → 3D 大脑点云 glb 生成脚本（零依赖 Node >= 18）
// 输入：tools/data/coordinates.csv（已解压）、tools/data/classification.csv（已解压）
// 输出：entry/src/main/resources/rawfile/gltf/brain.glb
// 结构：按 super_class 分 5 组（optic/sensory/central/motor/endocrine），
//       每个神经元一个小三角形，同组共享材质（自发光），节点可独立显隐。
// 运行：node tools/gen_brain_glb.mjs
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

// ---------- 构建 glb ----------
class Geometry {
  constructor() { this.positions = []; this.indices = []; }
}
const meshes = [];
const triSize = 0.028; // 三角形边长（场景单位）

for (let g = 0; g < GROUPS.length; g++) {
  const geo = new Geometry();
  const pts = byGroup[g];
  for (let n = 0; n < pts.length; n++) {
    const x = (pts[n][0] - cx) * S;
    const y = (pts[n][1] - cy) * S;
    const z = (pts[n][2] - cz) * S;
    const b = geo.positions.length / 3;
    // 小三角形（三顶点，双面渲染）
    geo.positions.push(x - triSize, y, z, x + triSize, y, z, x, y + triSize * 1.4, z);
    geo.indices.push(b, b + 1, b + 2);
  }
  meshes.push({ geo, group: g });
  console.log(`mesh ${GROUPS[g]}: verts=${geo.positions.length / 3}`);
}

// 法线：所有三角形共用向上法线（双面材质，视觉为自发光小片）
function floatArr(a) { return new Float32Array(a); }
function indexArr(a, big) { return big ? new Uint32Array(a) : new Uint16Array(a); }

const accessors = [], bufferViews = [], bufferParts = [];
let bufferOffset = 0;
const pad4 = (n) => (4 - (n % 4)) % 4;

function pushView(typedArr, target) {
  const padding = pad4(bufferOffset);
  if (padding) bufferParts.push(Buffer.alloc(padding));
  bufferOffset += padding;
  // 重新计算当前总长（含 padding）
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
  const nor = floatArr(new Array(pos.length).fill(0).map((_, i) => (i % 3 === 1 ? 1 : 0)));
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

const materials = [
  { name: 'optic',     base: srgb(0x33bbff), emis: [0.15, 0.62, 1.00] },
  { name: 'sensory',   base: srgb(0xff7733), emis: [1.00, 0.42, 0.10] },
  { name: 'central',   base: srgb(0x9966ff), emis: [0.55, 0.33, 1.00] },
  { name: 'motor',     base: srgb(0x44dd88), emis: [0.15, 0.90, 0.45] },
  { name: 'endocrine', base: srgb(0xffdd44), emis: [1.00, 0.88, 0.20] },
];
function srgb(hex) {
  const f = (c) => { const v = c / 255; return v <= 0.04045 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4); };
  return [f((hex >> 16) & 255), f((hex >> 8) & 255), f(hex & 255), 1];
}

const gltfNodes = gltfMeshes.map((m, i) => ({ name: `brain_${GROUPS[i]}`, mesh: i }));
const buffer = Buffer.concat(bufferParts);
const gltf = {
  asset: { version: '2.0', generator: 'guoying gen_brain_glb.mjs (data: FlyWire FAFB v783)' },
  scene: 0,
  scenes: [{ name: 'brain', nodes: gltfNodes.map((_, i) => i) }],
  nodes: gltfNodes,
  meshes: gltfMeshes,
  materials: materials.map((m) => ({
    name: m.name,
    doubleSided: true,
    pbrMetallicRoughness: { baseColorFactor: m.base, metallicFactor: 0, roughnessFactor: 0.9, emissiveFactor: m.emis },
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
writeFileSync(OUT_FILE, Buffer.concat([header, jh, jsonChunk, bh, binChunk]));
console.log(`brain.glb OK: ${total} bytes, groups=${GROUPS.length}, neurons=${byGroup.flat().length}`);
console.log('out:', OUT_FILE);
