// M3：端侧 LIF 神经仿真 Worker。
// 移植自 flybrain 项目 js/sim-worker.js（MIT License）：
// 在完整果蝇连接组（139,255 神经元 / 2,698,236 连接，FlyWire FAFB v783）
// 上运行泄漏积分放电（LIF）模型，按功能群门控加速（只更新活跃群）。
//
// 二进制格式（小端，见 flybrain sim-worker.js 头注释）：
//   uint32 neuron_count, uint32 edge_count,
//   edge_count x (uint32 pre, uint32 post, float32 weight)  按 pre 排序,
//   neuron_count x (uint8 region_type, uint16 group_id)
//
// 消息协议：
//   主线程 -> Worker: init(buffer) / start / stop / reset /
//                     setStimulusState{indices,intensities} / stimulate{indices,intensities}
//   Worker -> 主线程: ready{N,edges} / tick{groupSpikes,fired} / stats{...} / error{msg}
import { worker, ThreadWorkerGlobalScope, MessageEvents } from '@kit.ArkTS';
import { fileIo as fs } from '@kit.CoreFileKit';

const workerPort: ThreadWorkerGlobalScope = worker.workerPort;

const LEAK_RATE: number = 0.95;
const THRESHOLD: number = 1.0;
const REFRACTORY_PERIOD: number = 3;
const WEIGHT_SCALE: number = 0.15;
const TICK_MS: number = 100; // 10 Hz，与原版一致
const COOLDOWN_TICKS: number = 20;
const STATS_INTERVAL: number = 20;

let N = 0;
let edgeCount = 0;
let V: Float32Array = new Float32Array(0);
let fired: Uint8Array = new Uint8Array(0);
let refractory: Uint8Array = new Uint8Array(0);
let rowPtr: Uint32Array = new Uint32Array(0);
let colIdx: Uint32Array = new Uint32Array(0);
let values: Float32Array = new Float32Array(0);
let groupId: Uint16Array = new Uint16Array(0);

let numGroups = 0;
let groupOffset: Uint32Array = new Uint32Array(0);
let groupActive: Uint8Array = new Uint8Array(0);
let groupCooldown: Uint8Array = new Uint8Array(0);
let groupRecvInput: Uint8Array = new Uint8Array(0);
let groupFired: Uint8Array = new Uint8Array(0);
let groupStimulated: Uint8Array = new Uint8Array(0);

let sustainedIndices: number[] = [];
let sustainedIntensities: number[] = [];
let running = false;
let timerId = -1;
let tickCount = 0;
let tickTimeSum = 0;
let tickSamples = 0;
let firedSum = 0;

interface InitMessage {
  type: string;
  fd: number;
  offset: number;
  length: number;
}
interface StimMessage {
  type: string;
  indices: number[];
  intensities: number[];
}

function parseBinary(buffer: ArrayBuffer): void {
  const view = new DataView(buffer);
  N = view.getUint32(0, true);
  edgeCount = view.getUint32(4, true);
  const edgeOffset = 8;
  const metaOffset = edgeOffset + edgeCount * 12;

  rowPtr = new Uint32Array(N + 1);
  colIdx = new Uint32Array(edgeCount);
  values = new Float32Array(edgeCount);

  // 计数每个神经元的出边
  for (let e = 0; e < edgeCount; e++) {
    const pre = view.getUint32(edgeOffset + e * 12, true);
    rowPtr[pre + 1]++;
  }
  for (let i = 1; i <= N; i++) {
    rowPtr[i] += rowPtr[i - 1];
  }

  // 填充 CSR 并归一化权重
  let maxAbsW = 0;
  for (let e = 0; e < edgeCount; e++) {
    const base = edgeOffset + e * 12;
    colIdx[e] = view.getUint32(base + 4, true);
    values[e] = view.getFloat32(base + 8, true);
    const absW = values[e] < 0 ? -values[e] : values[e];
    if (absW > maxAbsW) {
      maxAbsW = absW;
    }
  }
  if (maxAbsW > 0) {
    for (let e = 0; e < edgeCount; e++) {
      values[e] = values[e] / maxAbsW * WEIGHT_SCALE;
    }
  }

  // 每神经元元数据
  const gid = new Uint16Array(N);
  for (let i = 0; i < N; i++) {
    gid[i] = view.getUint16(metaOffset + i * 3 + 1, true);
  }
  groupId = gid;

  V = new Float32Array(N);
  fired = new Uint8Array(N);
  refractory = new Uint8Array(N);
  tickCount = 0;
}

