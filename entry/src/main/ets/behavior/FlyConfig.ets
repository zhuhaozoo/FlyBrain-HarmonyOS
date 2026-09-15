// 果蝇行为参数（默认值语义沿用 flybrain 项目 fly-logic.js / SPEC，
// 详见 docs/果蝇大脑App开发文档.md 第 4.4 节）
export class FlyConfig {
  // ---- 运动 ----
  public walkSpeed: number = 0.9;         // 漫步速度（场景单位/秒）
  public fleeSpeed: number = 2.2;         // 惊吓逃离速度
  public flySpeed: number = 2.6;          // 飞行速度
  public turnRate: number = 1.6;          // 最大转向角速度（弧度/秒）
  public arenaRadius: number = 4.6;       // 活动半径（出界自动回转）

  // ---- 内驱力 ----
  public hungerGain: number = 0.008;      // 饥饿累计/秒
  public fearDecay: number = 0.10;        // 恐惧衰减/秒
  public fatigueGain: number = 0.010;     // 疲劳累计/秒（活动时，fly-logic 语义）
  public fatigueFlyGain: number = 0.020;  // 飞行时疲劳累计/秒
  public fatigueRecover: number = 0.060;  // 休息时疲劳恢复/秒
  public restThreshold: number = 0.7;     // 进入休息阈值（fly-logic restFatigue）
  public restThresholdDark: number = 0.4; // 黑暗环境的休息阈值（fly-logic）
  public wakeThreshold: number = 0.4;     // 结束休息阈值

  // ---- 惊吓 / 风 ----
  public startleFear: number = 0.5;       // 恐惧超过此值触发惊吓
  public flyFear: number = 0.8;           // 恐惧超过此值直接起飞
  public touchFear: number = 0.5;         // 被触碰增加的恐惧
  public gustFear: number = 0.35;         // 强风增加的恐惧
  public startleFreeze: number = 0.3;     // 惊吓僵住时长（秒）
  public startleFlee: number = 1.4;       // 惊吓逃离时长（秒）
  public windDuration: number = 1.8;      // 一阵风的时长（秒）
  public braceWindMax: number = 0.5;      // 风力低于此值→趴伏，否则惊吓

  // ---- 进食 / 觅食 ----
  public maxFoods: number = 5;            // 场上最多食物数
  public eatDuration: number = 4;         // 吃完一份食物的秒数
  public hungerSeek: number = 0.45;       // 饥饿超过此值且场上有食物→觅食
  public hungerStop: number = 0.15;       // 饥饿低于此值停止进食
  public seekTimeout: number = 14;        // 觅食超时（秒）
  public eatRadius: number = 0.38;        // 到食物多近算吃到

  // ---- 趋光 ----
  public phototaxisLight: number = 0.5;   // 光照超过此值才趋光（fly-logic）
  public phototaxisCuriosity: number = 0.2;

  // ---- 行为时长（秒，均匀随机区间）----
  public groomDurationMin: number = 2;
  public groomDurationMax: number = 5;
  public restDurationMin: number = 5;
  public restDurationMax: number = 15;
  public flyDurationMin: number = 10;
  public flyDurationMax: number = 16;
  public groomChance: number = 0.35;      // 每次理毛判定命中概率
  public groomCheckIntervalMin: number = 7;
  public groomCheckIntervalMax: number = 14;

  // ---- 起降 ----
  public takeoffDuration: number = 0.7;   // 起飞耗时
  public landDuration: number = 0.9;      // 降落耗时
  public flyHeight: number = 1.15;        // 巡航高度

  // ---- 动画 ----
  public wingFlapFlyHz: number = 10;
  public wingFlapFlyAmp: number = 0.9;
  public wingFlapStartleHz: number = 8;
  public wingFlapStartleAmp: number = 0.6;
  public wingFlapGroomHz: number = 1.6;
  public wingFlapGroomAmp: number = 0.22;
  public wingFlapIdleHz: number = 0.9;
  public wingFlapIdleAmp: number = 0.05;
  public walkBobAmp: number = 0.02;       // 爬行颠簸幅度
  public walkBobHz: number = 12;

