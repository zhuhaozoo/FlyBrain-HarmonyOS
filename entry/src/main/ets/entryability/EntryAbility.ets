import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window, UIContext } from '@kit.ArkUI';
import { BreakpointService } from '../common/BreakpointService';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  private windowObj: window.Window | null = null;

  // 窗口尺寸变化：刷新断点，驱动页面响应式重排
  private onWindowSizeChange: (size: window.Size) => void = (size: window.Size) => {
    this.refreshLayoutMetrics();
  };

  // 刷新断点与系统避让区高度（状态栏/导航条），写入 AppStorage 供页面响应式读取
  private refreshLayoutMetrics(): void {
    if (this.windowObj === null) {
      return;
    }
    const win: window.Window = this.windowObj;
    const ctx: UIContext = win.getUIContext();
    BreakpointService.refresh(ctx.px2vp(win.getWindowProperties().windowRect.width),
      ctx.px2vp(win.getWindowProperties().windowRect.height));
    try {
      const sysAvoid = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      const navAvoid = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
      AppStorage.setOrCreate('fy_top_avoid', ctx.px2vp(sysAvoid.topRect.height));
      AppStorage.setOrCreate('fy_bottom_avoid', ctx.px2vp(navAvoid.bottomRect.height));
    } catch (e) {
      hilog.warn(DOMAIN, 'testTag', 'avoid area read failed: %{public}s', JSON.stringify(e));
    }
  }

  private currentWidthVp(): number {
    if (this.windowObj === null) {
      return 0;
    }
    const ctx: UIContext = (this.windowObj as window.Window).getUIContext();
    return ctx.px2vp(this.windowObj.getWindowProperties().windowRect.width);
  }

  private currentHeightVp(): number {
    if (this.windowObj === null) {
      return 0;
    }
    const ctx: UIContext = (this.windowObj as window.Window).getUIContext();
    return ctx.px2vp(this.windowObj.getWindowProperties().windowRect.height);
  }

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Main window is created, set main page for this ability
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');
      // 多端适配：首刷断点并监听窗口尺寸变化
      try {
        this.windowObj = windowStage.getMainWindowSync();
        // 真全屏：布局延伸到状态栏/导航条后面（配合页面 ignoreLayoutSafeArea）
        this.windowObj.setWindowLayoutFullScreen(true);
        this.refreshLayoutMetrics();
        this.windowObj.on('windowSizeChange', this.onWindowSizeChange);
      } catch (e) {
        hilog.warn(DOMAIN, 'testTag', 'breakpoint init failed: %{public}s', JSON.stringify(e));
      }
    });
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    // Ability has brought to foreground
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    // Ability has back to background
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
  }
}