// 多端断点工具（轻量实现）
// 职责：把窗口宽度（vp）换算为适配决策写入 AppStorage，页面组件经 @StorageProp 响应式读取；
//       EntryAbility 在窗口尺寸变化时刷新。
// 阈值（vp）：sm<600 / md[600,840) / lg[840,1440) / xl≥1440
// 本应用策略：≥600vp 且非纵向高窗口 → 控制面板放到场景右侧（大屏布局）。
export class BreakpointService {
  static readonly THRESHOLD_WIDE: number = 600;
  static readonly THRESHOLD_LG: number = 840;
  static readonly THRESHOLD_XL: number = 1440;
  static readonly PORTRAIT_RATIO: number = 1.2;

  static readonly KEY_IS_WIDE: string = 'fy_is_wide';

  static refresh(widthVp: number, heightVp: number): void {
    // 宽度≥600vp 且非纵向高窗口（高宽比 < 1.2，如横屏/折叠展开）→ 右侧控制面板
    const isWide: boolean = widthVp >= BreakpointService.THRESHOLD_WIDE
      && heightVp < widthVp * BreakpointService.PORTRAIT_RATIO;
    AppStorage.setOrCreate(BreakpointService.KEY_IS_WIDE, isWide);
  }
}
