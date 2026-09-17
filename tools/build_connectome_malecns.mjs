// MaleCNS v1.0 连接组管线（零依赖 Node >= 18）—— 升级迁移文档 §4
//
// 职责：把 tools/data_malecns/ 下的 NeuPrint 导出（neurons.csv / connections.csv）加工成
// App 运行时四件套的同构产物：
//   1) entry/src/main/resources/rawfile/connectome.bin   —— 与现役 FAFB 逐字节同格式
//      （u32 N + u32 边数 + 边×(pre,post,f32 权重，按 pre 升序) + 每神经元(u8 region + u16 group)）
//   2) <data>/coordinates_app.csv / classification_app.csv —— 与旧四件套同格式，
//      gen_brain_glb.mjs 直接消费（点云"脑+腹索"）
//   3) <data>/groups.json —— 群表定义，gen_neuron_groups.mjs --malecns 消费
//
// 用法：
//   node tools/build_connectome_malecns.mjs                 # 正式生成（写 rawfile）
//   node tools/build_connectome_malecns.mjs --report        # 只看映射覆盖率/边分布，不写 rawfile
//   node tools/build_connectome_malecns.mjs --sample        # 合成小数据端到端自测（不碰 rawfile）
//   选项：--data <dir> --min-weight 3 --top-k 300 --max-edges 6000000
//
// 输入契约（列名别名宽容，见 parseCsv 的别名表；connections.csv 应为按神经元对聚合的邻接表）：
//   neurons.csv     bodyId,type,super_class,class,side,x,y,z   （x/y/z 或 somaLocation "(x,y,z)"）
//   connections.csv bodyId_pre,bodyId_post,weight[,nt_type]
import { readFileSync, writeFileSync, mkdirSync, existsSync, createReadStream } from 'node:fs';
import { createInterface } from 'node:readline';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const TOOLS = dirname(fileURLToPath(import.meta.url));
const ROOT = join(TOOLS, '..');
const RAW_BIN_DIR = join(ROOT, 'entry', 'src', 'main', 'resources', 'rawfile');
const RAW_BIN = join(RAW_BIN_DIR, 'connectome.bin');

// ---------- 参数 ----------
const argv = process.argv.slice(2);
const opt = {
  data: join(TOOLS, 'data_malecns'),
  minWeight: 3,
  topK: 300,
  maxEdges: 6000000,
  report: argv.includes('--report'),
  sample: argv.includes('--sample'),
};
for (let i = 0; i < argv.length; i++) {
  if (argv[i] === '--data') opt.data = argv[++i];
  else if (argv[i] === '--out-name') opt.outName = argv[++i];
  else if (argv[i] === '--min-weight') opt.minWeight = Number(argv[++i]);
  else if (argv[i] === '--top-k') opt.topK = Number(argv[++i]);
  else if (argv[i] === '--max-edges') opt.maxEdges = Number(argv[++i]);
}

