// 果蝇行为参数（默认值语义沿用 flybrain 项目 fly-logic.js / SPEC，
// 详见 docs/果蝇大脑App开发文档.md 第 4.4 节）
export class FlyConfig {
  // ---- 运动 ----
  // v6：场地放大 1.5 倍（脚本地盘 7.4 → 11.0），速度同步 ×1.5 保持"横穿场地的时间"不变。
  public walkSpeed: number = 1.35;        // 漫步速度（场景单位/秒）
  public fleeSpeed: number = 3.3;         // 惊吓逃离速度
  public flySpeed: number = 3.9;          // 飞行速度
  public turnRate: number = 1.6;          // 最大转向角速度（弧度/秒）
  // 活动半径（步行软边界）。M5P1.1 从 4.6 扩到 6.0；v6 从 6.0 扩到 9.0（与脚本地盘 11.0 成对）。
  // 树木在 7.5~8.4、落果最远 8.6，原来的 6.0 会让果蝇够不到落果、围着树转圈。
  // 河流弧（7.35~9.9，20°~108°）仍有斥力挡水。
  // M5.2 起是软边界：越过即开始向心转向 + 负面内驱力加速（见 edge* 段），没有硬墙。
  public arenaRadius: number = 9.0;

  // ---- 内驱力 ----
  // 注意：M1 定 0.008/s 时还没有 HP，饿了只是去找吃的、无害；
  // M4 加入"饥饿满值持续掉血"后，这个速率会让果蝇 1 分钟就到顶、不到 2 分钟饿死。
  // 因此调慢到 0.0025/s（约 3 分钟到顶），再由树上果实提供自主食物来源。
  public hungerGain: number = 0.0025;     // 饥饿累计/秒
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
  public maxFoods: number = 5;            // 场上最多用户投喂食物数
  public eatDuration: number = 4;         // 吃完一份食物的秒数
  public hungerSeek: number = 0.45;       // 饥饿超过此值且场上有食物→觅食
  public hungerStop: number = 0.15;       // 饥饿低于此值停止进食
  public seekTimeout: number = 14;        // 觅食超时（秒）
  public seekBanSeconds: number = 6;      // 觅食超时后对该食物的拉黑时长：
                                        // 超时=一直够不到，短期不再锁定它，防止"超时→立刻
                                        // 又锁定同一颗"绕圈死循环（食物落点已保证可达，此为兜底）
  public eatRadius: number = 0.30;        // 到食物多近算吃到（随 v5.1 体型 0.6 缩小）

  // ---- M4.1：树上果实（果蝇的自主食物来源，让它能自持而不是等人投喂）----
  public fruitCount: number = 9;          // 3 棵树 × 3 颗
  public fruitRespawn: number = 60;       // 被吃后多久重新结果（秒）
  public fruitFallTime: number = 0.9;     // 从树冠落到地面的时间（秒）
  public fruitGroundY: number = 0.07;     // 落地后的高度

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

  // ---- M5：自发短飞（反馈"果蝇只在地上走、从不主动飞"）----
  // 闲逛够久（flyCheckMin~Max 随机）就掷一次骰子：命中且不累不惊则自己起飞巡游一段
  // （飞行时长沿用 flyDurationMin~Max）。休息/理毛/进食会重新开始计时，所以不会刚落地又飞。
  public flyChance: number = 0.35;        // 每次判定起飞的概率
  public flyCheckMin: number = 25;        // 判定间隔下限（秒）
  public flyCheckMax: number = 45;        // 判定间隔上限（秒）
  public flyMaxFatigue: number = 0.6;     // 太累（≥此值）不主动飞
  public flyMaxFear: number = 0.3;        // 还在惊恐（≥此值）不主动飞

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
  // v7.1（NeuroMechFly 网格）：模型基准 = 双翅收拢贴背；spread=1 时绕竖轴外展的角度。
  // 旧 wingFoldYaw/wingFoldPitch 是程序化模型（展翅基准）的收翅参数，已弃用。
  public wingSpreadYaw: number = 1.9;
  public wingFoldRate: number = 6.0;      // 收/展速度（每秒变化量）
  // v7.2 关节链腿部动画：模型基准 = 关节链 FK 摆出的站姿（枢轴零旋转），
  // 运行时只叠加相对旋转（步态摆动 / 飞行收腿 / 死亡蜷腿）
  public legStrideHz: number = 13;        // 步频（三角步态，对侧交替）
  public legSwingAmp: number = 0.16;      // 步行时基节绕竖轴的摆幅（弧度）
  public legPoseRate: number = 4.0;       // 步态振幅/收腿/蜷腿的平滑速率（每秒变化量）

