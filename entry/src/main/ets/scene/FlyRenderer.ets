// 果蝇渲染器：把行为层输出的姿态写到场景节点上
// （位置/朝向/翅膀收展与拍动/腿部关节链动画，M4 增加：进食低头、饮水低头、死亡翻面、趋光兴奋振翅）
import { Node, Quaternion } from '@kit.ArkGraphics3D';
import { FlyConfig } from '../behavior/FlyConfig';
import { FlyPose, FlyState } from '../behavior/FlyTypes';
import { LegChain } from './SceneManager';
import { clamp, quatMul, quatX, quatY, quatZ } from '../common/Math3D';

const TWO_PI = Math.PI * 2;
const DEG = Math.PI / 180;

// 死亡时整体抬高一点：果蝇根节点在地面，翻面后躯干会沉到地下
// （v5.1 体型缩到 0.6 倍后同步缩小）
const DEAD_LIFT = 0.16;

export class FlyRenderer {
  private cfg: FlyConfig;
  private flyNode: Node | null = null;
  private wingLeft: Node | null = null;
  private wingRight: Node | null = null;
  private headPivot: Node | null = null;
  private mouthPivot: Node | null = null;
  private legChains: LegChain[] = [];
  private lastYaw: number = 0;
  // 步行摆腿的当前振幅（向目标值平滑，避免起/停步态瞬间跳变）
  private legAmp: number = 0;
  // v7.2 关节链腿部姿态：tuck=飞行收腿（整腿后扫折叠）、curl=死亡蜷腿，均平滑过渡
  private tuck: number = 0;
  private curl: number = 0;
  // v7.1：NeuroMechFly 网格基准 = 双翅收拢贴背（locomotion 站姿）。
  // spread: 0 = 保持模型原姿（收翅，停栖/死亡）；1 = 绕竖轴外展 1.9rad + 拍动（飞行）。
  private spread: number = 0;
  private lastTotal: number = 0;   // 上一帧的累计时间（用来推算 dt）
  private frameDt: number = 0.016; // 本帧 dt（apply 统一推算，翅膀/腿部平滑共用）

  constructor(cfg: FlyConfig) {
    this.cfg = cfg;
  }

  attach(fly: Node | null, wingL: Node | null, wingR: Node | null, headPivot: Node | null,
    legs: LegChain[], mouthPivot: Node | null): void {
    this.flyNode = fly;
    this.wingLeft = wingL;
    this.wingRight = wingR;
    this.headPivot = headPivot;
    this.legChains = legs;
    this.mouthPivot = mouthPivot;
  }

  isAttached(): boolean {
    return this.flyNode !== null && this.flyNode !== undefined;
  }

  // excited：趋光兴奋态（页面在 Wander + 光斑生效时传 true）→ 介于 idle 与 fly 之间的低幅振翅
  apply(pose: FlyPose, state: FlyState, total: number, excited: boolean): void {
    if (!this.isAttached()) {
      return;
    }
    const fly = this.flyNode as Node;
    const dead = state === FlyState.Dead;

    // 死亡：翻面躺地（绕本地 X 轴 180°），并抬高避免穿地
    fly.position = { x: pose.x, y: dead ? pose.y + DEAD_LIFT : pose.y, z: pose.z };
    const yawQ = quatY(pose.yaw);
    fly.rotation = dead ? quatMul(yawQ, quatX(Math.PI)) : yawQ;
    this.lastYaw = pose.yaw;

    // 帧率无关 dt：只在这里算一次（此前腿部平滑各自再算会因 lastTotal 已被
    // 翅膀更新而恒得 0，振幅永远平滑不动——顺手修掉的既有 bug）
    let dt = total - this.lastTotal;
    this.lastTotal = total;
    if (dt < 0 || dt > 0.1) {
      dt = 0.016;
    }
    this.frameDt = dt;

    this.applyHead(state, total);
    this.applyWings(state, total, excited, dead);
    this.applyLegs(state, total, dead);
    this.applyMouth(state, total);
  }

  // 翅膀（v7.1）：网格基准 = 收拢贴背（locomotion 站姿）。
  // 停栖/死亡 → spread 平滑归 0（保持贴背）；起飞/飞行/惊吓 → 外展 1.9rad 并拍动；
  // 趋光兴奋 → 半展（0.35）低幅振翅。拍动只在展开后叠加（收拢的翅膀拍不动）。
  private applyWings(state: FlyState, total: number, excited: boolean, dead: boolean): void {
    const dt = this.frameDt;
    const spreadState = state === FlyState.Takeoff || state === FlyState.Fly ||
      state === FlyState.Startle;
    const target = dead ? 0 : (spreadState ? 1 : (excited ? 0.35 : 0));
    this.spread += clamp(target - this.spread, -dt * this.cfg.wingFoldRate, dt * this.cfg.wingFoldRate);
    this.spread = clamp(this.spread, 0, 1);

    let amp = this.cfg.wingFlapIdleAmp;
    let hz = this.cfg.wingFlapIdleHz;
    if (state === FlyState.Fly || state === FlyState.Takeoff) {
      amp = this.cfg.wingFlapFlyAmp;
      hz = this.cfg.wingFlapFlyHz;
    } else if (state === FlyState.Groom) {
      amp = this.cfg.wingFlapGroomAmp;
      hz = this.cfg.wingFlapGroomHz;
    } else if (state === FlyState.Startle) {
      amp = this.cfg.wingFlapStartleAmp;
      hz = this.cfg.wingFlapStartleHz;
    } else if (state === FlyState.Brace) {
      amp = 0.008;
      hz = 0.3;
    } else if (excited) {
      amp = 0.18;
      hz = 2.0;
    }
    const flap = Math.sin(total * hz * TWO_PI) * amp * this.spread;
    const ext = this.cfg.wingSpreadYaw * this.spread;
    // 外展绕竖轴（Y）：左翼 +ext、右翼 -ext 把收拢的翅甩向两侧；拍动在展开后绕前向轴（Z）
    if (this.wingLeft) {
      (this.wingLeft as Node).rotation = quatMul(quatY(ext), quatZ(-flap));
    }
    if (this.wingRight) {
      (this.wingRight as Node).rotation = quatMul(quatY(-ext), quatZ(flap));
    }
  }