// 按群重排（原版 buildGroupStructures）：同群神经元连续存放，门控更新
function buildGroupStructures(): void {
  numGroups = 0;
  for (let i = 0; i < N; i++) {
    if (groupId[i] >= numGroups) {
      numGroups = groupId[i] + 1;
    }
  }
  const counts = new Uint32Array(numGroups);
  for (let i = 0; i < N; i++) {
    counts[groupId[i]]++;
  }
  groupOffset = new Uint32Array(numGroups + 1);
  for (let g = 0; g < numGroups; g++) {
    groupOffset[g + 1] = groupOffset[g] + counts[g];
  }
  const sortedByGroup = new Uint32Array(N);
  const writePos = new Uint32Array(numGroups);
  for (let g = 0; g < numGroups; g++) {
    writePos[g] = groupOffset[g];
  }
  for (let i = 0; i < N; i++) {
    const g = groupId[i];
    sortedByGroup[writePos[g]++] = i;
  }
  const o2s = new Uint32Array(N);
  for (let s = 0; s < N; s++) {
    o2s[sortedByGroup[s]] = s;
  }
  const newRowPtr = new Uint32Array(N + 1);
  for (let s = 0; s < N; s++) {
    const o = sortedByGroup[s];
    newRowPtr[s + 1] = rowPtr[o + 1] - rowPtr[o];
  }
  for (let s = 1; s <= N; s++) {
    newRowPtr[s] += newRowPtr[s - 1];
  }
  const newColIdx = new Uint32Array(edgeCount);
  const newValues = new Float32Array(edgeCount);
  for (let s = 0; s < N; s++) {
    const o = sortedByGroup[s];
    let wp = newRowPtr[s];
    for (let j = rowPtr[o]; j < rowPtr[o + 1]; j++) {
      newColIdx[wp] = o2s[colIdx[j]];
      newValues[wp] = values[j];
      wp++;
    }
  }
  rowPtr = newRowPtr;
  colIdx = newColIdx;
  values = newValues;
  const newGroupId = new Uint16Array(N);
  for (let s = 0; s < N; s++) {
    newGroupId[s] = groupId[sortedByGroup[s]];
  }
  groupId = newGroupId;

  groupActive = new Uint8Array(numGroups);
  groupCooldown = new Uint8Array(numGroups);
  groupRecvInput = new Uint8Array(numGroups);
  groupFired = new Uint8Array(numGroups);
  groupStimulated = new Uint8Array(numGroups);
}

function tick(): void {
  const t0 = Date.now();
  let firedNeurons = 0;
  const groupSpikes = new Uint16Array(numGroups);

  groupRecvInput.fill(0);
  groupFired.fill(0);
  groupStimulated.fill(0);

  // 持续刺激激活所在群
  for (let k = 0; k < sustainedIndices.length; k++) {
    const si = sustainedIndices[k];
    if (si < N) {
      const g = groupId[si];
      groupStimulated[g] = 1;
      if (groupActive[g] === 0) {
        groupActive[g] = 1;
        groupCooldown[g] = COOLDOWN_TICKS;
      }
    }
  }

  // 1) 活跃群：泄漏 + 不应期衰减
  for (let g = 0; g < numGroups; g++) {
    if (groupActive[g] === 0) {
      continue;
    }
    for (let i = groupOffset[g]; i < groupOffset[g + 1]; i++) {
      if (refractory[i] > 0) {
        refractory[i]--;
        V[i] = 0;
      } else {
        V[i] *= LEAK_RATE;
      }
    }
  }

  // 1.5) 施加持续刺激电流
  for (let k = 0; k < sustainedIndices.length; k++) {
    const si = sustainedIndices[k];
    if (si < N && refractory[si] === 0) {
      V[si] += sustainedIntensities[k];
    }
  }

  // 2) 已放电神经元沿 CSR 边传播
  for (let g = 0; g < numGroups; g++) {
    if (groupActive[g] === 0) {
      continue;
    }
    for (let i = groupOffset[g]; i < groupOffset[g + 1]; i++) {
      if (fired[i] === 0) {
        continue;
      }
      for (let j = rowPtr[i]; j < rowPtr[i + 1]; j++) {
        V[colIdx[j]] += values[j];
        groupRecvInput[groupId[colIdx[j]]] = 1;
      }
    }
  }

  // 收到突触输入的群激活
  for (let g = 0; g < numGroups; g++) {
    if (groupRecvInput[g] === 1 && groupActive[g] === 0) {
      groupActive[g] = 1;
      groupCooldown[g] = COOLDOWN_TICKS;
    }
  }

  // 3) 放电判定
  for (let g = 0; g < numGroups; g++) {
    if (groupActive[g] === 0) {
      continue;
    }
    for (let i = groupOffset[g]; i < groupOffset[g + 1]; i++) {
      fired[i] = 0;
      if (refractory[i] === 0 && V[i] >= THRESHOLD) {
        fired[i] = 1;
        V[i] = 0;
        refractory[i] = REFRACTORY_PERIOD;
        groupFired[g] = 1;
        groupSpikes[g]++;
        firedNeurons++;
      }
    }
  }

  // 群冷却
  for (let g = 0; g < numGroups; g++) {
    if (groupActive[g] === 0) {
      continue;
    }
    if (groupFired[g] === 1 || groupRecvInput[g] === 1 || groupStimulated[g] === 1) {
      groupCooldown[g] = COOLDOWN_TICKS;
    } else {
      groupCooldown[g]--;
      if (groupCooldown[g] <= 0) {
        groupActive[g] = 0;
        V.fill(0, groupOffset[g], groupOffset[g + 1]);
        fired.fill(0, groupOffset[g], groupOffset[g + 1]);
        refractory.fill(0, groupOffset[g], groupOffset[g + 1]);
      }
    }
  }

  // 汇报（转普通数组避免跨线程类型问题）
  const spikes: number[] = [];
  for (let g = 0; g < numGroups; g++) {
    spikes.push(groupSpikes[g]);
  }
  workerPort.postMessage({ type: 'tick', groupSpikes: spikes, fired: firedNeurons, tick: tickCount });
  tickCount++;
  firedSum += firedNeurons;

  const elapsed = Date.now() - t0;
  tickTimeSum += elapsed;
  tickSamples++;
  if (tickSamples >= STATS_INTERVAL) {
    let active = 0;
    for (let g = 0; g < numGroups; g++) {
      if (groupActive[g] === 1) {
        active++;
      }
    }
    workerPort.postMessage({
      type: 'stats',
      avgTickMs: tickTimeSum / tickSamples,
      avgFired: Math.round(firedSum / tickSamples),
      activeGroups: active,
      totalGroups: numGroups,
      totalNeurons: N,
      edges: edgeCount,
    });
    tickTimeSum = 0;
    tickSamples = 0;
    firedSum = 0;
  }
}

