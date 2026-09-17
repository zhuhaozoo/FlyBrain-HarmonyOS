// 3D 场景主页：沉浸式全屏 + 分类玻璃控制面板 + 大屏右栏布局 + 大脑状态小窗。
// 布局模式（胶囊工具栏 ⇄ 分类面板同槽切换、
// 遮罩收起、≥600vp 且非纵向窗口时控制面板移至右侧）。
// 注意：Component3D 在 DevEco 预览器中不支持渲染，需真机运行。
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { AnimatorOptions, AnimatorResult } from '@kit.ArkUI';
import { Node } from '@kit.ArkGraphics3D';
import { ConnectomeDriver } from '../behavior/ConnectomeDriver';
import { FlyAgents } from '../behavior/FlyAgents';
import { FoodWorld } from '../behavior/FoodWorld';
import { FlyBrain } from '../behavior/FlyBrain';
import { flyConfig } from '../behavior/FlyConfig';
import { Obstacles } from '../behavior/Obstacles';
import { WorldState } from '../behavior/WorldState';
import { FLY_DEATH_NAMES, FLY_STATE_NAMES, FlyDeathCause, FlyState } from '../behavior/FlyTypes';
import { groupLabel, groupRegion, datasetLabel } from '../behavior/NeuronGroups';
import { EnvironmentController } from '../scene/EnvironmentController';
import { FlyRenderer } from '../scene/FlyRenderer';
import { FrogController } from '../scene/FrogController';
import { SceneManager } from '../scene/SceneManager';

const TOOL_TOUCH = 0;
const TOOL_FEED = 1;
const TOOL_SPOT = 2;

// 独立大脑上限（M5P1.1：每只果蝇一个 BrainWorker 实例 = 各自一份完整连接组仿真）。
// 每个实例 ~31MB 内存 + 一个 10Hz 仿真线程，3 个已是中端机的合理上限；
// 同屏果蝇数超过上限时，多出的个体退化为纯阈值驱动（无连接组调制）。
const MAX_INDEPENDENT_BRAINS = 3;

// 大脑小窗"活跃脑区明细"固定 8 行、全部显示（不足补占位）：小窗高度恒定，
// 否则底部「查看 3D 大脑」按钮随放电数据上下跳动、点不中（用户实测反馈）
const GROUP_DETAIL_LINES = 8;

// 隐藏果蝇时把根节点移到的 y（远在地面圆盘与天空穹顶之外）。
// 预置的 6 份果蝇模型都烘焙在原点，未上场的若只写 visible=false，真机上仍会被画出来
// —— 叠在原点就表现为"地图中央多了一只不动的果蝇（像预置模型）"。
// 位置一定会传递给子节点，所以"移出视野"比只改可见性可靠（与场内特效节点埋在 y=-10 同款约定）。
const HIDDEN_FLY_Y: number = -80;

// 控制面板玻璃卡片样式（半透明深底卡片）
const GLASS_BG: string = '#6614141A';
const GLASS_CARD_BG: string = '#59202026';
const GLASS_BORDER: BorderOptions = { width: 0.5, color: '#33FFFFFF' };
const CHIP_BG: string = '#66262630';
const CHIP_BG_ON: string = '#CC3D6B5E';

@Component
export struct ScenePage {
  @Consume('nav') navStack: NavPathStack;
  @StorageProp('fy_is_wide') isWide: boolean = false;
  @StorageProp('fy_top_avoid') topAvoid: number = 40;
  @StorageProp('fy_bottom_avoid') bottomAvoid: number = 24;

  private sceneMgr: SceneManager = new SceneManager();
  // M5 多智能体：共享食物世界与世界状态，FlyAgents 统一持有/驱动全部果蝇；
  // 镜头跟随、行为按钮、投喂等交互默认作用于"主果蝇"（0 号）
  // 静态障碍（石块/河岸卵石/树干）的碰撞圆：场景加载后由 blocker_i 标记节点填入，
  // 必须先于 foods/agents 声明——它们的构造要用到同一个实例
  private obstacles: Obstacles = new Obstacles();
  private foods: FoodWorld = new FoodWorld(flyConfig, this.obstacles);
  private world: WorldState = new WorldState(flyConfig);
  private agents: FlyAgents = new FlyAgents(flyConfig, this.foods, this.world, this.obstacles);
  private renderers: FlyRenderer[] = [];
  // 独立大脑：drivers[i] 就是 i 号果蝇自己的连接组仿真（感觉刺激各自注入、运动群各自读取）
  private drivers: ConnectomeDriver[] = [];
  private env: EnvironmentController = new EnvironmentController(flyConfig);
  private frog: FrogController = new FrogController(flyConfig);
  private sceneOpt: SceneOptions | null = null;
  private animator: AnimatorResult | null = null;
  private lastFrameMs: number = 0;
  private panLast: PanSample = new PanSample();
  private panTwoLast: PanSample = new PanSample();  // 双指平移的上一帧位置
  private pinchBaseRadius: number = 8.0;   // v6：与 SceneManager 的默认 radius 同步（场地放大 1.5 倍）
  private lastState: FlyState = FlyState.Wander;
  private lastDriveTextMs: number = 0;
  private appliedAgentCount: number = flyConfig.agentCount; // 已生效的上场数量（设置页改动轮询生效）
  private areaW: number = 0;
  private areaH: number = 0;
  private pinchFingers: boolean = false;  // 捏合手势进行中（避免滑杆与手势互相打架）
  private lightNames: string[] = ['亮', '暗', '黑'];
  // M4：特效计时（秒）
  private plusFxT: number = -1;           // "+"进食特效
  private plusFxX: number = 0;            // 特效触发位置（哪只吃完就在哪只头顶）
  private plusFxZ: number = 0;
  private lastCycles: number = 0;         // 已完成的昼夜轮数（成就判定）
  private deathsAtCycleStart: number = 0;
  private achiTimer: number = 0;          // 成就文案显示倒计时

  @State private loading: boolean = true;
  @State private loadFailed: boolean = false;
  @State private stateLabel: string = '漫步';
  @State private paused: boolean = false;
  @State private speedValue: number = flyConfig.speedScale;
  @State private tool: number = TOOL_TOUCH;
  @State private driveText: string = '';
  @State private lightIdx: number = 0;   // 0 亮 / 1 暗 / 2 黑
  @State private connState: number = 0;  // 0 关 / 1 加载中 / 2 运行
  @State private activeCat: string = ''; // '' | behavior | interact | sim | view
  @State private brainPopup: boolean = false;
  // 视角控制（缩放滑杆 + 追踪开关 + 人称切换）
  @State private zoomRadius: number = 8.0;   // v6：与 SceneManager.radius 初值同步
  @State private followMode: boolean = false;
  @State private followPerson: number = 0;  // 0 第一人称 / 1 第三人称
  // 焦点果蝇（M5）：追踪镜头、状态行、行为按钮与投喂落点的共同目标，默认 0 号主果蝇；
  // 在「视角」面板开启追踪后可循环切换（数量变化时帧循环会钳回 0 号）
  @State private followIdx: number = 0;
  // 仿真运行统计：必须用 @State 独立变量承载，才能在帧循环里驱动 UI 刷新
  // （直接读 drivers[0].getDrive().xxx 不属于状态变量，值变化不会触发重建）
  @State private connSpikes: number = 0;
  @State private connActive: number = 0;
  @State private connTotal: number = 0;
  @State private connTickMs: number = 0;
  @State private connReady: boolean = false;
  @State private uiBeat: number = 0;  // 心跳自增，保证每轮统计都会触发一次重建
  // 数据集口径（来自运行时 ready 的真实数据，杜绝手写死数字）
  @State private brainScale: string = '';
  @State private datasetName: string = '';
  // M4：生命值 / 天敌预警 / 死亡文案
  @State private hpValue: number = 100;
  @State private crisis: boolean = false;
  @State private deathText: string = '';
  @State private achiText: string = '';
  // 活跃脑区明细：固定 8 行（不足补占位"—"），保证大脑小窗高度恒定
  @State private groupSummary: string = '—';
  @State private groupLines: string[] = ['—', '—', '—', '—', '—', '—', '—', '—'];

