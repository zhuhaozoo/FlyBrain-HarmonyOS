// 静态障碍物（场内石块的碰撞圆）：果蝇**步行不可穿越**，飞行（高度 > 0.3）可越过。
// 数据来源：场景加载后由页面从 world.glb 的 blocker_i 标记节点读入
// （节点 translation = 圆心、scale.x = 阻挡半径；契约见 tools/gen_world_glb.mjs 的 REQUIRED 清单）。
// 纯逻辑类，不依赖任何 3D/渲染 API。
import { clamp, normalizeAngle } from '../common/Math3D';
import { FlyPose } from './FlyTypes';

// 一个圆形阻挡区（世界坐标 xz 平面）
export class ObstacleCircle {
  public x: number = 0;
  public z: number = 0;
  public r: number = 0;
}

export class Obstacles {
  private circles: ObstacleCircle[] = [];

  add(x: number, z: number, r: number): void {
    const c = new ObstacleCircle();
    c.x = x;
    c.z = z;
    c.r = r;
    this.circles.push(c);
  }

  clear(): void {
    this.circles = [];
  }

  count(): number {
    return this.circles.length;
  }

  // 把一个点推出所有阻挡圆（含 margin 余量），返回调整后的坐标 [x, z]。
  // 用途：投喂落点若压在石块上，食物会被埋进石头里、果蝇够不到（只会顶着石壁走）
  // —— 落点先经这里推出，保证食物一定落在可走到的地面上。
  pushOut(x: number, z: number, margin: number): number[] {
    let px = x;
    let pz = z;
    for (let i = 0; i < this.circles.length; i++) {
      const c = this.circles[i];
      const dx = px - c.x;
      const dz = pz - c.z;
      const d = Math.hypot(dx, dz);
      const minD = c.r + margin;
      if (d >= minD) {
        continue;
      }
      // 圆心重合的退化情形：朝场地外侧（远离原点）推出
      let ux = 1;
      let uz = 0;
      if (d > 1e-4) {
        ux = dx / d;
        uz = dz / d;
      }
      px = c.x + ux * minD;
      pz = c.z + uz * minD;
    }
    return [px, pz];
  }

  // 把姿态推出所有重叠的阻挡圆，并朝切向偏一点（沿石壁绕行，而不是原地顶住）。
  // 只应由地面个体调用 —— 飞行个体高度足以越过石块。
  resolve(pose: FlyPose, bodyR: number, turnStep: number): void {
    for (let i = 0; i < this.circles.length; i++) {
      const c = this.circles[i];
      const dx = pose.x - c.x;
      const dz = pose.z - c.z;
      const d = Math.hypot(dx, dz);
      const minD = c.r + bodyR;
      if (d >= minD) {
        continue;
      }
      // 圆心重合的退化情形（正常不会发生）：沿"背后"方向推出
      let ux = -Math.sin(pose.yaw);
      let uz = -Math.cos(pose.yaw);
      if (d > 1e-4) {
        ux = dx / d;
        uz = dz / d;
      }
      pose.x = c.x + ux * minD;
      pose.z = c.z + uz * minD;
      // 绕行转向：两个切向里选与当前朝向夹角更小的一侧
      const away = Math.atan2(ux, uz);
      const t1 = normalizeAngle(away + Math.PI / 2);
      const t2 = normalizeAngle(away - Math.PI / 2);
      const d1 = Math.abs(normalizeAngle(t1 - pose.yaw));
      const d2 = Math.abs(normalizeAngle(t2 - pose.yaw));
      const want = d1 <= d2 ? t1 : t2;
      pose.yaw = normalizeAngle(pose.yaw + clamp(normalizeAngle(want - pose.yaw), -turnStep, turnStep));
    }
  }
}