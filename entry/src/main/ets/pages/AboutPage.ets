// 关于页：项目介绍、开源地址、科学数据来源与开源致谢（合规署名）。
// 标题栏使用官方 HdsNavDestination 沉浸材质。
import { common, OpenLinkOptions, Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hdsMaterial, HdsNavDestination } from '@kit.UIDesignKit';

// 开源仓库地址（点击用系统浏览器打开）
const REPO_URL: string = 'https://github.com/zhuhaozoo/FlyBrain-HarmonyOS';

// 其他作品：Mu水印（MakePro 项目），跳应用市场详情页 —— 与 MakePro「更多作品」同一套约定
const MAKEPRO_BUNDLE: string = 'com.zhuhao.makepro';

@Component
export struct AboutPage {
  @StorageProp('fy_top_avoid') topAvoid: number = 40;
  // M4：由场景页写入的「这只果蝇的一生」统计
  @StorageProp('fy_deaths') deaths: number = 0;
  @StorageProp('fy_last_death') lastDeath: string = '';
  // 当前连接组数据集口径（场景页在仿真 ready 后写入；未写入时用默认文案）
  @StorageProp('fy_brain_label') brainLabel: string = '';

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

  // 跳华为应用市场对应应用详情页（与 MakePro 项目「更多作品」的跳转写法一致）
  private openAppGallery(bundleName: string): void {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const want: Want = {
        uri: `store://appgallery.huawei.com/app/detail?id=${bundleName}`
      };
      context.startAbility(want).catch((err: BusinessError) => {
        console.error(`[FlyBrain] open appgallery failed: ${bundleName} ${JSON.stringify(err)}`);
      });
    } catch (err) {
      console.warn(`[FlyBrain] open appgallery exception: ${JSON.stringify(err)}`);
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

  // 当前数据集卡片：直接在 @Builder 内读 @StorageProp（值快照陷阱同上）
  @Builder
  DatasetCard() {
    Text(this.brainLabel === '' ? '开启仿真后读取当前连接组数据集' : `当前数据集：${this.brainLabel}`)
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

  // 其他作品条目：图标 + 名称 + 简介 + 跳转提示，整行可点（跳应用市场详情页）。
  // 说明：@Builder 的参数是值快照，这里传的都是静态文案，不受易错总结第 8 条影响。
  @Builder
  WorkLink(name: string, desc: string, bundleName: string) {
    Row({ space: 12 }) {
      // 作品图标（占位）：用户自行加好图标后，把下面这个 Row 换成
         Image($r('app.media.Mu')).width(48).height(48).borderRadius(12).objectFit(ImageFit.Cover)
      // Row() {
      //   Text('Mu')
      //     .fontSize(16)
      //     .fontWeight(FontWeight.Medium)
      //     .fontColor($r('app.color.fy_text_tertiary'))
      // }
      // .width(48)
      // .height(48)
      // .borderRadius(12)
      // .backgroundColor($r('app.color.fy_divider'))
      // .justifyContent(FlexAlign.Center)

      Column({ space: 4 }) {
        Text(name)
          .fontSize(15).fontWeight(FontWeight.Medium).fontColor($r('app.color.fy_text_primary'))
        Text(desc)
          .fontSize(12).fontColor($r('app.color.fy_text_tertiary'))
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Text('›')
        .fontSize(20)
        .fontColor($r('app.color.fy_text_tertiary'))
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding(12)
    .borderRadius(12)
    .backgroundColor($r('app.color.fy_card_bg'))
    .onClick(() => {
      this.openAppGallery(bundleName);
    })
  }

  build() {
    HdsNavDestination() {
      Scroll() {
        Column() {
          Text('赛博果蝇 CyberFly')
            .fontSize(20).fontWeight(FontWeight.Bold).width('100%').margin({ top: 12 })
          Text('M0-M5 · v0.3.0')
            .fontSize(12).fontColor($r('app.color.fy_text_tertiary')).width('100%').margin({ top: 4 })

          this.SectionTitle('开源地址')
          this.RepoCard()

          this.SectionTitle('这是什么')
          this.Card('2024 年，科学家完成了首张成年果蝇（黑腹果蝇）的完整大脑接线图；' +
            '2026 年，Janelia 与谷歌等又公开了首个雄性果蝇完整中枢神经系统连接组。' +
            '本应用把这一成果带到手机上：在一个 3D 场景里观察果蝇的自主活动，' +
            '「仿真」开启后，真实连接组在你的手机里实时放电，' +
            '行为受放电调制（行为骨架为内驱力与状态机，即混合驱动）；点「大脑」可查看完整连接组点云。')

          this.SectionTitle('当前数据集')
          this.DatasetCard()

          this.SectionTitle('科学数据来源')
          this.Card('FlyWire：Dorkenwald, S., Matsliah, A., Sterling, A.R. et al. ' +
            'Neuronal wiring diagram of an adult brain. Nature 634, 124–138 (2024)。' +
            '数据来自 FlyWire 联盟（flywire.ai），CC BY-NC 4.0（非商用）。\n' +
            'MaleCNS v1.0：HHMI Janelia 等，雄性果蝇完整中枢神经系统连接组' +
            '（male-cns.janelia.org），CC BY 4.0。')

          this.SectionTitle('这只果蝇的一生')
          this.LifeCard()

          this.SectionTitle('开源致谢')
          this.Card('· flybrain（snedea/flybrain，MIT License）——行为与仿真设计参考蓝本，' +
            '行为参数语义沿用其 fly-logic.js，LIF 仿真移植自其 sim-worker.js；\n' +
            '· worm-sim（heyseth/worm-sim）——连接驱动的虚拟生物开创性实践；\n' +
            '· google/neuroglancer（Apache-2.0）——FlyWire 官方查看器内核；\n' +
            '· 华为官方 Graphics3D 示例（Apache-2.0）——相机 lookAt 实现方式参考。')

          this.SectionTitle('素材说明')
          this.Card('本应用内的果蝇、青蛙模型与大脑点云由工程自带脚本（tools/gen_world_glb.mjs / ' +
            'gen_brain_glb.mjs）程序化生成，为项目自有资产。\n' +
            '场景中的树木、岩石与草丛几何来自 Quaternius「Ultimate Stylized Nature」系列模型' +
            '（CC0 1.0 公有领域，poly.pizza / quaternius.com）；花、蘑菇、灌木、倒木等静态配景' +
            '来自 Kenney「Nature Kit」（CC0 1.0 公有领域，kenney.nl）。以上素材均重新组织为工程' +
            '自己的场景结构，不含贴图。')

          this.SectionTitle('其他作品友情链接')
          this.WorkLink('Mu水印', '液态玻璃水印 · 影像编辑', MAKEPRO_BUNDLE)
          Text('点击用应用市场打开')
            .fontSize(11).fontColor($r('app.color.fy_text_tertiary')).width('100%')
            .margin({ top: 6 })

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