  // ---- 用户可调 ----
  public speedScale: number = 1.0;        // 全局速度倍率（设置页可调 0.2~2.0）

  // ---- 连接组涌现模式（M3）：放电累积量触发阈值 ----
  public connStartleG: number = 6;        // 机械感受群放电→惊吓
  public connFeedG: number = 3;           // 舐吸运动群放电→觅食意图
  public connGroomG: number = 5;          // 头/腹运动群放电→理毛
  // 升级 MaleCNS 后新启用的两路调制（FAFB 下腿/翅运动群为 0，恒不触发）：
  public connTurnG: number = 4;           // 左右腿群放电差 → 转向偏置阈值
  public connWingG: number = 4;           // 翅运动群放电 → 振翅意图（兴奋振翅）阈值

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

  // ---- M4：场地几何（**必须与 tools/gen_world_glb.mjs 成对一致**，易错总结第 37 条）----
  // v7：河道从"东侧弧带"改为"自西向东蜿蜒穿过场心的 S 形"。
  // riverPts = 生成脚本 RIVER_SAMPLES（Catmull-Rom 采样 23 点）逐点一致的扁平数组 [x0,z0,x1,z1,...]，
  // riverHalfWidth 对应脚本 RIVER_HALF。改河道形状时两边同一步改完。
  public flyArenaRadius: number = 10.8;   // 飞行软边界（M5.2 起软边界，无硬钳制）
  public riverPts: number[] = [
    -11.000, 2.000, -9.956, 0.970, -8.467, -0.459, -7.000, -1.600,
    -5.689, -2.230, -4.400, -2.570, -3.200, -2.600, -2.111, -2.237,
    -1.111, -1.563, -0.200, -0.800, 0.578, 0.052, 1.267, 0.993,
    2.000, 1.800, 2.830, 2.430, 3.704, 2.926, 4.600, 3.200,
    5.489, 3.193, 6.400, 2.963, 7.400, 2.600, 8.328, 2.192,
    9.375, 1.663, 10.334, 1.152, 11.000, 0.800,
  ];
  public riverHalfWidth: number = 0.7;    // 河道半宽（水面宽 1.4）
  public waterNearBand: number = 0.75;    // 距水域多近算"临水"（饮水彩蛋）
  public drinkWait: number = 2;           // 临水驻留多久触发饮水
  public drinkDuration: number = 3;       // 饮水动作时长

  // ---- M5：静态障碍碰撞（反馈②：原来果蝇会直接穿过石块/树干）----
  // 阻挡圆几何来自 world.glb 的 blocker_i 标记节点（translation=圆心、scale.x=半径；当前 33 个：
  // 石块 14 / 河岸卵石 16 / 树干 3），由 SceneManager 读入后交给 Obstacles；
  // 这里只放果蝇自身的碰撞尺寸与绕行手感。
  public bodyRadius: number = 0.10;       // 果蝇碰撞半径（体型 0.6 后体宽约 0.08）
  public obstacleTurn: number = 2.2;      // 撞上障碍物后的绕行转向速度（rad/s）

  // ---- M5.2：软边界压力（替代原来的硬钳制：出界不再"撞墙"，而是越待越难受）----
  // 越过活动半径（步行 arenaRadius / 飞行 flyArenaRadius）后，所有压力项按
  // 出界深度线性升到满值（深度 = edgeBand 时到达满值），配合随深度增强的向心转向，
  // 果蝇像受到神经刺激一样自己折返；一直赖在界外会饿/累/怕并持续掉血
  // （死亡原因记为 Lost「迷失野外」）。驱动群（DRIVE_*）经 setEnvironment 也会
  // 收到更强刺激，连接组模式下放电随之上升 —— 由既有管线兑现"神经刺激"语义。
  public edgeBand: number = 1.2;          // 出界多深压力到达满值（场景单位）
  public edgeHungerMul: number = 14;      // 饥饿额外增速倍数（满深度时 = 基础速率 ×(1+14)）
  public edgeFatigueMul: number = 10;     // 疲劳额外增速倍数
  public edgeFearPerSec: number = 0.25;   // 恐惧增速（满深度，每秒；会触发惊吓向场内逃）
  public edgeHpDrain: number = 6;         // 每秒扣血（满深度）
  public edgeTurnBoost: number = 2.5;     // 向心转向增强倍数（满深度时转向速率 ×(1+2.5)）

