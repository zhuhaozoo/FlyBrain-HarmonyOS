// 果蝇行为大脑：内驱力（饥饿/恐惧/好奇/疲劳）+ 行为状态机 + 环境交互。
// 优先级链对齐 flybrain 项目 fly-logic.js（简化版，详见开发文档 4.4/9.3 节）：
//   startle > fly > feed > groom > brace > rest > phototaxis > seek > wander > idle
// 本类为纯逻辑，不依赖任何 3D/渲染 API，可独立单测。
// M5 多智能体：食物世界（FoodWorld）与世界状态（WorldState，光/风/光斑）改为共享注入，
// 每只果蝇只私有"处境 + 内驱力 + 个体性格系数"；个体差异来源见设计稿 §2.4（处境差异 + 参数扰动）。
import { FlyConfig } from './FlyConfig';
import { FoodWorld } from './FoodWorld';
import { Obstacles } from './Obstacles';
import { RiverPath, RiverNearest } from './RiverPath';
import { WorldState } from './WorldState';
import { FlyDeathCause, FoodItem, FlyPose, FlyState } from './FlyTypes';
import { clamp, normalizeAngle } from '../common/Math3D';

const TWO_PI = Math.PI * 2;

export class FlyBrain {
  private cfg: FlyConfig;
  private agentIdx: number = 0;              // 代理编号（争食认领、个体列表用）
  private foods: FoodWorld;                  // 共享食物世界
  private world: WorldState;                 // 共享世界状态（光/风/光斑）
  private obstacles: Obstacles;              // 共享静态障碍（场内石块的碰撞圆）
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
  private flyTimer: number = 0;      // 距下次"自发短飞"判定（enterWander 里按 25~45s 随机重置）

  // ---- 内驱力 ----
  private hunger: number = 0.55;
  private fear: number = 0;
  private curiosity: number = 0.5;

  // ---- 个体性格（M5：参数扰动的载体）----
  private seed: number = 0;          // 个性种子（后期"这只果蝇的一生"可展示）
  private k: number = 1.0;           // 行为参数缩放（0.9~1.1）
  private turnBias: number = 0;      // 漫步固有转向偏好（±0.15 rad/s）
  private lastGustId: number = 0;    // 已处理的阵风编号（新阵风才加一次恐惧）
  private claimedFood: number = -1;  // 正在追逐/进食的食物下标（-1 无）
  private seekBanIdx: number = -1;   // 觅食超时拉黑的食物下标（一直够不到的目标短期内不再锁定）
  private seekBanTimer: number = 0;  // 拉黑剩余时间（秒）
  private stimulusX: number = 0;     // 惊吓刺激来源点
  private stimulusZ: number = 0;
  private startleFreezing: boolean = false;

  // ---- 连接组涌现模式（M3）：放电累积量 ----
  private connMode: boolean = false;
  private connWalk: number = 0;
  private connFeed: number = 0;
  private connGroom: number = 0;
  private connStartle: number = 0;
  private connTurn: number = 0;   // 左右腿群放电差（升级 MaleCNS 后才有真实读数）
  private connWing: number = 0;   // 翅运动群放电合计 → 振翅意图

  // ---- M4：生命值 / 饮水 / 死亡 / 青蛙 ----
  private hp: number = 100;
  private deathCount: number = 0;
  private lastDeathCause: FlyDeathCause = FlyDeathCause.None;
  private nearWaterTimer: number = 0;
  private drankHere: boolean = false;          // 本次临水是否已经喝过（离开水边才重置）
  private beachTimer: number = 0;              // 贴地在河滩上连续停留的时长（秒）
  private beachWet: number = 0;                // 河滩压力 0~1（翅膀打湿程度，见 updateBeachStress）
  private river: RiverPath = new RiverPath([], 0.7);
  private riverNearest: RiverNearest = new RiverNearest();
  private drinkGainApplied: boolean = false;
  private feedDoneFlag: boolean = false;       // 刚吃完一份（供页面触发 "+" 特效）
  private frogThreat: boolean = false;         // 青蛙蓄力中（危机提醒）
  private forceTakeoff: boolean = false;       // 被青蛙击中后挣脱起飞
  private feedStreak: number = 0;              // 连续进食次数（轻量成就）
  private trustFlag: boolean = false;          // 连续进食 3 次 → "信任+1"

  constructor(cfg: FlyConfig, agentIdx: number, foods: FoodWorld, world: WorldState,
    obstacles: Obstacles) {
    this.cfg = cfg;
    this.agentIdx = agentIdx;
    this.foods = foods;
    this.world = world;
    this.obstacles = obstacles;
    this.river = new RiverPath(cfg.riverPts, cfg.riverHalfWidth);
    this.hp = cfg.hpStart;
    this.pose.yaw = Math.random() * TWO_PI;
    this.turnTimer = 0.5;
    this.initPersonality();
  }

