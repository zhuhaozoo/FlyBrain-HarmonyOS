// 果蝇渲染器：把行为层输出的姿态写到场景节点上（位置/朝向/翅膀拍动）
import { Node, Quaternion } from '@kit.ArkGraphics3D';
import { FlyConfig } from '../behavior/FlyConfig';
import { FlyPose, FlyState } from '../behavior/FlyTypes';
import { quatY, quatZ } from '../common/Math3D';

const TWO_PI = Math.PI * 2;

export class FlyRenderer {
  private cfg: FlyConfig;
  private flyNode: Node | null = null;
  private wingLeft: Node | null = null;
  private wingRight: Node | null = null;
  private lastYaw: number = 0;

  constructor(cfg: FlyConfig) {
    this.cfg = cfg;
  }

  attach(fly: Node | null, wingL: Node | null, wingR: Node | null): void {
    this.flyNode = fly;
    this.wingLeft = wingL;
    this.wingRight = wingR;
  }

  isAttached(): boolean {
    return this.flyNode !== null && this.flyNode !== undefined;
  }

  apply(pose: FlyPose, state: FlyState, total: number): void {
    if (!this.isAttached()) {
      return;
    }
    const fly = this.flyNode as Node;
    fly.position = { x: pose.x, y: pose.y, z: pose.z };
    fly.rotation = this.smoothYaw(pose.yaw);

    // 翅膀按状态拍动（左右镜像，绕各自轴心 Z 轴）
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
    }
    const a = Math.sin(total * hz * TWO_PI) * amp;
    if (this.wingLeft) {
      (this.wingLeft as Node).rotation = quatZ(-a);
    }
    if (this.wingRight) {
      (this.wingRight as Node).rotation = quatZ(a);
    }
  }

  // 朝向回绕时的四元数插值防跳变：直接用目标角即可（quatY 无累积误差），
  // 这里仅保留最近一次角度用于未来扩展。
  private smoothYaw(yaw: number): Quaternion {
    this.lastYaw = yaw;
    return quatY(yaw);
  }
}
