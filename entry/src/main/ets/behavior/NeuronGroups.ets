// 神经功能群名称表（63 群）—— 数据源：tools/data/neuron_meta.json 的 groups。
//
// 用途：把 Worker 上报的「第 i 群放电率」翻译成用户能看懂的名字，
// 让大脑状态小窗能逐个列出到底哪些脑区在活跃，而不是只给一个「9/61」的计数。
//
// 维护说明：群号与名称来自 FlyWire 派生数据，**不要手工改动群号**；
// 若上游数据更新，请重新从 neuron_meta.json 生成此表。
export class NeuronGroupInfo {
  public id: number = 0;
  public code: string = '';    // 原始群名（与 neuron_meta.json 一致）
  public zh: string = '';      // 中文短标签（UI 显示用）
  public region: string = '';   // 所属脑区
  public count: number = 0;     // 神经元数量
}

function g(id: number, code: string, zh: string, region: string, count: number): NeuronGroupInfo {
  const info = new NeuronGroupInfo();
  info.id = id;
  info.code = code;
  info.zh = zh;
  info.region = region;
  info.count = count;
  return info;
}

const R_SENSE = '感觉';
const R_CENTRAL = '中央';
const R_DRIVE = '驱动';
const R_MOTOR = '运动';

export const NEURON_GROUPS: NeuronGroupInfo[] = [
  // ---- 感觉 ----
  g(0, 'VIS_R1R6', '视觉·R1-R6', R_SENSE, 11487),
  g(1, 'VIS_R7R8', '视觉·R7-R8', R_SENSE, 0),
  g(2, 'VIS_ME', '视觉·髓质', R_SENSE, 82318),
  g(3, 'VIS_LO', '视觉·小叶', R_SENSE, 1793),
  g(4, 'VIS_LC', '视觉·板层', R_SENSE, 0),
  g(5, 'VIS_LPTC', '视觉·小叶板', R_SENSE, 1907),
  g(6, 'OLF_ORN_FOOD', '嗅觉·食物', R_SENSE, 1851),
  g(7, 'OLF_ORN_DANGER', '嗅觉·危险', R_SENSE, 430),
  g(8, 'OLF_LN', '嗅觉·局部中间', R_SENSE, 453),
  g(9, 'OLF_PN', '嗅觉·投射', R_SENSE, 699),
  g(10, 'MECH_BRISTLE', '机械·刚毛', R_SENSE, 1927),
  g(11, 'MECH_JO', '机械·江氏器', R_SENSE, 879),
  g(12, 'MECH_CHORD', '机械·弦音器', R_SENSE, 0),
  g(13, 'ANTENNAL_MECH', '机械·触角', R_SENSE, 0),
  g(14, 'THERMO_WARM', '温度·暖', R_SENSE, 49),
  g(15, 'THERMO_COOL', '温度·冷', R_SENSE, 54),
  g(16, 'NOCI', '痛觉', R_SENSE, 0),
  // ---- 中央 ----
  g(17, 'MB_KC', '蘑菇体·Kenyon', R_CENTRAL, 5177),
  g(18, 'MB_APL', '蘑菇体·APL', R_CENTRAL, 0),
  g(19, 'MB_MBON_APP', '蘑菇体·食欲输出', R_CENTRAL, 96),
  g(20, 'MB_MBON_AV', '蘑菇体·厌恶输出', R_CENTRAL, 0),
  g(21, 'MB_DAN_REW', '蘑菇体·奖赏多巴胺', R_CENTRAL, 335),
  g(22, 'MB_DAN_PUN', '蘑菇体·惩罚多巴胺', R_CENTRAL, 0),
  g(23, 'LH_APP', '侧角·食欲', R_CENTRAL, 559),
  g(24, 'LH_AV', '侧角·厌恶', R_CENTRAL, 0),
  g(25, 'CX_EPG', '中心体·EPG', R_CENTRAL, 428),
  g(26, 'CX_PFN', '中心体·PFN', R_CENTRAL, 1244),
  g(27, 'CX_FC', '中心体·扇形体', R_CENTRAL, 822),
  g(28, 'CX_HDELTA', '中心体·头方向', R_CENTRAL, 611),
  g(29, 'SEZ_FEED', '食道下区·进食', R_CENTRAL, 34),
  g(30, 'SEZ_GROOM', '食道下区·理毛', R_CENTRAL, 0),
  g(31, 'SEZ_WATER', '食道下区·饮水', R_CENTRAL, 0),
  g(32, 'GUS_GRN_SWEET', '味觉·甜', R_CENTRAL, 214),
  g(33, 'GUS_GRN_BITTER', '味觉·苦', R_CENTRAL, 65),
  g(34, 'GUS_GRN_WATER', '味觉·水', R_CENTRAL, 131),
  g(35, 'GNG_DESC', '下行·下降', R_CENTRAL, 3581),
  g(36, 'CLOCK_DN', '生物钟', R_CENTRAL, 0),
  // ---- 内驱力 ----
  g(37, 'DRIVE_HUNGER', '内驱力·饥饿', R_DRIVE, 46),
  g(38, 'DRIVE_FEAR', '内驱力·恐惧', R_DRIVE, 0),
  g(39, 'DRIVE_FATIGUE', '内驱力·疲劳', R_DRIVE, 34),
  g(40, 'DRIVE_CURIOSITY', '内驱力·好奇', R_DRIVE, 0),
  g(41, 'DRIVE_GROOM', '内驱力·理毛', R_DRIVE, 0),
  // ---- 运动 ----
  g(42, 'DN_WALK', '下行·步行', R_MOTOR, 0),
  g(43, 'DN_FLIGHT', '下行·飞行', R_MOTOR, 0),
  g(44, 'DN_TURN', '下行·转向', R_MOTOR, 0),
  g(45, 'DN_BACKUP', '下行·后退', R_MOTOR, 0),
  g(46, 'DN_STARTLE', '下行·惊吓', R_MOTOR, 0),
  g(47, 'VNC_CPG', '腹神经索·步态节律', R_MOTOR, 4),
  g(48, 'MN_LEG_L1', '运动·左前腿', R_MOTOR, 0),
  g(49, 'MN_LEG_R1', '运动·右前腿', R_MOTOR, 0),
  g(50, 'MN_LEG_L2', '运动·左中腿', R_MOTOR, 0),
  g(51, 'MN_LEG_R2', '运动·右中腿', R_MOTOR, 0),
  g(52, 'MN_LEG_L3', '运动·左后腿', R_MOTOR, 0),
  g(53, 'MN_LEG_R3', '运动·右后腿', R_MOTOR, 0),
  g(54, 'MN_WING_L', '运动·左翅', R_MOTOR, 0),
  g(55, 'MN_WING_R', '运动·右翅', R_MOTOR, 0),
  g(56, 'MN_PROBOSCIS', '运动·口器', R_MOTOR, 24),
  g(57, 'MN_HEAD', '运动·头部', R_MOTOR, 40),
  g(58, 'MN_ABDOMEN', '运动·腹部', R_MOTOR, 8),
  // ---- 未归类（上游数据未细分，数量很大）----
  g(59, 'GENERIC_SENSORY', '未细分·感觉', R_SENSE, 0),
  g(60, 'GENERIC_CENTRAL', '未细分·中央', R_CENTRAL, 21955),
  g(61, 'GENERIC_DRIVES', '未细分·驱动', R_DRIVE, 0),
  g(62, 'GENERIC_MOTOR', '未细分·运动', R_MOTOR, 0),
];

// 群号 → 中文名（越界时回退成 "群N"，避免 UI 出现空白）
export function groupLabel(id: number): string {
  if (id >= 0 && id < NEURON_GROUPS.length) {
    return NEURON_GROUPS[id].zh;
  }
  return `群${id}`;
}

// 群号 → 所属脑区
export function groupRegion(id: number): string {
  if (id >= 0 && id < NEURON_GROUPS.length) {
    return NEURON_GROUPS[id].region;
  }
  return '';
}
