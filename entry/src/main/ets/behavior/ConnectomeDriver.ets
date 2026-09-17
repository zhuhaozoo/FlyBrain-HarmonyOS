// M3：连接组仿真驱动器（主线程）。
// 职责：读取 rawfile/connectome.bin（完整连接组），启动 BrainWorker 运行 LIF 仿真；
//       把 App 事件（食物/触碰/风/光照/内驱力）映射为对真实感觉神经群的持续刺激；
//       把运动群放电汇总为行为累积量。
//
// ⚠️ 群号不硬编码：刺激/读取目标全部经 NeuronGroups.findGroupByCode 按 **code（稳定契约）**
//    解析，群表本体来自生成文件 NeuronGroupsTable.ets（tools/gen_neuron_groups.mjs）。
//    升级数据集（FAFB → MaleCNS 全中枢）时只换数据与生成表，本文件无需改动；
//    MaleCNS 下腿/翅/下行群将首次拥有真实神经元，6 路调制自动生效。
//    群映射语义沿用 flybrain 项目（MIT）neuron_meta.json / sim-worker.js。
import { worker, MessageEvents, ErrorEvent } from '@kit.ArkTS';
import { common } from '@kit.AbilityKit';
import { datasetLabel, findGroupByCode, groupNeurons, groupOffsetOf } from './NeuronGroups';

// 关键功能群 code（稳定契约：跨数据集不变的只有 code，群号运行时解析）
const CODE_VIS_R1R6 = 'VIS_R1R6';
const CODE_VIS_ME = 'VIS_ME';
const CODE_VIS_LO = 'VIS_LO';
const CODE_VIS_LPTC = 'VIS_LPTC';
const CODE_OLF_FOOD = 'OLF_ORN_FOOD';
const CODE_OLF_DANGER = 'OLF_ORN_DANGER';
const CODE_MECH_BRISTLE = 'MECH_BRISTLE';
const CODE_MECH_JO = 'MECH_JO';
const CODE_DRIVE_HUNGER = 'DRIVE_HUNGER';
const CODE_DRIVE_FATIGUE = 'DRIVE_FATIGUE';
const CODE_VNC_CPG = 'VNC_CPG';
const CODE_MN_PROBOSCIS = 'MN_PROBOSCIS';
const CODE_MN_HEAD = 'MN_HEAD';
const CODE_MN_ABDOMEN = 'MN_ABDOMEN';
// MaleCNS 升级后新启用的群（FAFB 下神经元数为 0，读数恒 0，无害）
const CODE_MN_LEG_L = ['MN_LEG_L1', 'MN_LEG_L2', 'MN_LEG_L3'];
const CODE_MN_LEG_R = ['MN_LEG_R1', 'MN_LEG_R2', 'MN_LEG_R3'];
const CODE_MN_WING = ['MN_WING_L', 'MN_WING_R'];

// 行为累积量（EMA 平滑后的放电折算）+ 仿真运行统计
export class ConnectomeDrive {
  public walk: number = 0;
  public feed: number = 0;
  public groom: number = 0;
  public startle: number = 0;
  public turn: number = 0;    // 左右腿群放电差（+偏左 / −偏右）：升级 MaleCNS 后才有真实读数
  public wing: number = 0;    // 翅运动群放电合计 → 振翅意图
  public spikesPerSec: number = 0;
  public ready: boolean = false;
  public running: boolean = false;
  public avgTickMs: number = 0;
  public activeGroups: number = 0;
  public totalGroups: number = 0;
  public neurons: number = 0;
  public edges: number = 0;
  public dataset: string = '';   // 数据集中文名（来自生成群表，UI 口径显示用）

  // 各功能群的放电率（次/秒），下标即群号；用于大脑状态小窗逐个列出活跃脑区
  public groupRates: number[] = [];
}

// 全进程共享的 rawfile fd（getRawFd 只调一次；重复获取/关闭会互相失效）
export class SharedRawFd {
  public fd: number = 0;
  public offset: number = 0;
  public length: number = 0;
}

