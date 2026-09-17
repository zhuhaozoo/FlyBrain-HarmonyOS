// 临时预览工具：把 world.glb 的指定子树渲染成线框 PNG（正交投影），肉眼验证几何形状
// 用法：node tools/preview_glb.mjs out.png 800 600 tree_0 tree_1 tree_2
import { readFileSync, writeFileSync } from 'node:fs';
import { deflateSync } from 'node:zlib';

const [, , out, Ws, Hs, ...rest] = process.argv;
const W = +Ws, H = +Hs;
const roots = rest.filter((r) => !['top', 'side'].includes(r));
const buf = readFileSync(new URL('../entry/src/main/resources/rawfile/gltf/world.glb', import.meta.url));
const jl = buf.readUInt32LE(12);
const j = JSON.parse(buf.slice(20, 20 + jl).toString('utf8'));
const binStart = 20 + jl + 8;
const bin = buf.subarray(binStart, binStart + buf.readUInt32LE(binStart - 8));

function acc(idx) {
  const a = j.accessors[idx];
  const bv = j.bufferViews[a.bufferView];
  const s = (bv.byteOffset ?? 0) + (a.byteOffset ?? 0);
  const C = { 5126: Float32Array, 5125: Uint32Array, 5123: Uint16Array }[a.componentType];
  const n = { SCALAR: 1, VEC2: 2, VEC3: 3 }[a.type];
  return new C(bin.buffer, bin.byteOffset + s, a.count * n);
}
// 收集子树的所有三角形（世界坐标，逐节点 TRS 简化为平移*缩放即可满足预览需要）
const tris = [];
function walk(idx, ox, oy, oz, s) {
  const n = j.nodes[idx];
  const tx = ox + (n.translation?.[0] ?? 0) * s, ty = oy + (n.translation?.[1] ?? 0) * s, tz = oz + (n.translation?.[2] ?? 0) * s;
  const ns = s * (n.scale?.[0] ?? 1);
  if (n.mesh !== undefined) {
    for (const p of j.meshes[n.mesh].primitives) {
      const pos = acc(p.attributes.POSITION), ids = acc(p.indices);
      for (let i = 0; i < ids.length; i += 3) {
        const v = [];
        for (const k of [ids[i], ids[i + 1], ids[i + 2]]) {
          v.push([pos[k * 3] * ns + tx, pos[k * 3 + 1] * ns + ty, pos[k * 3 + 2] * ns + tz]);
        }
        tris.push(v);
      }
    }
  }
  for (const c of n.children ?? []) walk(c, tx, ty, tz, ns);
}
const byName = new Map(j.nodes.map((n, i) => [n.name, i]));
for (const r of roots) walk(byName.get(r), 0, 0, 0, 1);

// 包围盒 → 视口
let mn = [1e9, 1e9, 1e9], mx = [-1e9, -1e9, -1e9];
for (const t of tris) for (const v of t) for (let k = 0; k < 3; k++) { mn[k] = Math.min(mn[k], v[k]); mx[k] = Math.max(mx[k], v[k]); }
const cx = (mn[0] + mx[0]) / 2, cy = (mn[1] + mx[1]) / 2, cz = (mn[2] + mx[2]) / 2;
const span = Math.max(mx[0] - mn[0], mx[1] - mn[1], mx[2] - mn[2]) * 1.05;
const S = Math.min(W, H) / span; // 等比缩放，避免非正方形画布把形状拉扁造成误判
const view = rest.includes('top') ? 'top' : 'side';
const P = view === 'top'
  ? (v) => [(v[0] - cx) * S + W / 2, H / 2 + (v[2] - cz) * S] // 俯视：x→右，z→下
  : (v) => [(v[0] - cx) * S + W / 2, H / 2 - (v[1] - cy) * S]; // 侧视：x→右，y→上

// 画线（简单 Bresenham，亮绿色）
const img = new Uint8Array(W * H * 3);
const set = (x, y) => {
  if (x < 0 || y < 0 || x >= W || y >= H) return;
  const i = (y * W + x) * 3;
  img[i] = 120; img[i + 1] = 240; img[i + 2] = 120;
};
function line(x0, y0, x1, y1) {
  x0 |= 0; y0 |= 0; x1 |= 0; y1 |= 0;
  const dx = Math.abs(x1 - x0), dy = Math.abs(y1 - y0);
  const sx = x0 < x1 ? 1 : -1, sy = y0 < y1 ? 1 : -1;
  let err = dx - dy;
  for (;;) {
    set(x0, y0);
    if (x0 === x1 && y0 === y1) break;
    const e2 = 2 * err;
    if (e2 > -dy) { err -= dy; x0 += sx; }
    if (e2 < dx) { err += dx; y0 += sy; }
  }
}
const step = Math.max(1, Math.floor(tris.length / 9000));
for (let i = 0; i < tris.length; i += step) {
  const [a, b, c] = tris[i].map(P);
  line(a[0], a[1], b[0], b[1]); line(b[0], b[1], c[0], c[1]); line(c[0], c[1], a[0], a[1]);
}

// 编码 PNG（无滤波，zlib 压缩）
function crc32(b) {
  let c, table = [];
  for (let n = 0; n < 256; n++) { c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; table[n] = c; }
  let crc = 0xffffffff;
  for (const x of b) crc = table[(crc ^ x) & 255] ^ (crc >>> 8);
  return (crc ^ 0xffffffff) >>> 0;
}
function chunk(type, data) {
  const len = Buffer.alloc(4); len.writeUInt32BE(data.length);
  const td = Buffer.concat([Buffer.from(type), data]);
  const crc = Buffer.alloc(4); crc.writeUInt32BE(crc32(td));
  return Buffer.concat([len, td, crc]);
}
const ihdr = Buffer.alloc(13);
ihdr.writeUInt32BE(W, 0); ihdr.writeUInt32BE(H, 4); ihdr[8] = 8; ihdr[9] = 2;
const raw = Buffer.alloc(H * (1 + W * 3));
for (let y = 0; y < H; y++) {
  raw[y * (1 + W * 3)] = 0;
  Buffer.from(img.buffer, y * W * 3, W * 3).copy(raw, y * (1 + W * 3) + 1);
}
const png = Buffer.concat([
  Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
  chunk('IHDR', ihdr), chunk('IDAT', deflateSync(raw)), chunk('IEND', new Uint8Array(0)),
]);
writeFileSync(out, png);
console.log(`${out}: ${tris.length} tris, bbox span=${span.toFixed(2)}`);
