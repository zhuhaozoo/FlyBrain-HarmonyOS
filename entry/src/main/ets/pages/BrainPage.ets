// M2：真实连接组 3D 大脑可视化页。
// 数据：完整成年果蝇连接组神经元坐标（数据集随生成表切换：FAFB / MaleCNS，见升级迁移文档），
//       按 super_class 分 5 组着色（视觉/感觉/中央/运动/内分泌），可独立显隐。
// 交互：自动慢速自旋 + 单指拖拽旋转 + 双指缩放 + 分组开关。
import { AnimatorOptions, AnimatorResult } from '@kit.ArkUI';
import { Camera, Light, LightType, Node, Scene, SceneResourceFactory, Vec3 } from '@kit.ArkGraphics3D';
import { hdsMaterial, HdsNavDestination } from '@kit.UIDesignKit';
import { BRAIN_DATASET_LABEL, BRAIN_GROUPS, BrainGroupRow } from '../behavior/BrainGroups';
import { clamp, lookAt, quatMul, quatX, quatY } from '../common/Math3D';

class BrainGroup {
  public name: string;
  public nodePath: string;
  public count: number;
  public visible: boolean = true;

  constructor(name: string, nodePath: string, count: number) {
    this.name = name;
    this.nodePath = nodePath;
    this.count = count;
  }
}

@Component
export struct BrainPage {
  @StorageProp('fy_top_avoid') topAvoid: number = 40;
  private scene: Scene | null = null;
  private camera: Camera | null = null;
  private light: Light | null = null;
  private groupNodes: (Node | null)[] = [];
  private animator: AnimatorResult | null = null;
  private lastFrameMs: number = 0;
  private yaw: number = Math.PI * 0.5;
  private pitch: number = 0.12;
  private radius: number = 4.2;
  private panLast: PanSample = new PanSample();
  private pinchBase: number = 4.2;

  @State private sceneOpt: SceneOptions | null = null;
  @State private loading: boolean = true;
  @State private failed: boolean = false;
  @State private autoRotate: boolean = true;
  // 分组表来自生成的 BrainGroups.ets（升级数据集后重跑 gen_brain_glb 即可换表）
  @State private groups: BrainGroup[] = BRAIN_GROUPS.map((r: BrainGroupRow): BrainGroup =>
    new BrainGroup(r.zh, r.node, r.count));

  // 神经元总数（实际参与渲染的），顶栏/加载文案都用它——不写死数字
  private totalNeurons(): number {
    let sum = 0;
    for (let i = 0; i < this.groups.length; i++) {
      sum += this.groups[i].count;
    }
    return sum;
  }

  aboutToAppear(): void {
    Scene.load($rawfile('gltf/brain.glb')).then(async (scene: Scene) => {
      this.scene = scene;
      const rf: SceneResourceFactory = scene.getResourceFactory();
      this.camera = await rf.createCamera({ name: 'camera' });
      this.camera.enabled = true;
      this.camera.nearPlane = 0.05;
      this.camera.farPlane = 50.0;
      this.camera.fov = 50 * Math.PI / 180;
      this.camera.clearColor = { r: 0.016, g: 0.024, b: 0.043, a: 1.0 };
      const light = await rf.createLight({ name: 'ambient_sun' }, LightType.DIRECTIONAL);
      light.rotation = quatMul(quatY(Math.PI * 0.75), quatX(-Math.PI / 3));
      light.color = { r: 0.9, g: 0.93, b: 1.0, a: 1.0 };
      light.enabled = true;
      this.light = light;
      // 分组节点引用（找不到就按数组下标对齐为 null）
      this.groupNodes = this.groups.map((g) => {
        const n = scene.root ? scene.root.getNodeByPath(g.nodePath) : null;
        return n ?? this.findByName(scene, g.nodePath);
      });
      console.info(`[FlyBrain] brain groups found: ${this.groupNodes.filter((n) => n !== null).length}/5`);
      this.sceneOpt = { scene: scene, modelType: ModelType.SURFACE } as SceneOptions;
      this.loading = false;
      this.applyCamera();
      this.startLoop();
    }).catch((err: string) => {
      console.error(`[FlyBrain] brain load failed: ${err}`);
      this.loading = false;
      this.failed = true;
    });
  }

  aboutToDisappear(): void {
    if (this.animator !== null) {
      (this.animator as AnimatorResult).finish();
      this.animator = null;
    }
  }