export class ConnectomeDriver {
  private workerInst: worker.ThreadWorker | null = null;
  private refreshTimer: number = -1;
  private envFood: boolean = false;
  private envLight: number = 1;
  private envHunger: number = 0;
  private envFatigue: number = 0;
  private emaWalk = 0;
  private emaFeed = 0;
  private emaGroom = 0;
  private emaStartle = 0;
  private emaTurn = 0;
  private emaWing = 0;
  private emaSpikes = 0;
  private drive: ConnectomeDrive = new ConnectomeDrive();
  static rawFds: Map<string, SharedRawFd> = new Map<string, SharedRawFd>();
  private modeFull: boolean = false;
  // 逐群放电累积（每个 tick 累加一次，取用时换算成"次/秒"并清空）
  private groupAcc: number[] = [];
  private groupTicks: number = 0;
  // code → 群号解析缓存（code 是稳定契约；未命中的 code 返回 -1，全部调用点都会跳过）
  private codeIds: Map<string, number> = new Map<string, number>();

  isRunning(): boolean {
    return this.workerInst !== null;
  }

  isReady(): boolean {
    return this.drive.ready;
  }

  private readyWaiters: (() => void)[] = [];

  // 等待该驱动器的连接组就绪（完整连接组 2500 万边的 CSR 峰值内存不小，
  // 多驱动器必须"上一个就绪再加载下一个"，避免峰值叠加触发系统杀进程）
  waitReady(timeoutMs: number): Promise<boolean> {
    if (this.drive.ready) {
      return Promise.resolve(true);
    }
    return new Promise<boolean>((resolve) => {
      let done = false;
      const finish = (v: boolean) => {
        if (!done) {
          done = true;
          resolve(v);
        }
      };
      this.readyWaiters.push((): void => finish(true));
      setTimeout((): void => finish(this.drive.ready), timeoutMs);
    });
  }

  getDrive(): ConnectomeDrive {
    return this.drive;
  }

  // 取各组放电率（次/秒）并重置累积窗口；窗口内无数据时返回上一次结果。
  // worker 的 tick 为 10Hz，故实耗秒数 = tick 数 × 0.1。
  takeGroupRates(): number[] {
    if (this.groupTicks > 0 && this.groupAcc.length > 0) {
      const secs = Math.max(0.001, this.groupTicks * 0.1);
      const out: number[] = [];
      for (let i = 0; i < this.groupAcc.length; i++) {
        out.push(this.groupAcc[i] / secs);
        this.groupAcc[i] = 0;
      }
      this.drive.groupRates = out;
      this.groupTicks = 0;
    }
    return this.drive.groupRates;
  }

  // 初始化并启动（读取连接组，需要数秒）
  async start(context: common.UIAbilityContext, full: boolean): Promise<boolean> {
    if (this.workerInst !== null) {
      return true;
    }
    this.modeFull = full;
    try {
      // v7.1：48MB 级 rawfile 的读取绝不能在主线程做（读入即阻塞，超 3s 会被系统
      // 判定 THREAD_BLOCK 冻结强杀）。主线程只取 rawfile 的 fd/offset/length（元数据），
      // 由 Worker 用 fs.readSync 分块读入并在 Worker 内完成解析。
      // 实测 getRawFd 重复获取同一文件会让先前 fd 失效（13900008）—— 因此每个文件全进程
      // 只取一次，按文件名缓存，所有 BrainWorker 共享（Worker 侧不 close，随进程存活）。
      // Lite 与全仿真是两个不同的 rawfile，各自的 fd 互不影响。
      const rawName = full ? 'connectome_full.bin' : 'connectome.bin';
      let fdInfo = ConnectomeDriver.rawFds.get(rawName);
      if (fdInfo === undefined) {
        const got = await context.resourceManager.getRawFd(rawName);
        fdInfo = new SharedRawFd();
        fdInfo.fd = got.fd;
        fdInfo.offset = got.offset;
        fdInfo.length = got.length;
        ConnectomeDriver.rawFds.set(rawName, fdInfo);
      }
      const tw: worker.ThreadWorker = new worker.ThreadWorker('entry/ets/worker/BrainWorker.ets');
      this.workerInst = tw;
      tw.onmessage = (e: MessageEvents) => {
        this.onWorkerMessage(e);
      };
      tw.onerror = (err: ErrorEvent) => {
        console.error(`[FlyBrain-C] worker error: ${err.message}`);
      };
      tw.postMessage({
        type: 'init', fd: fdInfo.fd, offset: fdInfo.offset, length: fdInfo.length,
      });
      return true;
    } catch (err) {
      console.error(`[FlyBrain-C] start failed: ${JSON.stringify(err)}`);
      this.workerInst = null;
      return false;
    }
  }

