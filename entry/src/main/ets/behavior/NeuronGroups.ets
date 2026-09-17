// 神经功能群：名称表 + 查找工具。
//
// ⚠️ 群表本体在 NeuronGroupsTable.ets —— 由 tools/gen_neuron_groups.mjs 生成，
//    请勿手工编辑。升级数据集（如 MaleCNS 全中枢）时重跑生成器即可换表；
//    运行时的一切映射只认 **群 code（稳定契约）**，数字群号随数据集重排。
//    关键刺激/读取群的 14 个 code 跨数据集不变（升级迁移文档 §4.3）。
import { DATASET_LABEL, GROUP_ROWS } from './NeuronGroupsTable';

// 群表行（下标即群号）
const ROWS = GROUP_ROWS;

// 数据集中文名（UI 口径显示用，如「FAFB 雌性全脑 (FlyWire 2024)」）
export function datasetLabel(): string {
  return DATASET_LABEL;
}

// 群总数（含神经元数为 0 的占位群）
export function groupTotal(): number {
  return ROWS.length;
}

// 群号 → 中文名（越界时回退成 "群N"，避免 UI 出现空白）
export function groupLabel(id: number): string {
  if (id >= 0 && id < ROWS.length) {
    return ROWS[id].zh;
  }
  return `群${id}`;
}

// 群号 → 所属脑区
export function groupRegion(id: number): string {
  if (id >= 0 && id < ROWS.length) {
    return ROWS[id].region;
  }
  return '';
}

// 群号 → 神经元数（0 = 该数据集里此功能群没有神经元，运行时跳过刺激/读取）
export function groupNeurons(id: number): number {
  return id >= 0 && id < ROWS.length ? ROWS[id].count : 0;
}

// code → 群号（未命中返回 -1；调用方对 -1 一律跳过）
export function findGroupByCode(code: string): number {
  for (let i = 0; i < ROWS.length; i++) {
    if (ROWS[i].code === code) {
      return i;
    }
  }
  return -1;
}

// 群号前缀和（懒计算）：群在连接组二进制里的起始神经元下标
let offsets: number[] = [];

export function groupOffsetOf(id: number): number {
  if (offsets.length === 0) {
    let acc = 0;
    for (let i = 0; i < ROWS.length; i++) {
      offsets.push(acc);
      acc += ROWS[i].count;
    }
  }
  return id >= 0 && id < offsets.length ? offsets[id] : 0;
}