// ---------- 功能群元数据（zh/region 与现役 FAFB 表同构；code 是运行时稳定契约） ----------
// region：感觉/中央/驱动/运动 ↔ 二进制里的 u8：0/1/2/3
const REGION_NUM = { '感觉': 0, '中央': 1, '驱动': 2, '运动': 3 };
// 点云 5 分组（gen_brain_glb 的 canonical super_class）← 功能群 code 前缀
const CODE_META = {
  VIS_R1R6: ['视觉·R1-R6', '感觉'], VIS_R7R8: ['视觉·R7-R8', '感觉'],
  VIS_ME: ['视觉·髓质', '感觉'], VIS_LO: ['视觉·小叶', '感觉'],
  VIS_LPTC: ['视觉·小叶板', '感觉'], VIS_LC: ['视觉·板层', '感觉'],
  OLF_ORN_FOOD: ['嗅觉·食物', '感觉'], OLF_ORN_DANGER: ['嗅觉·危险', '感觉'],
  OLF_LN: ['嗅觉·局部中间', '感觉'], OLF_PN: ['嗅觉·投射', '感觉'],
  MECH_BRISTLE: ['机械·刚毛', '感觉'], MECH_JO: ['机械·江氏器', '感觉'],
  MECH_CHORD: ['机械·弦音器', '感觉'], ANTENNAL_MECH: ['机械·触角', '感觉'],
  THERMO_WARM: ['温度·暖', '感觉'], THERMO_COOL: ['温度·冷', '感觉'], NOCI: ['痛觉', '感觉'],
  MB_KC: ['蘑菇体·Kenyon', '中央'], MB_APL: ['蘑菇体·APL', '中央'],
  MB_MBON_APP: ['蘑菇体·食欲输出', '中央'], MB_MBON_AV: ['蘑菇体·厌恶输出', '中央'],
  MB_DAN_REW: ['蘑菇体·奖赏多巴胺', '中央'], MB_DAN_PUN: ['蘑菇体·惩罚多巴胺', '中央'],
  LH_APP: ['侧角·食欲', '中央'], LH_AV: ['侧角·厌恶', '中央'],
  CX_EPG: ['中心体·EPG', '中央'], CX_PFN: ['中心体·PFN', '中央'],
  CX_FC: ['中心体·扇形体', '中央'], CX_HDELTA: ['中心体·头方向', '中央'],
  SEZ_FEED: ['食道下区·进食', '中央'], SEZ_GROOM: ['食道下区·理毛', '中央'],
  SEZ_WATER: ['食道下区·饮水', '中央'],
  GUS_GRN_SWEET: ['味觉·甜', '中央'], GUS_GRN_BITTER: ['味觉·苦', '中央'],
  GUS_GRN_WATER: ['味觉·水', '中央'],
  GNG_DESC: ['下行·下降', '中央'], CLOCK_DN: ['生物钟', '中央'],
  DRIVE_HUNGER: ['内驱力·饥饿', '驱动'], DRIVE_FEAR: ['内驱力·恐惧', '驱动'],
  DRIVE_FATIGUE: ['内驱力·疲劳', '驱动'], DRIVE_CURIOSITY: ['内驱力·好奇', '驱动'],
  DRIVE_GROOM: ['内驱力·理毛', '驱动'],
  DN_WALK: ['下行·步行', '运动'], DN_FLIGHT: ['下行·飞行', '运动'],
  DN_TURN: ['下行·转向', '运动'], DN_BACKUP: ['下行·后退', '运动'],
  DN_STARTLE: ['下行·惊吓', '运动'],
  VNC_CPG: ['腹神经索·步态节律', '运动'],
  MN_LEG_L1: ['运动·左前腿', '运动'], MN_LEG_R1: ['运动·右前腿', '运动'],
  MN_LEG_L2: ['运动·左中腿', '运动'], MN_LEG_R2: ['运动·右中腿', '运动'],
  MN_LEG_L3: ['运动·左后腿', '运动'], MN_LEG_R3: ['运动·右后腿', '运动'],
  MN_WING_L: ['运动·左翅', '运动'], MN_WING_R: ['运动·右翅', '运动'],
  MN_PROBOSCIS: ['运动·口器', '运动'], MN_HEAD: ['运动·头部', '运动'],
  MN_ABDOMEN: ['运动·腹部', '运动'],
  AN_ASC: ['上行·上行', '运动'],
  GENERIC_SENSORY: ['未细分·感觉', '感觉'], GENERIC_CENTRAL: ['未细分·中央', '中央'],
  GENERIC_DRIVES: ['未细分·驱动', '驱动'], GENERIC_MOTOR: ['未细分·运动', '运动'],
};
// 运行时稳定契约：缺了这些 code 的群表无法通过 gen_neuron_groups 的校验
const KEY_CODES = ['VIS_R1R6', 'VIS_ME', 'VIS_LO', 'VIS_LPTC', 'OLF_ORN_FOOD', 'OLF_ORN_DANGER',
  'MECH_BRISTLE', 'MECH_JO', 'DRIVE_HUNGER', 'DRIVE_FATIGUE', 'VNC_CPG', 'MN_PROBOSCIS',
  'MN_HEAD', 'MN_ABDOMEN'];

