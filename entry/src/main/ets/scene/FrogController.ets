// 捕食者：青蛙 AI（M4）。
//
// 状态机：Idle 蹲坐鼓腮/眨眼 → Charge 蓄力预警（给用户 0.8s 救援窗口）→ Attack 舌头弹射
//         → Cooldown 冷却（命中 40s / 未命中 8s，避免劝退）。
//
// 与行为层的接口刻意做成「页面轮询」而不是回调，保持两个类的低耦合：
//   isCharging()   → 页面把 brain.setFrogThreat(true)，状态行变红提示
//   consumeHit()   → 页面调用 brain.hitByFrog()（重伤 + 挣脱起飞）
//
// 节点驱动：frog 整体 yaw 负责朝向（舌头只沿本地 +Z 伸缩），
// 这样避免在运行时算舌头的朝向四元数（设计文档 §7 明确规避的风险点）。
import { Node, Quaternion, Vec3 } from '@kit.ArkGraphics3D';
import { FlyConfig } from '../behavior/FlyConfig';
import { clamp, quatY } from '../common/Math3D';

enum FrogState {
  Idle = 0,
  Puff,
  Charge,
  Attack,
  Cooldown,
}

const PUFF_DURATION = 1.0;      // 鼓腮时长
const BLINK_DURATION = 0.15;    // 眨眼时长
const RETRACT_DURATION = 0.30;  // 舌头收回时长
const TONGUE_MAX = 3.2;         // 舌头最大伸出长度

export class FrogController {
  private cfg: FlyConfig;
  private nodes: Map<string, Node> = new Map<string, Node>();

  private state: FrogState = FrogState.Idle;
  private timer: number = 0;
  private cooldown: number = 0;
  private puffTimer: number = 6;
  private blinkTimer: number = 4;
  private blinkT: number = -1;
  private tongueLen: number = 0;
  private tongueTarget: number = 0;
  private hitFlag: boolean = false;
  private hitChecked: boolean = false;   // 本次扑击是否已做过命中判定
  private total: number = 0;

  // 节点基准值（首次驱动时记录，之后只做增量）
  private baseFrogRot: Quaternion = { x: 0, y: 0, z: 0, w: 1 };
  private basePupilL: Vec3 = { x: 0, y: 0, z: 0 };
  private basePupilR: Vec3 = { x: 0, y: 0, z: 0 };
  private baseCaptured: boolean = false;

  constructor(cfg: FlyConfig) {
    this.cfg = cfg;
  }

  setNodes(nodes: Map<string, Node>): void {
    this.nodes = nodes;
    this.captureBase();
  }

  // 蓄力中（页面据此显示「⚠ 天敌！」）
  isCharging(): boolean {
    return this.state === FrogState.Charge;
  }

  // 本次攻击是否命中（读取即清除）
  consumeHit(): boolean {
    const v = this.hitFlag;
    this.hitFlag = false;
    return v;
  }

  // 每帧驱动。flyX/flyZ 为果蝇位置；flyAlive=false 时不索敌（对死掉的果蝇不再攻击）
  update(dt: number, flyX: number, flyZ: number, flyAlive: boolean): void {
    this.total += dt;
    this.captureBase();

    if (this.cooldown > 0) {
      this.cooldown -= dt;
    }

    // 关闭青蛙时：立刻复位并保持蹲坐
    if (!this.cfg.frogEnabled) {
      this.state = FrogState.Idle;
      this.tongueLen = 0;
      this.tongueTarget = 0;
      this.hitFlag = false;
      this.applyPose(flyX, flyZ, true);
      return;
    }

    const dx = flyX - this.cfg.frogX;
    const dz = flyZ - this.cfg.frogZ;
    const dist = Math.hypot(dx, dz);

    this.timer += dt;

    switch (this.state) {
      case FrogState.Idle: {
        this.tongueLen = 0;
        this.updateBlink(dt);
        this.puffTimer -= dt;
        if (this.puffTimer <= 0) {
          this.puffTimer = this.cfg.frogPuffMin +
            Math.random() * (this.cfg.frogPuffMax - this.cfg.frogPuffMin);
          this.enter(FrogState.Puff);
        }
        // 索敌：进入警戒圈且冷却结束
        if (flyAlive && dist < this.cfg.frogGuardRadius && this.cooldown <= 0) {
          this.enter(FrogState.Charge);
        }
        break;
      }
      case FrogState.Puff: {
        this.tongueLen = 0;
        this.updateBlink(dt);
        if (this.timer >= PUFF_DURATION) {
          this.enter(FrogState.Idle);
        }
        break;
      }
      case FrogState.Charge: {
        this.tongueLen = 0;
        // 救援窗口：蓄力期间果蝇被吓出警戒圈（吹风/自逃）→ 放弃攻击
        if (!flyAlive || dist > this.cfg.frogGuardRadius * 1.25) {
          this.cooldown = this.cfg.frogMissCooldown * 0.5;
          this.enter(FrogState.Idle);
          break;
        }
        if (this.timer >= this.cfg.frogChargeTime) {
          this.tongueTarget = clamp(dist, 0.2, TONGUE_MAX);
          this.hitChecked = false;
          this.enter(FrogState.Attack);
        }
        break;
      }
      case FrogState.Attack: {
        const tc = this.cfg.frogAttackTime;
        if (this.timer < tc) {
          // 弹出
          this.tongueLen = this.tongueTarget * (this.timer / tc);
        } else {
          // 到达伸出终点：用独立标志位做一次命中判定
          // （不能靠 tongueLen >= target 判断 —— 帧步长会让最后一帧插值不到 1，判定被跳过）
          if (!this.hitChecked) {
            this.hitChecked = true;
            if (flyAlive && dist <= Math.max(this.cfg.frogHitRadius, this.tongueTarget * 0.25)) {
              this.hitFlag = true;
              this.cooldown = this.cfg.frogCooldown;
            } else {
              this.cooldown = this.cfg.frogMissCooldown;
            }
          }
          if (this.timer < tc + RETRACT_DURATION) {
            this.tongueLen = this.tongueTarget * (1 - (this.timer - tc) / RETRACT_DURATION);
          } else {
            this.tongueLen = 0;
            this.enter(FrogState.Idle);
          }
        }
        break;
      }
      case FrogState.Cooldown: {
        if (this.timer >= 1.0) {
          this.enter(FrogState.Idle);
        }
        break;
      }
      default:
        break;
    }

    this.applyPose(flyX, flyZ, false);
  }

