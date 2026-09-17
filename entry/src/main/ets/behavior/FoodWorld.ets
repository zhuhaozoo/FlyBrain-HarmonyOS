// 共享食物世界（M5）：用户投喂 + 树上果实的唯一事实源。
// M4 及之前这份状态私有于单个 FlyBrain；多果蝇必须共享同一份食物，
// "先到先得"的争食才有载体：claimedBy 记录哪只果蝇（代理编号）正把它当目标。
// 纯逻辑类，不依赖任何 3D/渲染 API。
import { FlyConfig } from './FlyConfig';
import { Obstacles } from './Obstacles';
import { RiverPath, RiverNearest } from './RiverPath';
import { FoodItem } from './FlyTypes';
import { clamp } from '../common/Math3D';

export class FoodWorld {
  private cfg: FlyConfig;
  private obstacles: Obstacles;        // 共享静态障碍：投喂落点要避开石块
  private river: RiverPath = new RiverPath([], 0.7);   // 蜿蜒河道（v7）
  private riverNearest: RiverNearest = new RiverNearest();
  private foods: FoodItem[] = [];
  private claimedBy: number[] = [];   // -1 = 无人占用
  private userCount: number = 0;

  constructor(cfg: FlyConfig, obstacles: Obstacles) {
    this.cfg = cfg;
    this.obstacles = obstacles;
    this.river = new RiverPath(cfg.riverPts, cfg.riverHalfWidth);
    this.userCount = cfg.maxFoods;
    // 槽位 0..maxFoods-1：用户投喂；紧随其后 fruitCount 个：树上果实
    for (let i = 0; i < cfg.maxFoods; i++) {
      this.foods.push(new FoodItem());
      this.claimedBy.push(-1);
    }
    for (let i = 0; i < cfg.fruitCount; i++) {
      const f = new FoodItem();
      f.kind = 1;
      this.foods.push(f);
      this.claimedBy.push(-1);
    }
  }

  getFoods(): FoodItem[] {
    return this.foods;
  }

  // 用户投喂槽位数量：foods[0..maxFoods-1] 是投喂，之后是树上果实
  getUserFoodCount(): number {
    return this.userCount;
  }

  // 页面在场景加载后把每个果实的水平位置与"挂果高度"告诉行为层（数据来自 glb 节点）。
  // 运行时兜底：落点钳在步行可达范围内（软边界内；河流弧上再往里收到内岸）——
  // 否则够不到的果实会让果蝇围着树转圈（P1 真机踩过的坑）。
  setFruitPosition(index: number, x: number, z: number, hangY: number): void {
    const slot = this.userCount + index;
    if (slot < 0 || slot >= this.foods.length) {
      return;
    }
    let px = x;
    let pz = z;
    const r = Math.hypot(px, pz);
    const limit = this.cfg.arenaRadius - 0.25;
    if (r > limit && r > 1e-4) {
      const k = limit / r;
      px *= k;
      pz *= k;
    }
    // v7：河道蜿蜒折线 —— 果实落点压进水带时沿法向推到近岸外侧
    const rn = this.riverNearest;
    if (this.river.pushOut(px, pz, 0.45, rn)) {
      px = rn.cx;
      pz = rn.cz;
    }
    // 落点若压在石块的阻挡圆里，沿径向推出 —— 果实落在石头里会变成永远够不到的目标
    const out2 = this.obstacles.pushOut(px, pz, this.cfg.bodyRadius);
    px = out2[0];
    pz = out2[1];
    const f = this.foods[slot];
    f.x = px;
    f.z = pz;
    f.hangY = hangY;
    f.y = hangY;
    f.kind = 1;
    f.eaten = 0;
    f.ready = false;
    f.active = false;      // 未落地不可食
    f.respawn = 0;
    f.fallT = 0;
  }