// ---------- 功能群映射规则（升级迁移文档 附录 A；有序，首条命中为准） ----------
// 作用于小写化的 `type + ' ' + class + ' ' + super_class` 拼接串
const RULES = [
  [/r1-r6|r1r6/, 'VIS_R1R6'],
  [/^r7|^r8|\br7\b|\br8\b|hbeyelet/, 'VIS_R7R8'],
  [/lobula plate|lobula-plate|\blptc\b|lplc|\bt4[a-z]?\b|\bt5[a-z]?\b/, 'VIS_LPTC'],
  [/\blc[0-9a-z]*\b/, 'VIS_LC'],
  [/lobula/, 'VIS_LO'],
  [/medulla|\bmi[0-9]+\b|\btm[0-9y]+\b|optic/, 'VIS_ME'],
  [/co2|vc3|v glomeruli/, 'OLF_ORN_DANGER'],
  [/orn|\bor[0-9]{2}/, 'OLF_ORN_FOOD'],
  [/(^|[^a-z])l{1,2}n/, 'OLF_LN'],
  [/(^|[^a-z])pn/, 'OLF_PN'],
  [/johnston|\bjo\b/, 'MECH_JO'],
  [/chordotonal/, 'MECH_CHORD'],
  [/antennal mech/, 'ANTENNAL_MECH'],
  [/bristle|mechanosensory|macrochaete|microchaete|^bm[_ ]/, 'MECH_BRISTLE'],
  [/warm/, 'THERMO_WARM'], [/cool|cold/, 'THERMO_COOL'],
  [/noci|pain/, 'NOCI'],
  [/\bsweet\b|sugar/, 'GUS_GRN_SWEET'], [/\bbitter\b/, 'GUS_GRN_BITTER'],
  [/gustatory|\bgrn\b|water taste/, 'GUS_GRN_WATER'],
  [/\bmbon/, 'MB_MBON_AV'],
  [/dan.*pun|pun.*dan|dan.*av/, 'MB_DAN_PUN'],
  [/pam[0-9]|ppl[0-9]|ppi[0-9]|\bdan\b/, 'MB_DAN_REW'],
  [/^kc|kca|kcg|kcy|kenyon|mb intrinsic|mushroom body/, 'MB_KC'],
  [/lh[a-z]*[0-9]|(^|[^a-z])lh/, 'LH_APP'],
  [/apl/, 'MB_APL'],
  [/subesophageal|sez/, 'SEZ_FEED'],
  [/epg|ellipsoid/, 'CX_EPG'],
  [/pfn|pfg/, 'CX_PFN'],
  [/fan.?shaped|\bfc[0-9]|\bfs[0-9]|delta/, 'CX_FC'],
  [/head.?direction|\bhd\b/, 'CX_HDELTA'],
  [/central complex|nodulus|protocerebral bridge|pb[0-9]/, 'CX_PFN'],
  [/clock|\bpdf\b|lnv|ln\d/, 'CLOCK_DN'],
  [/ipc|hugin|dh44|satiety/, 'DRIVE_HUNGER'],
  [/fatigue|sleep/, 'DRIVE_FATIGUE'],
  [/curiosity|novelty/, 'DRIVE_CURIOSITY'],
  [/groom.*drive/, 'DRIVE_GROOM'],
  [/fear|threat/, 'DRIVE_FEAR'],
  [/dn.*flight|flight.*descending/, 'DN_FLIGHT'],
  [/dn.*walk|walk.*descending/, 'DN_WALK'],
  [/dn.*turn|turn.*descending/, 'DN_TURN'],
  [/dn.*back|back.*descending/, 'DN_BACKUP'],
  [/dn.*startle|startle.*descending/, 'DN_STARTLE'],
  [/descending|\bdn[a-z]*\b/, 'GNG_DESC'],
  [/cpg|central pattern|gait/, 'VNC_CPG'],
  // —— MaleCNS 运动神经元命名（"肌肉功能 MN" + somaSide + somaNeuromere）——
  // 规则串固定为 "type class sup side=x neu=y"，side 在 neu 之前
  [/proboscis/, 'MN_PROBOSCIS'],
  [/\bmn[1-7]\b/, 'MN_PROBOSCIS'],                       // SEZ 咳喙肌肉 MN1~MN7
  [/neck|cervical|\bcvn\b|\bcem\b|\bmn(8|9|1[0-9])\b/, 'MN_HEAD'],
  [/halter/, 'GENERIC_MOTOR'],                            // 平衡棒（后翅）不算腿/翅
  [/dvmn.*side=l|dlmn.*side=l|wing.*side=l/, 'MN_WING_L'],// DVM/DLM = 飞行动力肌
  [/dvmn.*side=r|dlmn.*side=r|wing.*side=r/, 'MN_WING_R'],
  [/mn.*neu=a[0-9]/, 'MN_ABDOMEN'],
  [/mn.*side=l.*neu=t1/, 'MN_LEG_L1'],
  [/mn.*side=r.*neu=t1/, 'MN_LEG_R1'],
  [/mn.*side=l.*neu=t2/, 'MN_LEG_L2'],
  [/mn.*side=r.*neu=t2/, 'MN_LEG_R2'],
  [/mn.*side=l.*neu=t3/, 'MN_LEG_L3'],
  [/mn.*side=r.*neu=t3/, 'MN_LEG_R3'],
  [/\bmn\b|\bmn[a-z0-9]/, 'GENERIC_MOTOR'],               // 其余运动神经元兜底
  [/ascending|\ban[0-9]\b/, 'AN_ASC'],
  [/endocrine|secretory|insulin|\bipc\b/, 'GENERIC_DRIVES'],
];
// 未命中兜底：按 superclass（兼容 MaleCNS 的 ol_/cb_/vnc_ 前缀命名与旧四件套命名）
const GENERIC_BY_SUPER = {
  sensory: 'GENERIC_SENSORY', motor: 'GENERIC_MOTOR',
  endocrine: 'GENERIC_DRIVES', optic: 'VIS_ME', central: 'GENERIC_CENTRAL',
  // MaleCNS superclass（build_connectome 的注释表）
  ol_intrinsic: 'VIS_ME', ol_sensory: 'VIS_R1R6', visual_projection: 'VIS_ME',
  visual_centrifugal: 'VIS_ME', visual: 'VIS_ME',
  cb_intrinsic: 'GENERIC_CENTRAL', central: 'GENERIC_CENTRAL',
  cb_sensory: 'GENERIC_SENSORY', sensory: 'GENERIC_SENSORY',
  vnc_intrinsic: 'GENERIC_CENTRAL', vnc_sensory: 'GENERIC_SENSORY',
  vnc_motor: 'GENERIC_MOTOR', cb_motor: 'GENERIC_MOTOR', motor: 'GENERIC_MOTOR',
  vnc_efferent: 'GENERIC_MOTOR', efferent_ascending: 'GENERIC_MOTOR',
  efferent_descending: 'GENERIC_MOTOR', cb_efferent: 'GENERIC_MOTOR',
  ascending_neuron: 'AN_ASC', sensory_ascending: 'GENERIC_SENSORY',
  descending_neuron: 'GNG_DESC', sensory_descending: 'GENERIC_SENSORY',
  cb_endocrine: 'GENERIC_DRIVES', vnc_endocrine: 'GENERIC_DRIVES',
  endocrine: 'GENERIC_DRIVES', ENS: 'GENERIC_DRIVES',
};
// 点云 5 分组（canonical super_class）← code 前缀（供 classification_app.csv 与图例）
function displayClassOf(code) {
  if (code.startsWith('VIS_')) return 'optic';
  if (code.startsWith('GENERIC_')) {
    return { GENERIC_SENSORY: 'sensory', GENERIC_MOTOR: 'motor', GENERIC_DRIVES: 'endocrine',
      GENERIC_CENTRAL: 'central' }[code];
  }
  if (code.startsWith('MN_') || code.startsWith('DN_') || code === 'VNC_CPG' ||
    code === 'AN_ASC') return 'motor';
  if (code.startsWith('DRIVE_')) return 'endocrine';
  if (code.startsWith('OLF_') || code.startsWith('MECH_') || code.startsWith('THERMO_') ||
    code === 'NOCI' || code.startsWith('GUS_')) return 'sensory';
  return 'central';
}