  // ---------- 内部 ----------
  private enter(s: FrogState): void {
    this.state = s;
    this.timer = 0;
  }

  private updateBlink(dt: number): void {
    if (this.blinkT >= 0) {
      this.blinkT += dt;
      if (this.blinkT >= BLINK_DURATION) {
        this.blinkT = -1;
      }
      return;
    }
    this.blinkTimer -= dt;
    if (this.blinkTimer <= 0) {
      this.blinkTimer = 3 + Math.random() * 5;
      this.blinkT = 0;
    }
  }

  private captureBase(): void {
    if (this.baseCaptured) {
      return;
    }
    const frog = this.nodes.get('frog');
    if (frog) {
      this.baseFrogRot = frog.rotation;
    }
    const pl = this.nodes.get('frog_pupil_l');
    if (pl) {
      this.basePupilL = pl.position;
    }
    const pr = this.nodes.get('frog_pupil_r');
    if (pr) {
      this.basePupilR = pr.position;
    }
    this.baseCaptured = frog !== undefined;
  }

  // 把状态写进节点
  private applyPose(flyX: number, flyZ: number, reset: boolean): void {
    const frog = this.nodes.get('frog');
    const body = this.nodes.get('frog_body');
    const tongue = this.nodes.get('frog_tongue');

    // 朝向：蓄力/攻击时面向果蝇，其余时间回归基准朝向
    if (frog) {
      if (reset || (this.state !== FrogState.Charge && this.state !== FrogState.Attack)) {
        frog.rotation = this.baseFrogRot;
      } else {
        const dx = flyX - this.cfg.frogX;
        const dz = flyZ - this.cfg.frogZ;
        frog.rotation = quatY(Math.atan2(dx, dz));
      }
      // 蓄力下蹲
      const crouch = this.state === FrogState.Charge ? 0.85 : 1.0;
      frog.scale = { x: 1, y: crouch, z: 1 };
    }

    // 鼓腮：身体纵向 1.0 → 1.12 → 1.0
    if (body) {
      let sy = 1.0;
      if (this.state === FrogState.Puff) {
        const p = clamp(this.timer / PUFF_DURATION, 0, 1);
        sy = 1.0 + 0.12 * Math.sin(p * Math.PI);
      }
      body.scale = { x: 1, y: sy, z: 1 };
    }

    // 舌头：仅攻击期间可见，沿本地 +Z 伸缩
    if (tongue) {
      const show = this.tongueLen > 0.02;
      tongue.visible = show;
      if (show) {
        tongue.scale = { x: 1, y: 1, z: this.tongueLen };
      }
    }

    // 瞳孔：蓄力时朝向果蝇（本地 +Z 前移），眨眼时隐藏
    const blink = this.blinkT >= 0;
    const shift = this.state === FrogState.Charge ? 0.03 : 0;
    const pl = this.nodes.get('frog_pupil_l');
    if (pl) {
      pl.position = { x: this.basePupilL.x, y: this.basePupilL.y, z: this.basePupilL.z + shift };
      pl.visible = !blink;
    }
    const pr = this.nodes.get('frog_pupil_r');
    if (pr) {
      pr.position = { x: this.basePupilR.x, y: this.basePupilR.y, z: this.basePupilR.z + shift };
      pr.visible = !blink;
    }
  }
}
