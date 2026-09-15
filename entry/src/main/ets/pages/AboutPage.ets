// 关于页：项目介绍、开源地址、科学数据来源与开源致谢（合规署名）。
// 标题栏使用官方 HdsNavDestination 沉浸材质。
import { common, OpenLinkOptions } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hdsMaterial, HdsNavDestination } from '@kit.UIDesignKit';

// 开源仓库地址（点击用系统浏览器打开）
const REPO_URL: string = 'https://github.com/zhuhaozoo/FlyBrain-HarmonyOS';

@Component
export struct AboutPage {
  @StorageProp('fy_top_avoid') topAvoid: number = 40;
  // M4：由场景页写入的「这只果蝇的一生」统计
  @StorageProp('fy_deaths') deaths: number = 0;
  @StorageProp('fy_last_death') lastDeath: string = '';

  private openRepo(): void {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const options: OpenLinkOptions = { appLinkingOnly: false };
      context.openLink(REPO_URL, options).catch((err: BusinessError) => {
        console.error(`[FlyBrain] open repo link failed: ${JSON.stringify(err)}`);
      });
    } catch (err) {
      console.warn(`[FlyBrain] open repo link exception: ${JSON.stringify(err)}`);
    }
  }

  @Builder
  SectionTitle(t: string) {
    Text(t).fontSize(13).fontColor($r('app.color.fy_text_tertiary')).width('100%').margin({ top: 16, bottom: 4 })
  }

  // 开源地址卡片：URL 行可点（用系统浏览器打开），长按可复制
  @Builder
  RepoCard() {
    Column() {
      Text('本项目已完整开源（MIT License），欢迎 Star、提 Issue 与 PR。')
        .fontSize(14).fontColor($r('app.color.fy_text_primary')).lineHeight(22).width('100%')
      // 点击直接挂在 URL 文字上：整卡 onClick 在 Scroll 内的命中不稳定，文字本身更可靠
      Text(REPO_URL)
        .fontSize(14).fontColor($r('app.color.fy_accent')).lineHeight(22).width('100%')
        .margin({ top: 8 })
        .copyOption(CopyOptions.LocalDevice)
        .onClick(() => {
          this.openRepo();
        })
      Text('点击用系统浏览器打开 · 长按可复制')
        .fontSize(11).fontColor($r('app.color.fy_text_tertiary')).width('100%')
        .margin({ top: 6 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(12)
    .borderRadius(12)
    .backgroundColor($r('app.color.fy_card_bg'))
    .onClick(() => {
      this.openRepo();
    })
  }

  // 这只果蝇的一生：必须在本 @Builder 内直接引用 @StorageProp，
  // 不能靠参数传值（@Builder 参数是值快照，见易错总结第 8 条）
  @Builder
  LifeCard() {
    Text(this.deaths <= 0
      ? '这只果蝇目前安然无恙 —— 还没死过。'
      : `累计死亡 ${this.deaths} 次 · 最后一次：${this.lastDeath}`)
      .fontSize(14).fontColor($r('app.color.fy_text_primary')).lineHeight(22)
      .width('100%')
      .padding(12)
      .borderRadius(12)
      .backgroundColor($r('app.color.fy_card_bg'))
  }

  @Builder
  Card(content: string) {
    Text(content)
      .fontSize(14).fontColor($r('app.color.fy_text_primary')).lineHeight(22)
      .width('100%')
      .padding(12)
      .borderRadius(12)
      .backgroundColor($r('app.color.fy_card_bg'))
  }

  build() {
    HdsNavDestination() {
      Scroll() {
        Column() {
          Text('果蝇大脑 FlyBrain')
            .fontSize(20).fontWeight(FontWeight.Bold).width('100%').margin({ top: 12 })
          Text('M0-M3 Demo · v0.2.0')
            .fontSize(12).fontColor($r('app.color.fy_text_tertiary')).width('100%').margin({ top: 4 })

          this.SectionTitle('开源地址')
          this.RepoCard()

          this.SectionTitle('这是什么')
          this.Card('2024 年，科学家完成了首张成年果蝇（黑腹果蝇）的完整大脑接线图：' +
            '约 139,255 个神经元、约 5,000 万个突触（FlyWire 全脑连接组）。' +
            '本应用把这一成果带到手机上：在一个 3D 场景里观察一只果蝇的自主活动，' +
            '「仿真」开启后，13.9 万神经元的真实连接组在你的手机里实时放电，' +
            '行为部分由放电驱动；点「大脑」可查看完整脑的点云。')

          this.SectionTitle('科学数据来源')
          this.Card('Dorkenwald, S., Matsliah, A., Sterling, A.R. et al. ' +
            'Neuronal wiring diagram of an adult brain. Nature 634, 124–138 (2024).\n' +
            '数据来自 FlyWire 联盟（flywire.ai / codex.flywire.ai）公开数据集（FAFB v783）。')

          this.SectionTitle('这只果蝇的一生')
          this.LifeCard()

          this.SectionTitle('开源致谢')
          this.Card('· flybrain（snedea/flybrain，MIT License）——行为与仿真设计参考蓝本，' +
            '行为参数语义沿用其 fly-logic.js，LIF 仿真移植自其 sim-worker.js；\n' +
            '· worm-sim（heyseth/worm-sim）——连接驱动的虚拟生物开创性实践；\n' +
            '· google/neuroglancer（Apache-2.0）——FlyWire 官方查看器内核；\n' +
            '· 华为官方 Graphics3D 示例（Apache-2.0）——相机 lookAt 实现方式参考。')

          this.SectionTitle('素材说明')
          this.Card('本应用内的 3D 场景与果蝇模型由工程自带脚本（tools/gen_world_glb.mjs）程序化生成，' +
            '大脑点云由 tools/gen_brain_glb.mjs 从公开数据生成，均为项目自有资产，不含第三方版权素材。')

          Text('仅用于科普演示，不构成任何科学结论。')
            .fontSize(11).fontColor($r('app.color.fy_text_tertiary')).width('100%')
            .margin({ top: 16, bottom: 24 })
        }
        .padding({ left: 16, right: 16, top: this.topAvoid + 52 })
        .alignItems(HorizontalAlign.Start)
      }
        .layoutWeight(1)
        .width('100%')
        .backgroundColor($r('app.color.fy_page_bg'))
        .scrollBar(BarState.Off)
    }
    .titleBar({
      content: {
        title: {
          mainTitle: '关于'
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