// ---------- CSV 解析（列名别名宽容） ----------
const ALIAS = {
  id: ['bodyid', 'root_id', 'id', 'body_id'],
  type: ['type', 'cell_type'],
  super: ['super_class', 'superclass', 'superclass'],
  cls: ['class', 'cellclass'],
  side: ['side', 'hemi'],
  x: ['x', 'posx'], y: ['y', 'posy'], z: ['z', 'posz'],
  soma: ['somalocation', 'position', 'soma'],
  pre: ['bodyid_pre', 'pre', 'pre_id', 'pre_root_id'],
  post: ['bodyid_post', 'post', 'post_id', 'post_root_id'],
  weight: ['weight', 'syn_count', 'synapses', 'w'],
  nt: ['nt_type', 'nt', 'neurotransmitter'],
  neuro: ['neuromere', 'somaneuromere', 'neu'],
};
function colIndex(header, kind) {
  const hs = header.map((h) => h.trim().toLowerCase());
  for (const a of ALIAS[kind]) {
    const i = hs.indexOf(a);
    if (i >= 0) return i;
  }
  return -1;
}
function parseCsv(path, kinds) {
  if (!existsSync(path)) {
    throw new Error(`缺少输入文件: ${path}（先用 tools/fetch_malecns.py 导出，或 --sample 自测）`);
  }
  const lines = readFileSync(path, 'utf8').split('\n');
  const header = lines[0].split(',');
  const idx = {};
  for (const k of kinds) idx[k] = colIndex(header, k);
  const rows = [];
  for (let i = 1; i < lines.length; i++) {
    const line = lines[i].trim();
    if (!line) continue;
    const cells = line.split(',');
    const r = {};
    for (const k of kinds) r[k] = idx[k] >= 0 ? (cells[idx[k]] ?? '').trim() : '';
    rows.push(r);
  }
  return rows;
}
// "(x, y, z)" / "[x y z]" → [x,y,z]
function parseVec3(s) {
  const m = s.match(/[-+0-9.eE]+/g);
  return m && m.length >= 3 ? [Number(m[0]), Number(m[1]), Number(m[2])] : null;
}

