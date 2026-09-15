// 果蝇行为大脑：内驱力（饥饿/恐惧/好奇/疲劳）+ 行为状态机 + 环境交互。
// 优先级链对齐 flybrain 项目 fly-logic.js（简化版，详见开发文档 4.4/9.3 节）：
//   startle > fly > feed > groom > brace > rest > phototaxis > seek > wander > idle
// 本类为纯逻辑，不依赖任何 3D/渲染 API，可独立单测。
import { FlyConfig } from './FlyConfig';
import { FoodItem, FlyPose, FlyState } from './FlyTypes';
import { clamp, normalizeAngle } from '../common/Math3D';

const TWO_PI = Math.PI * 2;

export class FlyBrain {
  private cfg: FlyConfig;
  private pose: FlyPose = new FlyPose();
  private state: FlyState = FlyState.Wander;
  private paused: boolean = false;

  private total: number = 0;         // 累计时间（翅膀/颠簸相位）
  private stateTimer: number = 0;    // 当前状态持续时间
  private phaseDuration: number = 0; // 当前状态的目标时长
  private fatigue: number = 0;
  private turn: number = 0;          // 当前转向速率
  private turnTimer: number = 0;     // 距下次换向
  private groomTimer: number = 8;    // 距下次理毛判定

  // ---- 内驱力（M1）----
  private hunger: number = 0.55;
  private fear: number = 0;
  private curiosity: number = 0.5;

  // ---- 环境刺激 ----
  private foods: FoodItem[] = [];
  private windTimer: number = 0;
  private windStrength: number = 0;
  private lightLevel: number = 1;            // 0 黑暗 / 0.5 昏暗 / 1 明亮
  private spotActive: boolean = false;
  private spotX: number = 0;
  private spotZ: number = 0;
  private stimulusX: number = 0;             // 惊吓刺激来源点
  private stimulusZ: number = 0;
  private startleFreezing: boolean = false;

  // ---- 连接组涌现模式（M3）：放电累积量 ----
  private connMode: boolean = false;
  private connWalk: number = 0;
  private connFeed: number = 0;
  private connGroom: number = 0;
  private connStartle: number = 0;

  constructor(cfg: FlyConfig) {
    this.cfg = cfg;
    this.pose.yaw = Math.random() * TWO_PI;
    this.turnTimer = 0.5;
    for (let i = 0; i < cfg.maxFoods; i++) {
      this.foods.push(new FoodItem());
    }
  }

  // ---------- 对外接口 ----------
  update(dt: number): void {
    if (dt <= 0 || this.paused) {
      return;
    }
    if (dt > 0.05) {
      dt = 0.05; // 切后台回来等大步长场景，防瞬移
    }
    this.total += dt;
    this.stateTimer += dt;
    this.updateDrives(dt);
    switch (this.state) {
      case FlyState.Wander:
        this.updateWander(dt);
        break;
      case FlyState.Groom:
        this.updateGroom(dt);
        break;
      case FlyState.Rest:
        this.updateRest(dt);
        break;
      case FlyState.Takeoff:
        this.updateTakeoff(dt);
        break;
      case FlyState.Fly:
        this.updateFly(dt);
        break;
      case FlyState.Land:
        this.updateLand(dt);
        break;
      case FlyState.Startle:
        this.updateStartle(dt);
        break;
      case FlyState.Feed:
        this.updateFeed(dt);
        break;
      case FlyState.Brace:
        this.updateBrace(dt);
        break;
      case FlyState.Seek:
        this.updateSeek(dt);
        break;
      case FlyState.Idle:
        if (this.stateTimer >= this.phaseDuration) {
          this.enterWander();
        }
        break;
      default:
        break;
    }
    this.applyBoundary();
  }

  getPose(): FlyPose {
    return this.pose;
  }

  getState(): FlyState {
    return this.state;
  }

  getTotalTime(): number {
    return this.total;
  }

  isPaused(): boolean {
    return this.paused;
  }

  setPaused(v: boolean): void {
    this.paused = v;
  }

