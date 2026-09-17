// 自动生成：node tools/gen_brain_glb.mjs（MaleCNS v1.0 雄性全中枢 (Janelia 2026)）—— 请勿手工编辑
// 点云 5 分组表：BrainPage 的图例与显隐目标都来自这里（计数 = 实际参与渲染的神经元数）
export interface BrainGroupRow {
  zh: string;
  node: string;
  count: number;
}

export const BRAIN_DATASET_LABEL: string = 'MaleCNS v1.0 雄性全中枢 (Janelia 2026)';

export const BRAIN_GROUPS: BrainGroupRow[] = [
  { zh: '视觉', node: 'brain_optic', count: 103246 },
  { zh: '感觉', node: 'brain_sensory', count: 12155 },
  { zh: '中央', node: 'brain_central', count: 46638 },
  { zh: '运动', node: 'brain_motor', count: 2775 },
  { zh: '内分泌', node: 'brain_endocrine', count: 94 },
];