// ---------- --sample：合成数据端到端自测 ----------
function makeSample(dir) {
  console.log('== --sample：生成合成数据（不触碰 rawfile）==');
  // 类型清单：覆盖全部 14 个关键 code + 兜底 + 部分新增 VNC 群
  const TYPES = [
    ['R1R6 photoreceptor', 'optic'], ['R7 photoreceptor', 'optic'], ['R8 photoreceptor', 'optic'],
    ['Mi1', 'optic'], ['Tm3', 'optic'], ['T4d', 'optic'], ['T5a', 'optic'], ['LC10', 'optic'],
    ['LC', 'optic'], ['lobula neuron LO', 'optic'], ['ORN Or42a', 'sensory'], ['ORN co2', 'sensory'], ['LN antennal local', 'sensory'],
    ['PN antennal projection', 'sensory'], ['JO sensory', 'sensory'], ['chordotonal neuron', 'sensory'],
    ['bristle mechanosensory', 'sensory'], ['thermo warm cell', 'sensory'],
    ['gustatory sweet GRN', 'sensory'], ['nociceptive neuron', 'sensory'],
    ['KC mushroom body', 'central'], ['MBON appetitive', 'central'], ['DAN PAM', 'central'],
    ['APL neuron', 'central'], ['EPG neuron', 'central'], ['PFN neuron', 'central'],
    ['LH appetitive', 'central'], ['SEZ feeding', 'central'], ['clock PDF neuron', 'central'],
    ['hunger satiety neuron', 'central'], ['sleep fatigue neuron', 'central'],
    ['descending neuron flight', 'motor'], ['descending neuron', 'motor'],
    ['CPG gait neuron', 'motor'], ['MNleg_L1 motor', 'motor'], ['MNleg_R2 motor', 'motor'],
    ['MNwing_L motor', 'motor'], ['MNwing_R motor', 'motor'],
    ['proboscis MN motor', 'motor'], ['neck MN motor', 'motor'], ['abdominal MN motor', 'motor'],
    ['ascending neuron', 'motor'], ['mystery central neuron', 'central'],
  ];
  mkdirSync(dir, { recursive: true });
  let s = 12345;
  const rng = () => { s = (s * 1664525 + 1013904223) >>> 0; return s / 4294967296; };
  const N = 600;
  const neurons = ['bodyId,type,super_class,class,side,x,y,z'];
  const meta = []; // {id, type, sup, x,y,z}
  for (let i = 0; i < N; i++) {
    const [t, sup] = TYPES[Math.floor(rng() * TYPES.length)];
    const x = Math.round(rng() * 100000), y = Math.round(rng() * 80000), z = Math.round(rng() * 90000);
    neurons.push(`${900000 + i},${t},${sup},${t},left,${x},${y},${z}`);
    meta.push({ id: 900000 + i, type: t, sup, x, y, z });
  }
  writeFileSync(join(dir, 'neurons.csv'), neurons.join('\n'));
  const conns = ['bodyId_pre,bodyId_post,weight,nt_type'];
  let e = 0;
  for (let p = 0; p < N; p++) {
    const k = 3 + Math.floor(rng() * 8);
    for (let j = 0; j < k; j++) {
      const q = Math.floor(rng() * N);
      const w = 1 + Math.floor(rng() * 60);
      const nt = rng() < 0.3 ? 'gaba' : 'acetylcholine';
      conns.push(`${900000 + p},${900000 + q},${w},${nt}`);
      e++;
    }
  }
  writeFileSync(join(dir, 'connections.csv'), conns.join('\n'));
  console.log(`sample: neurons=${N} edgeRows=${e} → ${dir}`);
  return meta;
}

// ---------- 主流程 ----------
let dataDir = opt.data;
let outBin = opt.outName ? join(RAW_BIN_DIR, opt.outName) : RAW_BIN;
if (opt.sample) {
  dataDir = join(TOOLS, 'data_malecns_sample');
  makeSample(dataDir);
  outBin = join(dataDir, 'connectome_sample.bin');
}
if (opt.report) {
  outBin = join(dataDir, 'connectome_preview.bin');
}

// 1) 神经元
console.log('reading neurons...');
const neuronRows = parseCsv(join(dataDir, 'neurons.csv'),
  ['id', 'type', 'super', 'cls', 'side', 'x', 'y', 'z', 'soma', 'neuro']);
const neuronIds = [];            // 按文件顺序 → 群编号 u16
const idToIdx = new Map();
const neuronMeta = [];
let skippedNoCoord = 0;
for (const r of neuronRows) {
  const idStr = r.id;
  if (!idStr || idToIdx.has(idStr)) continue;
  let xyz = [Number(r.x), Number(r.y), Number(r.z)];
  if (!Number.isFinite(xyz[0])) xyz = parseVec3(r.soma) ?? null;
  if (!xyz) { skippedNoCoord++; }
  const idx = neuronIds.length;
  neuronIds.push(idStr);
  idToIdx.set(idStr, idx);
  neuronMeta.push({ id: idStr, type: r.type, cls: r.cls, sup: r.super,
    side: r.side, neuro: r.neuro, xyz });
}
const N = neuronIds.length;
if (N < 100) throw new Error(`神经元过少 (${N})，数据可能没导全`);

