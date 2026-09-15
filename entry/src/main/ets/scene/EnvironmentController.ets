// 环境控制器（M4）：昼夜循环、日月星、树木风摆、风线、河面涟漪。
//
// 职责边界：本类是**纯渲染层**，不碰行为逻辑。夜间语义（休息阈值、无趋光）由页面把
// 折算后的 lightLevel 交给 FlyBrain，这里只负责画面。
//
// 性能约定（设计文档 §5）：常态每帧只驱动必要的节点（太阳/月亮/树/水面微动 ≈ 12 个），
// 风线与涟漪这类特效节点**仅在阵风事件期间**才参与变换，其余时间保持隐藏。
import { Camera, Light, Node } from '@kit.ArkGraphics3D';
import { FlyConfig } from '../behavior/FlyConfig';
import { clamp, quatY, quatZ } from '../common/Math3D';

const DEG = Math.PI / 180;

// 昼夜关键帧（相位 0..1，0 = 日出）。关键帧之间线性插值。
// 时段占比：黎明 12% → 白天 50% → 黄昏 12% → 夜晚 26%
const PHASES: number[] = [0.00, 0.12, 0.62, 0.68, 0.74, 0.90, 1.00];
// 天空色（clearColor）
const SKY_R: number[] = [0.56, 0.53, 0.53, 1.00, 0.043, 0.043, 0.56];
const SKY_G: number[] = [0.65, 0.81, 0.81, 0.60, 0.063, 0.063, 0.65];
const SKY_B: number[] = [0.85, 0.92, 0.92, 0.35, 0.149, 0.149, 0.85];
// 平行光强度（倍率，相对基准强度）
const SUN_I: number[] = [0.40, 1.00, 1.00, 0.50, 0.15, 0.18, 0.40];
// 平行光颜色
const SUN_R: number[] = [1.00, 1.00, 1.00, 1.00, 0.55, 0.55, 1.00];
const SUN_G: number[] = [0.85, 0.97, 0.97, 0.70, 0.65, 0.65, 0.85];
const SUN_B: number[] = [0.70, 0.90, 0.90, 0.45, 0.95, 0.95, 0.70];

// 白天结束（日落）相位：日出→日落恰好扫过 180°，之后继续走完另外 180°（地平线以下）
const LIT_FRAC = 0.74;

// 3 棵树的摆动相位偏移（错开，避免整齐划一地摆）
const TREE_PHASE: number[] = [0, 2.1, 4.2];
// 6 条风线各自的车道（z 偏移）与起始延迟
const WIND_LANE_Z: number[] = [-2.1, -1.3, -0.5, 0.3, 1.1, 1.9];
const WIND_DELAY: number[] = [0, 0.10, 0.20, 0.30, 0.40, 0.50];
// 3 个涟漪在河流弧上的角度（落在弧带中段，靠近活动区一侧）与延迟
const RIPPLE_ANGLE: number[] = [38 * DEG, 62 * DEG, 86 * DEG];
const RIPPLE_DELAY: number[] = [0, 0.25, 0.50];
const RIPPLE_RADIUS = 5.6;   // 落在水带中间

const WIND_LINE_DURATION = 0.9;   // 单条风线横穿耗时
const RIPPLE_DURATION = 1.2;      // 单个涟漪扩散耗时

export class EnvironmentController {
  private cfg: FlyConfig;
  private light: Light | null = null;
  private camera: Camera | null = null;
  private nodes: Map<string, Node> = new Map<string, Node>();

  private t: number = 0.22;          // 昼夜相位（起始在白天，避免一进场景就是夜里）
  private userLightFactor: number = 1.0;
  private baseIntensity: number = -1;
  private gustT: number = -1;        // 本次阵风已进行的时间（<0 表示无阵风）
  private lastWind: number = 0;
  private riverY: number = 0.012;    // 河面基准高度（与生成脚本一致）
  private curSeg: number = 0;        // 当前所在关键帧区间（每帧算一次）
  private curK: number = 0;          // 区间内进度 0..1
  private deathDim: number = 1.0;    // 果蝇死亡时整体压暗（×0.9）
  private cycles: number = 0;        // 已完成的昼夜轮数（轻量成就用）
  private anim: number = 0;          // 独立动画时钟（秒）——不能复用昼夜相位，
                                     // 否则关闭昼夜循环后树摆/水波会一起冻住

  constructor(cfg: FlyConfig) {
    this.cfg = cfg;
  }