  // ---- 用户可调 ----
  public speedScale: number = 1.0;        // 全局速度倍率（设置页可调 0.2~2.0）

  // ---- 连接组涌现模式（M3）：放电累积量触发阈值 ----
  public connStartleG: number = 6;        // 机械感受群放电→惊吓
  public connFeedG: number = 3;           // 舐吸运动群放电→觅食意图
  public connGroomG: number = 5;          // 头/腹运动群放电→理毛

  // ---- M4：生命系统（HP）----
  public hpMax: number = 100;
  public hpStart: number = 100;
  public hpRespawn: number = 60;          // 重生后的 HP
  public hpStarveDrain: number = 2;       // 饥饿满值时每秒扣血
  public hpWaterDrain: number = 30;       // 落水每秒扣血
  public hpEatGain: number = 18;          // 吃完一份食物回血
  public hpDrinkGain: number = 5;         // 饮水回血
  public hpSpotGain: number = 1;          // 在光斑内晒太阳每秒回血
  public deathDuration: number = 5;       // 死亡到重生的秒数
  public feedLowHunger: number = 0.9;     // 饥饿超过此值才开始扣血（留一点缓冲）

  // ---- M4：场地几何（与 tools/gen_world_glb.mjs 的河流参数保持一致）----
  public flyArenaRadius: number = 7.2;    // 飞行可达半径（> 河流外沿 6.6，实现"飞行可过河"）
  public riverA0: number = 0.349;         // 河流弧起始角（弧度，atan2(z,x) 度量；20°）
  public riverA1: number = 1.885;         // 河流弧结束角（108°）
  public riverInner: number = 4.9;        // 河流内半径
  public riverOuter: number = 6.6;        // 河流外半径
  public waterNearBand: number = 0.5;     // 距水域多近算"临水"
  public drinkWait: number = 2;           // 临水驻留多久触发饮水
  public drinkDuration: number = 3;       // 饮水动作时长

  // ---- M4：昼夜循环（渲染层 EnvironmentController 使用）----
  public dayCycleSeconds: number = 240;   // 一轮昼夜时长
  public dayNightRatio: number = 0.50;    // 白天占比
  public duskRatio: number = 0.12;        // 黄昏
  public nightRatio: number = 0.26;       // 夜晚
  // 黎明 = 1 - 其余三者
  public skyDay: string = '#87CEEB';
  public skyDusk: string = '#FF9A5A';
  public skyNight: string = '#0B1026';
  public skyDawn: string = '#8FA6D8';
  public sunOrbitRadius: number = 9;

  // ---- M4：青蛙 ----
  public frogGuardRadius: number = 2.2;   // 警戒圈半径
  public frogChargeTime: number = 0.8;    // 蓄力（预警）时长 → 用户救援窗口
  public frogAttackTime: number = 0.18;   // 舌头弹出时长
  public frogHitRadius: number = 0.35;    // 命中判定半径
  public frogHitDamage: number = 50;      // 命中扣血
  public frogCooldown: number = 40;       // 进食一次后的冷却（避免劝退）
  public frogMissCooldown: number = 8;    // 未命中后的冷却
  public frogPuffMin: number = 6;         // 鼓腮间隔（随机区间）
  public frogPuffMax: number = 10;
  public frogX: number = 4.55 * Math.cos(1.117);  // 与生成脚本一致（r=4.55, θ=64°）
  public frogZ: number = 4.55 * Math.sin(1.117);

  // ---- M4：功能开关（设置页可调，持久化）----
  public dayNightEnabled: boolean = true;
  public frogEnabled: boolean = true;
}

// 全局单例：行为层与 UI 共享同一份配置
export const flyConfig: FlyConfig = new FlyConfig();