// 2) 功能群映射（有序规则，首中为准）
console.log('mapping functional groups...');
const groupCodeByIdx = []; // 群号未定，先记 code
const ruleHits = new Map();
const unmatched = new Map();
for (const m of neuronMeta) {
  // side/neuromere 追加到规则串：MaleCNS 的腿运动神经元按"肌肉功能 + 体节 + 侧别"命名
  //（如 "ti flexor MN" + side=l + neu=t1 → MN_LEG_L1），单看类型名区分不了腿别
  const s = (`${m.type} ${m.cls} ${m.sup} side=${(m.side || '')} neu=${(m.neuro || '')}`)
    .toLowerCase();
  let code = '';
  for (const [re, c] of RULES) {
    if (re.test(s)) {
      code = c;
      ruleHits.set(c, (ruleHits.get(c) ?? 0) + 1);
      break;
    }
  }
  if (!code) {
    const sup = (m.sup || 'central').toLowerCase();
    code = GENERIC_BY_SUPER[sup] ?? 'GENERIC_CENTRAL';
    ruleHits.set(code, (ruleHits.get(code) ?? 0) + 1);
    const key = `${m.type || '(空)'} [${(m.sup || '').toLowerCase()}]`;
    unmatched.set(key, (unmatched.get(key) ?? 0) + 1);
  }
  groupCodeByIdx.push(code);
}
// 群注册表：关键群预播种（保证 code 恒在表中，即使该数据集没有匹配神经元——
// count=0 的群运行时自动跳过），其余按首次出现顺序发号
const groupOrder = [];      // code 列表
const groupIdOfCode = new Map();
for (const c of KEY_CODES) {
  groupIdOfCode.set(c, groupOrder.length);
  groupOrder.push(c);
}
for (const c of groupCodeByIdx) {
  if (!groupIdOfCode.has(c)) {
    groupIdOfCode.set(c, groupOrder.length);
    groupOrder.push(c);
  }
}
// 关键 code 检查（缺 → 明确报错而不是静默丢功能；--report 宽免，先看报告再迭代规则）
const missingKey = KEY_CODES.filter((c) => !groupIdOfCode.has(c));
if (missingKey.length > 0 && !opt.report) {
  throw new Error(`映射结果缺少运行时关键群 code: ${missingKey.join(', ')} —— ` +
    `检查附录 A 规则表与导出数据的命名`);
}

// 3) 边：流式读取（连接表可达 GB 级，不能整文件进内存）→ min-weight → top-k → max-edges
console.log('reading connections (streaming)...');
const rl = createInterface({
  input: createReadStream(join(dataDir, 'connections.csv'), 'utf8'),
  crlfDelay: Infinity,
});
let header = null;
const colIdx = {};   // kind → 列号
let rows = 0, unknownDropped = 0, thinDropped = 0;
let cap = 1 << 22, eN = 0;
let ePre = new Uint32Array(cap), ePost = new Uint32Array(cap), eW = new Int32Array(cap);
const grow = () => {
  const nCap = cap * 2;
  const p = new Uint32Array(nCap); p.set(ePre); ePre = p;
  const q = new Uint32Array(nCap); q.set(ePost); ePost = q;
  const r = new Int32Array(nCap); r.set(eW); eW = r;
  cap = nCap;
};
for await (const line of rl) {
  if (header === null) {
    header = line.split(',');
    const hs = header.map((h) => h.trim().toLowerCase());
    for (const [kind, aliases] of [['pre', ALIAS.pre], ['post', ALIAS.post], ['weight', ALIAS.weight], ['nt', ALIAS.nt]]) {
      colIdx[kind] = -1;
      for (const a of aliases) {
        const i = hs.indexOf(a);
        if (i >= 0) { colIdx[kind] = i; break; }
      }
    }
    if (colIdx.pre < 0 || colIdx.post < 0 || colIdx.weight < 0) {
      throw new Error(`connections.csv 缺少 pre/post/weight 列: ${header.join(',')}`);
    }
    continue;
  }
  const cells = line.split(',');
  const a = idToIdx.get(cells[colIdx.pre]);
  const b = idToIdx.get(cells[colIdx.post]);
  if (a === undefined || b === undefined) { unknownDropped++; continue; }
  rows++;
  let w = Number(cells[colIdx.weight]);
  if (!Number.isFinite(w) || w === 0) continue;
  if (colIdx.nt >= 0) {
    const nt = cells[colIdx.nt] ?? '';
    if (/gaba|inhib/i.test(nt)) w = -Math.abs(w);
  }
  if (Math.abs(w) < opt.minWeight) { thinDropped++; continue; }
  if (eN === cap) grow();
  ePre[eN] = a; ePost[eN] = b; eW[eN] = w; eN++;
}
console.log(`edges: rows=${rows} kept(min-weight ${opt.minWeight})=${eN} ` +
  `unknownDropped=${unknownDropped} thinDropped=${thinDropped}`);