  getFoods(): FoodItem[] {
    return this.foods;
  }

  // 内驱力读取（UI 显示用）
  getHunger(): number {
    return this.hunger;
  }

  getFear(): number {
    return this.fear;
  }

  getFatigue(): number {
    return this.fatigue;
  }

  getLightLevel(): number {
    return this.lightLevel;
  }

  isSpotActive(): boolean {
    return this.spotActive;
  }

  // 连接组涌现模式开关与放电输入
  setConnectomeMode(on: boolean): void {
    this.connMode = on;
    if (!on) {
      this.connWalk = 0;
      this.connFeed = 0;
      this.connGroom = 0;
      this.connStartle = 0;
    }
  }

  isConnectomeMode(): boolean {
    return this.connMode;
  }

  setConnectomeDrive(walk: number, feed: number, groom: number, startle: number): void {
    this.connWalk = walk;
    this.connFeed = feed;
    this.connGroom = groom;
    this.connStartle = startle;
  }

  // ---- 交互 ----
  // 在场景坐标放一份食物（复用最旧的非活跃槽位）
  placeFood(x: number, z: number): void {
    let slot: FoodItem | null = null;
    for (let i = 0; i < this.foods.length; i++) {
      if (!this.foods[i].active) {
        slot = this.foods[i];
        break;
      }
    }
    if (slot === null) {
      slot = this.foods[0]; // 满了就覆盖第 0 份
    }
    const r = Math.hypot(x, z);
    const k = r > this.cfg.arenaRadius ? this.cfg.arenaRadius / r : 1;
    slot.x = x * k;
    slot.z = z * k;
    slot.eaten = 0;
    slot.active = true;
  }

