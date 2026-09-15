// 3D 场景主页：沉浸式全屏 + 分类玻璃控制面板 + 大屏右栏布局 + 大脑状态小窗。
// 布局模式（胶囊工具栏 ⇄ 分类面板同槽切换、
// 遮罩收起、≥600vp 且非纵向窗口时控制面板移至右侧）。
// 注意：Component3D 在 DevEco 预览器中不支持渲染，需真机运行。
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { AnimatorOptions, AnimatorResult } from '@kit.ArkUI';
import { Node } from '@kit.ArkGraphics3D';
import { ConnectomeDriver } from '../behavior/ConnectomeDriver';
import { FlyBrain } from '../behavior/FlyBrain';
import { flyConfig } from '../behavior/FlyConfig';
import { FLY_STATE_NAMES, FlyState } from '../behavior/FlyTypes';
import { FlyRenderer } from '../scene/FlyRenderer';
import { SceneManager } from '../scene/SceneManager';

const TOOL_TOUCH = 0;
const TOOL_FEED = 1;
const TOOL_SPOT = 2;

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
  private renderer: FlyRenderer = new FlyRenderer(flyConfig);
  private brain: FlyBrain = new FlyBrain(flyConfig);
  private driver: ConnectomeDriver = new ConnectomeDriver();
  private sceneOpt: SceneOptions | null = null;
  private animator: AnimatorResult | null = null;
  private lastFrameMs: number = 0;
  private panLast: PanSample = new PanSample();
  private pinchBaseRadius: number = 6.0;
  private lastState: FlyState = FlyState.Wander;
  private lastDriveTextMs: number = 0;
  private areaW: number = 0;
  private areaH: number = 0;
  private pinchFingers: boolean = false;  // 捏合手势进行中（避免滑杆与手势互相打架）
  private lightNames: string[] = ['亮', '暗', '黑'];

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
  @State private zoomRadius: number = 5.6;
  @State private followMode: boolean = false;
  @State private followPerson: number = 0;  // 0 第一人称 / 1 第三人称
  // 仿真运行统计：必须用 @State 独立变量承载，才能在帧循环里驱动 UI 刷新
  // （直接读 this.driver.getDrive().xxx 不属于状态变量，值变化不会触发重建）
  @State private connSpikes: number = 0;
  @State private connActive: number = 0;
  @State private connTotal: number = 61;
  @State private connTickMs: number = 0;
  @State private connReady: boolean = false;
  @State private uiBeat: number = 0;  // 心跳自增，保证每轮统计都会触发一次重建

  aboutToAppear(): void {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const store = preferences.getPreferencesSync(context, { name: 'flycfg' });
      const saved = store.getSync('speedScale', flyConfig.speedScale) as number;
      if (saved >= 0.2 && saved <= 2.0) {
        flyConfig.speedScale = saved;
        this.speedValue = saved;
      }
    } catch (err) {
      console.warn(`[FlyBrain] load speed prefs failed: ${JSON.stringify(err)}`);
    }

    this.sceneMgr.init().then((ok: boolean) => {
      this.loading = false;
      if (ok && this.sceneMgr.scene !== null) {
        this.renderer.attach(this.sceneMgr.flyNode, this.sceneMgr.wingLeft, this.sceneMgr.wingRight);
        this.sceneOpt = { scene: this.sceneMgr.scene, modelType: ModelType.SURFACE } as SceneOptions;
        this.loadFailed = !this.renderer.isAttached();
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
    this.driver.stop();
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
      this.brain.update(dt);
      this.renderer.apply(this.brain.getPose(), this.brain.getState(), this.brain.getTotalTime());
      this.syncPropNodes();
      const pose = this.brain.getPose();
      this.sceneMgr.setFlyPose(pose.x, pose.y, pose.z, pose.yaw);
      this.sceneMgr.followFly(pose.x, pose.z);
      // 缩放滑杆跟随手势变化（追踪模式下同步）
      if (!this.pinchFingers) {
        const r = this.sceneMgr.getRadius();
        if (Math.abs(r - this.zoomRadius) > 0.05) {
          this.zoomRadius = r;
        }
      }
      const st = this.brain.getState();
      if (st !== this.lastState) {
        this.lastState = st;
        this.stateLabel = FLY_STATE_NAMES[st];
      }
      if (now - this.lastDriveTextMs > 300) {
        this.lastDriveTextMs = now;
        let text = `饿${Math.round(this.brain.getHunger() * 100)}% ` +
          `怕${Math.round(this.brain.getFear() * 100)}% ` +
          `累${Math.round(this.brain.getFatigue() * 100)}%`;
        if (this.connState === 2 && this.driver.isReady()) {
          const d = this.driver.getDrive();
          this.brain.setConnectomeDrive(d.walk, d.feed, d.groom, d.startle);
          let foodNear = false;
          const foods = this.brain.getFoods();
          for (let i = 0; i < foods.length; i++) {
            const f = foods[i];
            if (f.active && Math.hypot(f.x - pose.x, f.z - pose.z) < 2.5) {
              foodNear = true;
              break;
            }
          }
          this.driver.setEnvironment(foodNear, this.brain.getLightLevel(),
            this.brain.getHunger(), this.brain.getFatigue());
          text += ` ⚡${Math.round(d.spikesPerSec)}/s`;
          // 同步仿真统计到 @State（驱动面板/小窗实时刷新）
          this.connSpikes = Math.round(d.spikesPerSec);
          this.connActive = d.activeGroups;
          this.connTotal = d.totalGroups;
          this.connTickMs = Math.round(d.avgTickMs);
          this.connReady = d.ready;
        }
        this.uiBeat++;
        this.driveText = text;
      }
    };
    (this.animator as AnimatorResult).play();
  }

  private syncPropNodes(): void {
    const foods = this.brain.getFoods();
    for (let i = 0; i < this.sceneMgr.foodNodes.length && i < foods.length; i++) {
      const node = this.sceneMgr.foodNodes[i];
      const f = foods[i];
      if (!node) {
        continue;
      }
      if (f.active) {
        (node as Node).visible = true;
        const s = 1 - 0.7 * f.eaten;
        (node as Node).scale = { x: s, y: s, z: s };
        (node as Node).position = { x: f.x, y: 0.07 * s, z: f.z };
      } else {
        (node as Node).visible = false;
      }
    }
    const spot = this.sceneMgr.spotNode;
    if (spot) {
      if (this.brain.isSpotActive()) {
        (spot as Node).visible = true;
        (spot as Node).position = { x: this.brain.getSpotX(), y: 0.02, z: this.brain.getSpotZ() };
      } else {
        (spot as Node).visible = false;
      }
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
      this.brain.placeFood(p.x, p.z);
    } else if (this.tool === TOOL_SPOT) {
      this.brain.setLightSpot(p.x, p.z, true);
      if (this.lightIdx !== 0) {
        this.lightIdx = 0;
        this.brain.setLightLevel(1);
        this.sceneMgr.setLightLevel(1);
      }
    } else {
      const hit = this.brain.touch(p.x, p.z);
      if (hit && this.connState === 2 && this.driver.isReady()) {
        this.driver.joltTouch();
      }
    }
  }

  private cycleLight(): void {
    this.lightIdx = (this.lightIdx + 1) % 3;
    const level = this.lightIdx === 0 ? 1 : (this.lightIdx === 1 ? 0.5 : 0);
    this.brain.setLightLevel(level);
    this.sceneMgr.setLightLevel(level);
    if (level < 1) {
      this.brain.setLightSpot(0, 0, false);
    }
  }

  private async toggleConnectome(): Promise<void> {
    if (this.connState === 1) {
      return;
    }
    if (this.connState === 2) {
      this.driver.stop();
      this.connState = 0;
      this.brain.setConnectomeMode(false);
      return;
    }
    this.connState = 1;
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const ok = await this.driver.start(context);
      this.connState = ok && this.driver.isRunning() ? 2 : 0;
      this.brain.setConnectomeMode(this.connState === 2);
    } catch (err) {
      console.error(`[FlyBrain] connectome toggle failed: ${JSON.stringify(err)}`);
      this.connState = 0;
    }
  }

  private toggleCat(cat: string): void {
    this.animateToggle((): void => {
      this.activeCat = this.activeCat === cat ? '' : cat;
      this.brainPopup = false;
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

  // 状态行：行为 + 内驱力 + 放电率
  @Builder
  StatusLine() {
    Row({ space: 8 }) {
      Text(`${this.stateLabel} · ${this.driveText}`)
        .fontSize(12)
        .fontColor('#FF9AD5CA')
        .fontWeight(FontWeight.Medium)
        .maxLines(1)
        .layoutWeight(1)
      Button(this.paused ? '继续' : '暂停')
        .fontSize(12).height(28).backgroundColor(CHIP_BG)
        .onClick(() => {
          this.paused = !this.paused;
          this.brain.setPaused(this.paused);
        })
    }
    .width('100%')
    .padding({ left: 12, right: 10, top: 6, bottom: 6 })
    .borderRadius(14)
    .backgroundColor(GLASS_BG)
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
            .onClick(() => this.brain.wanderNow())
          Button('理毛').fontSize(13).height(34).layoutWeight(1).backgroundColor(CHIP_BG)
            .onClick(() => this.brain.groomNow())
          Button('起飞').fontSize(13).height(34).layoutWeight(1).backgroundColor(CHIP_BG)
            .onClick(() => this.brain.takeoff())
          Button('降落').fontSize(13).height(34).layoutWeight(1).backgroundColor(CHIP_BG)
            .onClick(() => this.brain.land())
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
              this.brain.gust();
              if (this.connState === 2 && this.driver.isReady()) {
                this.driver.joltWind();
              }
            })
          Button(`光照·${this.lightNames[this.lightIdx]}`).fontSize(12).height(32).layoutWeight(2)
            .backgroundColor(CHIP_BG)
            .onClick(() => {
              this.cycleLight();
            })
        }.width('100%')
        Text('投喂/聚光：选工具后点地面放置')
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
        }

        Row({ space: 6 }) {
          Button('重置视角').fontSize(12).height(30).layoutWeight(1).backgroundColor(CHIP_BG)
            .onClick(() => {
              this.followMode = false;
              this.sceneMgr.setFollowMode(false);
              this.zoomRadius = 5.6;
              this.sceneMgr.setRadius(5.6);
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

        Text('单指拖动转视角 · 双指捏合缩放 · 滑杆精确缩放')
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
          Text('开启后：13.9 万神经元的真实连接组在手机上实时仿真，行为部分由放电驱动')
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
        Row() {
          Text('单步耗时').fontSize(12).fontColor('#FF9FB0BD')
          Blank()
          Text(`${this.connTickMs} ms`).fontSize(12).fontColor('#FFE6ECF2')
        }.width('100%')
      } else {
        this.StatRow('仿真状态', this.connState === 1 ? '载入中…' : '未开启（控制栏→仿真）')
      }
      this.StatRow('脑规模', '13.9万神经元 · 270万突触')

      Row() {
        Text('查看 3D 大脑 →')
          .fontSize(12).fontColor('#FF9AD5CA')
          .padding({ top: 6, bottom: 6 })
          .onClick(() => {
            this.brainPopup = false;
            this.navStack.pushPathByName('brain', '');
          })
      }.width('100%').justifyContent(FlexAlign.End)
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
                    this.sceneMgr.orbitByPixels(dx, dy);
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

      // ==== 层3：顶部栏（标题 + 大脑徽章 + 设置/关于）+ 大脑状态小窗 ====
      // 注：不再有全屏遮罩——面板展开时 3D 视角拖拽保持可用，面板仅经分类按钮开合
      Column() {
        Row({ space: 8 }) {
          Text('果蝇大脑')
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
