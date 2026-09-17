// 果蝇行为状态与姿态数据类型（纯数据，无渲染依赖）
export enum FlyState {
  Wander = 0,    // 漫步
  Groom,         // 理毛
  Rest,          // 休息
  Takeoff,       // 起飞
  Fly,           // 飞行
  Land,          // 降落
  Idle,          // 待机（保留）
  Startle,       // 惊吓（僵住后逃离）
  Feed,          // 进食
  Brace,         // 趴伏（弱风）
  Seek,          // 觅食（走向食物）
  Drinking,      // 饮水（河岸彩蛋，M4）
  Dead,          // 死亡（翻面躺地，等待重生，M4）
}

// UI 上的状态名（下标与 FlyState 对齐）
export const FLY_STATE_NAMES: string[] =
  ['漫步', '理毛', '休息', '起飞', '飞行', '降落', '待机', '惊吓', '进食', '趴伏', '觅食', '饮水', '死亡'];

// 死亡原因（用于「关于」页「这只果蝇的一生」与死亡文案，M4）
export enum FlyDeathCause {
  None = 0,
  Hunger,   // 饥饿耗尽
  Frog,     // 被青蛙捕获
  Water,    // 落水
  Lost,     // 迷失野外（M5 软边界：在活动半径外停留过久，力竭）
}

export const FLY_DEATH_NAMES: string[] = ['', '饥饿耗尽', '被青蛙捕获', '落水', '迷失野外'];

// 果蝇当前姿态：位置 + 朝向
export class FlyPose {
  public x: number = 0;     // 场景 X
  public y: number = 0;     // 离地高度（根节点贴地为 0）
  public z: number = 0;     // 场景 Z
  public yaw: number = 0;   // 朝向角（绕 Y 轴，0 = 朝 +Z）
}

// 场景中的一个食物项（逻辑数据；渲染节点由页面层同步）
// kind=0：用户投喂（落点处弹跳落地即食）
// kind=1：树上果实（成熟时从树冠落下，落地后才可食；被吃后过一段时间重新结果）
export class FoodItem {
  public x: number = 0;
  public z: number = 0;
  public y: number = 0.07;         // 当前高度（果实下落过程中变化）
  public hangY: number = 0;        // 挂在树冠上的高度（果实专用）
  public eaten: number = 0;        // 0~1，1 表示吃完
  public active: boolean = false;  // 是否可作为觅食目标（果实落地后才置 true）
  public dropT: number = 1;        // 投喂落地弹跳进度 0~1（1 表示已落地）
  public kind: number = 0;         // 0 用户投喂 / 1 树上果实
  public ready: boolean = false;   // 果实：已落地、可食用
  public respawn: number = 0;      // 果实：重新结果倒计时（秒）
  public fallT: number = 0;        // 果实：下落过程计时（秒）
}