  // 光照档位：0 黑暗 / 0.5 昏暗 / 1 明亮
  setLightLevel(v: number): void {
    this.lightLevel = v;
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

  getSpotX(): number {
    return this.spotX;
  }

  getSpotZ(): number {
    return this.spotZ;
  }

  // 一阵风
  gust(): void {
    this.windTimer = this.cfg.windDuration;
    this.windStrength = 0.3 + Math.random() * 0.55;
    if (this.windStrength >= this.cfg.braceWindMax) {
      this.fear = clamp(this.fear + this.cfg.gustFear, 0, 1);
    }
  }

  // 触碰：落在果蝇附近才算触到；返回是否命中
  touch(x: number, z: number): boolean {
    const d = Math.hypot(this.pose.x - x, this.pose.z - z);
    if (d > 0.55 || this.isAirborne()) {
      return false;
    }
    this.fear = clamp(this.fear + this.cfg.touchFear, 0, 1);
    this.stimulusX = x;
    this.stimulusZ = z;
    return true;
  }

  // 请求起飞
  takeoff(): void {
    if (!this.isAirborne() && this.state !== FlyState.Land) {
      this.enterState(FlyState.Takeoff, this.cfg.takeoffDuration);
    }
  }

  // 请求降落
  land(): void {
    if (this.state === FlyState.Fly || this.state === FlyState.Takeoff) {
      this.enterState(FlyState.Land, this.cfg.landDuration);
    }
  }

  // 回到漫步
  wanderNow(): void {
    if (this.state === FlyState.Fly || this.state === FlyState.Takeoff) {
      this.land();
      return;
    }
    if (this.state !== FlyState.Land) {
      this.enterWander();
    }
  }

  // 立即理毛（地面状态可用）
  groomNow(): void {
    if (this.isGrounded()) {
      this.enterGroom();
    }
  }

  // ---------- 内驱力与全局优先级 ----------
  private updateDrives(dt: number): void {
    this.hunger = clamp(this.hunger + this.cfg.hungerGain * dt, 0, 1);
    this.fear = clamp(this.fear - this.cfg.fearDecay * dt, 0, 1);
    this.curiosity = clamp(this.curiosity + (Math.random() - 0.5) * 0.12 * dt, 0, 1);
    if (this.windTimer > 0) {
      this.windTimer -= dt;
    }
  }

  // 高优先级刺激：每帧在任何状态逻辑前检查（对齐 fly-logic 优先级链头部）
  private checkUrgent(): boolean {
    if (this.fear >= this.cfg.flyFear) {
      this.takeoff();
      return true;
    }
    if (this.fear >= this.cfg.startleFear && this.isGrounded() &&
      this.state !== FlyState.Startle && this.state !== FlyState.Land) {
      this.enterStartle();
      return true;
    }
    // 涌现：机械感受群放电率超阈值 → 惊吓（连接组模式）
    if (this.connMode && this.connStartle >= this.cfg.connStartleG && this.isGrounded() &&
      this.state !== FlyState.Startle && this.state !== FlyState.Land) {
      this.stimulusX = this.pose.x;
      this.stimulusZ = this.pose.z + 1;
      this.enterStartle();
      return true;
    }
    return false;
  }

  // ---------- 各状态 ----------
  private updateWander(dt: number): void {
    if (this.checkUrgent()) {
      return;
    }
    // 风：弱风趴伏
    if (this.windTimer > 0 && this.windStrength < this.cfg.braceWindMax) {
      this.enterState(FlyState.Brace, this.windTimer);
      return;
    }
    // 饥饿觅食（内驱力驱动 或 连接组舐吸运动群放电驱动）
    const wantFeed = this.hunger >= this.cfg.hungerSeek ||
      (this.connMode && this.connFeed >= this.cfg.connFeedG);
    if (wantFeed && this.nearestFood(0) !== null) {
      this.enterState(FlyState.Seek, this.cfg.seekTimeout);
      return;
    }
    // 涌现：头/腹运动群放电 → 理毛（连接组模式）
    if (this.connMode && this.connGroom >= this.cfg.connGroomG) {
      this.enterGroom();
      return;
    }
    // 疲劳休息（黑暗环境阈值更低，fly-logic 语义）
    const restLine = this.lightLevel === 0 ? this.cfg.restThresholdDark : this.cfg.restThreshold;
    this.fatigue = clamp(this.fatigue + this.cfg.fatigueGain * dt, 0, 1);
    if (this.fatigue >= restLine) {
      this.phaseDuration = this.randRange(this.cfg.restDurationMin, this.cfg.restDurationMax);
      this.enterState(FlyState.Rest, this.phaseDuration);
      return;
    }
    // 周期性理毛判定
    this.groomTimer -= dt;
    if (this.groomTimer <= 0) {
      this.groomTimer = this.randRange(this.cfg.groomCheckIntervalMin, this.cfg.groomCheckIntervalMax);
      if (Math.random() < this.cfg.groomChance) {
        this.enterGroom();
        return;
      }
    }
    // 漫步移动 + 趋光偏置；连接组模式下步行速度受 VNC_CPG 放电调制
    this.turnTimer -= dt;
    if (this.turnTimer <= 0) {
      this.turn = (Math.random() * 2 - 1) * this.cfg.turnRate;
      this.turnTimer = 0.4 + Math.random() * 0.9;
    }
    let steer = this.turn;
    if (this.lightLevel > this.cfg.phototaxisLight && this.curiosity > this.cfg.phototaxisCuriosity &&
      this.spotActive) {
      steer += clamp(this.steerDelta(this.spotX, this.spotZ), -this.cfg.turnRate, this.cfg.turnRate) * 0.9;
    }
    this.pose.yaw = normalizeAngle(this.pose.yaw + steer * dt);
    const walkMul = this.connMode ? 0.7 + Math.min(1.3, this.connWalk * 0.15) : 1.0;
    this.advance(dt, this.cfg.walkSpeed * this.cfg.speedScale * walkMul);
    this.pose.y = this.cfg.walkBobAmp * Math.abs(Math.sin(this.total * this.cfg.walkBobHz));
  }

  private updateGroom(dt: number): void {
    if (this.checkUrgent()) {
      return;
    }
    this.pose.y = 0;
    this.fatigue = clamp(this.fatigue - 0.01 * dt, 0, 1);
    if (this.stateTimer >= this.phaseDuration) {
      this.enterWander();
    }
  }

  private updateRest(dt: number): void {
    if (this.checkUrgent()) {
      return;
    }
    this.pose.y = 0;
    this.fatigue = clamp(this.fatigue - this.cfg.fatigueRecover * dt, 0, 1);
    if (this.fatigue <= this.cfg.wakeThreshold || this.stateTimer >= this.phaseDuration) {
      this.enterWander();
    }
  }

  private updateTakeoff(dt: number): void {
    const e = this.smoothStep(clamp(this.stateTimer / this.cfg.takeoffDuration, 0, 1));
    this.pose.y = this.cfg.flyHeight * e;
    this.advance(dt, 0.25);
    if (this.stateTimer >= this.cfg.takeoffDuration) {
      this.phaseDuration = this.randRange(this.cfg.flyDurationMin, this.cfg.flyDurationMax);
      this.enterState(FlyState.Fly, this.phaseDuration);
    }
  }

  private updateFly(dt: number): void {
    this.turnTimer -= dt;
    if (this.turnTimer <= 0) {
      this.turn = (Math.random() * 2 - 1) * this.cfg.turnRate * 0.6;
      this.turnTimer = 0.8 + Math.random() * 1.2;
    }
    this.pose.yaw = normalizeAngle(this.pose.yaw + this.turn * dt);
    this.advance(dt, this.cfg.flySpeed * this.cfg.speedScale);
    this.pose.y = this.cfg.flyHeight + Math.sin(this.total * 2.2) * 0.15;
    this.fatigue = clamp(this.fatigue + this.cfg.fatigueFlyGain * dt, 0, 1);
    if (this.stateTimer >= this.phaseDuration) {
      this.enterState(FlyState.Land, this.cfg.landDuration);
    }
  }

  private updateLand(dt: number): void {
    const e = this.smoothStep(clamp(this.stateTimer / this.cfg.landDuration, 0, 1));
    const startY = this.cfg.flyHeight;
    this.pose.y = startY * (1 - e);
    this.advance(dt, 0.35);
    if (this.stateTimer >= this.cfg.landDuration) {
      this.fatigue *= 0.5;
      this.enterWander();
    }
  }

  // 惊吓：先僵住，再背向刺激源快速逃离
  private updateStartle(dt: number): void {
    if (this.stateTimer < this.cfg.startleFreeze) {
      this.pose.y = 0;
      return;
    }
    if (this.startleFreezing) {
      this.startleFreezing = false;
      // 朝向背离刺激源的方向
      this.pose.yaw = normalizeAngle(Math.atan2(this.pose.x - this.stimulusX, this.pose.z - this.stimulusZ));
    }
    this.pose.y = this.cfg.walkBobAmp * Math.abs(Math.sin(this.total * this.cfg.walkBobHz * 2));
    this.advance(dt, this.cfg.fleeSpeed * this.cfg.speedScale);
    if (this.stateTimer >= this.cfg.startleFreeze + this.cfg.startleFlee) {
      this.enterWander();
    }
  }

  // 进食：停在食物上吃，食物逐渐消失
  private updateFeed(dt: number): void {
    if (this.checkUrgent()) {
      return;
    }
    this.pose.y = 0;
    const idx = this.nearestFood(0);
    if (idx === null) {
      this.enterWander();
      return;
    }
    const food = this.foods[idx];
    food.eaten = clamp(food.eaten + dt / this.cfg.eatDuration, 0, 1);
    this.hunger = clamp(this.hunger - 0.12 * dt, 0, 1);
    this.fatigue = clamp(this.fatigue - 0.005 * dt, 0, 1);
    if (food.eaten >= 1) {
      food.active = false;
    }
    if (food.eaten >= 1 || this.hunger <= this.cfg.hungerStop) {
      this.enterWander();
    }
  }

  // 趴伏：弱风中贴地不动
  private updateBrace(dt: number): void {
    if (this.checkUrgent()) {
      return;
    }
    this.pose.y = 0;
    if (this.windTimer <= 0 || this.stateTimer >= this.phaseDuration) {
      this.enterWander();
    }
  }

  // 觅食：朝最近的食物走，到达即进食
  private updateSeek(dt: number): void {
    if (this.checkUrgent()) {
      return;
    }
    const idx = this.nearestFood(0);
    if (idx === null || this.stateTimer >= this.phaseDuration) {
      this.enterWander();
      return;
    }
    const food = this.foods[idx];
    const dist = Math.hypot(food.x - this.pose.x, food.z - this.pose.z);
    if (dist <= this.cfg.eatRadius) {
      this.enterState(FlyState.Feed, this.cfg.eatDuration * 2);
      return;
    }
    const delta = this.steerDelta(food.x, food.z);
    this.pose.yaw = normalizeAngle(this.pose.yaw + clamp(delta, -this.cfg.turnRate * 1.5, this.cfg.turnRate * 1.5) * dt);
    this.pose.y = this.cfg.walkBobAmp * Math.abs(Math.sin(this.total * this.cfg.walkBobHz));
    this.advance(dt, this.cfg.walkSpeed * 1.25 * this.cfg.speedScale);
  }

  // ---------- 内部工具 ----------
  private enterWander(): void {
    this.enterState(FlyState.Wander, 0);
    this.turn = 0;
    this.turnTimer = 0.3;
  }

  private enterGroom(): void {
    this.phaseDuration = this.randRange(this.cfg.groomDurationMin, this.cfg.groomDurationMax);
    this.enterState(FlyState.Groom, this.phaseDuration);
  }

  private enterStartle(): void {
    this.startleFreezing = true;
    this.enterState(FlyState.Startle, this.cfg.startleFreeze + this.cfg.startleFlee);
  }

  private enterState(s: FlyState, duration: number): void {
    this.state = s;
    this.stateTimer = 0;
    this.phaseDuration = duration;
  }

  private isAirborne(): boolean {
    return this.state === FlyState.Fly || this.state === FlyState.Takeoff;
  }

  private isGrounded(): boolean {
    return !this.isAirborne() && this.state !== FlyState.Land;
  }

  // 最近活跃食物的下标；none 时返回 null（minDist 保留参数语义：目前恒为 0）
  private nearestFood(minDist: number): number | null {
    let best = -1;
    let bestD = 1e9;
    for (let i = 0; i < this.foods.length; i++) {
      const f = this.foods[i];
      if (!f.active || f.eaten >= 1) {
        continue;
      }
      const d = Math.hypot(f.x - this.pose.x, f.z - this.pose.z);
      if (d > minDist && d < bestD) {
        bestD = d;
        best = i;
      }
    }
    return best >= 0 ? best : null;
  }

  // 朝目标转向的角度差（-PI..PI）
  private steerDelta(tx: number, tz: number): number {
    const want = Math.atan2(tx - this.pose.x, tz - this.pose.z);
    return normalizeAngle(want - this.pose.yaw);
  }

  private advance(dt: number, speed: number): void {
    this.pose.x += Math.sin(this.pose.yaw) * speed * dt;
    this.pose.z += Math.cos(this.pose.yaw) * speed * dt;
  }

  // 超出活动半径时平滑转向圆心
  private applyBoundary(): void {
    const r = Math.hypot(this.pose.x, this.pose.z);
    const limit = this.cfg.arenaRadius - 0.4;
    if (r > limit && r > 1e-4) {
      const toCenter = Math.atan2(-this.pose.x, -this.pose.z);
      const diff = normalizeAngle(toCenter - this.pose.yaw);
      const maxTurn = this.cfg.turnRate * 2.2 * 0.016; // 逐帧小步转向
      this.pose.yaw = normalizeAngle(this.pose.yaw + clamp(diff, -maxTurn, maxTurn));
      if (r > this.cfg.arenaRadius) {
        const k = this.cfg.arenaRadius / r;
        this.pose.x *= k;
        this.pose.z *= k;
      }
    }
  }

  private smoothStep(t: number): number {
    return t * t * (3 - 2 * t);
  }

  private randRange(min: number, max: number): number {
    return min + Math.random() * (max - min);
  }
}