  attach(light: Light | null, camera: Camera | null): void {
    this.light = light;
    this.camera = camera;
  }

  // 一次性注入按名字缓存的场景节点（页面从 SceneManager 取）
  setNodes(nodes: Map<string, Node>): void {
    this.nodes = nodes;
  }

  // 用户手动光照档位倍率（明亮 1.0 / 昏暗 0.35 / 黑暗 0.05）
  setUserLightFactor(f: number): void {
    this.userLightFactor = f;
  }

  getPhase(): number {
    return this.t;
  }

  // 已完成昼夜轮数（页面用「一轮内零死亡」判定「平安一夜」）
  getCycles(): number {
    return this.cycles;
  }

  // 果蝇死亡期间整体压暗 10%
  setDeathDim(on: boolean): void {
    this.deathDim = on ? 0.9 : 1.0;
  }

  // 当前是否处于夜晚（日落之后、次日日出之前）
  isNight(): boolean {
    return this.t >= 0.74;
  }

  // 每帧驱动。windStrength 来自行为层（0~1）
  update(dt: number, windStrength: number): void {
    this.anim += dt;   // 动画时钟与昼夜相位解耦
    if (this.cfg.dayNightEnabled) {
      this.t += dt / Math.max(1, this.cfg.dayCycleSeconds);
      while (this.t >= 1) {
        this.t -= 1;
        this.cycles++;
      }
    } else {
      this.t = 0.30; // 关闭昼夜循环时固定为白天
    }

    this.updateSegment();
    this.applySkyAndLight();
    this.applySunMoonStars();
    this.applyTrees(windStrength);
    this.applyWaterAndFx(dt, windStrength);
  }

  // 天空色 + 平行光强度/颜色（单一写入者：其它地方不要再直接改 light.intensity）
  private applySkyAndLight(): void {
    const sky = this.sample(SKY_R, SKY_G, SKY_B);
    if (this.camera) {
      this.camera.clearColor = { r: sky[0], g: sky[1], b: sky[2], a: 1.0 };
    }
    const light = this.light;
    if (!light) {
      return;
    }
    if (this.baseIntensity < 0) {
      this.baseIntensity = light.intensity;
      console.info(`[FlyBrain] env light base intensity=${this.baseIntensity}`);
    }
    const i = this.sample1(SUN_I) * this.userLightFactor * this.deathDim;
    light.intensity = this.baseIntensity * i;
    light.color = {
      r: this.sample1(SUN_R), g: this.sample1(SUN_G), b: this.sample1(SUN_B), a: 1.0,
    };
  }

  // 太阳绕 Z 轴匀速走完一圈，月亮反相 180°；两者只有一个在地平线上方时可见
  private applySunMoonStars(): void {
    const litFrac = LIT_FRAC;
    let angle = 0;
    if (this.t < litFrac) {
      angle = Math.PI * this.t / litFrac;            // 0 → π：东升西落（地平线以上）
    } else {
      angle = Math.PI + Math.PI * (this.t - litFrac) / (1 - litFrac); // π → 2π：地平线以下
    }
    const sunPivot = this.getNode('sun_pivot');
    if (sunPivot) {
      sunPivot.rotation = quatZ(angle);
    }
    const moonPivot = this.getNode('moon_pivot');
    const moonAngle = angle + Math.PI;
    if (moonPivot) {
      moonPivot.rotation = quatZ(moonAngle);
    }
    const sun = this.getNode('sun_disc');
    if (sun) {
      sun.visible = Math.sin(angle) > -0.02;
    }
    const moon = this.getNode('moon_disc');
    if (moon) {
      moon.visible = Math.sin(moonAngle) > -0.02;
    }
    const stars = this.getNode('stars');
    if (stars) {
      stars.visible = this.isNight();
      if (stars.visible) {
        // 天球缓慢自转（0.5°/s）
        stars.rotation = quatY(this.t * this.cfg.dayCycleSeconds * 0.5 * DEG);
      }
    }
  }