  stop(): void {
    if (this.refreshTimer >= 0) {
      clearInterval(this.refreshTimer);
      this.refreshTimer = -1;
    }
    if (this.workerInst !== null) {
      (this.workerInst as worker.ThreadWorker).postMessage({ type: 'stop' });
      (this.workerInst as worker.ThreadWorker).terminate();
      this.workerInst = null;
    }
    this.drive = new ConnectomeDrive();
    const waiters = this.readyWaiters;
    this.readyWaiters = [];
    for (const w of waiters) {
      w();
    }
    this.emaWalk = 0;
    this.emaFeed = 0;
    this.emaGroom = 0;
    this.emaStartle = 0;
    this.emaTurn = 0;
    this.emaWing = 0;
    this.emaSpikes = 0;
  }

  // ---- 环境状态（每秒刷新为持续刺激）----
  setEnvironment(foodNear: boolean, lightLevel: number, hunger: number, fatigue: number): void {
    this.envFood = foodNear;
    this.envLight = lightLevel;
    this.envHunger = hunger;
    this.envFatigue = fatigue;
  }

  // 一次性强刺激：触碰
  joltTouch(): void {
    this.stimulateGroup(this.gid(CODE_MECH_BRISTLE), 60, 2.0);
    this.stimulateGroup(this.gid(CODE_OLF_DANGER), 30, 1.5);
  }

  // 一次性强刺激：风
  joltWind(): void {
    this.stimulateGroup(this.gid(CODE_MECH_JO), 50, 1.8);
  }

  // code → 群号（带缓存）
  private gid(code: string): number {
    const cached = this.codeIds.get(code);
    if (cached !== undefined) {
      return cached;
    }
    const id = findGroupByCode(code);
    this.codeIds.set(code, id);
    return id;
  }

  private stimulateGroup(group: number, count: number, intensity: number): void {
    if (this.workerInst === null || group < 0 || groupNeurons(group) <= 0) {
      return;
    }
    const start = groupOffsetOf(group);
    const size = groupNeurons(group);
    const indices: number[] = [];
    const intensities: number[] = [];
    const n = Math.min(count, size);
    for (let k = 0; k < n; k++) {
      indices.push(start + Math.floor(Math.random() * size));
      intensities.push(intensity);
    }
    (this.workerInst as worker.ThreadWorker).postMessage({ type: 'stimulate', indices, intensities });
  }

  private refreshSustained(): void {
    if (this.workerInst === null) {
      return;
    }
    const indices: number[] = [];
    const intensities: number[] = [];
    // 光照 → 视觉群持续刺激
    if (this.envLight > 0) {
      const per = this.envLight >= 1 ? 25 : 10;
      this.pushRandom(indices, intensities, this.gid(CODE_VIS_R1R6), per, 0.7);
      this.pushRandom(indices, intensities, this.gid(CODE_VIS_ME), per, 0.7);
      if (this.envLight >= 1) {
        this.pushRandom(indices, intensities, this.gid(CODE_VIS_LO), per, 0.7);
        this.pushRandom(indices, intensities, this.gid(CODE_VIS_LPTC), per, 0.7);
      }
    }
    // 食物气味 → 嗅觉食物受体群
    if (this.envFood) {
      this.pushRandom(indices, intensities, this.gid(CODE_OLF_FOOD), 30, 1.0);
    }
    // 内驱力 → 驱力群
    if (this.envHunger > 0.6) {
      this.pushRandom(indices, intensities, this.gid(CODE_DRIVE_HUNGER), 8, 0.8);
    }
    if (this.envFatigue > 0.6) {
      this.pushRandom(indices, intensities, this.gid(CODE_DRIVE_FATIGUE), 6, 0.7);
    }
    (this.workerInst as worker.ThreadWorker).postMessage({ type: 'setStimulusState', indices, intensities });
  }

  private pushRandom(indices: number[], intensities: number[], group: number, count: number,
    intensity: number): void {
    const size = groupNeurons(group);
    if (group < 0 || size <= 0) {
      return;
    }
    const offset = groupOffsetOf(group);
    const n = Math.min(count, size);
    for (let k = 0; k < n; k++) {
      indices.push(offset + Math.floor(Math.random() * size));
      intensities.push(intensity * (0.7 + Math.random() * 0.6));
    }
  }