  // 腿部关节链动画（v7.2）：每条腿四级枢轴（基节/股节/胫节/跗节），模型基准 =
  // 生成期 FK 摆出的站姿（枢轴零旋转），这里只叠加相对旋转——
  // 步行（漫步/觅食）：三角步态，对侧同相、同侧反相；基节绕竖轴前后摆，
  //   摆动相股节上抬、胫节前折把脚提起，支撑相归零；
  // 飞行/起飞/惊吓：tuck→1 整腿后扫（基节后摆 + 股节上收 + 胫节前折 + 跗节顺随）；
  // 死亡：curl→1 蜷腿（翻面后六腿向腹面卷收）。
  // 其余状态回到模型基准站姿（静止站立）。
  private applyLegs(state: FlyState, total: number, dead: boolean): void {
    if (this.legChains.length === 0) {
      return;
    }
    const dt = this.frameDt;
    const walking = state === FlyState.Wander || state === FlyState.Seek;
    const rate = this.cfg.legPoseRate;
    this.legAmp += clamp((walking ? this.cfg.legSwingAmp : 0) - this.legAmp, -dt * rate, dt * rate);
    this.tuck += clamp((!dead && (state === FlyState.Takeoff || state === FlyState.Fly ||
      state === FlyState.Startle) ? 1 : 0) - this.tuck, -dt * rate, dt * rate);
    this.curl += clamp((dead ? 1 : 0) - this.curl, -dt * rate, dt * rate);
    // 相位：同侧前后足与对侧中足同相（近似三角步态）
    const phases = [0, Math.PI, Math.PI, 0, 0, Math.PI];
    for (let i = 0; i < this.legChains.length && i < phases.length; i++) {
      const chain = this.legChains[i];
      if (!chain) {
        continue;
      }
      const ph = total * this.cfg.legStrideHz * TWO_PI + phases[i];
      const swing = Math.sin(ph) * this.legAmp;              // 基节前后摆
      const lift = Math.max(0, Math.sin(ph)) * this.legAmp;  // 摆动相抬腿（支撑相为 0）
      if (chain.coxa) {
        // 先绕 X 后扫/蜷腿，再绕 Y 前后摆（quatMul 先应用右侧参数）
        (chain.coxa as Node).rotation =
          quatMul(quatY(swing), quatX(this.tuck * 0.9 + this.curl * 0.45));
      }
      if (chain.femur) {
        (chain.femur as Node).rotation = quatX(lift * 0.30 + this.tuck * 0.95 + this.curl * 0.85);
      }
      if (chain.tibia) {
        (chain.tibia as Node).rotation = quatX(-lift * 0.55 - this.tuck * 1.25 - this.curl * 1.7);
      }
      if (chain.tarsus) {
        (chain.tarsus as Node).rotation = quatX(-lift * 0.2 + this.tuck * 0.55 - this.curl * 1.1);
      }
    }
  }

  // 口器（v7 高精度模型）：进食时绕 Rostrum 关节下压伸出并小幅点动，饮水半伸，其余收起
  private applyMouth(state: FlyState, total: number): void {
    const piv = this.mouthPivot;
    if (!piv) {
      return;
    }
    if (state === FlyState.Feed) {
      (piv as Node).rotation = quatX(0.55 + 0.12 * Math.sin(total * 3));
    } else if (state === FlyState.Drinking) {
      (piv as Node).rotation = quatX(0.4);
    } else {
      (piv as Node).rotation = quatX(0);
    }
  }

  // 头部轴心：进食时低头 20° 并以 1.5Hz 小幅点动；饮水时低头 15°
  private applyHead(state: FlyState, total: number): void {
    const pivot = this.headPivot;
    if (!pivot) {
      return;
    }
    if (state === FlyState.Feed) {
      // 绕 +X 的正角度把头部朝下压（+Z 方向的头会转向 -Y）
      const nod = 20 * DEG + 4 * DEG * Math.sin(total * 1.5 * TWO_PI);
      pivot.rotation = quatX(nod);
    } else if (state === FlyState.Drinking) {
      pivot.rotation = quatX(15 * DEG);
    } else {
      pivot.rotation = quatX(0);
    }
  }

}