  // 个性种子 → 行为参数扰动（±10%）+ 固有转向偏好。
  // 处境差异之外的第二差异来源（设计稿 §2.4），避免共用连接组的三只果蝇行为完全同步。
  private initPersonality(): void {
    this.seed = Math.floor(Math.random() * 2147483647);
    let s = this.seed;
    const next = (): number => {
      s = (s * 48271 + 11) % 2147483647;
      return s / 2147483647;
    };
    this.k = 0.9 + next() * 0.2;
    this.turnBias = (next() * 2 - 1) * 0.15;
  }

  getAgentIdx(): number {
    return this.agentIdx;
  }

  getSeed(): number {
    return this.seed;
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
    // 死亡期间冻结内驱力与状态机，只跑重生倒计时。
    // 注意：这里必须用 isDead() 而不是 this.state === FlyState.Dead ——
    // ArkTS 的类型收窄会把 this.state 收窄成"不含 Dead"的联合类型，
    // 导致函数内后续再比较 FlyState.Dead 时报「两类型无重叠」（易错总结第 28 条）。
    if (this.isDead()) {
      this.updateDead();
      return;
    }
    this.updateDrives(dt);
    if (this.isDead()) {
      return; // updateDrives 里可能因伤害致死
    }
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
      case FlyState.Drinking:
        this.updateDrinking(dt);
        break;
      case FlyState.Idle:
        if (this.stateTimer >= this.phaseDuration) {
          this.enterWander();
        }
        break;
      default:
        break;
    }
    this.applyBoundary(dt);
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
    return this.foods.getFoods();
  }

  // 用户投喂槽位数量：foods[0..maxFoods-1] 是投喂，之后是树上果实
  getUserFoodCount(): number {
    return this.foods.getUserFoodCount();
  }

  // 页面在场景加载后把每个果实的水平位置与"挂果高度"告诉行为层（数据来自 glb 节点）
  setFruitPosition(index: number, x: number, z: number, hangY: number): void {
    this.foods.setFruitPosition(index, x, z, hangY);
  }

  // 出生/激活时摆放位置（多果蝇在出生圈上错开，避免全部叠在原点）
  spawnAt(x: number, z: number): void {
    this.releaseClaim();
    const p = this.groundSpawnPoint(x, z);
    this.pose.x = p[0];
    this.pose.z = p[1];
    this.pose.y = 0;
    this.pose.yaw = Math.random() * TWO_PI;
    this.enterWander();
  }

  // 退场（数量调小）：释放认领即可；渲染层负责隐藏节点，协调器不再驱动它
  despawn(): void {
    this.releaseClaim();
    this.frogThreat = false;
  }

  // 个体互斥（FlyAgents 调用）：把姿态推开一小步，边界下一帧统一处理
  nudge(dx: number, dz: number): void {
    this.pose.x += dx;
    this.pose.z += dz;
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
    return this.world.getLightLevel();
  }

  // 当前风力强度 0~1（阵风期间 >0；渲染层据此驱动树木摇摆与风线）
  getWindStrength(): number {
    return this.world.getWindStrength();
  }

  isSpotActive(): boolean {
    return this.world.isSpotActive();
  }

  getSpotX(): number {
    return this.world.getSpotX();
  }

  getSpotZ(): number {
    return this.world.getSpotZ();
  }

  // ---------- M4：生命值 / 死亡 ----------
  getHp(): number {
    return this.hp;
  }

  getHpRatio(): number {
    return clamp(this.hp / this.cfg.hpMax, 0, 1);
  }

  isDead(): boolean {
    return this.state === FlyState.Dead;
  }

  getDeathCount(): number {
    return this.deathCount;
  }

  getLastDeathCause(): FlyDeathCause {
    return this.lastDeathCause;
  }

  // 死亡到重生的剩余秒数（UI 文案用）
  getRespawnCountdown(): number {
    if (!this.isDead()) {
      return 0;
    }
    return Math.max(0, this.cfg.deathDuration - this.stateTimer);
  }

  // 吃完一份食物的瞬时事件（页面据此触发 "+" 特效），读取即清除
  consumeFeedDone(): boolean {
    const v = this.feedDoneFlag;
    this.feedDoneFlag = false;
    return v;
  }

  // 连续进食 3 次（轻量成就「信任+1」），读取即清除
  consumeTrustUp(): boolean {
    const v = this.trustFlag;
    this.trustFlag = false;
    return v;
  }

  // ---------- M4：青蛙事件接口（由页面/青蛙控制器驱动，行为层只做逻辑响应） ----------
  // 蓄力预警：供状态行显示「⚠ 天敌！」并提供救援窗口
  setFrogThreat(on: boolean): void {
    this.frogThreat = on;
  }

  isFrogThreat(): boolean {
    return this.frogThreat;
  }

  // 被舌头命中：先被"叼住"拖到青蛙嘴边，再按伤情分两种结局（M5P1.3 起：
