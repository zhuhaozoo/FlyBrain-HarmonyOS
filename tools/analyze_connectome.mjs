// 连接组二进制分析器（零依赖 Node >= 18，升级迁移文档 §4.7 等价性验证工具）
//
// 用法：node tools/analyze_connectome.mjs [path/to/connectome.bin] [--groups <NeuronGroupsTable.ets 路径>]
// 缺省分析 entry/src/main/resources/rawfile/connectome.bin。
// 输出：N / 边数 / 文件尺寸核对 / 是否按 pre 有序 / 群号范围与各群神经元数 / region 分布 / 权重分位数。
// 现役 FAFB 基准：N=139255 edges=2698236 maxGroupId=60 regions={sensory:103847, central:35252, drives:80, motor:76}
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const file = process.argv[2] && !process.argv[2].startsWith('--')
  ? process.argv[2]
  : join(ROOT, 'entry', 'src', 'main', 'resources', 'rawfile', 'connectome.bin');

// 可选：带群表路径时翻译群名
let codes = null;
const gi = process.argv.indexOf('--groups');
if (gi > 0) {
  const src = readFileSync(process.argv[gi + 1], 'utf8');
  codes = [...src.matchAll(/code: '([^']+)'/g)].map((m) => m[1]);
}

const buf = readFileSync(file);
const N = buf.readUInt32LE(0);
const E = buf.readUInt32LE(4);
const expect = 8 + E * 12 + N * 3;
console.log(`file=${file}`);
console.log(`N=${N} edges=${E} bytes=${buf.length} expect=${expect} ${buf.length === expect ? 'OK' : '❌ 尺寸不符'}`);
if (buf.length !== expect) process.exit(1);

// 边：是否按 pre 有序；权重分位数
let lastPre = -1;
let sorted = true;
let minW = Infinity, maxW = -Infinity;
const absW = [];
for (let e = 0; e < E; e++) {
  const o = 8 + e * 12;
  const pre = buf.readUInt32LE(o);
  const post = buf.readUInt32LE(o + 4);
  const w = buf.readFloatLE(o + 8);
  if (pre < lastPre) sorted = false;
  lastPre = pre;
  if (pre >= N || post >= N) {
    console.error(`❌ 边 ${e} 引用越界神经元 pre=${pre} post=${post}`);
    process.exit(1);
  }
  if (!Number.isFinite(w)) {
    console.error(`❌ 边 ${e} 权重非有限数`);
    process.exit(1);
  }
  if (w < minW) minW = w;
  if (w > maxW) maxW = w;
  absW.push(Math.abs(w));
}
console.log(`按 pre 有序: ${sorted ? 'OK' : '❌'}  权重范围 [${minW}, ${maxW}]`);
absW.sort((a, b) => a - b);
const q = (p) => absW.length ? absW[Math.min(absW.length - 1, Math.floor(p * absW.length))] : 0;
console.log(`|w| 分位数 p50=${q(0.5)} p90=${q(0.9)} p99=${q(0.99)} p999=${q(0.999)}`);

// 每神经元元数据：region + group
const off = 8 + E * 12;
const regionCount = new Map();
const groupCount = new Map();
let maxG = 0;
for (let i = 0; i < N; i++) {
  const r = buf.readUInt8(off + i * 3);
  const g = buf.readUInt16LE(off + i * 3 + 1);
  if (g > maxG) maxG = g;
  regionCount.set(r, (regionCount.get(r) ?? 0) + 1);
  groupCount.set(g, (groupCount.get(g) ?? 0) + 1);
}
const REGION_NAMES = { 0: 'sensory', 1: 'central', 2: 'drives', 3: 'motor' };
const regions = [...regionCount.entries()].sort((a, b) => a[0] - b[0])
  .map(([r, c]) => `${REGION_NAMES[r] ?? r}:${c}`).join(' ');
console.log(`regions: ${regions}`);
console.log(`maxGroupId=${maxG} ${codes ? `(表 ${codes.length} 行, ${maxG < codes.length ? 'OK' : '❌ 越界'})` : ''}`);

// 非零群分布（可带群名）
const nz = [...groupCount.entries()].filter(([, c]) => c > 0).sort((a, b) => b[1] - a[1]);
console.log(`有神经元的群: ${nz.length}/${maxG + 1}`);
for (const [g, c] of nz.slice(0, 80)) {
  const name = codes ? codes[g] : `G${g}`;
  console.log(`  [${g}] ${name}: ${c}`);
}
console.log('analyze OK');