  private findByName(scene: Scene, target: string): Node | null {
    const root = scene.root;
    if (!root) {
      return null;
    }
    const stack: Node[] = [root];
    while (stack.length > 0) {
      const cur: Node | undefined = stack.pop();
      if (!cur || !cur.children) {
        continue;
      }
      for (let i = 0; i < cur.children.count(); i++) {
        const ch: Node | null = cur.children.get(i);
        if (!ch) {
          continue;
        }
        if (ch.name === target) {
          return ch;
        }
        stack.push(ch);
      }
    }
    return null;
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
      if (this.autoRotate) {
        this.yaw += dt * 0.35;
      }
      this.applyCamera();
    };
    (this.animator as AnimatorResult).play();
  }

  private applyCamera(): void {
    if (!this.camera) {
      return;
    }
    const target: Vec3 = { x: 0, y: 0, z: 0 };
    const cp = Math.cos(this.pitch);
    const eye: Vec3 = {
      x: this.radius * cp * Math.sin(this.yaw),
      y: this.radius * Math.sin(this.pitch),
      z: this.radius * cp * Math.cos(this.yaw),
    };
    lookAt(this.camera, eye, target, { x: 0, y: 1, z: 0 });
  }

  private toggleGroup(idx: number): void {
    const g = this.groups[idx];
    g.visible = !g.visible;
    const node = this.groupNodes[idx];
    if (node) {
      (node as Node).visible = g.visible;
    }
    this.groups.splice(idx, 1, g); // 触发 UI 刷新
  }

  build() {
    HdsNavDestination() {
      Stack() {
        if (this.sceneOpt) {
          Component3D(this.sceneOpt)
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
                    this.yaw -= dx * 0.008;
                    this.pitch = clamp(this.pitch + dy * 0.005, -1.2, 1.2);
                  }),
                PinchGesture({ fingers: 2 })
                  .onActionStart(() => {
                    this.pinchBase = this.radius;
                  })
                  .onActionUpdate((event: GestureEvent) => {
                    const s = event.scale > 0.2 ? event.scale : 0.2;
                    this.radius = clamp(this.pinchBase / s, 1.8, 12);
                  })
              )
            )
        } else if (this.failed) {
          Column({ space: 12 }) {
            Text('大脑数据加载失败').fontSize(17).fontColor('#FFEEEEEE')
            Text('安装包需包含 rawfile/gltf/brain.glb').fontSize(13).fontColor('#FF999999')
          }.justifyContent(FlexAlign.Center).width('100%').height('100%')
        } else {
          Column({ space: 12 }) {
            LoadingProgress().width(46).height(46).color('#FF7FA8D0')
            Text(`载入 ${this.totalNeurons()} 个神经元…`).fontSize(14).fontColor('#FFBBBBBB')
          }.justifyContent(FlexAlign.Center).width('100%').height('100%')
        }

        // 全屏覆盖层：顶部信息 / 底部图例（SpaceBetween 上下分布）
        Column() {
          Column({ space: 2 }) {
            Text('完整成年果蝇连接组').fontSize(16).fontWeight(FontWeight.Bold).fontColor('#FFFFFFFF')
            Text(`${BRAIN_DATASET_LABEL} · ${this.totalNeurons()} 神经元`)
              .fontSize(11).fontColor('#FF8899AA')
          }
          .alignItems(HorizontalAlign.Center)
          .width('100%')
          .margin({ top: 4 })

          Blank()

          // 底部控制：自旋开关 + 分组图例
          Column({ space: 8 }) {
          Row() {
            Text('数据来源 FlyWire (flywire.ai) · Nature 634, 124-138 (2024)')
              .fontSize(10).fontColor('#FF667788')
            Blank()
            Button(this.autoRotate ? '停转' : '自旋')
              .fontSize(12).height(28).backgroundColor('#66262630')
              .onClick(() => {
                this.autoRotate = !this.autoRotate;
              })
          }.width('100%')

          Row({ space: 6 }) {
            ForEach(this.groups, (g: BrainGroup, idx: number) => {
              Column({ space: 2 }) {
                Text(g.name).fontSize(12)
                  .fontColor(g.visible ? '#FFFFFFFF' : '#FF666677')
                Text(this.formatCount(g.count)).fontSize(10)
                  .fontColor(g.visible ? '#FF9FB4C8' : '#FF4D5560')
              }
              .padding({ left: 10, right: 10, top: 6, bottom: 6 })
              .borderRadius(10)
              .backgroundColor(g.visible ? '#88303C4E' : '#55202630')
              .onClick(() => {
                this.toggleGroup(idx);
              })
            }, (g: BrainGroup) => g.name + g.visible.toString())
          }
          .width('100%')
          .justifyContent(FlexAlign.Center)
        }
        .padding({ left: 12, right: 12, top: 8, bottom: 14 })
        .borderRadius(14)
        .backgroundColor('#9910141A')
        .margin({ left: 12, right: 12, bottom: 20 })
        }
        .width('100%')
        .height('100%')
        .padding({ left: 12, right: 12, top: this.topAvoid + 52, bottom: 12 })
        .hitTestBehavior(HitTestMode.Transparent)
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#FF04070C')
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    }
    .titleBar({
      content: {
        title: {
          mainTitle: '果蝇大脑'
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
  }

  private formatCount(n: number): string {
    return n >= 10000 ? `${Math.round(n / 1000)}k` : `${n}`;
  }
}

class PanSample {
  public x: number = 0;
  public y: number = 0;
}
