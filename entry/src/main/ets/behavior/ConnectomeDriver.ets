// M3：连接组仿真驱动器（主线程）。
// 职责：读取 rawfile/connectome.bin（FlyWire FAFB v783 完整连接组，31MB），
//       启动 BrainWorker 运行 LIF 仿真；把 App 事件（食物/触碰/风/光照/内驱力）
//       映射为对真实感觉神经群的持续刺激；把运动群放电汇总为行为累积量。
// 群编号与刺激映射语义沿用 flybrain 项目（MIT）neuron_meta.json / sim-worker.js。
import { worker, MessageEvents, ErrorEvent } from '@kit.ArkTS';
import { common } from '@kit.AbilityKit';

// neuron_meta.json 的 group_sizes（63 群，神经元按群连续编号）
const GROUP_SIZES: number[] = [
  11487, 0, 82318, 1793, 0, 1907, 1851, 430, 453, 699, 1927, 879, 0, 0, 49, 54, 0, 5177, 0, 96,
  0, 335, 0, 559, 0, 428, 1244, 822, 611, 34, 0, 0, 214, 65, 131, 3581, 0, 46, 0, 34, 0, 0, 0, 0,
  0, 0, 0, 4, 0, 0, 0, 0, 0, 0, 0, 0, 24, 40, 8, 0, 21955, 0, 0,
];

// 关键群编号（见 neuron_meta.json groups）
const G_VIS_R1R6 = 0;
const G_VIS_ME = 2;
const G_VIS_LO = 3;
const G_VIS_LPTC = 5;
const G_OLF_FOOD = 6;
const G_OLF_DANGER = 7;
const G_MECH_BRISTLE = 10;
const G_MECH_JO = 11;
const G_DRIVE_HUNGER = 37;
const G_DRIVE_FATIGUE = 39;
const G_VNC_CPG = 47;
const G_MN_PROBOSCIS = 56;
const G_MN_HEAD = 57;
const G_MN_ABDOMEN = 58;

// 行为累积量（EMA 平滑后的放电折算）+ 仿真运行统计
export class ConnectomeDrive {
  public walk: number = 0;
  public feed: number = 0;
  public groom: number = 0;
  public startle: number = 0;
  public spikesPerSec: number = 0;
  public ready: boolean = false;
  public running: boolean = false;
  public avgTickMs: number = 0;
  public activeGroups: number = 0;
  public totalGroups: number = 61;
  public neurons: number = 139255;
  public edges: number = 2698236;
}

export class ConnectomeDriver {
  private workerInst: worker.ThreadWorker | null = null;
  private groupOffsets: number[] = [];
  private refreshTimer: number = -1;
  private envFood: boolean = false;
  private envLight: number = 1;
  private envHunger: number = 0;
  private envFatigue: number = 0;
  private emaWalk = 0;
  private emaFeed = 0;
  private emaGroom = 0;
  private emaStartle = 0;
  private emaSpikes = 0;
  private drive: ConnectomeDrive = new ConnectomeDrive();

  isRunning(): boolean {
    return this.workerInst !== null;
  }

  isReady(): boolean {
    return this.drive.ready;
  }

  getDrive(): ConnectomeDrive {
    return this.drive;
  }