// top-k：每个 pre 只保留 |w| 最大的 K 条（按 pre 计数排序分段处理后回填）
{
  const cnt = new Uint32Array(N + 1);
  for (let i = 0; i < eN; i++) cnt[ePre[i] + 1]++;
  for (let i = 1; i <= N; i++) cnt[i] += cnt[i - 1];
  const order = new Uint32Array(eN);   // 按 pre 分段的边下标
  const cursor = cnt.slice(0, N);
  for (let i = 0; i < eN; i++) order[cursor[ePre[i]]++] = i;
  const fPre = new Uint32Array(eN), fPost = new Uint32Array(eN), fW = new Int32Array(eN);
  let fN = 0;
  const seg = [];
  for (let pre = 0; pre < N; pre++) {
    const s = cnt[pre], t = cnt[pre + 1];
    const len = t - s;
    if (len === 0) continue;
    if (len <= opt.topK) {
      for (let j = s; j < t; j++) {
        const i = order[j];
        fPre[fN] = ePre[i]; fPost[fN] = ePost[i]; fW[fN] = eW[i]; fN++;
      }
      continue;
    }
    seg.length = 0;
    for (let j = s; j < t; j++) seg.push(order[j]);
    seg.sort((x, y) => Math.abs(eW[y]) - Math.abs(eW[x]));
    for (let j = 0; j < opt.topK; j++) {
      const i = seg[j];
      fPre[fN] = ePre[i]; fPost[fN] = ePost[i]; fW[fN] = eW[i]; fN++;
    }
  }
  ePre = fPre.subarray(0, fN); ePost = fPost.subarray(0, fN); eW = fW.subarray(0, fN);
  eN = fN;
  console.log(`after top-k(${opt.topK}): ${eN}`);
}
// max-edges：按 |w| 全局降序截断
if (eN > opt.maxEdges) {
  const idx = Array.from(ePre.keys());
  idx.sort((x, y) => Math.abs(eW[y]) - Math.abs(eW[x]));
  const keep = new Uint32Array(idx.slice(0, opt.maxEdges));
  const dropped = eN - opt.maxEdges;
  const p2 = new Uint32Array(opt.maxEdges); const q2 = new Uint32Array(opt.maxEdges);
  const r2 = new Int32Array(opt.maxEdges);
  for (let i = 0; i < opt.maxEdges; i++) { p2[i] = ePre[keep[i]]; q2[i] = ePost[keep[i]]; r2[i] = eW[keep[i]]; }
  ePre = p2; ePost = q2; eW = r2; eN = opt.maxEdges;
  console.warn(`⚠️ --max-edges 截断：丢弃最弱 ${dropped} 条边（建议调大 min-weight 后重跑）`);
}
// 最终排序：pre 升序、post 次序（与 BrainWorker 的 CSR 兼容）
{
  const idx = Array.from(ePre.keys());
  idx.sort((x, y) => ePre[x] - ePre[y] || ePost[x] - ePost[y]);
  const p = new Uint32Array(eN), q = new Uint32Array(eN), r = new Int32Array(eN);
  for (let i = 0; i < eN; i++) { p[i] = ePre[idx[i]]; q[i] = ePost[idx[i]]; r[i] = eW[idx[i]]; }
  ePre = p; ePost = q; eW = r;
}
const E = eN;
if (E < 1000) throw new Error(`边数过少 (${E})，检查 connections.csv 是否为聚合邻接表`);

// 4) 写 connectome.bin（格式与现役逐字节一致）
console.log(`writing connectome.bin (N=${N}, edges=${E})...`);
const bin = Buffer.alloc(8 + E * 12 + N * 3);
bin.writeUInt32LE(N, 0);
bin.writeUInt32LE(E, 4);
for (let i = 0; i < E; i++) {
  const o = 8 + i * 12;
  bin.writeUInt32LE(ePre[i], o);
  bin.writeUInt32LE(ePost[i], o + 4);
  bin.writeFloatLE(eW[i], o + 8);
}
// 每神经元：region u8 + group u16
for (let i = 0; i < N; i++) {
  const code = groupCodeByIdx[i];
  const g = groupIdOfCode.get(code);
  const region = CODE_META[code][1];
  const o = 8 + E * 12 + i * 3;
  bin.writeUInt8(REGION_NUM[region], o);
  bin.writeUInt16LE(g, o + 1);
}
if (!opt.report) {
  mkdirSync(dirname(outBin), { recursive: true });
  writeFileSync(outBin, bin);
}

// 5) 群表定义（gen_neuron_groups.mjs --malecns 消费）
const groupsJson = {
  dataset: 'MaleCNS v1.0 雄性全中枢 (Janelia 2026)',
  neurons: N,
  edges: E,
  groups: groupOrder.map((c, g) => ({
    id: g, code: c, zh: CODE_META[c][0], region: CODE_META[c][1],
    count: groupCodeByIdx.reduce((a, x) => a + (x === c ? 1 : 0), 0),
  })),
};
writeFileSync(join(dataDir, 'groups.json'), JSON.stringify(groupsJson, null, 2));

// 6) 点云同构 CSV（gen_brain_glb.mjs 直接消费；坐标沿用旧四件套的 [x y z] 括号格式）
const coordLines = ['root_id,position,supervoxel_id'];
const clsLines = ['root_id,flow,super_class,class,sub_class,hemilineage,side,nerve'];
for (let i = 0; i < N; i++) {
  const m = neuronMeta[i];
  if (m.xyz) {
    coordLines.push(`${m.id},[${m.xyz[0]} ${m.xyz[1]} ${m.xyz[2]}],0`);
  }
  const code = groupCodeByIdx[i];
  clsLines.push(`${m.id},intrinsic,${displayClassOf(code)},${m.type},,,left,`);
}
writeFileSync(join(dataDir, 'coordinates_app.csv'), coordLines.join('\n'));
writeFileSync(join(dataDir, 'classification_app.csv'), clsLines.join('\n'));

