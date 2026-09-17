// 临时分析脚本：统计 world.glb 的 chunk 构成与各 mesh 面数/材质分布
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const FILE = process.argv[2] ?? join(dirname(fileURLToPath(import.meta.url)),
  '..', 'entry', 'src', 'main', 'resources', 'rawfile', 'gltf', 'world.glb');
const buf = readFileSync(FILE);
const jsonLen = buf.readUInt32LE(12);
const json = JSON.parse(buf.slice(20, 20 + jsonLen).toString('utf8'));
const binStart = 20 + jsonLen + 8;
const binLen = buf.readUInt32LE(binStart - 8);
console.log(`file=${buf.length}B  json=${jsonLen}B  bin=${binLen}B  nodes=${json.nodes.length} meshes=${json.meshes.length} materials=${json.materials.length}`);

const per = new Map();
let triTotal = 0, vertTotal = 0;
for (const m of json.meshes) {
  const p = m.primitives[0];
  const mat = json.materials[p.material].name;
  const tris = json.accessors[p.indices].count / 3;
  const verts = json.accessors[p.attributes.POSITION].count;
  triTotal += tris; vertTotal += verts;
  if (!per.has(mat)) per.set(mat, { tris: 0, verts: 0, meshes: 0 });
  const e = per.get(mat);
  e.tris += tris; e.verts += verts; e.meshes++;
}
console.log(`TOTAL triangles=${triTotal} vertices=${vertTotal}`);
const rows = [...per.entries()].sort((a, b) => b[1].tris - a[1].tris);
for (const [mat, e] of rows) {
  console.log(`  ${mat.padEnd(16)} tris=${String(Math.round(e.tris)).padStart(6)} verts=${String(e.verts).padStart(6)} meshes=${e.meshes}`);
}

// 节点统计：果蝇子树 / 青蛙子树 / 其他
const nameOf = (i) => json.nodes[i].name ?? `#${i}`;
const childrenOf = (i) => json.nodes[i].children ?? [];
function countSubtree(rootName) {
  const top = json.scenes[0].nodes.map((i) => ({ i, name: nameOf(i) }));
  let total = 0;
  const walk = (i) => { total++; for (const c of childrenOf(i)) walk(c); };
  for (const t of top) {
    if (t.name === rootName) { walk(t.i); return total; }
  }
  return -1;
}
console.log(`fly subtree nodes=${countSubtree('fly')}, frog subtree nodes=${countSubtree('frog')}`);