// 伤害由 frogHitDamage 决定，默认 60 < 满血 100 ⇒ 首咬不致死）：
//   1) HP 归零 → 在嘴边毙命（尸体隐藏 deathDuration 秒后原点重生，数量可见地减一）；
//   2) 仍活着 → **挣脱起飞**：僵一下 → 背向青蛙逃窜 1.4s → 起飞（forceTakeoff 在这里置位）。
  hitByFrog(frogX: number, frogZ: number): void {
    if (this.isDead()) {
      return;
    }
    this.frogThreat = false;
    const dx = this.pose.x - frogX;
    const dz = this.pose.z - frogZ;
    const l = Math.max(1e-4, Math.hypot(dx, dz));
    const k = 0.28 / l;   // 拖到青蛙嘴前 0.28 处
    this.pose.x = frogX + dx * k;
    this.pose.z = frogZ + dz * k;
    this.damage(this.cfg.frogHitDamage, FlyDeathCause.Frog);
    if (this.isDead()) {
      return;   // 咬死：原地（青蛙嘴边）毙命
    }
    // 挣脱：恐惧拉满，刺激源记为青蛙，逃窜结束后起飞
    this.fear = clamp(this.fear + 0.6, 0, 1);
    this.stimulusX = frogX;
    this.stimulusZ = frogZ;
    this.forceTakeoff = true;
    this.enterStartle();
  }

  // ---------- M4：河域判定（v7：蜿蜒河道折线，纯几何，行为层与渲染层共用） ----------
  // (x,z) 是否落在河道水带内
  isInWater(x: number, z: number): boolean {
    return this.river.isWater(x, z);
  }

  // 是否临水（含岸边缓冲带，用于饮水彩蛋）
  isNearWater(): boolean {
    return this.river.isNearWater(this.pose.x, this.pose.z, this.cfg.waterNearBand);
  }

  // 连接组涌现模式开关与放电输入
  setConnectomeMode(on: boolean): void {
    this.connMode = on;
    if (!on) {
      this.connWalk = 0;
      this.connFeed = 0;
      this.connGroom = 0;
      this.connStartle = 0;
      this.connTurn = 0;
      this.connWing = 0;
    }
  }

  isConnectomeMode(): boolean {
    return this.connMode;
  }

  setConnectomeDrive(walk: number, feed: number, groom: number, startle: number,
    turn: number, wing: number): void {
    this.connWalk = walk;
    this.connFeed = feed;
    this.connGroom = groom;
    this.connStartle = startle;
    this.connTurn = turn;
    this.connWing = wing;
  }

  // 翅运动群放电合计（页面据此触发"振翅意图"兴奋态；MaleCNS 后才有真实读数）
  getConnWing(): number {
    return this.connWing;
  }

  // ---- 交互 ----
  // 在场景坐标放一份食物（共享食物世界；页面投喂入口）
  placeFood(x: number, z: number): void {
    this.foods.placeFood(x, z);
  }

  // 触碰：落在果蝇附近才算触到（体型 0.6 后半径收窄）；返回是否命中
  touch(x: number, z: number): boolean {
    const d = Math.hypot(this.pose.x - x, this.pose.z - z);
    if (d > 0.40 || this.isAirborne()) {
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
    // 新的一阵风（世界级）：强风加一次恐惧（弱风只触发趴伏，不加恐惧）
    const gid = this.world.getGustId();
    if (gid !== this.lastGustId) {
      this.lastGustId = gid;
      if (this.world.isGustStrong()) {
        this.fear = clamp(this.fear + this.cfg.gustFear, 0, 1);
      }
    }
    this.hunger = clamp(this.hunger + this.cfg.hungerGain * dt, 0, 1);
    this.fear = clamp(this.fear - this.cfg.fearDecay * dt, 0, 1);
    this.curiosity = clamp(this.curiosity + (Math.random() - 0.5) * 0.12 * dt, 0, 1);
    // 自发短飞的倒计时（只在漫步里判定，但计时不中断：休息/理毛完再闲逛够久才飞）
    if (this.flyTimer > 0) {
      this.flyTimer -= dt;
    }
    // 够不到目标的拉黑倒计时
    if (this.seekBanTimer > 0) {
      this.seekBanTimer -= dt;
      if (this.seekBanTimer <= 0) {
        this.seekBanIdx = -1;
      }
    }
    this.updateHp(dt);
    this.updateWaterProximity(dt);
    this.updateEdgeStress(dt);
    this.updateBeachStress(dt);
  }

  // 生命值：饥饿耗尽持续掉血、落水重伤、光斑内晒太阳回血
  private updateHp(dt: number): void {
    if (this.hunger >= this.cfg.feedLowHunger) {
      // 从"有缓冲的阈值"到全饥饿线性升到满额，避免一刀切
      const t = (this.hunger - this.cfg.feedLowHunger) /
        Math.max(1e-6, 1 - this.cfg.feedLowHunger);
      this.damage(this.cfg.hpStarveDrain * t * dt, FlyDeathCause.Hunger);
      if (this.isDead()) {
        return;
      }
    }
    // 落水扣血只在**贴近水面**（y < 0.3）时生效：巡航高度飞越河面是正常过河方式，
    // 不能过一趟河就白掉一截血（此前没有高度判断，跨河一次要掉 ~20 HP）
    if (this.pose.y < 0.3 && this.isInWater(this.pose.x, this.pose.z)) {
      this.damage(this.cfg.hpWaterDrain * dt, FlyDeathCause.Water);
      if (this.isDead()) {
        return;
      }
    }
    if (this.world.isSpotActive() && this.world.getLightLevel() > 0) {
      const d = Math.hypot(this.pose.x - this.world.getSpotX(), this.pose.z - this.world.getSpotZ());
      // 回血圈半径 = 光斑圆盘半径（v6：0.82，与生成脚本 makeDisc(0.82) 成对）的 0.64 倍
      if (d <= 0.52) {
        this.heal(this.cfg.hpSpotGain * dt);
      }
    }
  }

  // 临水驻留计时 → 触发饮水彩蛋。
  // v7.2：**一次临水只喝一次**（drankHere）——原来喝完直接原地再等 drinkWait 秒又喝，
  // 在河滩上就表现为"站着一动不动"（真机反馈②的观感来源之一）。离开水边后才算新的一轮。
  private updateWaterProximity(dt: number): void {
    if (this.isGrounded() && this.state !== FlyState.Drinking &&
      this.state !== FlyState.Startle) {
      if (this.isNearWater()) {
        this.nearWaterTimer += dt;
        if (this.nearWaterTimer >= this.cfg.drinkWait && !this.drankHere) {
          this.nearWaterTimer = 0;
          this.drinkGainApplied = false;
          this.drankHere = true;
          this.enterState(FlyState.Drinking, this.cfg.drinkDuration);
        }
      } else {
        this.nearWaterTimer = 0;
        this.drankHere = false;
      }
    }
  }

  // 河滩软边界（v7.2）：贴地在河滩上待太久 → 越待越难受，自己走上岸。
  // 与 updateEdgeStress 同款"深度线性升到满值"的口径，区别是深度换成停留时长：
  //   停留 ≤ beachGrace 秒：零压力（正常路过 / 饮水不受罚）；
  //   之后 beachRamp 秒内线性升到满值：饥饿 ×(1+beachHungerMul)、疲劳 ×(1+beachFatigueMul)。
  // 压力值 beachWet 同时是"翅膀打湿程度"，被 checkUrgent / 自发起飞判定与
  // applyBoundary 的背离河道转向偏置共用。河滩压在软边界内侧，不额外扣血（不像出界那样"迷失"）。
  private updateBeachStress(dt: number): void {
    const onBeach = this.isGrounded() &&
      this.river.isNearWater(this.pose.x, this.pose.z, this.cfg.beachBand);
    if (onBeach) {
      this.beachTimer += dt;
    } else {
      this.beachTimer = 0;
    }
    const over = this.beachTimer - this.cfg.beachGrace;
    const f = over <= 0 ? 0 : clamp(over / Math.max(1e-6, this.cfg.beachRamp), 0, 1);
    this.beachWet = f;
    if (f <= 0) {
      return;
    }
    this.hunger = clamp(this.hunger + this.cfg.hungerGain * this.cfg.beachHungerMul * f * dt, 0, 1);
    this.fatigue = clamp(this.fatigue + this.cfg.fatigueGain * this.cfg.beachFatigueMul * f * dt, 0, 1);
  }

  // 软边界压力（M5.2）：越过活动半径后没有硬墙，改为"越深越难受"——
  // 饥饿/疲劳加速累积、恐惧上升、持续掉血，全部按出界深度线性升到满值。
  // 恐惧的惊吓刺激源设在身体外侧：一旦触发惊吓，逃离方向必然朝向场心。
  // 与 applyBoundary 的向心转向共同构成"果蝇靠神经刺激自己回场"的闭环；
  // 饥饿/疲劳上升后经 setEnvironment 加重 DRIVE_* 驱动群刺激，连接组放电同步上升。
  private updateEdgeStress(dt: number): void {
    const r = Math.hypot(this.pose.x, this.pose.z);
    const edge = this.isAirborne() ? this.cfg.flyArenaRadius : this.cfg.arenaRadius;
    const over = r - edge;
    if (over <= 0) {
      return;
    }
    const f = clamp(over / this.cfg.edgeBand, 0, 1);
    this.hunger = clamp(this.hunger + this.cfg.hungerGain * this.cfg.edgeHungerMul * f * dt, 0, 1);
    this.fatigue = clamp(this.fatigue + this.cfg.fatigueGain * this.cfg.edgeFatigueMul * f * dt, 0, 1);
    this.fear = clamp(this.fear + this.cfg.edgeFearPerSec * f * dt, 0, 1);
    const l = Math.max(1e-4, r);
    this.stimulusX = this.pose.x + this.pose.x / l * 2.0;
    this.stimulusZ = this.pose.z + this.pose.z / l * 2.0;
    this.damage(this.cfg.edgeHpDrain * f * dt, FlyDeathCause.Lost);
  }

  // 高优先级刺激：每帧在任何状态逻辑前检查（对齐 fly-logic 优先级链头部）
  private checkUrgent(): boolean {
    // 河滩压力（翅膀打湿）会抬高"受惊起飞"的门槛：飞行能力下降（v7.2）
    if (this.fear >= this.cfg.flyFear + this.cfg.beachFearAdd * this.beachWet) {
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
    // 风：弱风趴伏（风是世界状态，所有果蝇感受同一阵）
    const wind = this.world.getWindStrength();
    if (wind > 0 && !this.world.isGustStrong()) {
      this.enterState(FlyState.Brace, this.cfg.windDuration);
      return;
    }
    // 饥饿觅食（内驱力驱动 或 连接组舐吸运动群放电驱动）
    const wantFeed = this.hunger >= this.cfg.hungerSeek * this.k ||
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
    // 疲劳休息（黑暗环境阈值更低，fly-logic 语义；个体性格扰动阈值）
    const restLine = Math.min(1, (this.world.getLightLevel() === 0
      ? this.cfg.restThresholdDark : this.cfg.restThreshold) * this.k);
    this.fatigue = clamp(this.fatigue + this.cfg.fatigueGain * this.k * dt, 0, 1);
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
    // 自发短飞（M5：此前飞行只能靠受惊或按钮触发，果蝇从不主动飞）：
    // 闲逛够久就掷一次骰子，命中且不累不惊 → 自己起飞巡游 flyDurationMin~Max 一段
    if (this.flyTimer <= 0) {
      this.flyTimer = this.randRange(this.cfg.flyCheckMin, this.cfg.flyCheckMax);
      // 翅膀打湿（河滩压力）时不自发起飞：飞行能力下降（v7.2）
      if (this.fatigue <= this.cfg.flyMaxFatigue && this.fear <= this.cfg.flyMaxFear &&
        this.beachWet <= this.cfg.beachFlyMaxWet &&
        Math.random() < this.cfg.flyChance) {
        this.enterState(FlyState.Takeoff, this.cfg.takeoffDuration);
        return;
      }
    }
    // 漫步移动 + 趋光偏置 + 个体固有转向偏好；连接组模式下步行速度受 VNC_CPG 放电调制
    this.turnTimer -= dt;
    if (this.turnTimer <= 0) {
      this.turn = (Math.random() * 2 - 1) * this.cfg.turnRate * this.k + this.turnBias;
      this.turnTimer = 0.4 + Math.random() * 0.9;
    }
    let steer = this.turn;
    if (this.world.getLightLevel() > this.cfg.phototaxisLight &&
      this.curiosity > this.cfg.phototaxisCuriosity && this.world.isSpotActive()) {
      steer += clamp(this.steerDelta(this.world.getSpotX(), this.world.getSpotZ()),
        -this.cfg.turnRate, this.cfg.turnRate) * 0.9;
    }
    // 连接组转向调制：左右腿运动群放电差（MaleCNS 升级后才有真实读数；
    // FAFB 下恒 0，此分支不生效）
    if (this.connMode && Math.abs(this.connTurn) >= this.cfg.connTurnG) {
      steer += clamp(this.connTurn * 0.35, -this.cfg.turnRate, this.cfg.turnRate);
    }
    this.pose.yaw = normalizeAngle(this.pose.yaw + steer * dt);
    const walkMul = this.connMode ? 0.7 + Math.min(1.3, this.connWalk * 0.15) : 1.0;
    this.advance(dt, this.cfg.walkSpeed * this.k * this.cfg.speedScale * walkMul);
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
      this.turn = (Math.random() * 2 - 1) * this.cfg.turnRate * 0.6 * this.k + this.turnBias * 0.5;
      this.turnTimer = 0.8 + Math.random() * 1.2;
    }
    this.pose.yaw = normalizeAngle(this.pose.yaw + this.turn * dt);
    this.advance(dt, this.cfg.flySpeed * this.cfg.speedScale);
    this.pose.y = this.cfg.flyHeight + Math.sin(this.total * 2.2) * 0.15;
    this.fatigue = clamp(this.fatigue + this.cfg.fatigueFlyGain * dt, 0, 1);
    if (this.stateTimer >= this.phaseDuration) {
      // 正下方是水域时先不降落——继续飞到岸外再落（水带最宽 2.55，最多多飞 ~1s）。
      // 否则会"降落在河中央"，随后被河岸处理推到岸边（自动巡航不主动把果蝇投进水里；
      // 手动「降落」按钮不受此限制，落进水里会被就近推上岸）
      if (this.isInWater(this.pose.x, this.pose.z)) {
        this.phaseDuration = this.stateTimer + 0.2;
        return;
      }
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
      if (this.forceTakeoff) {
        // 被青蛙击中后挣脱起飞
        this.forceTakeoff = false;
        this.fear = clamp(this.fear + 0.3, 0, 1);
        this.enterState(FlyState.Takeoff, this.cfg.takeoffDuration);
      } else {
        this.enterWander();
      }
    }
  }

  // 进食：停在认领的食物上吃，食物逐渐消失；吃完一份回血并置完成标记
  private updateFeed(dt: number): void {
    if (this.checkUrgent()) {
      return;
    }
    this.pose.y = 0;
    // 优先吃自己认领的那份（Seek→Feed 全程锁定）；认领丢了再找
    let idx = this.claimedFood;
    if (idx < 0 || !this.foods.getFoods()[idx].active) {
      this.releaseClaim();
      const found = this.nearestFood(0);
      if (found === null) {
        this.enterWander();
        return;
      }
      this.foods.claim(found, this.agentIdx);
      this.claimedFood = found;
      idx = found;
    }
    const food = this.foods.getFoods()[idx];
    food.eaten = clamp(food.eaten + dt / (this.cfg.eatDuration / this.k), 0, 1);
    this.hunger = clamp(this.hunger - 0.12 * dt, 0, 1);
    this.fatigue = clamp(this.fatigue - 0.005 * dt, 0, 1);
    if (food.eaten >= 1) {
      // consume 内部会失活食物并安排果实重新结果，nearestFood 不再返回它，
      // 因此这里的回血与特效标记只会触发一次
      this.foods.consume(idx, this.agentIdx);
      this.claimedFood = -1;
      this.heal(this.cfg.hpEatGain);
      this.feedDoneFlag = true;
      // 轻量成就：连续吃完 3 份 → 「信任+1」
      this.feedStreak++;
      if (this.feedStreak >= 3) {
        this.feedStreak = 0;
        this.trustFlag = true;
      }
    }
    if (food.eaten >= 1 || this.hunger <= this.cfg.hungerStop) {
      this.enterWander();
    }
  }

  // 饮水彩蛋：河岸边低头 3 秒，中途离开或受惊则中断
  private updateDrinking(dt: number): void {
    if (this.checkUrgent()) {
      return;
    }
    this.pose.y = 0;
    if (!this.isNearWater()) {
      this.enterWander();
      return;
    }
    if (!this.drinkGainApplied && this.stateTimer >= this.cfg.drinkDuration * 0.6) {
      this.drinkGainApplied = true;
      this.heal(this.cfg.hpDrinkGain);
    }
    if (this.stateTimer >= this.cfg.drinkDuration) {
      this.enterWander();
    }
  }

  // 死亡：翻面躺地，倒计时结束后原点重生
  private updateDead(): void {
    this.pose.y = 0;
    if (this.stateTimer >= this.cfg.deathDuration) {
      this.respawn();
    }
  }

  // 趴伏：弱风中贴地不动
  private updateBrace(dt: number): void {
    if (this.checkUrgent()) {
      return;
    }
    this.pose.y = 0;
    if (this.world.getWindStrength() <= 0 || this.stateTimer >= this.phaseDuration) {
      this.enterWander();
    }
  }

  // 觅食：朝最近的食物走，到达即进食；锁定目标 = 争食的"先到先得"
  private updateSeek(dt: number): void {
    if (this.checkUrgent()) {
      return;
    }
    const idx = this.nearestFood(0);
    if (idx === null || this.stateTimer >= this.phaseDuration) {
      // 超时说明目标一直够不到（地形挡住等）：短期拉黑它——换个目标，或先回去逛
      if (idx !== null) {
        this.seekBanIdx = idx;
        this.seekBanTimer = this.cfg.seekBanSeconds;
      }
      this.enterWander();
      return;
    }
    // 认领目标（nearestFood 已跳过别人认领的，claim 必然成功）；换目标先释放旧认领
    if (idx !== this.claimedFood) {
      this.releaseClaim();
      this.foods.claim(idx, this.agentIdx);
      this.claimedFood = idx;
    }
    const food = this.foods.getFoods()[idx];
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
    // 回到漫步即重置"自发短飞"的倒计时：闲逛够久才考虑飞，落地后不会立刻又起飞
    this.flyTimer = this.randRange(this.cfg.flyCheckMin, this.cfg.flyCheckMax);
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
    // 离开觅食/进食状态时释放食物认领（争食标记）
    if (s !== FlyState.Seek && s !== FlyState.Feed) {
      this.releaseClaim();
    }
    this.state = s;
    this.stateTimer = 0;
    this.phaseDuration = duration;
  }

  // 释放当前认领的食物
  private releaseClaim(): void {
    if (this.claimedFood >= 0) {
      this.foods.release(this.claimedFood, this.agentIdx);
      this.claimedFood = -1;
    }
  }

  // ---------- M4：伤害 / 治疗 / 死亡 / 重生 ----------
  private damage(amount: number, cause: FlyDeathCause): void {
    if (this.isDead()) {
      return;
    }
    this.hp = clamp(this.hp - amount, 0, this.cfg.hpMax);
    if (this.hp <= 0) {
      this.die(cause);
    }
  }

  private heal(amount: number): void {
    if (this.isDead()) {
      return;
    }
    this.hp = clamp(this.hp + amount, 0, this.cfg.hpMax);
  }

  private die(cause: FlyDeathCause): void {
    if (this.isDead()) {
      return;
    }
    this.deathCount++;
    this.lastDeathCause = cause;
    this.frogThreat = false;
    this.forceTakeoff = false;
    this.nearWaterTimer = 0;
    this.foods.releaseAll(this.agentIdx);
    this.claimedFood = -1;
    this.enterState(FlyState.Dead, this.cfg.deathDuration);
    this.pose.y = 0;
  }

  // 原点重生：HP 与全部内驱力重置（场上食物保留，不清除用户的投喂）
  private respawn(): void {
    // 出生点必须是"能站的地面"：v7 的河道穿过场心，原点 (0,0) 就在水里（距中心线 0.39 < 0.7），
    // 直接重生会一头扎进水里、被推上岸后可能压在河岸卵石上（真机反馈的"中央静止果蝇"）
    const p = this.groundSpawnPoint(0, 0);
    this.pose.x = p[0];
    this.pose.z = p[1];
    this.pose.y = 0;
    this.pose.yaw = Math.random() * TWO_PI;
    this.hp = this.cfg.hpRespawn;
    this.hunger = 0.55;
    this.fear = 0;
    this.fatigue = 0;
    this.curiosity = 0.5;
    this.nearWaterTimer = 0;
    this.drankHere = false;
    this.beachTimer = 0;
    this.beachWet = 0;
    this.frogThreat = false;
    this.forceTakeoff = false;
    this.feedStreak = 0;
    this.turn = 0;
    this.turnTimer = 0.3;
    this.groomTimer = 8;
    this.enterWander();
  }

  // 把出生/重生点修到可站立的地面：推离水域（沿河道法向推到近岸外侧 0.30），
  // 再推出所有阻挡圆；推出后可能又落回水线附近，最多迭代 3 轮直到两个约束都满足。
  // 只在出生/重生时调用（不是每帧），这里 new 一个 RiverNearest 无性能问题。
  private groundSpawnPoint(x: number, z: number): number[] {
    const bank = this.cfg.riverHalfWidth + 0.30;
    let px = x;
    let pz = z;
    for (let pass = 0; pass < 3; pass++) {
      const rn = this.river.nearest(px, pz);
      if (rn.d < bank) {
        px = rn.cx + rn.nx * bank;
        pz = rn.cz + rn.nz * bank;
      }
      const pushed = this.obstacles.pushOut(px, pz, this.cfg.bodyRadius + 0.05);
      const moved = Math.hypot(pushed[0] - px, pushed[1] - pz);
      px = pushed[0];
      pz = pushed[1];
      if (moved < 1e-4 && this.river.nearest(px, pz).d >= bank) {
        break;
      }
    }
    return [px, pz];
  }

  // 是否在空中（FlyAgents 的个体互斥只作用于地面个体，故公开）
  isAirborne(): boolean {
    return this.state === FlyState.Fly || this.state === FlyState.Takeoff;
  }

  private isGrounded(): boolean {
    return !this.isAirborne() && this.state !== FlyState.Land;
  }

  // 最近的可食食物下标；none 时返回 null（minDist 保留参数语义：目前恒为 0）。
  // 委托给共享食物世界：被其他果蝇认领的目标会被跳过（争食：先到先得）；
  // 本体拉黑的目标（超时仍够不到）也跳过，防止"超时→再锁定同一目标"的绕圈死循环
  private nearestFood(minDist: number): number | null {
    const idx = this.foods.nearestFood(this.pose.x, this.pose.z, minDist, this.agentIdx);
    if (idx !== null && idx === this.seekBanIdx) {
      return null;
    }
    return idx;
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

  // 边界处理：河域斥力 + 场内石块碰撞 + 软边界向心转向。
  // 步行软边界为 arenaRadius（v6：9.0），飞行可放到 flyArenaRadius（10.8，越过河流外沿 9.9）。
  // M5.2 起不再有硬钳制：越过软边界就开始向心转向，出界越深转向越强（edgeTurnBoost），
  // 出界的代价由 updateEdgeStress 的负面内驱力承担 —— 果蝇靠"转向 + 越待越难受"自己回场。
  // （转向步长改为 ×dt，帧率无关；原来写死 0.016 在低帧率下回转会更慢。）
  private applyBoundary(dt: number): void {
    // 1) 河域：把河当作两条岸线。贴地（含降落末段）个体进入水带时，
    //    沿法向推到更近的一侧岸边，并沿岸切向滑动（与绕石头同款手感）；
    //    巡航高度（y ≥ 0.3）照常从水面上方掠过。
    if (!this.isAirborne() && this.pose.y < 0.3) {
      const rn = this.riverNearest;
      const moved = this.river.pushOut(this.pose.x, this.pose.z, 0.05, rn);
      if (moved) {
        this.pose.x = rn.cx;
        this.pose.z = rn.cz;
        // 沿岸滑动：切向 = 法向 ±90°，选与当前朝向夹角更小的一侧
        const t1 = Math.atan2(-rn.nz, rn.nx);
        const t2 = Math.atan2(rn.nz, -rn.nx);
        const d1 = Math.abs(normalizeAngle(t1 - this.pose.yaw));
        const d2 = Math.abs(normalizeAngle(t2 - this.pose.yaw));
        const want = d1 <= d2 ? t1 : t2;
        this.pose.yaw = normalizeAngle(this.pose.yaw +
          clamp(normalizeAngle(want - this.pose.yaw),
            -this.cfg.obstacleTurn * dt, this.cfg.obstacleTurn * dt));
      }
    }

    // 2) 静态障碍（石块/卵石/树干）：贴地时被阻挡（沿障碍滑走），高空飞行可越过
    if (!this.isAirborne() && this.pose.y < 0.3) {
      this.obstacles.resolve(this.pose, this.cfg.bodyRadius, this.cfg.obstacleTurn * dt);
    }

    // 3) 软边界向心转向（无硬钳制）
    const r = Math.hypot(this.pose.x, this.pose.z);
    const softLimit = this.isAirborne() ? this.cfg.flyArenaRadius : this.cfg.arenaRadius;
    if (r > softLimit && r > 1e-4) {
      const f = clamp((r - softLimit) / this.cfg.edgeBand, 0, 1);
      const toCenter = Math.atan2(-this.pose.x, -this.pose.z);
      const diff = normalizeAngle(toCenter - this.pose.yaw);
      // 出界越深转向越强：把"最坏过冲"压回有限范围（步行 ≈0.4、迎头飞行 ≈0.5，
      // 草地盘半径 11.0 内）。逐帧小步转向，步长与 dt 成比例（帧率无关）。
      const maxTurn = this.cfg.turnRate * 2.2 * (1 + this.cfg.edgeTurnBoost * f) * dt;
      this.pose.yaw = normalizeAngle(this.pose.yaw + clamp(diff, -maxTurn, maxTurn));
    }

    // 4) 河滩软边界转向（v7.2）：在河滩上待久了就朝背离河道的方向偏——"劝"它自己走上岸。
    //    与 3) 同款逐帧限速（步长 ×dt），压力越大偏得越快；走上岸后 beachWet 归零即自动停止。
    if (this.beachWet > 0 && !this.isAirborne()) {
      const rnBeach = this.river.nearest(this.pose.x, this.pose.z);
      const away = Math.atan2(rnBeach.nx, rnBeach.nz);
      const diff = normalizeAngle(away - this.pose.yaw);
      const maxTurn = this.cfg.turnRate * (1 + this.cfg.beachTurnBoost * this.beachWet) * dt;
      this.pose.yaw = normalizeAngle(this.pose.yaw + clamp(diff, -maxTurn, maxTurn));
    }
  }

  private smoothStep(t: number): number {
    return t * t * (3 - 2 * t);
  }

  private randRange(min: number, max: number): number {
    return min + Math.random() * (max - min);
  }
}