// 7) 报告
console.log('\n===== 报告 =====');
console.log(`neurons=${N} (无坐标 ${skippedNoCoord})  edges=${E}  groups=${groupOrder.length}`);
console.log('规则命中：');
for (const [re, c] of RULES) {
  const h = ruleHits.get(c) ?? 0;
  if (h === 0) console.log(`  ⚠️ 0 命中: /${re.source}/ → ${c}`);
}
const totalAssigned = groupCodeByIdx.length;
const covered = totalAssigned - [...unmatched.values()].reduce((a, b) => a + b, 0);
console.log(`覆盖率: ${(covered / totalAssigned * 100).toFixed(2)}% ` +
  `（未命中走 GENERIC_* 的 ${(unmatched.values().reduce((a, b) => a + b, 0))} 个）`);
const topUnmatched = [...unmatched.entries()].sort((a, b) => b[1] - a[1]).slice(0, 30);
if (topUnmatched.length > 0) {
  console.log('Top 未命中类型（迭代附录 A 规则表的入口）：');
  for (const [t, c] of topUnmatched) console.log(`  ${c}\t${t}`);
}
// 各 superclass 的 Top 类型（设计规则的原始素材）
{
  const perSup = new Map();
  for (const m of neuronMeta) {
    const sup = (m.sup || '(null)').toLowerCase();
    if (!perSup.has(sup)) perSup.set(sup, new Map());
    const tm = perSup.get(sup);
    const key = m.type || '(空)';
    tm.set(key, (tm.get(key) ?? 0) + 1);
  }
  console.log('== 各 superclass Top 类型 ==');
  for (const [sup, tm] of [...perSup.entries()].sort((a, b) => {
    const sa = [...a[1].values()].reduce((x, y) => x + y, 0);
    const sb = [...b[1].values()].reduce((x, y) => x + y, 0);
    return sb - sa;
  })) {
    const total = [...tm.values()].reduce((x, y) => x + y, 0);
    const top = [...tm.entries()].sort((a, b) => b[1] - a[1]).slice(0, 18)
      .map(([t, c]) => `${t}:${c}`).join(', ');
    console.log(`  ${sup} (${total}): ${top}`);
  }
}
console.log('各群神经元数：');
for (const c of groupOrder) {
  const g = groupIdOfCode.get(c);
  console.log(`  [${g}] ${c}: ${groupsJson.groups[g].count}`);
}
const absW = new Float64Array(E);
for (let i = 0; i < E; i++) absW[i] = Math.abs(eW[i]);
absW.sort();
const q = (p) => absW.length ? absW[Math.floor(p * absW.length)] : 0;
console.log(`|w| 分位数 p50=${q(0.5)} p90=${q(0.9)} p99=${q(0.99)}`);
console.log(`minWeight=${opt.minWeight} topK=${opt.topK} maxEdges=${opt.maxEdges}`);
console.log(opt.report ? `--report 模式：bin 写到 ${outBin}（rawfile 未改动）`
  : `bin → ${outBin}`);
console.log(`groups.json / coordinates_app.csv / classification_app.csv → ${dataDir}`);

// 8) 端到端自校验：重新读回 bin 断言（--sample / --report 都跑）
console.log('\nself-check: re-parsing written bin...');
const rb = readFileSync(outBin);
const rN = rb.readUInt32LE(0), rE = rb.readUInt32LE(4);
if (rN !== N || rE !== E) throw new Error(`回读不符 N=${rN}/${N} E=${rE}/${E}`);
let last = -1;
let maxG = 0;
const sumByG = new Map();
for (let e = 0; e < rE; e++) {
  const o = 8 + e * 12;
  const pre = rb.readUInt32LE(o), post = rb.readUInt32LE(o + 4);
  const w = rb.readFloatLE(o + 8);
  if (pre < last) throw new Error('回读发现边未按 pre 排序');
  if (pre >= N || post >= N || !Number.isFinite(w)) throw new Error('回读发现非法边');
  last = pre;
}
const metaOff = 8 + rE * 12;
for (let i = 0; i < rN; i++) {
  const g = rb.readUInt16LE(metaOff + i * 3 + 1);
  if (g >= groupOrder.length) throw new Error(`回读发现越界群号 ${g}`);
  maxG = Math.max(maxG, g);
  sumByG.set(g, (sumByG.get(g) ?? 0) + 1);
}
for (const [g, c] of sumByG) {
  if (c !== groupsJson.groups[g].count) throw new Error(`群 ${g} 计数与群表不符`);
}
console.log(`self-check OK: N=${rN} edges=${rE} maxGroupId=${maxG} groups=${groupOrder.length}`);
if (opt.sample) {
  console.log('\n--sample PASS ✅  （合成数据端到端管线自测通过，rawfile 未被触碰）');
}
