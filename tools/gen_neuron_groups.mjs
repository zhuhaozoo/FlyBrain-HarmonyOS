// 神经功能群表生成器（零依赖 Node >= 18）
//
// 作用：生成 entry/src/main/ets/behavior/NeuronGroupsTable.ets —— 运行时唯一的群表来源
//（ConnectomeDriver / 大脑小窗 / 刺激映射全部消费它，"群号禁止手工硬编码"原则的落地）。
//
// 两种模式：
//   node tools/gen_neuron_groups.mjs
//       —— legacy 模式：生成现役 FAFB（FlyWire 雌性全脑）群表，与 2026-09 版手写
//          NeuronGroups.ets 的 63 行逐字段等价（升级迁移的等价性验证基准，见
//          docs/升级迁移-MaleCNS全中枢连接组.md §4.7）。
//   node tools/gen_neuron_groups.mjs --malecns tools/data_malecns/groups.json
//       —— 读取 build_connectome_malecns.mjs 产出的群表定义，生成 MaleCNS 群表。
//
// ⚠️ 生成的文件带"自动生成"头注释，请勿手工编辑；调整群表请改本脚本（legacy）或
//    管线映射规则（malecns）。
import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const OUT_FILE = join(ROOT, 'entry', 'src', 'main', 'ets', 'behavior', 'NeuronGroupsTable.ets');

// ---------- 现役 FAFB 群表（与 neuron_meta.json groups 一一对应；zh 为 UI 中文标签） ----------
// [id, code, zh, region, count]
const LEGACY_ROWS = [
  [0, 'VIS_R1R6', '视觉·R1-R6', '感觉', 11487],
  [1, 'VIS_R7R8', '视觉·R7-R8', '感觉', 0],
  [2, 'VIS_ME', '视觉·髓质', '感觉', 82318],
  [3, 'VIS_LO', '视觉·小叶', '感觉', 1793],
  [4, 'VIS_LC', '视觉·板层', '感觉', 0],
  [5, 'VIS_LPTC', '视觉·小叶板', '感觉', 1907],
  [6, 'OLF_ORN_FOOD', '嗅觉·食物', '感觉', 1851],
  [7, 'OLF_ORN_DANGER', '嗅觉·危险', '感觉', 430],
  [8, 'OLF_LN', '嗅觉·局部中间', '感觉', 453],
  [9, 'OLF_PN', '嗅觉·投射', '感觉', 699],
  [10, 'MECH_BRISTLE', '机械·刚毛', '感觉', 1927],
  [11, 'MECH_JO', '机械·江氏器', '感觉', 879],
  [12, 'MECH_CHORD', '机械·弦音器', '感觉', 0],
  [13, 'ANTENNAL_MECH', '机械·触角', '感觉', 0],
  [14, 'THERMO_WARM', '温度·暖', '感觉', 49],
  [15, 'THERMO_COOL', '温度·冷', '感觉', 54],
  [16, 'NOCI', '痛觉', '感觉', 0],
  [17, 'MB_KC', '蘑菇体·Kenyon', '中央', 5177],
  [18, 'MB_APL', '蘑菇体·APL', '中央', 0],
  [19, 'MB_MBON_APP', '蘑菇体·食欲输出', '中央', 96],
  [20, 'MB_MBON_AV', '蘑菇体·厌恶输出', '中央', 0],
  [21, 'MB_DAN_REW', '蘑菇体·奖赏多巴胺', '中央', 335],
  [22, 'MB_DAN_PUN', '蘑菇体·惩罚多巴胺', '中央', 0],
  [23, 'LH_APP', '侧角·食欲', '中央', 559],
  [24, 'LH_AV', '侧角·厌恶', '中央', 0],
  [25, 'CX_EPG', '中心体·EPG', '中央', 428],
  [26, 'CX_PFN', '中心体·PFN', '中央', 1244],
  [27, 'CX_FC', '中心体·扇形体', '中央', 822],
  [28, 'CX_HDELTA', '中心体·头方向', '中央', 611],
  [29, 'SEZ_FEED', '食道下区·进食', '中央', 34],
  [30, 'SEZ_GROOM', '食道下区·理毛', '中央', 0],
  [31, 'SEZ_WATER', '食道下区·饮水', '中央', 0],
  [32, 'GUS_GRN_SWEET', '味觉·甜', '中央', 214],
  [33, 'GUS_GRN_BITTER', '味觉·苦', '中央', 65],
  [34, 'GUS_GRN_WATER', '味觉·水', '中央', 131],
  [35, 'GNG_DESC', '下行·下降', '中央', 3581],
  [36, 'CLOCK_DN', '生物钟', '中央', 0],
  [37, 'DRIVE_HUNGER', '内驱力·饥饿', '驱动', 46],
  [38, 'DRIVE_FEAR', '内驱力·恐惧', '驱动', 0],
  [39, 'DRIVE_FATIGUE', '内驱力·疲劳', '驱动', 34],
  [40, 'DRIVE_CURIOSITY', '内驱力·好奇', '驱动', 0],
  [41, 'DRIVE_GROOM', '内驱力·理毛', '驱动', 0],
  [42, 'DN_WALK', '下行·步行', '运动', 0],
  [43, 'DN_FLIGHT', '下行·飞行', '运动', 0],
  [44, 'DN_TURN', '下行·转向', '运动', 0],
  [45, 'DN_BACKUP', '下行·后退', '运动', 0],
  [46, 'DN_STARTLE', '下行·惊吓', '运动', 0],
  [47, 'VNC_CPG', '腹神经索·步态节律', '运动', 4],
  [48, 'MN_LEG_L1', '运动·左前腿', '运动', 0],
  [49, 'MN_LEG_R1', '运动·右前腿', '运动', 0],
  [50, 'MN_LEG_L2', '运动·左中腿', '运动', 0],
  [51, 'MN_LEG_R2', '运动·右中腿', '运动', 0],
  [52, 'MN_LEG_L3', '运动·左后腿', '运动', 0],
  [53, 'MN_LEG_R3', '运动·右后腿', '运动', 0],
  [54, 'MN_WING_L', '运动·左翅', '运动', 0],
  [55, 'MN_WING_R', '运动·右翅', '运动', 0],
  [56, 'MN_PROBOSCIS', '运动·口器', '运动', 24],
  [57, 'MN_HEAD', '运动·头部', '运动', 40],
  [58, 'MN_ABDOMEN', '运动·腹部', '运动', 8],
  [59, 'GENERIC_SENSORY', '未细分·感觉', '感觉', 0],
  [60, 'GENERIC_CENTRAL', '未细分·中央', '中央', 21955],
  [61, 'GENERIC_DRIVES', '未细分·驱动', '驱动', 0],
  [62, 'GENERIC_MOTOR', '未细分·运动', '运动', 0],
];