  // ---- M5 v7.2：河滩软边界（真机反馈②："果蝇走到河滩上就被卡住"）----
  // 河滩 = 水面外沿再往外 beachBand 的带状区域（独立于 waterNearBand：那个是饮水判定）。
  // 与出界压力同款思路：贴地在河滩上停留超过 beachGrace 秒后，压力从 0 线性升到 1
  // （再经过 beachRamp 秒到满值），越待越难受：
  //   · 饥饿 / 疲劳加速累积 → 饿了去找吃的、累了去休息，两者都会把它带离河滩；
  //   · 翅膀打湿 → 飞行能力下降（不能自发起飞，受惊起飞的恐惧阈值也抬高）；
  //   · 背离河道的转向偏置 → 像出界压力那样"劝"它自己走上岸。
  // 注意：河滩不是"禁区"，正常路过 / 饮水（宽限期内）不受任何影响。
  public beachBand: number = 0.55;        // 河滩带宽（水面外沿 + 该值 = 河滩外沿）
  public beachGrace: number = 6;          // 宽限时长（秒）：前 6 秒零压力
  public beachRamp: number = 10;          // 宽限之后再过这么久压力到达满值（秒）
  public beachHungerMul: number = 5;      // 饥饿额外增速倍数（满压力）
  public beachFatigueMul: number = 7;     // 疲劳额外增速倍数（满压力）—— 高于休息恢复率，赖着走不掉
  public beachTurnBoost: number = 1.6;    // 背离河道转向增强倍数（满压力）
  public beachFearAdd: number = 0.15;     // 翅膀打湿后"起飞所需恐惧"的增量（飞行能力下降）
  public beachFlyMaxWet: number = 0.2;    // 打湿程度超过该值就不自发起飞

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
  public sunOrbitRadius: number = 13.5;

  // 天空穹顶分段（**必须与 tools/gen_world_glb.mjs 的 SKY_PHASES / SKY_HEX 一致**）：
  // 相位落在 [skyPhases[i], skyPhases[i+1]) 时显示 sky_i。
  // 之所以用"多个预置穹顶 + 切换可见"而非单个穹顶运行时改色：
  // camera.clearColor 在真机不生效，而运行时改材质要走 MaterialProperty、写入口径不确定。
  public skyPhases: number[] = [0, 0.06, 0.12, 0.45, 0.60, 0.66, 0.70, 0.74, 0.90, 1.0];
  public skyDomeCount: number = 9;

  // ---- M4：青蛙 ----
  public frogGuardRadius: number = 2.2;   // 警戒圈半径
  public frogChargeTime: number = 0.8;    // 蓄力（预警）时长 → 用户救援窗口
  public frogAttackTime: number = 0.18;   // 舌头弹出时长
  public frogHitRadius: number = 0.25;    // 命中判定半径（随 v5.1 果蝇体型缩小）
  public frogHitDamage: number = 60;      // 命中扣血：<hpStart 时首咬不致死 → 果蝇"挣脱起飞"逃生；
                                        // 第二咬（或残血时）必死。设回 100 = 一咬必杀（M5P1.3 的"命中即捕获"）
  public frogCooldown: number = 40;       // 进食一次后的冷却（避免劝退）
  public frogMissCooldown: number = 8;    // 未命中后的冷却
  public frogPuffMin: number = 6;         // 鼓腮间隔（随机区间）
  public frogPuffMax: number = 10;
  // v7：出生点移到蜿蜒河道北岸（与生成脚本 FROG_R=5.46 / FROG_A=52.8° 成对）
  public frogX: number = 5.46 * Math.cos(0.9215);
  public frogZ: number = 5.46 * Math.sin(0.9215);

  // ---- M4：功能开关（设置页可调，持久化）----
  public dayNightEnabled: boolean = true;
  public frogEnabled: boolean = true;

  // ---- 连接组模式（v7.1）：false=Lite（瘦身 400 万边，默认，省内存）/ true=全仿真 ----
  // （2556 万边完整连接组，多耗约 600MB 内存；设置页可切换，切换即热重建驱动器）
  public connFull: boolean = false;

  // ---- M5：多智能体 ----
  public agentCount: number = 3;          // 同屏果蝇数量（1~6，设置页可调；模型已烘焙 6 份）
  public separateDist: number = 0.35;     // 个体互斥间距（随 v5.1 体型缩小；仍 ≥ 体长一半）
}

// 全局单例：行为层与 UI 共享同一份配置
export const flyConfig: FlyConfig = new FlyConfig();
