// 捕食者：青蛙 AI（M4 引入；M5P1.2 升级为"会跳的伏击手"）。
//
// 状态机：Idle 蹲坐鼓腮/眨眼/跳跃接近 → Charge 蓄力预警（给用户 0.8s 救援窗口）
//        → Attack 舌头弹射 → Cooldown 冷却（命中 40s / 未命中 8s，避免劝退）。
//
// P1.2 修复与变化：
//  1) 瞳孔飞出 bug：captureBase 之前直接保存引擎 position/rotation getter 返回的
//     **对象引用**——引擎复用内部对象后，"基准位置"变成别的节点的坐标，
//     瞳孔就被写到满场乱飞。现在逐分量快照拷贝，写回时也构造新对象。
//  2) 青蛙会动了：Idle 且冷却结束时，猎物进入追击半径（v6：6.3）就向其跳跃接近
//     （单跳 ≤1.2 单位、抛物线 0.38s），落地休息 0.5~1.3s 再跳；距离 ≤1.4 就地蹲守蓄力。
//     逃跑中的果蝇（惊吓 3.3 速度）仍甩得开青蛙 —— "吹风救援"玩法保留。
//  3) 命中判定：果蝇距离 ≤ 舌头锁定距离 + 命中容差（旧公式对远目标过严，从未命中）。
//
// 与行为层的接口保持「页面轮询」：isCharging() / consumeHit() / update(dt, flyX, flyZ, flyAlive)。
// 节点驱动：frog 整体 yaw 负责朝向（舌头只沿本地 +Z 伸缩），规避运行时算舌头朝向四元数。
import { Node, Quaternion, Vec3 } from '@kit.ArkGraphics3D';
import { FlyConfig } from '../behavior/FlyConfig';
import { clamp, normalizeAngle, quatX, quatY } from '../common/Math3D';

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
const TONGUE_HIDE_SCALE = 0.001; // 舌头收回时塌缩到的缩放（≈不可见，见 applyPose 说明）
// v6：场地放大 1.5 倍，下面这组"作战半径"同步 ×1.5（否则青蛙在放大后的场地里
// 变成角落里的摆设：追不到、够不着），跳跃时长/高度不变（节奏感靠速度而非位移）。
const TONGUE_MAX = 4.4;         // 舌头最大伸出长度（原 3.2）
const HOP_DURATION = 0.38;      // 一次跳跃时长
const HOP_HEIGHT = 0.30;        // 跳跃最高点
const HOP_MAX = 1.2;            // 单跳最大距离（原 0.9）
const CHASE_RADIUS = 6.3;       // 追击半径：猎物进入才会跳过去（原 4.2）
const CHASE_STOP = 1.4;         // 距离缩到该值内不再追（就地蹲守/蓄力；原 1.0）
const FROAM_RADIUS = 9.6;       // 青蛙自身活动半径（不跳出地盘；原 6.4）
const FROG_TURN_RATE = 3.5;     // 朝向最大转向速率（弧度/秒）：转向平滑、不瞬移

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
  private tongueShown: boolean = false;   // 上帧舌头可见态（变更时打日志，排查真机问题用）
  private hitFlag: boolean = false;
  private hitChecked: boolean = false;   // 本次扑击是否已做过命中判定
  private total: number = 0;
  private tgtY: number = 0;      // 当前目标高度（舌头俯仰用）
  private tgtDist: number = 0;   // 当前目标水平距离

  // 运行时位置（会跳跃移动；出生点来自配置，与生成脚本一致）
  private posX: number;
  private posZ: number;
  private hopT: number = -1;      // 跳跃进度（-1 = 未在跳）
  private hopDx: number = 0;      // 跳跃水平速度（单位/秒）
  private hopDz: number = 0;
  private hopY: number = 0;       // 跳跃离地高度
  private hopRest: number = 0.8;  // 落地后的休息时间
  // 当前朝向（弧度，quatY 约定 0 = +Z）。不再每帧写回烘焙基准——
  // 那会让青蛙每次跳完瞬间"转回"出生朝向（真机反馈的瞬移旋转）；
  // 改为按转向速率平滑转到目标朝向，静止时保持最后朝向
  private yaw: number = Number.NaN;   // NaN = 尚未从模型基准初始化
  private frameDt: number = 0.016;    // update 里缓存，applyPose 转向限速用

  // 节点基准值（首次驱动时逐分量快照——不能存引擎返回的对象引用，见文件头说明 1)
  private baseFrogRot: Quaternion = { x: 0, y: 0, z: 0, w: 1 };
  private basePupilL: Vec3 = { x: 0, y: 0, z: 0 };
  private basePupilR: Vec3 = { x: 0, y: 0, z: 0 };
  private baseCaptured: boolean = false;

  constructor(cfg: FlyConfig) {
    this.cfg = cfg;
    this.posX = cfg.frogX;
    this.posZ = cfg.frogZ;
  }

  setNodes(nodes: Map<string, Node>): void {
    this.nodes = nodes;
    this.captureBase();
  }

  // 青蛙当前实时位置（页面据此算"最近果蝇"）
  getPosX(): number {
    return this.posX;
  }

  getPosZ(): number {
    return this.posZ;
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

  // 每帧驱动。flyX/flyZ/flyY 为当前目标果蝇位置；flyAlive=false 时不索敌
  update(dt: number, flyX: number, flyZ: number, flyY: number, flyAlive: boolean): void {
    this.total += dt;
    this.captureBase();
    let dtc = dt;
    if (dtc < 0 || dtc > 0.1) {
      dtc = 0.016;
    }
    this.frameDt = dtc;

    if (this.cooldown > 0) {
      this.cooldown -= dt;
    }

    // 跳跃推进（任何状态都让空中的这一跳先落地）
    let hopping = this.hopT >= 0;
    if (hopping) {
      const remain = Math.max(0, HOP_DURATION - this.hopT);
      this.hopT += dt;
      if (this.hopT >= HOP_DURATION) {
        this.posX += this.hopDx * remain;
        this.posZ += this.hopDz * remain;
        this.hopT = -1;
        this.hopY = 0;
        hopping = false;
        this.hopRest = 0.5 + Math.random() * 0.8;
      } else {
        this.posX += this.hopDx * dt;
        this.posZ += this.hopDz * dt;
        this.hopY = HOP_HEIGHT * Math.sin(this.hopT / HOP_DURATION * Math.PI);
      }
      // 别跳出地盘
      const r = Math.hypot(this.posX, this.posZ);
      if (r > FROAM_RADIUS) {
        const k = FROAM_RADIUS / r;
        this.posX *= k;
        this.posZ *= k;
      }
    } else if (this.hopRest > 0) {
      this.hopRest -= dt;
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

    const dx = flyX - this.posX;
    const dz = flyZ - this.posZ;
    const dist = Math.hypot(dx, dz);
    // 舌头俯仰瞄准（v7）：目标高度与水平距离决定舌头攻击时的上抬角
    this.tgtY = flyY;
    this.tgtDist = dist;

    this.timer += dt;

    // 跳跃接近（只在 Idle、未在跳、休息完毕、冷却结束时发起）
    if (this.state === FrogState.Idle && !hopping && this.hopRest <= 0 && this.cooldown <= 0) {
      if (flyAlive && dist < CHASE_RADIUS && dist > CHASE_STOP * 0.6) {
        const move = Math.min(dist - CHASE_STOP * 0.5, HOP_MAX);
        if (move > 0.15) {
          const l = Math.max(1e-4, dist);
          this.hopDx = dx / l * (move / HOP_DURATION);
          this.hopDz = dz / l * (move / HOP_DURATION);
          this.hopT = 0;
        }
      }
    }

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
          //（帧步长会让最后一帧插值不到 1，不能靠 tongueLen >= target 判断）
          // 命中条件（P1.1 修复）：距离 ≤ 舌头锁定距离 + 命中容差。
          // 旧公式 max(0.35, 舌长×0.25) 对远目标过严，视觉拍到也必 miss。
          if (!this.hitChecked) {
            this.hitChecked = true;
            if (flyAlive && dist <= this.tongueTarget + this.cfg.frogHitRadius) {
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
    if (this.state !== s) {
      // 状态迁移是低频事件，常驻日志便于真机排查舌头/朝向类问题
      console.info(`[FlyBrain-Frog] state ${this.state}->${s} dist=${this.tgtDist.toFixed(2)} ` +
        `tongueLen=${this.tongueLen.toFixed(2)} target=${this.tongueTarget.toFixed(2)}`);
    }
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
      const r = frog.rotation;
      // 逐分量快照：直接存 getter 返回的对象引用会被引擎复用/改写（瞳孔飞走的根因）
      this.baseFrogRot = { x: r.x, y: r.y, z: r.z, w: r.w };
      // 模型基准朝向（生成期烘焙的 quatY 纯偏航）→ 取出 yaw 作为初始朝向。
      // 纯 Y 旋转四元数：yaw = 2·atan2(y, w)
      this.yaw = normalizeAngle(2 * Math.atan2(this.baseFrogRot.y, this.baseFrogRot.w));
    }
    const pl = this.nodes.get('frog_pupil_l');
    if (pl) {
      const p = pl.position;
      this.basePupilL = { x: p.x, y: p.y, z: p.z };
    }
    const pr = this.nodes.get('frog_pupil_r');
    if (pr) {
      const p = pr.position;
      this.basePupilR = { x: p.x, y: p.y, z: p.z };
    }
    this.baseCaptured = frog !== undefined && frog !== null;
  }

  // 把状态写进节点
  private applyPose(flyX: number, flyZ: number, reset: boolean): void {
    const frog = this.nodes.get('frog');
    const body = this.nodes.get('frog_body');
    const tongue = this.nodes.get('frog_tongue');

    if (frog) {
      // 位置：跳跃会移动（出生点为基准）
      frog.position = { x: this.posX, y: this.hopY, z: this.posZ };
      // 朝向：跳跃时朝跳向、蓄力/攻击时面向果蝇、其余时间保持当前朝向，
      // 一律经限速平滑转向（修掉"每帧写回烘焙基准→跳完瞬间转回原方向"的瞬移）
      let desired = this.yaw;
      if (this.state === FrogState.Charge || this.state === FrogState.Attack) {
        desired = Math.atan2(flyX - this.posX, flyZ - this.posZ);
      } else if (this.hopT >= 0) {
        desired = Math.atan2(this.hopDx, this.hopDz);
      }
      if (Number.isNaN(this.yaw)) {
        this.yaw = desired;   // 兜底：基准朝向尚未捕获时直接对齐目标
      }
      const dYaw = normalizeAngle(desired - this.yaw);
      const step = clamp(dYaw, -FROG_TURN_RATE * this.frameDt, FROG_TURN_RATE * this.frameDt);
      this.yaw = normalizeAngle(this.yaw + step);
      frog.rotation = quatY(this.yaw);
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

    // 舌头：仅攻击期间可见，沿本地 +Z 伸缩。
    // 收回时**同时**把三轴缩放塌缩到 ~0（而不只是写 visible=false）：
    // 真机上出现过"舌头一直保持伸出"的表现 —— 只靠可见性不够稳，
    // 塌缩后即使可见性没生效也只是一个点（与"隐藏果蝇要移出视野"同款双保险）。
    if (tongue) {
      const show = this.tongueLen > 0.02;
      if (show !== this.tongueShown) {
        this.tongueShown = show;
        console.info(`[FlyBrain-Frog] tongue show=${show} len=${this.tongueLen.toFixed(2)} state=${this.state}`);
      }
      tongue.visible = show;
      if (show) {
        tongue.scale = { x: 1, y: 1, z: this.tongueLen };
        // v7：舌头俯仰瞄准——目标在空中时舌头上抬（否则舌头贴地掠过空中目标的下方）
        const mouthY = 0.150 + this.hopY;
        const pitch = clamp(Math.atan2(this.tgtY - mouthY, Math.max(0.2, this.tgtDist)), 0, 0.6);
        tongue.rotation = quatX(-pitch);
      } else {
        tongue.scale = { x: TONGUE_HIDE_SCALE, y: TONGUE_HIDE_SCALE, z: TONGUE_HIDE_SCALE };
        tongue.rotation = quatX(0);
      }
    }

    // 瞳孔：蓄力时朝果蝇方向（本地 +Z）微微前移，眨眼时隐藏；位置来自快照基准
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
