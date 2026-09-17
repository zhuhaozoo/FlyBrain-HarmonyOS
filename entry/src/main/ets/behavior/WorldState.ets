// 共享世界状态（M5）：光照档位、聚光点、风——这些本质是"全世界只有一份"的环境量，
// M4 及之前存在每个 FlyBrain 里，多果蝇后必须共享（一阵风吹到所有果蝇、光斑只有一个）。
// 纯逻辑类，不依赖任何 3D/渲染 API。
import { FlyConfig } from './FlyConfig';

export class WorldState {
  private cfg: FlyConfig;
  private lightLevel: number = 1;            // 0 黑暗 / 0.5 昏暗 / 1 明亮
  private spotActive: boolean = false;
  private spotX: number = 0;
  private spotZ: number = 0;
  private windTimer: number = 0;
  private windStrength: number = 0;
  private gustId: number = 0;                // 每次阵风自增：果蝇据此判断"这是新的一阵风"

  constructor(cfg: FlyConfig) {
    this.cfg = cfg;
  }

  // 光照档位：0 黑暗 / 0.5 昏暗 / 1 明亮（夜间由页面压到 0）
  setLightLevel(v: number): void {
    this.lightLevel = v;
  }

  getLightLevel(): number {
    return this.lightLevel;
  }

  // 移动/开关聚光点
  setLightSpot(x: number, z: number, on: boolean): void {
    this.spotActive = on;
    if (on) {
      const r = Math.hypot(x, z);
      const k = r > this.cfg.arenaRadius ? this.cfg.arenaRadius / r : 1;
      this.spotX = x * k;
      this.spotZ = z * k;
    }
  }

  isSpotActive(): boolean {
    return this.spotActive;
  }

  getSpotX(): number {
    return this.spotX;
  }

  getSpotZ(): number {
    return this.spotZ;
  }

  // 一阵风（世界级：所有果蝇感受到同一阵）
  gust(): void {
    this.windTimer = this.cfg.windDuration;
    this.windStrength = 0.3 + Math.random() * 0.55;
    this.gustId++;
  }

  getWindStrength(): number {
    return this.windTimer > 0 ? this.windStrength : 0;
  }

  // 强风是否应触发惊吓（弱风趴伏、强风惊吓的分界）
  isGustStrong(): boolean {
    return this.windStrength >= this.cfg.braceWindMax;
  }

  // 阵风编号（FlyBrain 记住上次处理到的编号，新编号才加一次恐惧）
  getGustId(): number {
    return this.gustId;
  }

  // 每帧推进风力计时（由 FlyAgents 调一次）
  update(dt: number): void {
    if (this.windTimer > 0) {
      this.windTimer -= dt;
    }
  }
}