// 分块读取 rawfile（fs.readSync 只接受纯 ArrayBuffer，传 Uint8Array 视图报 EINVAL）。
// 注意：fd 是全进程共享的（多个 BrainWorker 用同一个），不在这里 close。
function nmfReadRawFile(fd: number, offset: number, length: number): ArrayBuffer {
  const buf = new ArrayBuffer(length);
  const dst = new Uint8Array(buf);
  let done = 0;
  const chunk = 4 * 1024 * 1024;
  while (done < length) {
    const n = Math.min(chunk, length - done);
    const chunkBuf = new ArrayBuffer(n);
    const got = fs.readSync(fd, chunkBuf, { offset: offset + done, length: n });
    if (got <= 0) {
      throw new Error('rawfile read short: ' + done + '/' + length);
    }
    dst.set(new Uint8Array(chunkBuf, 0, got), done);
    done += got;
  }
  return buf;
}

workerPort.onmessage = (e: MessageEvents) => {
  const msg = e.data as InitMessage | StimMessage;
  const t = msg.type;
  if (t === 'init') {
    try {
      // v7.1：rawfile 读取在 Worker 线程分块进行（主线程只传 fd/offset/length）。
      // 完整连接组 2500 万边时读取缓冲约 310MB —— 把读取封装成独立函数并内联传参，
      // parseBinary 返回后大 buffer 即可达回收条件，显著降低 buildGroupStructures
      // 二次重排（新旧 CSR 并存）时的内存峰值。
      const im = msg as InitMessage;
      parseBinary(nmfReadRawFile(im.fd, im.offset, im.length));
      buildGroupStructures();
      console.info(`[FlyBrain-W] ready N=${N} edges=${edgeCount} groups=${numGroups}`);
      workerPort.postMessage({ type: 'ready', neurons: N, edges: edgeCount, groups: numGroups });
    } catch (err) {
      console.error(`[FlyBrain-W] init failed: ${JSON.stringify(err)}`);
      workerPort.postMessage({ type: 'error', message: `${JSON.stringify(err)}` });
    }
  } else if (t === 'start') {
    if (N === 0) {
      return;
    }
    running = true;
    if (timerId < 0) {
      timerId = setInterval(tick, TICK_MS);
    }
  } else if (t === 'stop') {
    running = false;
    if (timerId >= 0) {
      clearInterval(timerId);
      timerId = -1;
    }
  } else if (t === 'setStimulusState') {
    const sm = msg as StimMessage;
    sustainedIndices = sm.indices;
    sustainedIntensities = sm.intensities;
  } else if (t === 'stimulate') {
    const sm = msg as StimMessage;
    for (let k = 0; k < sm.indices.length; k++) {
      const idx = sm.indices[k];
      if (idx < N) {
        V[idx] += sm.intensities[k];
        if (groupActive[groupId[idx]] === 0) {
          groupActive[groupId[idx]] = 1;
          groupCooldown[groupId[idx]] = COOLDOWN_TICKS;
        }
      }
    }
  } else if (t === 'reset') {
    V.fill(0);
    fired.fill(0);
    refractory.fill(0);
    sustainedIndices = [];
    sustainedIntensities = [];
    if (groupActive.length > 0) {
      groupActive.fill(0);
      groupCooldown.fill(0);
      groupRecvInput.fill(0);
      groupFired.fill(0);
      groupStimulated.fill(0);
    }
  }
};
