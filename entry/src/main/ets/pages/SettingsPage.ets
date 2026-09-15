// 设置页：查看行为参数默认值 + 调节全局速度倍率 + M4 生态开关（本地持久化）。
// 标题栏使用系统材质沉浸光感（HdsNavDestination + hdsMaterial.IMMERSIVE）。
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { hdsMaterial, HdsNavDestination } from '@kit.UIDesignKit';
import { FlyConfig, flyConfig } from '../behavior/FlyConfig';

@Component
export struct SettingsPage {
  @State private speed: number = flyConfig.speedScale;
  @State private dayNight: boolean = flyConfig.dayNightEnabled;
  @State private frogOn: boolean = flyConfig.frogEnabled;
  private store: preferences.Preferences | null = null;

  aboutToAppear(): void {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const store = preferences.getPreferencesSync(context, { name: 'flycfg' });
      this.store = store;
      const saved = store.getSync('speedScale', flyConfig.speedScale) as number;
      if (saved >= 0.2 && saved <= 2.0) {
        this.speed = saved;
        flyConfig.speedScale = saved;
      }
      this.dayNight = store.getSync('dayNight', flyConfig.dayNightEnabled) as boolean;
      this.frogOn = store.getSync('frogEnabled', flyConfig.frogEnabled) as boolean;
      flyConfig.dayNightEnabled = this.dayNight;
      flyConfig.frogEnabled = this.frogOn;
    } catch (err) {
      console.warn(`[FlyBrain] load prefs failed: ${JSON.stringify(err)}`);
    }
  }

  private persistSpeed(v: number): void {
    flyConfig.speedScale = v;
    this.persist('speedScale', v);
  }

  private persistBool(key: string, v: boolean): void {
    this.persist(key, v);
  }

  private persist(key: string, v: number | boolean): void {
    const store = this.store;
    if (store === null) {
      return;
    }
    try {
      store.putSync(key, v);
      store.flush();
    } catch (err) {
      console.warn(`[FlyBrain] save prefs failed: ${JSON.stringify(err)}`);
    }
  }

  @Builder
  ParamRow(name: string, value: string, note: string) {
    Row() {
      Column({ space: 2 }) {
        Text(name).fontSize(15).fontColor($r('app.color.fy_text_primary'))
        Text(note).fontSize(11).fontColor($r('app.color.fy_text_tertiary'))
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Text(value).fontSize(14).fontColor($r('app.color.fy_text_secondary'))
    }
    .width('100%')
    .padding({ top: 10, bottom: 10 })
  }

  build() {
    HdsNavDestination() {
      Scroll() {
        Column({ space: 4 }) {
          Text('全局')
            .fontSize(13).fontColor($r('app.color.fy_text_tertiary')).width('100%')
            .margin({ top: 12, bottom: 4 })
          Row() {
            Text('速度倍率').fontSize(15).fontColor($r('app.color.fy_text_primary')).layoutWeight(1)
            Text(this.speed.toFixed(2) + 'x').fontSize(14).fontColor($r('app.color.fy_text_secondary'))
          }.width('100%').padding({ top: 6 })
          Slider({ value: this.speed, min: 0.2, max: 2.0, step: 0.05, style: SliderStyle.OutSet })
            .selectedColor($r('app.color.fy_accent'))
            .onChange((value: number, mode: SliderChangeMode) => {
              this.speed = value;
              if (mode === SliderChangeMode.End) {
                this.persistSpeed(value);
              }
            })

          Text('生态')
            .fontSize(13).fontColor($r('app.color.fy_text_tertiary')).width('100%')
            .margin({ top: 16, bottom: 4 })

          Column({ space: 0 }) {
            // 开关直接内联在 build 里读取 @State（@Builder 参数是值快照，会读到旧值 —— 见易错总结第 8 条）
            Row() {
              Column({ space: 2 }) {
                Text('昼夜循环').fontSize(15).fontColor($r('app.color.fy_text_primary'))
                Text('一轮 4 分钟：日月升落、天色与光照同步变化')
                  .fontSize(11).fontColor($r('app.color.fy_text_tertiary'))
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              Toggle({ type: ToggleType.Switch, isOn: this.dayNight })
                .selectedColor($r('app.color.fy_accent'))
                .onChange((v: boolean) => {
                  this.dayNight = v;
                  flyConfig.dayNightEnabled = v;
                  this.persistBool('dayNight', v);
                })
            }
            .width('100%')
            .padding({ top: 10, bottom: 10 })

            Divider().color($r('app.color.fy_divider'))

            Row() {
              Column({ space: 2 }) {
                Text('捕食者青蛙').fontSize(15).fontColor($r('app.color.fy_text_primary'))
                Text('关闭后青蛙不再索敌（低端机可关以提性能）')
                  .fontSize(11).fontColor($r('app.color.fy_text_tertiary'))
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              Toggle({ type: ToggleType.Switch, isOn: this.frogOn })
                .selectedColor($r('app.color.fy_accent'))
                .onChange((v: boolean) => {
                  this.frogOn = v;
                  flyConfig.frogEnabled = v;
                  this.persistBool('frogEnabled', v);
                })
            }
            .width('100%')
            .padding({ top: 10, bottom: 10 })
          }
          .width('100%')
          .padding(12)
          .borderRadius(12)
          .backgroundColor($r('app.color.fy_card_bg'))

          Text('行为参数（默认值，取自 flybrain 项目语义）')
            .fontSize(13).fontColor($r('app.color.fy_text_tertiary')).width('100%')
            .margin({ top: 16, bottom: 4 })

          Column({ space: 0 }) {
            this.ParamRow('漫步速度', `${FlyConfigDef.walkSpeed} 单位/秒`, '地面爬行的基础速度')
            Divider().color($r('app.color.fy_divider'))
            this.ParamRow('飞行速度', `${FlyConfigDef.flySpeed} 单位/秒`, '巡航速度')
            Divider().color($r('app.color.fy_divider'))
            this.ParamRow('转向速率', `${FlyConfigDef.turnRate} 弧度/秒`, '漫步换向的最大角速度')
            Divider().color($r('app.color.fy_divider'))
            this.ParamRow('活动半径', `${FlyConfigDef.arenaRadius} 单位`, '超出后自动向圆心回转')
            Divider().color($r('app.color.fy_divider'))
            this.ParamRow('疲劳累计', `${FlyConfigDef.fatigueGain}/秒`, '活动时增长，阈值 0.7 触发休息')
            Divider().color($r('app.color.fy_divider'))
            this.ParamRow('疲劳恢复', `${FlyConfigDef.fatigueRecover}/秒`, '降至 0.4 结束休息')
            Divider().color($r('app.color.fy_divider'))
            this.ParamRow('理毛间隔', `${FlyConfigDef.groomCheckIntervalMin}~${FlyConfigDef.groomCheckIntervalMax} 秒`, '每次判定有 35% 概率理毛 2~5 秒')
            Divider().color($r('app.color.fy_divider'))
            this.ParamRow('巡航高度', `${FlyConfigDef.flyHeight} 单位`, '飞行时的离地高度')
          }
          .width('100%')
          .padding(12)
          .borderRadius(12)
          .backgroundColor($r('app.color.fy_card_bg'))
        }
        .padding({ left: 16, right: 16, bottom: 24 })
      }
        .layoutWeight(1)
        .width('100%')
        .backgroundColor($r('app.color.fy_page_bg'))
        .scrollBar(BarState.Off)
    }
    .titleBar({
      content: {
        title: {
          mainTitle: '设置'
        }
      },
      // 标题栏内容避让系统安全区（状态栏），材质背景仍可沉浸延伸
      avoidLayoutSafeArea: true,
      style: {
        systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.IMMERSIVE,
          materialLevel: hdsMaterial.MaterialLevel.EXQUISITE
        }
      }
    })
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
  }
}

// 只读展示用的默认值（不随运行时修改变化）
const FlyConfigDef: FlyConfig = new FlyConfig();