  private onWorkerMessage(e: MessageEvents): void {
    const msg = e.data as Record<string, Object>;
    const type = msg.type as string;
    if (type === 'ready') {
      console.info(`[FlyBrain-C] ready neurons=${msg.neurons} edges=${msg.edges} dataset=${datasetLabel()}`);
      const waiters = this.readyWaiters;
      this.readyWaiters = [];
      for (const w of waiters) {
        w();
      }
      this.drive.ready = true;
      this.drive.running = true;
      this.drive.neurons = msg.neurons as number;
      this.drive.edges = msg.edges as number;
      this.drive.dataset = datasetLabel() + (this.modeFull ? ' · 全仿真' : ' · Lite');
      this.refreshSustained();
      if (this.refreshTimer < 0) {
        this.refreshTimer = setInterval(() => this.refreshSustained(), 1000);
      }
      (this.workerInst as worker.ThreadWorker).postMessage({ type: 'start' });
    } else if (type === 'tick') {
      const spikes = msg.groupSpikes as number[];
      const fired = msg.fired as number;
      const k = 0.25; // EMA 系数（10Hz tick）
      // 步行：步态节律 + 三个腿运动群（FAFB 下腿群为 0，读数与旧口径一致）
      this.emaWalk += (this.g(spikeOf(spikes, this.gid(CODE_VNC_CPG))) +
        this.g(this.sumGroup(spikes, CODE_MN_LEG_L)) + this.g(this.sumGroup(spikes, CODE_MN_LEG_R)) -
        this.emaWalk) * k;
      this.emaFeed += (this.g(spikeOf(spikes, this.gid(CODE_MN_PROBOSCIS))) - this.emaFeed) * k;
      this.emaGroom += (this.g(spikeOf(spikes, this.gid(CODE_MN_HEAD)) +
        spikeOf(spikes, this.gid(CODE_MN_ABDOMEN))) - this.emaGroom) * k;
      this.emaStartle += (this.g(spikeOf(spikes, this.gid(CODE_MECH_BRISTLE))) - this.emaStartle) * k * 2;
      // 升级通道（MaleCNS 后有真实读数；FAFB 下恒 0）：左右腿差 → 转向，翅群 → 振翅意图
      this.emaTurn += (this.g(this.sumGroup(spikes, CODE_MN_LEG_L)) -
        this.g(this.sumGroup(spikes, CODE_MN_LEG_R)) - this.emaTurn) * k;
      this.emaWing += (this.g(this.sumGroup(spikes, CODE_MN_WING)) - this.emaWing) * k;
      this.drive.walk = this.emaWalk;
      this.drive.feed = this.emaFeed;
      this.drive.groom = this.emaGroom;
      this.drive.startle = this.emaStartle;
      this.drive.turn = this.emaTurn;
      this.drive.wing = this.emaWing;
      // 放电率用 EMA 平滑：单 tick 放电数剧烈波动，直接 ×10 会显示成 0 或几百
      this.emaSpikes += (fired * 10 - this.emaSpikes) * 0.15;
      this.drive.spikesPerSec = this.emaSpikes;
      // 逐群累积（用于大脑状态小窗的"活跃脑区"明细）
      if (this.groupAcc.length !== spikes.length) {
        const acc: number[] = [];
        for (let i = 0; i < spikes.length; i++) {
          acc.push(0);
        }
        this.groupAcc = acc;
        this.groupTicks = 0;
      }
      for (let i = 0; i < spikes.length; i++) {
        this.groupAcc[i] += spikes[i];
      }
      this.groupTicks++;
    } else if (type === 'stats') {
      this.drive.avgTickMs = msg.avgTickMs as number;
      this.drive.activeGroups = msg.activeGroups as number;
      this.drive.totalGroups = msg.totalGroups as number;
      console.info(`[FlyBrain-C] tick=${(msg.avgTickMs as number).toFixed(1)}ms ` +
        `fired=${msg.avgFired} activeGroups=${msg.activeGroups}/${msg.totalGroups}`);
    } else if (type === 'error') {
      console.error(`[FlyBrain-C] worker error: ${msg.message}`);
    }
  }

  // 多个 code 群的放电合计（code 未命中/群为 0 时按 0 计）
  private sumGroup(spikes: number[], codes: string[]): number {
    let sum = 0;
    for (let i = 0; i < codes.length; i++) {
      sum += spikeOf(spikes, this.gid(codes[i]));
    }
    return sum;
  }

  private g(v: number): number {
    return v;
  }
}

function spikeOf(spikes: number[], group: number): number {
  return group >= 0 && group < spikes.length ? spikes[group] : 0;
}