const LEGACY_DATASET = 'FAFB 雌性全脑 (FlyWire 2024)';
const LEGACY_NEURONS = 139255;

// ---------- 参数 ----------
const args = process.argv.slice(2);
let mode = 'legacy';
let malecnsFile = '';
let outFile = OUT_FILE;
for (let i = 0; i < args.length; i++) {
  if (args[i] === '--malecns') {
    mode = 'malecns';
    malecnsFile = args[i + 1] ?? '';
    i++;
  } else if (args[i] === '--out') {
    outFile = args[i + 1] ?? '';
    i++;
  }
}

// ---------- 取行 ----------
let rows;           // [id, code, zh, region, count]
let dataset;
let neuronsTotal;
if (mode === 'legacy') {
  rows = LEGACY_ROWS;
  dataset = LEGACY_DATASET;
  neuronsTotal = LEGACY_NEURONS;
} else {
  if (!malecnsFile) {
    console.error('用法: node tools/gen_neuron_groups.mjs --malecns <groups.json>');
    process.exit(1);
  }
  const def = JSON.parse(readFileSync(malecnsFile, 'utf8'));
  dataset = String(def.dataset ?? 'MaleCNS');
  neuronsTotal = Number(def.neurons ?? 0);
  rows = (def.groups ?? []).map((g, i) => [i, String(g.code), String(g.zh), String(g.region), Number(g.count)]);
}

// ---------- 自查（宁可脚本崩，也不生成坏表）----------
if (rows.length === 0) throw new Error('群表为空');
const codes = new Set();
for (const [id, code] of rows) {
  if (codes.has(code)) throw new Error(`群 code 重复: ${code}`);
  codes.add(code);
  if (!Number.isInteger(id) || id < 0) throw new Error(`群号非法: ${id}`);
}
for (let i = 0; i < rows.length; i++) {
  if (rows[i][0] !== i) throw new Error(`群号必须连续且从 0 开始：第 ${i} 行 id=${rows[i][0]}`);
}
const sum = rows.reduce((a, r) => a + r[4], 0);
if (neuronsTotal > 0 && sum !== neuronsTotal) {
  throw new Error(`群神经元数合计 ${sum} ≠ 数据集总数 ${neuronsTotal}`);
}
// 14 个关键刺激/读取 code 是运行时稳定契约，两个数据集都必须有
const KEY_CODES = ['VIS_R1R6', 'VIS_ME', 'VIS_LO', 'VIS_LPTC', 'OLF_ORN_FOOD', 'OLF_ORN_DANGER',
  'MECH_BRISTLE', 'MECH_JO', 'DRIVE_HUNGER', 'DRIVE_FATIGUE', 'VNC_CPG', 'MN_PROBOSCIS',
  'MN_HEAD', 'MN_ABDOMEN'];
const missingKey = KEY_CODES.filter((c) => !codes.has(c));
if (missingKey.length > 0) {
  throw new Error(`缺少运行时关键群 code: ${missingKey.join(', ')}`);
}

// ---------- 序列化为 ArkTS ----------
const header = `// 自动生成：node tools/gen_neuron_groups.mjs（${mode} 模式，${new Date().toISOString().slice(0, 10)}）
// 数据集：${dataset}
// ⚠️ 本文件由工具生成，请勿手工编辑——改群表请改生成脚本（legacy）或管线映射规则（malecns）。
// 运行时契约：14 个关键刺激/读取群的 code 跨数据集不变（见升级迁移文档 §4.3）。
export interface GroupRow {
  id: number;
  code: string;
  zh: string;
  region: string;
  count: number;
}

export const DATASET_LABEL: string = '${dataset}';

export const DATASET_NEURONS: number = ${neuronsTotal};

export const GROUP_ROWS: GroupRow[] = [
`;
const body = rows.map(([id, code, zh, region, count]) =>
  `  { id: ${id}, code: '${code}', zh: '${zh}', region: '${region}', count: ${count} },`).join('\n');
const tail = `
];
`;

writeFileSync(outFile, header + body + tail);
console.log(`NeuronGroupsTable.ets OK: dataset='${dataset}' groups=${rows.length} ` +
  `neurons=${neuronsTotal} (sum=${sum})`);
console.log('out:', outFile);