  // 初始化并启动（读取 31MB 连接组，需要数秒）
  async start(context: common.UIAbilityContext): Promise<boolean> {
    if (this.workerInst !== null) {
      return true;
    }
    try {
      const u8 = await context.resourceManager.getRawFileContent('connectome.bin');
      // Uint8Array 可能只是大 buffer 的一段视图，复制出精确的 ArrayBuffer
      const ab: ArrayBuffer = u8.buffer.slice(u8.byteOffset, u8.byteOffset + u8.byteLength);
      const tw: worker.ThreadWorker = new worker.ThreadWorker('entry/ets/worker/BrainWorker.ets');
      this.workerInst = tw;
      tw.onmessage = (e: MessageEvents) => {
        this.onWorkerMessage(e);
      };
      tw.onerror = (err: ErrorEvent) => {
        console.error(`[FlyBrain-C] worker error: ${err.message}`);
      };
      // 用转移（transfer）方式传 31MB buffer，避免序列化拷贝
      const transfer: ArrayBuffer[] = [ab];
      tw.postMessage({ type: 'init', buffer: ab }, transfer);
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
    this.emaWalk = 0;
    this.emaFeed = 0;
    this.emaGroom = 0;
    this.emaStartle = 0;
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
    this.stimulateGroup(G_MECH_BRISTLE, 60, 2.0);
    this.stimulateGroup(G_OLF_DANGER, 30, 1.5);
  }

  // 一次性强刺激：风
  joltWind(): void {
    this.stimulateGroup(G_MECH_JO, 50, 1.8);
  }

  private stimulateGroup(group: number, count: number, intensity: number): void {
    if (this.workerInst === null || group >= GROUP_SIZES.length || GROUP_SIZES[group] <= 0) {
      return;
    }
    const start = this.groupOffsetOf(group);
    const size = GROUP_SIZES[group];
    const indices: number[] = [];
    const intensities: number[] = [];
    const n = Math.min(count, size);
    for (let k = 0; k < n; k++) {
      indices.push(start + Math.floor(Math.random() * size));
      intensities.push(intensity);
    }
    (this.workerInst as worker.ThreadWorker).postMessage({ type: 'stimulate', indices, intensities });
  }

  private groupOffsetOf(group: number): number {
    if (this.groupOffsets.length === 0) {
      let acc = 0;
      for (let i = 0; i < GROUP_SIZES.length; i++) {
        this.groupOffsets.push(acc);
        acc += GROUP_SIZES[i];
      }
    }
    return this.groupOffsets[group];
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
      this.pushRandom(indices, intensities, G_VIS_R1R6, per, 0.7);
      this.pushRandom(indices, intensities, G_VIS_ME, per, 0.7);
      if (this.envLight >= 1) {
        this.pushRandom(indices, intensities, G_VIS_LO, per, 0.7);
        this.pushRandom(indices, intensities, G_VIS_LPTC, per, 0.7);
      }
    }
    // 食物气味 → 嗅觉食物受体群
    if (this.envFood) {
      this.pushRandom(indices, intensities, G_OLF_FOOD, 30, 1.0);
    }
    // 内驱力 → 驱力群
    if (this.envHunger > 0.6) {
      this.pushRandom(indices, intensities, G_DRIVE_HUNGER, 8, 0.8);
    }
    if (this.envFatigue > 0.6) {
      this.pushRandom(indices, intensities, G_DRIVE_FATIGUE, 6, 0.7);
    }
    (this.workerInst as worker.ThreadWorker).postMessage({ type: 'setStimulusState', indices, intensities });
  }

  private pushRandom(indices: number[], intensities: number[], group: number, count: number,
    intensity: number): void {
    const size = GROUP_SIZES[group];
    if (size <= 0) {
      return;
    }
    const offset = this.groupOffsetOf(group);
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
      console.info(`[FlyBrain-C] ready neurons=${msg.neurons} edges=${msg.edges}`);
      this.drive.ready = true;
      this.drive.running = true;
      this.drive.neurons = msg.neurons as number;
      this.drive.edges = msg.edges as number;
      this.refreshSustained();
      if (this.refreshTimer < 0) {
        this.refreshTimer = setInterval(() => this.refreshSustained(), 1000);
      }
      (this.workerInst as worker.ThreadWorker).postMessage({ type: 'start' });
    } else if (type === 'tick') {
      const spikes = msg.groupSpikes as number[];
      const fired = msg.fired as number;
      const k = 0.25; // EMA 系数（10Hz tick）
      this.emaWalk += (this.g(spikeOf(spikes, G_VNC_CPG)) - this.emaWalk) * k;
      this.emaFeed += (this.g(spikeOf(spikes, G_MN_PROBOSCIS)) - this.emaFeed) * k;
      this.emaGroom += (this.g(spikeOf(spikes, G_MN_HEAD) + spikeOf(spikes, G_MN_ABDOMEN)) - this.emaGroom) * k;
      this.emaStartle += (this.g(spikeOf(spikes, G_MECH_BRISTLE)) - this.emaStartle) * k * 2;
      this.drive.walk = this.emaWalk;
      this.drive.feed = this.emaFeed;
      this.drive.groom = this.emaGroom;
      this.drive.startle = this.emaStartle;
      // 放电率用 EMA 平滑：单 tick 放电数在 0~90 间剧烈波动，直接 ×10 会显示成 0 或几百
      this.emaSpikes += (fired * 10 - this.emaSpikes) * 0.15;
      this.drive.spikesPerSec = this.emaSpikes;
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

  private g(v: number): number {
    return v;
  }
}

function spikeOf(spikes: number[], group: number): number {
  return group >= 0 && group < spikes.length ? spikes[group] : 0;
}