  // 风摆：树干绕根部一级摆动，树冠二级摆动（幅度更大、相位 +90°）；无风时树冠微颤
  private applyTrees(windStrength: number): void {
    const w = clamp(windStrength, 0, 1);
    const time = this.anim;
    const trunkAmp = 4 * DEG * w;
    const crownAmp = w > 0.02 ? 6.4 * DEG * w : 0.5 * DEG;
    for (let i = 0; i < TREE_PHASE.length; i++) {
      const ph = TREE_PHASE[i];
      const trunk = this.getNode(`trunk_${i}`);
      if (trunk) {
        trunk.rotation = quatZ(trunkAmp * Math.sin(time * 1.2 + ph));
      }
      const crown = this.getNode(`crown_${i}`);
      if (crown) {
        // 无风时用慢速相位做"呼吸感"微颤
        const hz = w > 0.02 ? 1.2 : 0.7;
        crown.rotation = quatZ(crownAmp * Math.sin(time * hz + ph + Math.PI / 2));
      }
    }
  }

  // 河面常态微波 + 阵风事件（风线掠过 + 涟漪扩散）
  private applyWaterAndFx(dt: number, windStrength: number): void {
    // 阵风上升沿 → 重新开始一轮特效
    if (windStrength > 0.02 && this.lastWind <= 0.02) {
      this.gustT = 0;
    }
    this.lastWind = windStrength;
    if (this.gustT >= 0) {
      this.gustT += dt;
      if (this.gustT > WIND_LINE_DURATION + 0.6) {
        this.gustT = -1;
      }
    }

    // 河面微波：振幅 0.004 的 1Hz 起伏
    const river = this.getNode('river');
    const time = this.anim;
    if (river) {
      const pos = river.position;
      river.position = { x: pos.x, y: this.riverY + 0.004 * Math.sin(time * 1.0), z: pos.z };
    }

    // 风线：横穿场景（+X → -X），依次延迟
    for (let i = 0; i < WIND_LANE_Z.length; i++) {
      const line = this.getNode(`wind_line_${i}`);
      if (!line) {
        continue;
      }
      const p = this.gustT < 0 ? -1 : (this.gustT - WIND_DELAY[i]) / WIND_LINE_DURATION;
      if (p < 0 || p > 1) {
        line.visible = false;
        continue;
      }
      line.visible = true;
      line.position = {
        x: 5.2 - 10.4 * p,
        y: 0.55 + 0.35 * WIND_LANE_Z[i] * 0.2 + 0.05 * Math.sin(p * Math.PI),
        z: WIND_LANE_Z[i],
      };
      line.rotation = quatY(Math.PI / 2); // 长边沿 X 轴
    }

    // 涟漪：从河流弧上向外扩散
    for (let i = 0; i < RIPPLE_ANGLE.length; i++) {
      const ring = this.getNode(`ripple_${i}`);
      if (!ring) {
        continue;
      }
      const p = this.gustT < 0 ? -1 : (this.gustT - RIPPLE_DELAY[i]) / RIPPLE_DURATION;
      if (p < 0 || p > 1) {
        ring.visible = false;
        continue;
      }
      ring.visible = true;
      const s = 0.35 + 1.5 * p;
      ring.position = {
        x: RIPPLE_RADIUS * Math.cos(RIPPLE_ANGLE[i]),
        y: this.riverY + 0.006,
        z: RIPPLE_RADIUS * Math.sin(RIPPLE_ANGLE[i]),
      };
      ring.scale = { x: s, y: 1, z: s };
    }
  }

  private getNode(name: string): Node | null {
    const n = this.nodes.get(name);
    return n === undefined ? null : n;
  }

  // 定位当前所在的关键帧区间与区间内进度（每帧调用一次）
  private updateSegment(): void {
    const p = this.t;
    for (let i = 0; i < PHASES.length - 1; i++) {
      if (p >= PHASES[i] && p <= PHASES[i + 1]) {
        const span = PHASES[i + 1] - PHASES[i];
        this.curSeg = i;
        this.curK = span > 1e-6 ? (p - PHASES[i]) / span : 0;
        return;
      }
    }
    this.curSeg = PHASES.length - 2;
    this.curK = 0;
  }

  // 三通道关键帧插值（返回长度 3 的数组：[r, g, b]）
  private sample(ra: number[], ga: number[], ba: number[]): number[] {
    const i = this.curSeg;
    const k = this.curK;
    return [
      ra[i] + (ra[i + 1] - ra[i]) * k,
      ga[i] + (ga[i + 1] - ga[i]) * k,
      ba[i] + (ba[i + 1] - ba[i]) * k,
    ];
  }

  // 单通道关键帧插值
  private sample1(a: number[]): number {
    const i = this.curSeg;
    const k = this.curK;
    return a[i] + (a[i + 1] - a[i]) * k;
  }
}