  // 在场景坐标放一份食物（复用最旧的非活跃用户槽位；不占用果实槽位）
  placeFood(x: number, z: number): void {
    let slot: FoodItem | null = null;
    for (let i = 0; i < this.userCount && i < this.foods.length; i++) {
      if (!this.foods[i].active) {
        slot = this.foods[i];
        break;
      }
    }
    if (slot === null) {
      slot = this.foods[0]; // 满了就覆盖第 0 份
    }
    // 落点先经两道约束，保证食物一定落在果蝇**走得到**的地面上：
    // 1) 推出石块阻挡圆（否则食物埋进石头里，果蝇只会顶着石壁干等 seekTimeout）；
    // 2) 河流弧带是步行禁区：点在水面上时把食物收到内岸 —— 否则同样永远够不到
    const out = this.obstacles.pushOut(x, z, this.cfg.bodyRadius);
    let px = out[0];
    let pz = out[1];
    // v7：河道蜿蜒折线 —— 点在水面上时把食物推到近岸（否则果蝇永远够不到）
    const rn = this.riverNearest;
    if (this.river.pushOut(px, pz, 0.3, rn)) {
      px = rn.cx;
      pz = rn.cz;
    }
    let r = Math.hypot(px, pz);
    if (r > this.cfg.arenaRadius) {
      const k = this.cfg.arenaRadius / r;
      px *= k;
      pz *= k;
    }
    slot.x = px;
    slot.z = pz;
    slot.y = this.cfg.fruitGroundY;
    slot.eaten = 0;
    slot.active = true;
    slot.kind = 0;
    slot.dropT = 0;   // 触发"弹跳落地"（渲染层按 dropT 计算高度）
  }

  // 最近的可食食物下标；skipAgent 的占用食物会被跳过（别人正吃着/赶过去的），
  // 但自己占用的仍会返回 —— 保证 Seek→Feed 全程锁定同一份。
  nearestFood(x: number, z: number, minDist: number, skipAgent: number): number | null {
    let best = -1;
    let bestD = 1e9;
    for (let i = 0; i < this.foods.length; i++) {
      const f = this.foods[i];
      if (!f.active || f.eaten >= 1) {
        continue;
      }
      const owner = this.claimedBy[i];
      if (owner !== -1 && owner !== skipAgent) {
        continue;
      }
      const d = Math.hypot(f.x - x, f.z - z);
      if (d > minDist && d < bestD) {
        bestD = d;
        best = i;
      }
    }
    return best >= 0 ? best : null;
  }

  // 认领食物（争食：先到先得）。返回是否认领成功
  claim(index: number, agentIdx: number): boolean {
    if (index < 0 || index >= this.foods.length) {
      return false;
    }
    if (this.claimedBy[index] !== -1 && this.claimedBy[index] !== agentIdx) {
      return false;
    }
    this.claimedBy[index] = agentIdx;
    return true;
  }

  // 释放认领（离开觅食/进食、被吃光、死亡时调用）
  release(index: number, agentIdx: number): void {
    if (index >= 0 && index < this.foods.length && this.claimedBy[index] === agentIdx) {
      this.claimedBy[index] = -1;
    }
  }

  releaseAll(agentIdx: number): void {
    for (let i = 0; i < this.claimedBy.length; i++) {
      if (this.claimedBy[i] === agentIdx) {
        this.claimedBy[i] = -1;
      }
    }
  }

  // 果实状态推进 + 被吃光后的收尾。由 FlyAgents 每帧调一次（共享世界只推进一次）
  update(dt: number): void {
    for (let i = 0; i < this.foods.length; i++) {
      const f = this.foods[i];
      if (f.kind !== 1) {
        continue;
      }
      if (f.respawn > 0) {
        f.respawn -= dt;
        if (f.respawn <= 0) {
          f.respawn = 0;
          f.eaten = 0;
          f.ready = false;
          f.active = false;
          f.fallT = 0;
          f.y = f.hangY;      // 重新挂到树冠上，开始下落
        }
        continue;
      }
      if (!f.ready && f.hangY > 0) {
        f.fallT += dt;
        const p = clamp(f.fallT / this.cfg.fruitFallTime, 0, 1);
        f.y = f.hangY * (1 - p) + this.cfg.fruitGroundY * p;
        if (p >= 1) {
          f.y = this.cfg.fruitGroundY;
          f.ready = true;
          f.active = true;    // 落地后才成为觅食目标
        }
      }
    }
  }

  // 吃光一份（FlyBrain.updateFeed 在 eaten>=1 时调用）：失活 + 果实重新结果倒计时 + 释放认领
  consume(index: number, agentIdx: number): void {
    if (index < 0 || index >= this.foods.length) {
      return;
    }
    const f = this.foods[index];
    f.active = false;
    f.ready = false;
    if (f.kind === 1) {
      f.respawn = this.cfg.fruitRespawn;   // 果实：过一会儿重新结果
    }
    this.release(index, agentIdx);
  }
}
