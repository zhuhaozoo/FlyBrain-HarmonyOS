// MaleCNS feather → 管线输入 CSV（流式，内存受限）
// 输出：neurons.csv / connections.csv（bodyId_pre,bodyId_post,weight,nt_type）
import { RecordBatchFileReader, tableFromIPC, compressionRegistry, CompressionType } from 'apache-arrow';
import lz4js from 'lz4js';
import { readFileSync, writeFileSync } from 'node:fs';
import { createWriteStream } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const DIR = process.argv[2] ?? join(dirname(fileURLToPath(import.meta.url)), 'data_malecns');
process.chdir(DIR);

compressionRegistry.set(CompressionType.LZ4_FRAME, {
  decode(buf) { return lz4js.decompress(buf instanceof Uint8Array ? buf : new Uint8Array(buf)); },
});

const t0 = Date.now();
// 1) 注释表 → 神经元集合（只保留 status=Traced 的真神经元）
const ann = tableFromIPC(readFileSync('body-annotations.feather'));
const g = (name, i) => ann.getChild(name)?.get(i);
const neurons = [];   // {id, type, sup, cls, side, neu, x, y, z}
const inSet = new Set();
for (let i = 0; i < ann.numRows; i++) {
  if (g('status', i) !== 'Traced') continue;
  const id = g('bodyId', i);
  if (id === null || id === undefined) continue;
  const neu = g('somaNeuromere', i) ?? '';
  const sl = g('somaLocation', i);
  const xyz = sl && sl.length === 3 ? [...sl] : null;
  neurons.push({
    id: Number(id),
    type: g('type', i) ?? '',
    sup: g('superclass', i) ?? '',
    cls: g('class', i) ?? '',
    side: g('somaSide', i) ?? '',
    neu: String(neu ?? ''),
    xyz,
  });
  inSet.add(Number(id));
}
console.log(`neurons (Traced): ${neurons.length}`);

// 2) 递质表 → body → consensus_nt（无则 predicted_nt）
const ntOf = new Map();
{
  const t = tableFromIPC(readFileSync('body-nt.feather'));
  const body = t.getChild('body'), cons = t.getChild('consensus_nt'), pred = t.getChild('predicted_nt');
  for (let i = 0; i < t.numRows; i++) {
    const b = body.get(i);
    if (b === null) continue;
    const nt = cons.get(i) ?? pred.get(i) ?? '';
    if (nt) ntOf.set(Number(b), String(nt));
  }
  console.log(`nt map: ${ntOf.size}`);
}

// 3) 写 neurons.csv
{
  const out = createWriteStream('neurons.csv');
  out.write('bodyId,type,super_class,class,side,neuromere,x,y,z\n');
  for (const n of neurons) {
    const xyz = n.xyz ? `${n.xyz[0]},${n.xyz[1]},${n.xyz[2]}` : ',,';
    out.write(`${n.id},${n.type},${n.sup},${n.cls},${n.side},${n.neu},${xyz}\n`);
  }
  out.end();
}

// 4) 流式过权重表 → connections.csv（两端都必须是 Traced 神经元；nt 取 pre 的共识递质）
const reader = RecordBatchFileReader.from(readFileSync('connectome-weights.feather'));
const out = createWriteStream('connections.csv');
out.write('bodyId_pre,bodyId_post,weight,nt_type\n');
let rows = 0, kept = 0, droppedUnknown = 0;
let schema = null;
let buf = '';
for (const batch of reader) {
  if (!schema) {
    schema = batch.schema;
    console.log('weights schema:', batch.schema.fields.map(f => `${f.name}:${f.type}`).join(' | '));
  }
  const names = batch.schema.fields.map(f => f.name);
  const preC = names.find(n => /pre/i.test(n));
  const postC = names.find(n => /post/i.test(n));
  const wC = names.find(n => /weight|syn|strength|n$/i.test(n));
  if (!preC || !postC || !wC) throw new Error(`权重表列名无法识别: ${names.join(', ')}`);
  const preV = batch.getChild(preC), postV = batch.getChild(postC), wV = batch.getChild(wC);
  for (let i = 0; i < batch.numRows; i++) {
    const a = preV.get(i), b = postV.get(i);
    if (a === null || b === null) continue;
    rows++;
    const pre = Number(a), post = Number(b);
    if (!inSet.has(pre) || !inSet.has(post)) { droppedUnknown++; continue; }
    const w = Math.round(Number(wV.get(i)) || 0);
    if (w === 0) continue;
    const nt = ntOf.get(pre) ?? '';
    out.write(`${pre},${post},${w},${nt}\n`);
    kept++;
  }
}
out.end();
console.log(`connections: rows=${rows} kept(both traced)=${kept} droppedUnknown=${droppedUnknown}`);
console.log(`done in ${((Date.now() - t0) / 1000).toFixed(1)}s`);
