// 多果蝇协调器（M5）：持有全部 FlyBrain 实例，每帧统一驱动，
// 并施加个体间互动（互斥斥力；后续阶段在此追加惊吓传染与信息素读场）。
// 纯逻辑类，不依赖任何 3D/渲染 API——互动规则全部写在这里而不是页面里。
import { FlyBrain } from './FlyBrain';
import { FlyConfig } from './FlyConfig';
import { FoodWorld } from './FoodWorld';
import { Obstacles } from './Obstacles';
import { WorldState } from './WorldState';

// 场景里最多烘焙 6 份果蝇模型（gen_world_glb.mjs 与此约定一致）
export const MAX_AGENTS: number = 6;

// 出生圈的半径。原来是 0.6 —— v7 河道改为穿过场心后，原点附近整圈都落在水带里
// （原点距河道中心线只有 0.39 < 半宽 0.7），三只果蝇会被推岸挤到同一段岸边。
// 放到 1.6 后出生点基本都在陆地上（FlyBrain.spawnAt 仍会把落水的点推到岸上兜底）。
const SPAWN_RING_R: number = 1.6;

export class FlyAgents {
  private cfg: FlyConfig;
  private foods: FoodWorld;
  private world: WorldState;
  private obstacles: Obstacles;
  private brains: FlyBrain[] = [];
  private activeCount: number = 0;

  constructor(cfg: FlyConfig, foods: FoodWorld, world: WorldState, obstacles: Obstacles) {
    this.cfg = cfg;
    this.foods = foods;
    this.world = world;
    this.obstacles = obstacles;
    // 全量创建 6 个实例（模型已全部烘焙），用 setActiveCount 决定几只上场
    for (let i = 0; i < MAX_AGENTS; i++) {
      this.brains.push(new FlyBrain(cfg, i, foods, world, obstacles));
    }
    this.setActiveCount(cfg.agentCount);
  }

  getActiveCount(): number {
    return this.activeCount;
  }

  getBrain(i: number): FlyBrain {
    return this.brains[i];
  }

  // 主果蝇（镜头跟随、行为按钮、投喂等交互的默认对象）
  getLead(): FlyBrain {
    return this.brains[0];
  }

  // 全体果蝇的累计死亡数（含未上场的；关于页统计用）
  totalDeaths(): number {
    let sum = 0;
    for (let i = 0; i < this.brains.length; i++) {
      sum += this.brains[i].getDeathCount();
    }
    return sum;
  }

  // 改变上场果蝇数量：新上场的在出生圈上错开，退场的隐藏并释放食物认领
  setActiveCount(n: number): void {
    const count = Math.max(1, Math.min(MAX_AGENTS, Math.round(n)));
    for (let i = 0; i < MAX_AGENTS; i++) {
      const b = this.brains[i];
      if (i < count) {
      if (i >= this.activeCount) {
        // 重新上场：放到出生圈（半径 SPAWN_RING_R 均匀分布），避免与现有果蝇叠在原点
        const ang = i * Math.PI * 2 / count;
        b.spawnAt(SPAWN_RING_R * Math.cos(ang), SPAWN_RING_R * Math.sin(ang));
      }
      } else if (i < this.activeCount) {
        b.despawn();
      }
    }
    this.activeCount = count;
    this.cfg.agentCount = count;
  }

  setPaused(v: boolean): void {
    for (let i = 0; i < this.activeCount; i++) {
      this.brains[i].setPaused(v);
    }
  }

  // 每帧：共享世界推进 → 逐个体行为 → 个体间互动
  update(dt: number): void {
    this.world.update(dt);
    this.foods.update(dt);
    for (let i = 0; i < this.activeCount; i++) {
      this.brains[i].update(dt);
    }
    this.applySeparation();
  }

  // 个体互斥：地面个体间距 < separateDist 时相互推开（O(N²)，N≤6 开销可忽略）。
  // 飞行中的个体不参与（它们在 1.15 高度，地面距离没有意义）。
  private applySeparation(): void {
    const minDist = this.cfg.separateDist;
    for (let i = 0; i < this.activeCount; i++) {
      const a = this.brains[i];
      if (a.isDead() || a.isAirborne()) {
        continue;
      }
      for (let j = i + 1; j < this.activeCount; j++) {
        const b = this.brains[j];
        if (b.isDead() || b.isAirborne()) {
          continue;
        }
        const pa = a.getPose();
        const pb = b.getPose();
        const dx = pb.x - pa.x;
        const dz = pb.z - pa.z;
        const d = Math.hypot(dx, dz);
        if (d >= minDist) {
          continue;
        }
        if (d < 1e-4) {
          // 完全重叠：给一个随机方向各推一半
          const ang = Math.random() * Math.PI * 2;
          a.nudge(-Math.cos(ang) * minDist / 2, -Math.sin(ang) * minDist / 2);
          b.nudge(Math.cos(ang) * minDist / 2, Math.sin(ang) * minDist / 2);
          continue;
        }
        const push = (minDist - d) / 2;
        const ux = dx / d;
        const uz = dz / d;
        a.nudge(-ux * push, -uz * push);
        b.nudge(ux * push, uz * push);
      }
    }
  }
}
