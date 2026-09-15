// 果蝇渲染器：把行为层输出的姿态写到场景节点上
// （位置/朝向/翅膀拍动，M4 增加：进食低头、饮水低头、死亡翻面、趋光兴奋振翅）
import { Node, Quaternion } from '@kit.ArkGraphics3D';
import { FlyConfig } from '../behavior/FlyConfig';
import { FlyPose, FlyState } from '../behavior/FlyTypes';
import { quatMul, quatX, quatY, quatZ } from '../common/Math3D';

const TWO_PI = Math.PI * 2;
const DEG = Math.PI / 180;

// 死亡时整体抬高一点：果蝇根节点在地面，翻面后躯干会沉到地下
const DEAD_LIFT = 0.26;
const DEAD_SPREAD = 1.05;   // 死亡时翅膀摊开角

export class FlyRenderer {
  private cfg: FlyConfig;
  private flyNode: Node | null = null;
  private wingLeft: Node | null = null;
  private wingRight: Node | null = null;
  private headPivot: Node | null = null;
  private lastYaw: number = 0;

  constructor(cfg: FlyConfig) {
    this.cfg = cfg;
  }

  attach(fly: Node | null, wingL: Node | null, wingR: Node | null, headPivot: Node | null): void {
    this.flyNode = fly;
    this.wingLeft = wingL;
    this.wingRight = wingR;
    this.headPivot = headPivot;
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

    this.applyHead(state, total);
    this.applyWings(state, total, excited, dead);
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

  private applyWings(state: FlyState, total: number, excited: boolean, dead: boolean): void {
    if (dead) {
      if (this.wingLeft) {
        (this.wingLeft as Node).rotation = quatZ(-DEAD_SPREAD);
      }
      if (this.wingRight) {
        (this.wingRight as Node).rotation = quatZ(DEAD_SPREAD);
      }
      return;
    }
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
      // 趋光兴奋：低幅快振（模仿"兴奋"）
      amp = 0.18;
      hz = 2.0;
    }
    const a = Math.sin(total * hz * TWO_PI) * amp;
    if (this.wingLeft) {
      (this.wingLeft as Node).rotation = quatZ(-a);
    }
    if (this.wingRight) {
      (this.wingRight as Node).rotation = quatZ(a);
    }
  }
}