  aboutToAppear(): void {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const store = preferences.getPreferencesSync(context, { name: 'flycfg' });
      const saved = store.getSync('speedScale', flyConfig.speedScale) as number;
      if (saved >= 0.2 && saved <= 2.0) {
        flyConfig.speedScale = saved;
        this.speedValue = saved;
      }
      // M4 功能开关（设置页可调，默认开）
      flyConfig.dayNightEnabled = store.getSync('dayNight', flyConfig.dayNightEnabled) as boolean;
      flyConfig.frogEnabled = store.getSync('frogEnabled', flyConfig.frogEnabled) as boolean;
      // M5 同屏果蝇数量（1~6）
      const savedCount = store.getSync('agentCount', flyConfig.agentCount) as number;
      if (savedCount >= 1 && savedCount <= 6) {
        flyConfig.agentCount = Math.round(savedCount);
      }
      // 连接组模式（Lite 瘦身 / 全仿真）持久化；默认 Lite
      flyConfig.connFull = store.getSync('connFull', false) as boolean;

    } catch (err) {
      console.warn(`[FlyBrain] load speed prefs failed: ${JSON.stringify(err)}`);
    }

    this.sceneMgr.init().then((ok: boolean) => {
      this.loading = false;
      if (ok && this.sceneMgr.scene !== null) {
        // 每份果蝇节点树配一个渲染器（未上场的由帧循环隐藏）
        for (let i = 0; i < this.sceneMgr.flySets.length; i++) {
          const set = this.sceneMgr.flySets[i];
          const r = new FlyRenderer(flyConfig);
          r.attach(set.fly, set.wingL, set.wingR, set.headPivot, set.legChains, set.mouthPivot);
          this.renderers.push(r);
        }
        // M4：环境控制器（昼夜/树摆/风线/涟漪）与青蛙控制器接管各自的节点
        this.env.attach(this.sceneMgr.light, this.sceneMgr.camera);
        this.env.setNodes(this.sceneMgr.extraNodes);
        this.frog.setNodes(this.sceneMgr.extraNodes);
        // 把树上果实的位置（顶层节点，position 即世界坐标）交给共享食物世界：
        // 果实成熟后自己落到地面，成为果蝇的自主食物来源
        for (let i = 0; i < this.sceneMgr.fruitNodes.length; i++) {
          const p = this.sceneMgr.fruitNodes[i].position;
          this.foods.setFruitPosition(i, p.x, p.z, p.y);
        }
        // 场内石块的碰撞圆：blocker_i 节点的 translation = 圆心、scale.x = 阻挡半径
        // （生成脚本写入，运行时不做任何几何推算）——果蝇步行不可穿过石块
        this.obstacles.clear();
        for (let i = 0; i < this.sceneMgr.blockerNodes.length; i++) {
          const bn = this.sceneMgr.blockerNodes[i];
          const bp = bn.position;
          this.obstacles.add(bp.x, bp.z, bn.scale.x);
        }
        console.info(`[FlyBrain] obstacles: ${this.obstacles.count()}`);
        this.applyLight(); // 把初始光照档位同步给环境控制器与行为层
        this.sceneOpt = { scene: this.sceneMgr.scene, modelType: ModelType.SURFACE } as SceneOptions;
        this.loadFailed = this.renderers.length === 0 || !this.renderers[0].isAttached();
        this.startLoop();
        // 仿真默认开启（M3）
        this.toggleConnectome();
      } else {
        this.loadFailed = true;
      }
    });
  }

  aboutToDisappear(): void {
    if (this.animator !== null) {
      (this.animator as AnimatorResult).finish();
      this.animator = null;
    }
    for (const d of this.drivers) {
      d.stop();
    }
    this.drivers = [];
  }

  private animateToggle(fn: () => void): void {
    this.getUIContext().animateTo({ duration: 220, curve: Curve.Friction }, fn);
  }

  private startLoop(): void {
    this.lastFrameMs = Date.now();
    const options: AnimatorOptions = {
      duration: 16,
      easing: 'linear',
      delay: 0,
      fill: 'none',
      direction: 'normal',
      iterations: -1,
      begin: 0,
      end: 1,
    };
    this.animator = this.getUIContext().createAnimator(options);
    (this.animator as AnimatorResult).onFrame = () => {
      const now = Date.now();
      const dt = Math.min((now - this.lastFrameMs) / 1000, 0.05);
      this.lastFrameMs = now;

      // 设置页改了数量 → 在帧循环里轮询生效（ScenePage 常驻，aboutToAppear 不会重跑）
      if (flyConfig.agentCount !== this.appliedAgentCount) {
        this.appliedAgentCount = flyConfig.agentCount;
        this.agents.setActiveCount(this.appliedAgentCount);
        this.syncDriverCount(); // 异步：独立大脑数量跟着上场数量对齐
      }
      const lead = this.agents.getLead();
      const n = this.agents.getActiveCount();
      // 上场数量变小时把焦点钳回 0 号；镜头追踪与行为按钮都作用于焦点果蝇
      if (this.followIdx >= n) {
        this.followIdx = 0;
      }
      const focus = this.getFocus();

      // M4：青蛙索敌最近的活果蝇（多目标；青蛙会跳，用它的实时位置）。
      // 蓄力提示只标给被盯上的那只；"变化才写 @State"刷新预警。
      let tIdx = -1;
      let tDist = 1e9;
      for (let i = 0; i < n; i++) {
        const b = this.agents.getBrain(i);
        if (b.isDead()) {
          continue;
        }
        const p = b.getPose();
        const d = Math.hypot(p.x - this.frog.getPosX(), p.z - this.frog.getPosZ());
        if (d < tDist) {
          tDist = d;
          tIdx = i;
        }
      }
      const charging = this.frog.isCharging();
      for (let i = 0; i < n; i++) {
        this.agents.getBrain(i).setFrogThreat(charging && i === tIdx);
      }
      if (charging !== this.crisis) {
        this.crisis = charging;
      }
      if (tIdx >= 0) {
        const tp = this.agents.getBrain(tIdx).getPose();
        this.frog.update(dt, tp.x, tp.z, tp.y, true);
        if (this.frog.consumeHit()) {
          // 命中：拖到青蛙嘴边 → 咬死（嘴边消失，5 秒后原点重生）或挣脱起飞（见 hitByFrog）
          this.agents.getBrain(tIdx).hitByFrog(this.frog.getPosX(), this.frog.getPosZ());
        }
      } else {
        this.frog.update(dt, flyConfig.frogX, flyConfig.frogZ, 0, false);
        this.frog.consumeHit();
      }

      // 全部果蝇推进（共享世界 → 逐个体 → 个体互斥）
      this.agents.update(dt);

      // 环境（昼夜/树摆/风线/涟漪）每帧驱动；风力来自共享世界状态
      this.env.update(dt, this.world.getWindStrength());
      // 逐个体写姿态；未上场的隐藏；被青蛙捕获的（死亡原因 Frog）尸体也隐藏——"被叼走"
      for (let i = 0; i < this.renderers.length; i++) {
        const set = this.sceneMgr.flySets[i];
        if (i < n && set.fly !== null) {
          const b = this.agents.getBrain(i);
          const bst = b.getState();
          const captured = bst === FlyState.Dead && b.getLastDeathCause() === FlyDeathCause.Frog;
          if (captured) {
            this.hideFlyNode(set.fly as Node);
          } else {
            (set.fly as Node).visible = true;
            this.renderers[i].apply(b.getPose(), bst, b.getTotalTime(), this.isExcited(b, bst));
          }
        } else if (set.fly !== null) {
          this.hideFlyNode(set.fly as Node);
        }
      }
      this.syncPropNodes(dt);
      // 相机跟随焦点果蝇（视角面板可切换追踪哪一只）
      const pose = focus.getPose();
      this.sceneMgr.setFlyPose(pose.x, pose.y, pose.z, pose.yaw);
      this.sceneMgr.followFly(pose.x, pose.z);
      // 缩放滑杆跟随手势变化（追踪模式下同步）
      if (!this.pinchFingers) {
        const r = this.sceneMgr.getRadius();
        if (Math.abs(r - this.zoomRadius) > 0.05) {
          this.zoomRadius = r;
        }
      }
      const st = focus.getState();
      if (st !== this.lastState) {
        this.lastState = st;
        this.stateLabel = FLY_STATE_NAMES[st];
      }
      if (now - this.lastDriveTextMs > 300) {
        this.lastDriveTextMs = now;
        // M4：生命值 / 死亡倒计时同步到 @State（crisis 已在帧循环里即时更新）。
        // HP 徽章显示最危急的一只（存活中 HP 最低），死亡提示对任何一只都生效。
        let worst = lead;
        let deadFly: FlyBrain | null = null;
        for (let i = 0; i < n; i++) {
          const b = this.agents.getBrain(i);
          if (b.isDead() && deadFly === null) {
            deadFly = b;
          }
          if (!b.isDead() && b.getHp() < worst.getHp()) {
            worst = b;
          }
        }
        // HP 徽章：锁定视角时显示焦点果蝇本人的 HP（个体状态），否则显示最危急的一只
        this.hpValue = this.followMode
          ? Math.round(this.getFocus().getHp())
          : Math.round(worst.getHp());
        // 只比较一次并存成 boolean：避免 ArkTS 对同一联合类型做多次比较时的收窄报错（易错总结第 28 条）
        const anyDead: boolean = deadFly !== null;
        if (anyDead && deadFly !== null) {
          const cause = FLY_DEATH_NAMES[deadFly.getLastDeathCause()];
          this.deathText = `💀 ${cause} · ${deadFly.getRespawnCountdown().toFixed(1)}s 后重生`;
          // 写入 AppStorage，供「关于」页展示果蝇种群的死亡统计（全体累计）
          AppStorage.setOrCreate('fy_deaths', this.agents.totalDeaths());
          AppStorage.setOrCreate('fy_last_death', cause);
        } else {
          this.deathText = '';
        }
        // 死亡期间整体压暗 10%
        this.env.setDeathDim(anyDead);
        // 轻量成就：连续喂养 3 次 / 完整一轮昼夜零死亡
        if (lead.consumeTrustUp()) {
          this.achiText = '🤝 信任+1';
          this.achiTimer = 3;
        }
        const cy = this.env.getCycles();
        if (cy !== this.lastCycles) {
          if (lead.getDeathCount() === this.deathsAtCycleStart) {
            this.achiText = '🌙 平安一夜';
            this.achiTimer = 4;
          }
          this.lastCycles = cy;
          this.deathsAtCycleStart = lead.getDeathCount();
        }
        if (this.achiTimer > 0) {
          this.achiTimer -= 0.3;
          if (this.achiTimer <= 0) {
            this.achiText = '';
          }
        }
        // 状态行文字：锁定视角时显示焦点果蝇的**个体**内驱力（不显示平均值），
        // 未锁定时保持群体摘要（数量 + 均值）
        let text: string;
        if (this.followMode) {
          text = `🎯第${this.followIdx + 1}只 饿${Math.round(focus.getHunger() * 100)}%` +
            ` 累${Math.round(focus.getFatigue() * 100)}%`;
        } else {
          let hungerSum = 0;
          let fatigueSum = 0;
          for (let i = 0; i < n; i++) {
            hungerSum += this.agents.getBrain(i).getHunger();
            fatigueSum += this.agents.getBrain(i).getFatigue();
          }
          text = `👥${n}只 饿均${Math.round(hungerSum / n * 100)}% 累均${Math.round(fatigueSum / n * 100)}%`;
        }
        if (this.connState === 2 && this.drivers.length > 0 && this.drivers[0].isReady()) {
          // 独立大脑（M5P1.1）：每只果蝇有自己的 BrainWorker——感觉刺激按各自处境注入，
          // 运动群放电各自读取；超出上限的个体无连接组调制（纯阈值驱动）
          let spikeSum = 0;
          let readyCount = 0;
          for (let i = 0; i < n; i++) {
            const b = this.agents.getBrain(i);
            const drv = i < this.drivers.length ? this.drivers[i] : null;
            if (drv === null || !drv.isReady()) {
              b.setConnectomeDrive(0, 0, 0, 0, 0, 0);
              continue;
            }
            readyCount++;
            let foodNear = false;
            const bp = b.getPose();
            const foodsArr = this.foods.getFoods();
            for (let k = 0; k < foodsArr.length; k++) {
              const f = foodsArr[k];
              if (f.active && Math.hypot(f.x - bp.x, f.z - bp.z) < 2.5) {
                foodNear = true;
                break;
              }
            }
            drv.setEnvironment(foodNear, this.world.getLightLevel(),
              b.getHunger(), b.getFatigue());
            const d = drv.getDrive();
            b.setConnectomeDrive(d.walk, d.feed, d.groom, d.startle, d.turn, d.wing);
            spikeSum += d.spikesPerSec;
          }
          // ⚡ 同样分两种口径：锁定视角时显示焦点果蝇自己大脑的放电率
          //（超出独立大脑上限的个体无连接组，不显示）；未锁定时为全体合计
          if (this.followMode) {
            const fd = this.followIdx < this.drivers.length ? this.drivers[this.followIdx] : null;
            if (fd !== null && fd.isReady()) {
              text += ` ⚡${Math.round(fd.getDrive().spikesPerSec)}/s`;
            }
          } else {
            text += ` ⚡${Math.round(spikeSum)}/s`;
          }
          // 同步仿真统计到 @State（驱动面板/小窗实时刷新；明细取 0 号大脑）
          this.connSpikes = Math.round(spikeSum);
          const d0 = this.drivers[0].getDrive();
          this.connActive = d0.activeGroups;
          this.connTotal = d0.totalGroups;
          this.connTickMs = Math.round(d0.avgTickMs);
          this.connReady = readyCount > 0;
          // 数据集口径：全部来自运行时真实数据（升级迁移文档 §5.4——消灭手写死数字）
          this.datasetName = d0.dataset;
          this.brainScale = `${(d0.neurons / 10000).toFixed(1)}万神经元 · ` +
            `${(d0.edges / 10000).toFixed(0)}万连接`;
          AppStorage.setOrCreate('fy_brain_label',
            `${d0.dataset} · ${(d0.neurons / 10000).toFixed(1)}万神经元`);
          // 活跃脑区明细：取本窗口内各群放电率（读取即重置累积，故只在这里调用一次）
          this.refreshGroupDetail(this.drivers[0].takeGroupRates());
        }
          this.uiBeat++;
          this.driveText = text;
      }
    };
    (this.animator as AnimatorResult).play();
  }

  // 隐藏一份果蝇（未上场 / 被青蛙叼走）：可见性 + 移出视野双保险。
  // 只写 visible=false 时，真机上这份"没被驱动的预置模型"仍会显示在原点——
  // 多份叠在一起看着就像"地图中央多了一只完全静止的果蝇"。
  private hideFlyNode(node: Node): void {
    node.visible = false;
    node.position = { x: 0, y: HIDDEN_FLY_Y, z: 0 };
  }

  // M4：趋光兴奋态（Wander + 光斑生效 + 够亮）——按个体判断；
  // 连接组"振翅意图"通道（翅运动群放电，MaleCNS 后有真实读数）也能触发
  private isExcited(b: FlyBrain, st: FlyState): boolean {
    if (st === FlyState.Wander && b.isSpotActive() &&
      b.getLightLevel() > flyConfig.phototaxisLight) {
      return true;
    }
    return st === FlyState.Wander && b.isConnectomeMode() &&
      b.getConnWing() >= flyConfig.connWingG;
  }

  // 光照档位：用户倍率交给渲染层，行为层用的 lightLevel 在夜间被压到 0
  // （夜晚 = 休息阈值 0.4、无趋光；用户开聚光仍可让果蝇晒太阳回血）
  private applyLight(): void {
    const level = this.lightIdx === 0 ? 1 : (this.lightIdx === 1 ? 0.5 : 0);
    this.sceneMgr.setLightLevel(level);
    this.env.setUserLightFactor(this.sceneMgr.getUserLightFactor());
    this.world.setLightLevel(this.env.isNight() ? 0 : level);
  }

  // M4.2：把「各群放电率」整理成可读明细。
  // 逐群放电数由 Worker 每 tick 上报，驱动侧累积后换算成"次/秒"再交到这里；
  // 名称表见 behavior/NeuronGroups.ets（数据源 neuron_meta.json）。
  // 注意：输出行数固定为 GROUP_DETAIL_LINES（不足补占位"—"）——
  // 大脑小窗高度必须恒定，否则底部的「查看 3D 大脑」按钮会随数据跳动点不中（用户实测反馈）。
  private refreshGroupDetail(rates: number[]): void {
    let maxRate = 0.5;
    const idx: number[] = [];
    for (let i = 0; i < rates.length; i++) {
      if (rates[i] > 0.5) {
        idx.push(i);
        if (rates[i] > maxRate) {
          maxRate = rates[i];
        }
      }
    }
    // 按放电率降序（简单插入排序：最多 63 项，开销可忽略）
    for (let i = 1; i < idx.length; i++) {
      const v = idx[i];
      let j = i - 1;
      while (j >= 0 && rates[idx[j]] < rates[v]) {
        idx[j + 1] = idx[j];
        j--;
      }
      idx[j + 1] = v;
    }
    // 脑区维度汇总：感觉 / 中央 / 驱动 / 运动 各有多少群在活跃（无数据时也占位）
    let nSense = 0;
    let nCentral = 0;
    let nDrive = 0;
    let nMotor = 0;
    for (let i = 0; i < idx.length; i++) {
      const r = groupRegion(idx[i]);
      if (r === '感觉') {
        nSense++;
      } else if (r === '中央') {
        nCentral++;
      } else if (r === '驱动') {
        nDrive++;
      } else if (r === '运动') {
        nMotor++;
      }
    }
    this.groupSummary = idx.length > 0
      ? `感觉${nSense} 中央${nCentral} 驱动${nDrive} 运动${nMotor}`
      : '—';

    const lines: string[] = [];
    for (let i = 0; i < GROUP_DETAIL_LINES; i++) {
      if (i < idx.length) {
        const gid = idx[i];
        const ratio = rates[gid] / maxRate;
        const bars = Math.max(1, Math.round(ratio * 6));
        let bar = '';
        for (let b = 0; b < bars; b++) {
          bar += '█';
        }
        lines.push(`${groupLabel(gid)} ${bar} ${rates[gid].toFixed(0)}/s`);
      } else {
        lines.push('—');
      }
    }
    this.groupLines = lines;
  }

  private syncPropNodes(dt: number): void {
    // 觅食路径点跟随焦点果蝇（与追踪镜头一致：看哪只就画哪只的觅食路线）
    const total = this.getFocus().getTotalTime();
    const pose = this.getFocus().getPose();
    const foods = this.foods.getFoods();
    const userCount = this.foods.getUserFoodCount();

    // 用户投喂：弹跳落地
    for (let i = 0; i < this.sceneMgr.foodNodes.length && i < userCount; i++) {
      const node = this.sceneMgr.foodNodes[i];
      const f = foods[i];
      if (!node) {
        continue;
      }
      if (f.active) {
        // 投喂落地弹跳：0.4s 内从 +0.6 高度落两次
        f.dropT = Math.min(1, f.dropT + dt / 0.4);
        const e = f.dropT;
        const bounce = 0.6 * (1 - e) * (0.5 + 0.5 * Math.cos(e * Math.PI * 4));
        (node as Node).visible = true;
        const s = 1 - 0.7 * f.eaten;
        (node as Node).scale = { x: s, y: s, z: s };
        (node as Node).position = { x: f.x, y: 0.07 * s + bounce, z: f.z };
      } else {
        (node as Node).visible = false;
      }
    }

    // 树上果实：挂果/下落/落地时可见，被吃掉后隐藏直到重新结果
    for (let i = 0; i < this.sceneMgr.fruitNodes.length; i++) {
      const node = this.sceneMgr.fruitNodes[i];
      const f = foods[userCount + i];
      if (!node || !f) {
        continue;
      }
      const visible = f.respawn <= 0 && (f.active || f.hangY > 0);
      (node as Node).visible = visible;
      if (visible) {
        const s = 1 - 0.7 * f.eaten;
        (node as Node).scale = { x: s, y: s, z: s };
        (node as Node).position = { x: f.x, y: f.y, z: f.z };
      }
    }

    // 光斑：呼吸缩放 0.94~1.06（0.8Hz）——世界唯一，位置来自共享世界状态
    const spot = this.sceneMgr.spotNode;
    if (spot) {
      if (this.world.isSpotActive()) {
        const breathe = 1.0 + 0.06 * Math.sin(total * 0.8 * Math.PI * 2);
        (spot as Node).visible = true;
        (spot as Node).position = { x: this.world.getSpotX(), y: 0.02, z: this.world.getSpotZ() };
        (spot as Node).scale = { x: breathe, y: 1, z: breathe };
      } else {
        (spot as Node).visible = false;
      }
    }

    // 觅食虚线路径：主果蝇 Seek 时在其与食物之间铺 6 个流动的路径点
    this.syncPathDots(total, pose.x, pose.z);

    // 进食完成「＋」特效（任意一只吃完都触发）
    this.syncPlusFx(dt);
  }

  private syncPathDots(total: number, flyX: number, flyZ: number): void {
    // 与传入的 flyX/flyZ 同源：只画焦点果蝇的觅食路线
    const show = this.getFocus().getState() === FlyState.Seek;
    if (!show) {
      for (let i = 0; i < 6; i++) {
        const n = this.sceneMgr.getNode(`path_dot_${i}`);
        if (n) {
          n.visible = false;
        }
      }
      return;
    }
    // 最近的食物作为路径终点
    const foods = this.foods.getFoods();
    let tx = 0;
    let tz = 0;
    let best = 1e9;
    for (let i = 0; i < foods.length; i++) {
      const f = foods[i];
      if (!f.active) {
        continue;
      }
      const d = Math.hypot(f.x - flyX, f.z - flyZ);
      if (d < best) {
        best = d;
        tx = f.x;
        tz = f.z;
      }
    }
    if (best > 1e8) {
      return;
    }
    for (let i = 0; i < 6; i++) {
      const n = this.sceneMgr.getNode(`path_dot_${i}`);
      if (!n) {
        continue;
      }
      const t = (i + 1) / 7;
      n.position = {
        x: flyX + (tx - flyX) * t,
        y: 0.02 + 0.01 * Math.sin(total * 4 + i),
        z: flyZ + (tz - flyZ) * t,
      };
      // 依次明灭，形成"朝食物流动"的指示
      const phase = (total * 1.6 - i * 0.18) % 1.0;
      n.visible = phase < 0.6;
    }
  }

  private syncPlusFx(dt: number): void {
    // 任意一只吃完都触发"+"特效（特效位置在那只果蝇头顶）
    for (let i = 0; i < this.agents.getActiveCount(); i++) {
      if (this.agents.getBrain(i).consumeFeedDone()) {
        this.plusFxT = 0;
        const p = this.agents.getBrain(i).getPose();
        this.plusFxX = p.x;
        this.plusFxZ = p.z;
      }
    }
    if (this.plusFxT < 0) {
      return;
    }
    this.plusFxT += dt;
    const p = this.plusFxT / 0.8;
    if (p >= 1) {
      for (let i = 0; i < 3; i++) {
        const n = this.sceneMgr.getNode(`plus_fx_${i}`);
        if (n) {
          n.visible = false;
        }
      }
      this.plusFxT = -1;
      return;
    }
    for (let i = 0; i < 3; i++) {
      const n = this.sceneMgr.getNode(`plus_fx_${i}`);
      if (!n) {
        continue;
      }
      const ang = i * 2.094; // 三个方向散开
      n.visible = true;
      n.position = {
        x: this.plusFxX + 0.18 * Math.cos(ang),
        y: 0.10 + 0.55 * p + i * 0.05,
        z: this.plusFxZ + 0.18 * Math.sin(ang),
      };
      const s = 1.0 - 0.45 * p;
      n.scale = { x: s, y: s, z: s };
    }
  }

  // 场景点击：按当前工具路由（忽略顶栏与控制区穿透）
  private onSceneTap(x: number, y: number): void {
    if (this.areaW <= 0 || this.areaH <= 0) {
      return;
    }
    if (y < this.topAvoid + 46) {
      return;
    }
    if (!this.isWide && y > this.areaH - (this.activeCat === '' ? 190 : 420) - this.bottomAvoid) {
      return;
    }
    if (this.isWide && x > this.areaW - 360) {
      return;
    }
    const aspect = this.areaW / this.areaH;
    const p = this.sceneMgr.groundPoint(x / this.areaW, y / this.areaH, aspect);
    if (p === null) {
      return;
    }
    if (this.tool === TOOL_FEED) {
      this.foods.placeFood(p.x, p.z);
    } else if (this.tool === TOOL_SPOT) {
      this.world.setLightSpot(p.x, p.z, true);
      if (this.lightIdx !== 0) {
        this.lightIdx = 0;
        this.applyLight();
      }
    } else {
      // 触碰：点到哪只算哪只，惊吓刺激只注入被碰到那只的独立大脑
      let hitIdx = -1;
      for (let i = 0; i < this.agents.getActiveCount() && hitIdx < 0; i++) {
        if (this.agents.getBrain(i).touch(p.x, p.z)) {
          hitIdx = i;
        }
      }
      if (hitIdx >= 0 && hitIdx < this.drivers.length && this.drivers[hitIdx].isReady()) {
        this.drivers[hitIdx].joltTouch();
      }
    }
  }

  // 点击「投喂」立即在焦点果蝇前方落一份食物（仍可点地面精确指定位置）
  private feedInFront(): void {
    const pose = this.getFocus().getPose();
    const d = 0.9;
    this.foods.placeFood(pose.x + Math.sin(pose.yaw) * d, pose.z + Math.cos(pose.yaw) * d);
  }

  // 焦点果蝇：视角追踪、状态行、行为按钮与投喂落点的共同目标（默认 0 号主果蝇）。
  // 越界时钳回 0 号，保证任何时刻都返回有效个体。
  private getFocus(): FlyBrain {
    const n = this.agents.getActiveCount();
    return this.agents.getBrain(this.followIdx < n ? this.followIdx : 0);
  }

  private cycleLight(): void {
    this.lightIdx = (this.lightIdx + 1) % 3;
    if (this.lightIdx !== 0) {
      this.world.setLightSpot(0, 0, false);
    }
    this.applyLight();
  }

  // 独立大脑数量与上场果蝇数对齐（上限 MAX_INDEPENDENT_BRAINS）。
  // 每个实例要加载 31MB 连接组并起一个仿真线程，串行启动避免内存峰值叠加。
  // 注意并发：toggleConnectome 与帧循环的数量轮询可能同时调用（真机实测曾因此
  // 起出 4 个 worker）——用 busy/pending 保证同一时刻只有一个循环在推进，
  // 且循环内每轮重算 want，把"执行期间又变的数量"也收敛掉。
  private syncBusy: boolean = false;
  private syncPending: boolean = false;

  private async syncDriverCount(): Promise<void> {
    if (this.connState === 0) {
      return; // 连接组已关闭：保持空
    }
    if (this.syncBusy) {
      this.syncPending = true; // 正在同步：让在跑的循环顺带收敛到最新数量
      return;
    }
    this.syncBusy = true;
    try {
      do {
        this.syncPending = false;
        const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
        for (;;) {
          const want = Math.min(this.agents.getActiveCount(), MAX_INDEPENDENT_BRAINS);
          if (this.drivers.length === want) {
            break;
          }
          if (this.drivers.length > want) {
            const d = this.drivers.pop();
            if (d) {
              d.stop();
            }
            continue;
          }
          const d = new ConnectomeDriver();
          const ok = await d.start(context, flyConfig.connFull);
          if (!ok) {
            return;
          }
          this.drivers.push(d);
          // v7.1：等上一个驱动器的连接组真正就绪再加载下一个 —— 完整连接组 2500 万边
          // 的 CSR 峰值内存不小，串行就绪避免三个 Worker 的加载峰值叠加触发系统杀进程；
          // 期间读取已在 Worker 线程，主线程只剩事件循环心跳
          await d.waitReady(120000);
          await new Promise<void>((resolve) => setTimeout(resolve, 80));
        }
      } while (this.syncPending);
    } finally {
      this.syncBusy = false;
    }
  }

  private async toggleConnectome(): Promise<void> {
    if (this.connState === 1) {
      return;
    }
    if (this.connState === 2) {
      for (const d of this.drivers) {
        d.stop();
      }
      this.drivers = [];
      this.connState = 0;
      for (let i = 0; i < this.agents.getActiveCount(); i++) {
        this.agents.getBrain(i).setConnectomeMode(false);
      }
      return;
    }
    this.connState = 1;
    try {
      await this.syncDriverCount();
      this.connState = this.drivers.length > 0 && this.drivers[0].isRunning() ? 2 : 0;
    } catch (err) {
      console.error(`[FlyBrain] connectome toggle failed: ${JSON.stringify(err)}`);
      this.connState = 0;
    }
    for (let i = 0; i < this.agents.getActiveCount(); i++) {
      this.agents.getBrain(i).setConnectomeMode(this.connState === 2);
    }
  }

  private toggleCat(cat: string): void {
    this.animateToggle((): void => {
      this.activeCat = this.activeCat === cat ? '' : cat;
      // 大脑状态小窗保持打开（用户要求：切控制面板不关闭小窗）
    });
  }

  // ---------- UI 片段 ----------
  @Builder
  GlassChip(label: string, onTap: () => void, highlight: boolean = false) {
    Text(label)
      .fontSize(13)
      .fontColor(highlight ? '#FFFFFFFF' : '#FFDDE4EA')
      .height(32)
      .padding({ left: 14, right: 14 })
      .textAlign(TextAlign.Center)
      .borderRadius(16)
      .backgroundColor(highlight ? CHIP_BG_ON : CHIP_BG)
      .border(GLASS_BORDER)
      .onClick(onTap)
  }

  // 状态行：行为 + 内驱力 + 放电率 + 生命值（M4）。
  // 青蛙蓄力时整行转为红色警示，给出 0.8s 的救援反应窗口。
  @Builder
  StatusLine() {
    Row({ space: 8 }) {
      Text(this.crisis ? `⚠ 天敌！${this.stateLabel}` : `${this.stateLabel} · ${this.driveText}`)
        .fontSize(12)
        .fontColor(this.crisis ? '#FFFF7A7A' : '#FF9AD5CA')
        .fontWeight(FontWeight.Medium)
        .maxLines(1)
        .layoutWeight(1)
      Text(`❤${this.hpValue}`)
        .fontSize(12)
        .fontColor(this.hpValue <= 30 ? '#FFFF6B6B' : '#FFDDE4EA')
        .fontWeight(FontWeight.Medium)
      Button(this.paused ? '继续' : '暂停')
        .fontSize(12).height(28).backgroundColor(CHIP_BG)
        .onClick(() => {
          this.paused = !this.paused;
          this.agents.setPaused(this.paused);
        })
    }
    .width('100%')
    .padding({ left: 12, right: 10, top: 6, bottom: 6 })
    .borderRadius(14)
    .backgroundColor(this.crisis ? '#66A03030' : GLASS_BG)
    .border(GLASS_BORDER)
  }

  // 分类胶囊条（收起态，窄屏横向）
  @Builder
  CategoryCapsule() {
    Row({ space: 6 }) {
      Text('控制')
        .fontSize(12).fontColor('#FF8FA3B0').margin({ left: 10, right: 2 })
      this.GlassChip('行为', (): void => this.toggleCat('behavior'), false)
      this.GlassChip('交互', (): void => this.toggleCat('interact'), false)
      this.GlassChip('视角', (): void => this.toggleCat('view'), false)
      this.GlassChip('仿真', (): void => this.toggleCat('sim'), false)
      // Blank()
      // Text('点场景使用工具').fontSize(11).fontColor('#FF6B7A86').margin({ right: 10 })
    }
    .width('100%')
    .height(46)
    .borderRadius(23)
    .backgroundColor(GLASS_BG)
    .border(GLASS_BORDER)
  }

  // 分类竖排栏（大屏右栏）
  @Builder
  CategoryRail() {
    Column({ space: 6 }) {
      Text('控制')
        .fontSize(12).fontColor('#FF8FA3B0')
        .width('100%').textAlign(TextAlign.Center)
      this.railChip('行为', 'behavior')
      this.railChip('交互', 'interact')
      this.railChip('视角', 'view')
      this.railChip('仿真', 'sim')
    }
    .width('100%')
    .padding(8)
    .borderRadius(18)
    .backgroundColor(GLASS_BG)
    .border(GLASS_BORDER)
  }

  @Builder
  railChip(label: string, cat: string) {
    Text(label)
      .fontSize(13)
      .fontColor(this.activeCat === cat ? '#FFFFFFFF' : '#FFDDE4EA')
      .width('100%')
      .height(38)
      .textAlign(TextAlign.Center)
      .borderRadius(12)
      .backgroundColor(this.activeCat === cat ? CHIP_BG_ON : '#33262630')
      .onClick(() => {
        this.toggleCat(cat);
      })
  }

  // 分类面板头：标题 + 文字「收起/展开」按钮（点击区加大，方便点按）
  @Builder
  PanelHeader(title: string, expanded: boolean, onToggle: () => void) {
    Row() {
      Text(title).fontSize(15).fontWeight(FontWeight.Medium).fontColor('#FFE6ECF2').layoutWeight(1)
      Text(expanded ? '收起' : '展开')
        .fontSize(13)
        .fontColor('#FFDDE4EA')
        .padding({ left: 18, right: 18, top: 9, bottom: 9 })
        .borderRadius(18)
        .backgroundColor('#3DFFFFFF')
        .onClick(onToggle)
    }
    .width('100%')
    .height(52)
    .alignItems(VerticalAlign.Center)
  }

  // 行为面板
  @Builder
  BehaviorSection() {
    Column({ space: 8 }) {
      this.PanelHeader('行为', this.activeCat === 'behavior', (): void => this.toggleCat('behavior'))
      if (this.activeCat === 'behavior') {
        Row() {
          Text('速度').fontSize(13).fontColor('#FFC6D2DC').width(44)
          Slider({ value: this.speedValue, min: 0.2, max: 2.0, step: 0.05, style: SliderStyle.InSet })
            .layoutWeight(1)
            .selectedColor('#FF9AD5CA')
            .onChange((value: number, mode: SliderChangeMode) => {
              this.speedValue = value;
              if (mode === SliderChangeMode.End) {
                flyConfig.speedScale = value;
              }
            })
          Text(this.speedValue.toFixed(2) + 'x')
            .fontSize(12).fontColor('#FFC6D2DC').width(44).textAlign(TextAlign.End)
        }.width('100%')

        Row({ space: 6 }) {
          Button('漫步').fontSize(13).height(34).layoutWeight(1).backgroundColor(CHIP_BG)
            .onClick(() => this.getFocus().wanderNow())
          Button('理毛').fontSize(13).height(34).layoutWeight(1).backgroundColor(CHIP_BG)
            .onClick(() => this.getFocus().groomNow())
          Button('起飞').fontSize(13).height(34).layoutWeight(1).backgroundColor(CHIP_BG)
            .onClick(() => this.getFocus().takeoff())
          Button('降落').fontSize(13).height(34).layoutWeight(1).backgroundColor(CHIP_BG)
            .onClick(() => this.getFocus().land())
        }.width('100%')
      }
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 4, bottom: 8 })
    .borderRadius(16)
    .backgroundColor(GLASS_CARD_BG)
    .border(GLASS_BORDER)
  }

  // 交互面板
  @Builder
  InteractSection() {
    Column({ space: 8 }) {
      this.PanelHeader('交互', this.activeCat === 'interact', (): void => this.toggleCat('interact'))
      if (this.activeCat === 'interact') {
        Row({ space: 6 }) {
          Text('工具').fontSize(13).fontColor('#FFC6D2DC').width(44)
          Button('触碰').fontSize(12).height(32).layoutWeight(1)
            .backgroundColor(this.tool === TOOL_TOUCH ? CHIP_BG_ON : CHIP_BG)
            .onClick(() => {
              this.tool = TOOL_TOUCH;
            })
          Button('投喂').fontSize(12).height(32).layoutWeight(1)
            .backgroundColor(this.tool === TOOL_FEED ? CHIP_BG_ON : CHIP_BG)
            .onClick(() => {
              this.tool = TOOL_FEED;
              // 点击即投喂：直接在果蝇前方落一份食物，不必再点场景
              this.feedInFront();
            })
          Button('聚光').fontSize(12).height(32).layoutWeight(1)
            .backgroundColor(this.tool === TOOL_SPOT ? CHIP_BG_ON : CHIP_BG)
            .onClick(() => {
              this.tool = TOOL_SPOT;
            })
        }.width('100%')

        Row({ space: 6 }) {
          Text('环境').fontSize(13).fontColor('#FFC6D2DC').width(44)
          Button('吹风').fontSize(12).height(32).layoutWeight(1).backgroundColor(CHIP_BG)
            .onClick(() => {
              this.world.gust();
              // 风是世界级的：所有独立大脑的约翰斯顿器感受群都收到一次强刺激
              for (const d of this.drivers) {
                d.joltWind();
              }
            })
          Button(`光照·${this.lightNames[this.lightIdx]}`).fontSize(12).height(32).layoutWeight(2)
            .backgroundColor(CHIP_BG)
            .onClick(() => {
              this.cycleLight();
            })
        }.width('100%')
        Text('点「投喂」立即在果蝇前方放食物；也可选工具后点地面指定位置')
          .fontSize(10).fontColor('#FF6B7A86').width('100%')
      }
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 4, bottom: 8 })
    .borderRadius(16)
    .backgroundColor(GLASS_CARD_BG)
    .border(GLASS_BORDER)
  }

  // 视角面板：缩放滑杆 + 追踪开关
  @Builder
  ViewSection() {
    Column({ space: 8 }) {
      this.PanelHeader('视角', this.activeCat === 'view', (): void => this.toggleCat('view'))
      if (this.activeCat === 'view') {
        Row() {
          Text('缩放').fontSize(13).fontColor('#FFC6D2DC').width(44)
          Slider({
            value: this.zoomRadius,
            min: this.radiusMin(),
            max: this.radiusMax(),
            step: 0.05,
            style: SliderStyle.InSet
          })
            .layoutWeight(1)
            .selectedColor('#FF9AD5CA')
            .onChange((value: number) => {
              this.zoomRadius = value;
              this.sceneMgr.setRadius(value);
            })
          Text(this.zoomRadius.toFixed(1))
            .fontSize(12).fontColor('#FFC6D2DC').width(40).textAlign(TextAlign.End)
        }.width('100%')

        Row() {
          Column({ space: 2 }) {
            Text('视角追踪').fontSize(13).fontColor('#FFDDE4EA')
            Text('相机锁定果蝇').fontSize(10).fontColor('#FF8FA3B0')
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.followMode })
            .selectedColor('#FF3D6B5E')
            .onChange((on: boolean) => {
              this.followMode = on;
              this.sceneMgr.setFollowMode(on);
            })
        }
        .width('100%')
        .padding({ top: 2 })

        // 跟随视角类型（开启追踪后可选）
        if (this.followMode) {
          Row({ space: 6 }) {
            Button('第一人称')
              .fontSize(13).height(36).layoutWeight(1)
              .backgroundColor(this.followPerson === 0 ? CHIP_BG_ON : CHIP_BG)
              .onClick(() => {
                this.followPerson = 0;
                this.sceneMgr.setFollowPerson(0);
              })
            Button('第三人称')
              .fontSize(13).height(36).layoutWeight(1)
              .backgroundColor(this.followPerson === 1 ? CHIP_BG_ON : CHIP_BG)
              .onClick(() => {
                this.followPerson = 1;
                this.sceneMgr.setFollowPerson(1);
              })
          }
          .width('100%')

          Text(this.followPerson === 0 ? '第一人称：从果蝇视角看世界' :
            '第三人称：从后上方跟随果蝇（缩放滑杆调距离）')
            .fontSize(10).fontColor('#FF8FA3B0').width('100%')

          // M5：多果蝇——追踪目标可切换。镜头、状态行、行为按钮与投喂落点跟的是同一只；
          // 点击按上场数量循环（数量在点击时现读，设置页改完回来立即正确）
          Button(`切换追踪目标 · 当前第 ${this.followIdx + 1} 只`)
            .fontSize(13).height(36).width('100%')
            .backgroundColor(CHIP_BG)
            .onClick(() => {
              const cnt = this.agents.getActiveCount();
              if (cnt > 1) {
                this.followIdx = (this.followIdx + 1) % cnt;
              }
            })
          Text('行为按钮与投喂落点也作用于这只果蝇')
            .fontSize(10).fontColor('#FF6B7A86').width('100%')
        }

        Row({ space: 6 }) {
          Button('重置视角').fontSize(12).height(30).layoutWeight(1).backgroundColor(CHIP_BG)
            .onClick(() => {
              this.followMode = false;
              this.sceneMgr.setFollowMode(false);
              this.zoomRadius = 8.0;
              this.sceneMgr.setRadius(8.0);
              this.sceneMgr.resetTarget();   // 平移过的注视点也回到场心
            })
          Button('最远').fontSize(12).height(30).layoutWeight(1).backgroundColor(CHIP_BG)
            .onClick(() => {
              this.zoomRadius = this.radiusMax();
              this.sceneMgr.setRadius(this.radiusMax());
            })
          Button('最近').fontSize(12).height(30).layoutWeight(1).backgroundColor(CHIP_BG)
            .onClick(() => {
              this.zoomRadius = this.radiusMin();
              this.sceneMgr.setRadius(this.radiusMin());
            })
        }.width('100%')

        Text('单指拖动转视角 · 双指拖动平移 · 双指捏合缩放 · 滑杆精确缩放')
          .fontSize(10).fontColor('#FF6B7A86').width('100%')
      }
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 4, bottom: 8 })
    .borderRadius(16)
    .backgroundColor(GLASS_CARD_BG)
    .border(GLASS_BORDER)
  }

  private radiusMin(): number {
    return this.sceneMgr.getRadiusRange()[0];
  }

  private radiusMax(): number {
    return this.sceneMgr.getRadiusRange()[1];
  }

  // 仿真面板
  @Builder
  SimSection() {
    Column({ space: 8 }) {
      this.PanelHeader('仿真', this.activeCat === 'sim', (): void => this.toggleCat('sim'))
      if (this.activeCat === 'sim') {
        Row() {
          Text('连接组仿真').fontSize(13).fontColor('#FFC6D2DC').layoutWeight(1)
          Button(this.connState === 0 ? '开启' : (this.connState === 1 ? '载入中…' : '关闭'))
            .fontSize(12).height(30)
            .backgroundColor(this.connState === 2 ? CHIP_BG_ON : CHIP_BG)
            .onClick(() => {
              this.toggleConnectome();
            })
        }.width('100%')

        if (this.connState === 2 && this.connReady) {
          this.SimStats()
        } else {
          Text(`开启后：${datasetLabel()}的真实连接组在手机上实时仿真，行为受放电调制`)
            .fontSize(10).fontColor('#FF6B7A86').width('100%')
        }
      }
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 4, bottom: 8 })
    .borderRadius(16)
    .backgroundColor(GLASS_CARD_BG)
    .border(GLASS_BORDER)
  }

  @Builder
  StatRow(name: string, value: string) {
    Row() {
      Text(name).fontSize(12).fontColor('#FF9FB0BD')
      Blank()
      Text(value).fontSize(12).fontColor('#FFE6ECF2')
    }.width('100%')
  }

  // 大脑小窗「活跃脑区明细」的一行（下标固定 0..GROUP_DETAIL_LINES-1，行高固定 16）。
  // 关键：值必须在 @Builder 内**直接读 @State**（this.groupLines）——
  // 一旦改成"把字符串当参数传进来"，参数就是值快照，数值会冻结（易错总结第 8 条）。
  @Builder
  GroupLine(i: number) {
    Text(this.groupLines[i] === '' ? '—' : this.groupLines[i])
      .fontSize(10.5)
      .fontColor(this.groupLines[i] === '' || this.groupLines[i] === '—' ? '#FF4A5560' : '#FFCBD8E2')
      .width('100%').maxLines(1).height(16)
  }

  // 仿真统计（实时区）：必须在 @Builder 内**直接引用 @State 变量**，
  // 不能通过 StatRow(name, value) 参数传值——参数是值快照，不建立状态依赖，数值不会刷新。
  @Builder
  SimStats() {
    Column({ space: 4 }) {
      Row() {
        Text('放电速率').fontSize(12).fontColor('#FF9FB0BD')
        Blank()
        Text(`⚡${this.connSpikes} 次/秒`).fontSize(12).fontColor('#FFE6ECF2')
      }.width('100%')
      Row() {
        Text('活跃脑区').fontSize(12).fontColor('#FF9FB0BD')
        Blank()
        Text(`${this.connActive} / ${this.connTotal}`).fontSize(12).fontColor('#FFE6ECF2')
      }.width('100%')
      Row() {
        Text('单步耗时').fontSize(12).fontColor('#FF9FB0BD')
        Blank()
        Text(`${this.connTickMs} ms`).fontSize(12).fontColor('#FFE6ECF2')
      }.width('100%')
      Row() {
        Text('行为驱动').fontSize(12).fontColor('#FF9FB0BD')
        Blank()
        Text('连接组放电 + 内驱力').fontSize(12).fontColor('#FFE6ECF2')
      }.width('100%')
    }
    .width('100%')
    .padding(8)
    .borderRadius(10)
    .backgroundColor('#14202A33')
  }

  // 大脑状态小窗
  @Builder
  BrainPopup() {
    Column({ space: 6 }) {
      Row({ space: 6 }) {
        Text('🧠').fontSize(16)
        Text('大脑状态').fontSize(13).fontWeight(FontWeight.Medium).fontColor('#FFE6ECF2').layoutWeight(1)
        Text('✕').fontSize(13).fontColor('#FF8FA3B0')
          .onClick(() => {
            this.animateToggle((): void => {
              this.brainPopup = false;
            });
          })
      }.width('100%')

      Divider().strokeWidth(0.5).color('#33FFFFFF')

      if (this.connState === 2 && this.connReady) {
        Row() {
          Text('仿真状态').fontSize(12).fontColor('#FF9FB0BD')
          Blank()
          Text('运行中').fontSize(12).fontColor('#FFE6ECF2')
        }.width('100%')
        Row() {
          Text('放电速率').fontSize(12).fontColor('#FF9FB0BD')
          Blank()
          Text(`⚡${this.connSpikes} / 秒`).fontSize(12).fontColor('#FFE6ECF2')
        }.width('100%')
        Row() {
          Text('活跃脑区').fontSize(12).fontColor('#FF9FB0BD')
          Blank()
          Text(`${this.connActive} / ${this.connTotal}`).fontSize(12).fontColor('#FFE6ECF2')
        }.width('100%')
        // 脑区明细：固定行数 + 固定行高，只变文字不变布局（高度抖动会让底部按钮点不中）。
        // ⚠️ 这 8 行**不能用 ForEach**：ForEach 按 key 复用子节点，key 不变就不会重建，
        //    文本会冻结在首次渲染的值上（真机实测：得关掉小窗再打开才刷新）。
        //    改为逐行调用 GroupLine(i)，由 @Builder 内部直接读 @State（见该方法注释）。
        //    行数 8 与 GROUP_DETAIL_LINES 保持一致，改行数时两处一起改。
        Text(this.groupSummary).fontSize(10.5).fontColor('#FF8FA3B0').width('100%').maxLines(1)
        Column({ space: 1 }) {
          this.GroupLine(0)
          this.GroupLine(1)
          this.GroupLine(2)
          this.GroupLine(3)
          this.GroupLine(4)
          this.GroupLine(5)
          this.GroupLine(6)
          this.GroupLine(7)
        }
        .width('100%')
        .margin({ top: 2, bottom: 2 })
        Row() {
          Text('单步耗时').fontSize(12).fontColor('#FF9FB0BD')
          Blank()
          Text(`${this.connTickMs} ms`).fontSize(12).fontColor('#FFE6ECF2')
        }.width('100%')
      } else {
        this.StatRow('仿真状态', this.connState === 1 ? '载入中…' : '未开启（控制栏→仿真）')
      }
      this.StatRow('脑规模', this.brainScale === '' ? '开启仿真后读取' : this.brainScale)
      this.StatRow('数据集', this.datasetName === '' ? '开启仿真后读取' : this.datasetName)

      // 整行可点（onClick 挂在撑满宽度的 Row 上，而不是只挂在文字上 ——
      // 文字自身的命中区太小、实测注入点击容易打空，见易错总结第 26 条）
      Row() {
        Blank()
        Text('查看 3D 大脑 →')
          .fontSize(12).fontColor('#FF9AD5CA')
          .padding({ top: 8, bottom: 8, left: 12, right: 4 })
      }
      .width('100%')
      .justifyContent(FlexAlign.End)
      .onClick(() => {
        this.brainPopup = false;
        this.navStack.pushPathByName('brain', '');
      })
    }
    .width(236)
    .padding(12)
    .borderRadius(16)
    .backgroundColor('#E614141A')
    .border(GLASS_BORDER)
    .shadow({ radius: 24, color: '#66000000', offsetX: 0, offsetY: 8 })
  }

  build() {
    Stack() {
      // ==== 层1：3D 场景 ====
      if (this.sceneReady()) {
        Column() {
          Component3D(this.sceneOpt!)
            .width('100%')
            .height('100%')
            .parallelGesture(
              GestureGroup(GestureMode.Parallel,
                PanGesture({ fingers: 1, distance: 1 })
                  .onActionStart((event: GestureEvent) => {
                    this.panLast.x = event.offsetX;
                    this.panLast.y = event.offsetY;
                  })
                  .onActionUpdate((event: GestureEvent) => {
                    const dx = event.offsetX - this.panLast.x;
                    const dy = event.offsetY - this.panLast.y;
                    this.panLast.x = event.offsetX;
                    this.panLast.y = event.offsetY;
                    // 双指落下后不平移视角（交给双指平移/捏合），只同步基准值，
                    // 这样松掉一根手指回到单指时不会因为基准陈旧而跳一下
                    if (event.fingerList.length > 1) {
                      return;
                    }
                    this.sceneMgr.orbitByPixels(dx, dy);
                  }),
                // 双指拖拽 → 平移视角（单指旋转 / 双指平移 + 捏合缩放，是 3D 观察器的通行操作）
                PanGesture({ fingers: 2, distance: 1 })
                  .onActionStart((event: GestureEvent) => {
                    this.panTwoLast.x = event.offsetX;
                    this.panTwoLast.y = event.offsetY;
                  })
                  .onActionUpdate((event: GestureEvent) => {
                    const dx = event.offsetX - this.panTwoLast.x;
                    const dy = event.offsetY - this.panTwoLast.y;
                    this.panTwoLast.x = event.offsetX;
                    this.panTwoLast.y = event.offsetY;
                    // 捏合缩放进行中不平移（两指距离变化时也会带出位移，避免"缩放顺手把镜头带跑"）
                    if (this.pinchFingers) {
                      return;
                    }
                    this.sceneMgr.panByPixels(dx, dy, this.areaH);
                  }),
                PinchGesture({ fingers: 2 })
                  .onActionStart(() => {
                    this.pinchFingers = true;
                    this.pinchBaseRadius = this.sceneMgr.getRadius();
                  })
                  .onActionUpdate((event: GestureEvent) => {
                    const s = event.scale > 0.2 ? event.scale : 0.2;
                    this.sceneMgr.setRadius(this.pinchBaseRadius / s);
                  })
                  .onActionEnd(() => {
                    this.pinchFingers = false;
                    this.zoomRadius = this.sceneMgr.getRadius();
                  })
              )
            )
            .onClick((event: ClickEvent) => {
              this.onSceneTap(event.x, event.y);
            })
            .onAreaChange((_old: Area, newArea: Area) => {
              this.areaW = newArea.width as number;
              this.areaH = newArea.height as number;
            })
        }
        .width('100%')
        .height('100%')
      } else if (this.loadFailed) {
        Column({ space: 12 }) {
          Text('3D 场景加载失败').fontSize(18).fontColor('#FFEEEEEE')
          Text('请确认安装包包含 rawfile/gltf/world.glb，并使用真机运行')
            .fontSize(13).fontColor('#FF999999').textAlign(TextAlign.Center)
        }
          .justifyContent(FlexAlign.Center)
          .width('100%')
          .height('100%')
      } else {
        Column({ space: 12 }) {
          LoadingProgress().width(46).height(46).color('#FF9AD5CA')
          Text('正在加载果蝇世界…').fontSize(14).fontColor('#FFBBBBBB')
        }
          .justifyContent(FlexAlign.Center)
          .width('100%')
          .height('100%')
      }

      // ==== 层2：死亡提示（M4）====
      if (this.deathText !== '') {
        Column({ space: 10 }) {
          Text('💀').fontSize(42)
          Text(this.deathText)
            .fontSize(14).fontColor('#FFFFD9D9')
            .textAlign(TextAlign.Center)
        }
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .width('100%')
        .height('100%')
        .hitTestBehavior(HitTestMode.Transparent)
      }

      // ==== 层2.5：轻量成就提示（M4）====
      if (this.achiText !== '') {
        Column() {
          Text(this.achiText)
            .fontSize(13).fontColor('#FFFFF0C0')
            .padding({ left: 14, right: 14, top: 6, bottom: 6 })
            .borderRadius(14)
            .backgroundColor(GLASS_BG)
            .border(GLASS_BORDER)
        }
        .width('100%')
        .height('100%')
        .padding({ top: this.topAvoid + 64 })
        .alignItems(HorizontalAlign.Center)
        .justifyContent(FlexAlign.Start)
        .hitTestBehavior(HitTestMode.Transparent)
      }

      // ==== 层3：顶部栏（标题 + 大脑徽章 + 设置/关于）+ 大脑状态小窗 ====
      // 注：不再有全屏遮罩——面板展开时 3D 视角拖拽保持可用，面板仅经分类按钮开合
      Column() {
        Row({ space: 8 }) {
          Text('赛博果蝇')
            .fontSize(19).fontWeight(FontWeight.Bold).fontColor('#FFFFFFFF')
          Blank()
          // 大脑徽章（含运行指示点）
          Stack() {
            Text('🧠')
              .fontSize(17)
              .width(38).height(32)
              .textAlign(TextAlign.Center)
              .borderRadius(16)
              .backgroundColor(this.brainPopup ? CHIP_BG_ON : CHIP_BG)
              .border(GLASS_BORDER)
            if (this.connState === 2) {
              Circle({ width: 7, height: 7 }).fill('#FF4ADE80').translate({ x: 13, y: -13 })
            }
          }
          .onClick(() => {
            this.animateToggle((): void => {
              this.brainPopup = !this.brainPopup;
              this.activeCat = '';
            });
          })
          this.GlassChip('设置', (): void => {
            this.navStack.pushPathByName('settings', '');
          }, false)
          this.GlassChip('关于', (): void => {
            this.navStack.pushPathByName('about', '');
          }, false)
        }
        .width('100%')

        // 大脑状态小窗（锚定左上，避开宽屏右栏面板）
        Row() {
          if (this.brainPopup) {
            Column() {
              this.BrainPopup()
            }
            .margin({ top: 8 })
            .transition(TransitionEffect.OPACITY.animation({ duration: 200 }))
          }
          Blank()
        }
        .width('100%')
      }
      .padding({ left: 16, right: 16, top: this.topAvoid + 6 })
      .width('100%')
      .height('100%')
      .hitTestBehavior(HitTestMode.Transparent)

      // ==== 层4：大屏（右栏控制面板，竖向排列） ====
      if (this.isWide) {
        Row() {
          Blank()
          Column({ space: 8 }) {
            this.StatusLine()
            this.CategoryRail()
            if (this.activeCat === 'behavior') {
              this.BehaviorSection()
            } else if (this.activeCat === 'interact') {
              this.InteractSection()
            } else if (this.activeCat === 'view') {
              this.ViewSection()
            } else if (this.activeCat === 'sim') {
              this.SimSection()
            }
          }
          .constraintSize({ maxWidth: 300 })
          .width('30%')
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: this.topAvoid + 56, bottom: this.bottomAvoid + 12 })
        .height('100%')
        .hitTestBehavior(HitTestMode.Transparent)
      } else {
        // ==== 层4：窄屏（底部悬浮控制区） ====
        Column() {
          Blank()
          Column({ space: 8 }) {
            this.StatusLine()
            if (this.activeCat === '') {
              this.CategoryCapsule()
            } else if (this.activeCat === 'behavior') {
              this.BehaviorSection()
            } else if (this.activeCat === 'interact') {
              this.InteractSection()
            } else if (this.activeCat === 'view') {
              this.ViewSection()
            } else if (this.activeCat === 'sim') {
              this.SimSection()
            }
          }
          .width('100%')
        }
        .width('100%')
        .padding({ left: 14, right: 14, bottom: this.bottomAvoid + 12 })
        .height('100%')
        .hitTestBehavior(HitTestMode.Transparent)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#FF101418')
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
  }

  // 场景与果蝇节点都就绪才挂 Component3D
  private sceneReady(): boolean {
    return !this.loading && !this.loadFailed && this.sceneOpt !== null;
  }
}

// 手势采样点（避免对象字面量直赋）
class PanSample {
  public x: number = 0;
  public y: number = 0;
}
