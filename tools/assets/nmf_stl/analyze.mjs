// NeuroMechFly STL 几何分析：整体包围盒/朝向判定 + 各部件 bbox
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';

function parseSTL(path) {
  const buf = readFileSync(path);
  const head = buf.subarray(0, 5).toString('ascii');
  let tris;
  if (head.startsWith('solid') && buf.length < 500) {
    throw new Error('ascii STL 暂不支持: ' + path);
  }
  // 二进制 STL（ascii 导出极少见，先按二进制解析并校验）
  const count = buf.readUInt32LE(80);
  if (84 + count * 50 !== buf.length) {
    throw new Error(`STL 尺寸校验失败 ${path}: ${buf.length} vs ${84 + count * 50}`);
  }
  tris = new Float32Array(count * 9);
  for (let i = 0; i < count; i++) {
    const o = 84 + i * 50 + 12; // 跳过法线（重算）
    for (let v = 0; v < 9; v++) tris[i * 9 + v] = buf.readFloatLE(o + v * 4);
  }
  return tris;
}

const dir = import.meta.dirname;
const files = readdirSync(dir).filter((f) => f.endsWith('.stl')).sort();
const mn = [1e9, 1e9, 1e9], mx = [-1e9, -1e9, -1e9];
const per = [];
for (const f of files) {
  const tris = parseSTL(join(dir, f));
  const p = [1e9, 1e9, 1e9], q = [-1e9, -1e9, -1e9];
  for (let i = 0; i < tris.length; i += 3) {
    for (let k = 0; k < 3; k++) {
      const v = tris[i + k];
      if (v < p[k]) p[k] = v;
      if (v > q[k]) q[k] = v;
      if (v < mn[k]) mn[k] = v;
      if (v > mx[k]) mx[k] = v;
    }
  }
  per.push({ f: f.replace('.stl', ''), tris: tris.length / 9,
    c: [(p[0] + q[0]) / 2, (p[1] + q[1]) / 2, (p[2] + q[2]) / 2],
    ext: [(q[0]-p[0])*1000,(q[1]-p[1])*1000,(q[2]-p[2])*1000], min: p.map((v)=>v*1000), max: q.map((v)=>v*1000) });
}
const ext = [mx[0] - mn[0], mx[1] - mn[1], mx[2] - mn[2]];
console.log(`parts=${per.length} triangles=${per.reduce((a, b) => a + b.tris, 0)}`);
console.log(`整体 bbox min=[${mn.map((v)=>(v*1000).toFixed(2))}] max=[${mx.map((v)=>(v*1000).toFixed(2))}]`);
console.log(`整体 ext X=${(ext[0]*1000).toFixed(2)} Y=${(ext[1]*1000).toFixed(2)} Z=${(ext[2]*1000).toFixed(2)}`);
console.log('part, tris, cx, cy, cz, extX, extY, extZ');
for (const p of per) {
  console.log(`${p.f}, ${p.tris}, ${p.c.map((v)=>(v*1000).toFixed(2)).join(', ')}, ` +
    `${p.ext.map((v)=>(v*1000).toFixed(2)).join(', ')}`);
}
