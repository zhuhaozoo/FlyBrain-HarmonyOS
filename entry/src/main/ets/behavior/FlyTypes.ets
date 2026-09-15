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
}

export const FLY_DEATH_NAMES: string[] = ['', '饥饿耗尽', '被青蛙捕获', '落水'];

// 果蝇当前姿态：位置 + 朝向
export class FlyPose {
  public x: number = 0;     // 场景 X
  public y: number = 0;     // 离地高度（根节点贴地为 0）
  public z: number = 0;     // 场景 Z
  public yaw: number = 0;   // 朝向角（绕 Y 轴，0 = 朝 +Z）
}

// 场景中的一个食物项（逻辑数据；渲染节点由页面层同步）
export class FoodItem {
  public x: number = 0;
  public z: number = 0;
  public eaten: number = 0;   // 0~1，1 表示吃完
  public active: boolean = false;
  public dropT: number = 1;   // 落地弹跳进度 0~1（1 表示已落地，M4 投喂反馈用）
}
