// 自动生成：node tools/gen_neuron_groups.mjs（malecns 模式，2026-09-16）
// 数据集：MaleCNS v1.0 雄性全中枢 (Janelia 2026)
// ⚠️ 本文件由工具生成，请勿手工编辑——改群表请改生成脚本（legacy）或管线映射规则（malecns）。
// 运行时契约：14 个关键刺激/读取群的 code 跨数据集不变（见升级迁移文档 §4.3）。
export interface GroupRow {
  id: number;
  code: string;
  zh: string;
  region: string;
  count: number;
}

export const DATASET_LABEL: string = 'MaleCNS v1.0 雄性全中枢 (Janelia 2026)';

export const DATASET_NEURONS: number = 165122;

export const GROUP_ROWS: GroupRow[] = [
  { id: 0, code: 'VIS_R1R6', zh: '视觉·R1-R6', region: '感觉', count: 1394 },
  { id: 1, code: 'VIS_ME', zh: '视觉·髓质', region: '感觉', count: 80889 },
  { id: 2, code: 'VIS_LO', zh: '视觉·小叶', region: '感觉', count: 0 },
  { id: 3, code: 'VIS_LPTC', zh: '视觉·小叶板', region: '感觉', count: 13997 },
  { id: 4, code: 'OLF_ORN_FOOD', zh: '嗅觉·食物', region: '感觉', count: 2601 },
  { id: 5, code: 'OLF_ORN_DANGER', zh: '嗅觉·危险', region: '感觉', count: 47 },
  { id: 6, code: 'MECH_BRISTLE', zh: '机械·刚毛', region: '感觉', count: 5084 },
  { id: 7, code: 'MECH_JO', zh: '机械·江氏器', region: '感觉', count: 672 },
  { id: 8, code: 'DRIVE_HUNGER', zh: '内驱力·饥饿', region: '驱动', count: 26 },
  { id: 9, code: 'DRIVE_FATIGUE', zh: '内驱力·疲劳', region: '驱动', count: 0 },
  { id: 10, code: 'VNC_CPG', zh: '腹神经索·步态节律', region: '运动', count: 0 },
  { id: 11, code: 'MN_PROBOSCIS', zh: '运动·口器', region: '运动', count: 12 },
  { id: 12, code: 'MN_HEAD', zh: '运动·头部', region: '运动', count: 15 },
  { id: 13, code: 'MN_ABDOMEN', zh: '运动·腹部', region: '运动', count: 194 },
  { id: 14, code: 'GNG_DESC', zh: '下行·下降', region: '中央', count: 1324 },
  { id: 15, code: 'GENERIC_CENTRAL', zh: '未细分·中央', region: '中央', count: 37170 },
  { id: 16, code: 'MB_MBON_AV', zh: '蘑菇体·厌恶输出', region: '中央', count: 97 },
  { id: 17, code: 'GENERIC_MOTOR', zh: '未细分·运动', region: '运动', count: 211 },
  { id: 18, code: 'AN_ASC', zh: '上行·上行', region: '运动', count: 1889 },
  { id: 19, code: 'OLF_LN', zh: '嗅觉·局部中间', region: '感觉', count: 349 },
  { id: 20, code: 'LH_APP', zh: '侧角·食欲', region: '中央', count: 2028 },
  { id: 21, code: 'MB_DAN_REW', zh: '蘑菇体·奖赏多巴胺', region: '中央', count: 340 },
  { id: 22, code: 'OLF_PN', zh: '嗅觉·投射', region: '感觉', count: 56 },
  { id: 23, code: 'CX_FC', zh: '中心体·扇形体', region: '中央', count: 1243 },
  { id: 24, code: 'CX_EPG', zh: '中心体·EPG', region: '中央', count: 50 },
  { id: 25, code: 'MB_APL', zh: '蘑菇体·APL', region: '中央', count: 2 },
  { id: 26, code: 'VIS_LC', zh: '视觉·板层', region: '感觉', count: 4246 },
  { id: 27, code: 'CX_PFN', zh: '中心体·PFN', region: '中央', count: 474 },
  { id: 28, code: 'CLOCK_DN', zh: '生物钟', region: '中央', count: 16 },
  { id: 29, code: 'GENERIC_DRIVES', zh: '未细分·驱动', region: '驱动', count: 68 },
  { id: 30, code: 'SEZ_FEED', zh: '食道下区·进食', region: '中央', count: 27 },
  { id: 31, code: 'MB_KC', zh: '蘑菇体·Kenyon', region: '中央', count: 4064 },
  { id: 32, code: 'GUS_GRN_WATER', zh: '味觉·水', region: '中央', count: 1428 },
  { id: 33, code: 'VIS_R7R8', zh: '视觉·R7-R8', region: '感觉', count: 2720 },
  { id: 34, code: 'GENERIC_SENSORY', zh: '未细分·感觉', region: '感觉', count: 1918 },
  { id: 35, code: 'MN_WING_R', zh: '运动·右翅', region: '运动', count: 7 },
  { id: 36, code: 'MN_LEG_L1', zh: '运动·左前腿', region: '运动', count: 78 },
  { id: 37, code: 'MN_LEG_R2', zh: '运动·右中腿', region: '运动', count: 79 },
  { id: 38, code: 'MN_LEG_R3', zh: '运动·右后腿', region: '运动', count: 72 },
  { id: 39, code: 'MN_LEG_L3', zh: '运动·左后腿', region: '运动', count: 74 },
  { id: 40, code: 'MN_LEG_L2', zh: '运动·左中腿', region: '运动', count: 79 },
  { id: 41, code: 'MN_WING_L', zh: '运动·左翅', region: '运动', count: 7 },
  { id: 42, code: 'MN_LEG_R1', zh: '运动·右前腿', region: '运动', count: 75 },
];
