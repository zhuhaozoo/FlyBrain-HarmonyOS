# 果蝇大脑 App（guoying）开发文档

| 项目 | 内容 |
|---|---|
| 开源地址 | https://github.com/zhuhaozoo/FlyBrain-HarmonyOS |
| Bundle | `com.zhuhao.guoying` |
| 目标平台 | HarmonyOS（stage 模型，compatibleSdkVersion 6.1.0(23)，targetSdkVersion 6.1.1(24)） |
| 文档版本 | v1.0（2026-09-15） |
| 本期目标 | **M0 Demo**：预设 3D 场景 + 简单果蝇模型 + 基础行为控制 |
| 参考开源项目 | [snedea/flybrain](https://github.com/snedea/flybrain)（复刻蓝本）、[google/neuroglancer](https://github.com/google/neuroglancer)（上游查看器）、FlyWire 完整果蝇脑连接组（数据源头） |

---

## 1. 项目背景与目标

### 1.1 背景

2024 年，FlyWire 联盟（普林斯顿大学等）在《Nature》发表了**首张完整的成年果蝇（黑腹果蝇）全脑连接组**：约 **139,255 个神经元、约 5,000 万个突触**的完整接线图（FAFB 数据集，FAFB v783），是神经科学里程碑成果。随后开源社区出现了把它跑在浏览器里的实时仿真项目 **FlyBrain**（flybrain.app）：13.9 万神经元用泄漏积分放电（LIF）模型在 Web Worker 中实时仿真，**果蝇的行为不是脚本写死的，而是从神经连接的信号传导中"涌现"出来的**——放置食物它会觅食，触碰它会惊跳，改变光照它会趋光。该项目在社交网络上走红，被认为是最直观体验"完整大脑数字化"的方式。

这些项目都是网页（WebGL）形态，普通手机用户访问门槛高。本项目要做的，就是把这一体验**复刻到鸿蒙上，做成原生 App**，让更多人直观体会"一个完整大脑被完整画出来并跑起来"是什么感觉。

### 1.2 目标拆解

| 阶段 | 内容 | 状态 |
|---|---|---|
| **M0（本期 Demo）** | 预设 3D 场景（地面/光照/相机）+ 简单果蝇 glTF 模型 + 行为状态机（漫步/理毛/起飞/飞行/休息）+ 基础交互（视角拖拽缩放、行为切换、速度调节） | **本文档设计对象** |
| M1 | 交互丰富化：投喂、触碰、光照变化（趋光），内驱力（饥饿/恐惧/疲劳）系统，对齐原版 SPEC 的交互表 | 规划 |
| M2 | 真实连接组可视化：加载 FlyWire 派生数据（13.9 万神经元点云，分区着色），3D 大脑可视化页 | ✅（见第 10.2 节） |
| M3 | 端侧神经仿真：将 flybrain 的 `sim-worker.js` LIF 仿真移植为 ArkTS Worker，行为由连接组信号驱动（"涌现"） | ✅（见第 10.3 节） |
| M4 | 场景丰富化（河流/树木/日月星辰昼夜循环）+ 交互效果深化（投喂/聚光/吹风反馈）+ 玩法（果蝇生命值、捕食者青蛙） | 📋 设计完成：见《[场景与玩法设计-M4.md](./场景与玩法设计-M4.md)》 |

### 1.3 Demo 明确不做的事（M0 范围外）

- 不加载真实连接组数据（13.9 万神经元的仿真与渲染放 M2/M3）；
- 不做精细生物建模（官方要求"简单模型即可"，允许下载或自制简模）；
- 不做联网、账号、后端。

---

## 2. 开源项目调研

### 2.1 数据与成果源头：FlyWire 完整果蝇脑

- 官网：https://flywire.ai ；在线浏览器：https://codex.flywire.ai
- 奠基论文：Dorkenwald, S., Matsliah, A., Sterling, A.R. et al. *Neuronal wiring diagram of an adult brain.* **Nature 634, 124–138 (2024)**. https://doi.org/10.1038/s41586-024-07558-y
- 内容：成年黑腹果蝇全脑（FAFB）电子显微镜重建 + 众包校对，得到首个完整全脑连接组；FAFB v783 为 flybrain 所用版本。
- 数据许可：公开数据集，使用需署名（App 内"关于"页将注明出处，见第 6 节）。

### 2.2 上游查看器：google/neuroglancer

| 项 | 内容 |
|---|---|
| 地址 | https://github.com/google/neuroglancer |
| 许可 | Apache-2.0 |
| 语言/规模 | TypeScript，约 1.4k stars，Google 官方维护 |
| 定位 | WebGL 体数据（神经组学切片、点云、网格）查看器前端，FlyWire Codex 即基于它部署 |

**架构要点**（对理解"为什么不能直接移植"重要）：
- 渲染：WebGL 2.0，多线程架构——主线程跑 UI，数据解码/切片放在 Web Worker 后端；
- 数据格式：自带 precomputed 分块体数据格式，兼容 N5/Zarr 等；
- 本质是"超大科学数据的**切片/体渲染查看器**"，不是移动端 3D 场景引擎，无任何移动原生实现。**不整体移植**，只在 M2/M3 借鉴其分块/LOD 思想。

### 2.3 复刻蓝本：snedea/flybrain ⭐（本期主要参考）

| 项 | 内容 |
|---|---|
| 地址 | https://github.com/snedea/flybrain |
| 在线 Demo | https://flybrain.app |
| 许可 | **MIT**（可复用代码，保留版权声明即可） |
| 语言 | 原生 JavaScript（Vanilla JS，无构建步骤），three.js 以 `js/vendor/three.min.js` 内嵌 |
| 规模 | 88 个文件；JavaScript |
| 数据 | FlyWire FAFB v783 派生二进制：**139,255 神经元 / 270 万连接**，LIF 模型在 Web Worker 实时仿真 |
| 血统 | Fork 自 [heyseth/worm-sim](https://github.com/heyseth/worm-sim)（秀丽隐杆线虫 302 神经元浏览器仿真），把线虫换成 13.9 万神经元的果蝇 |

#### 2.3.1 完整代码结构（仓库全部 88 个文件中与本 App 相关的部分）

```
flybrain/
├── index.html                 # 单页入口（顶栏工具 + 画布 + 底部神经面板 + 内驱力表）
├── SPEC.md                    # ⭐ 设计规格书（交互表/身体部件/脑架构/行为表，移植行为设计的直接依据）
├── js/
│   ├── main.js                # 主循环：果蝇实体、用户交互、渲染调度
│   ├── sim-worker.js          # ⭐ LIF 神经仿真（Web Worker，14KB）：13.9 万神经元实时放电
│   ├── brain-worker-bridge.js # 主线程 <-> 仿真 Worker 的消息桥
│   ├── connectome.js          # 连接组数据加载/解析（gz 二进制）
│   ├── fly-logic.js           # ⭐ 行为决策纯函数：行为阈值、优先级链、觅食转向（可近乎直接翻译成 ArkTS）
│   ├── brain3d.js             # 3D 大脑/神经渲染（three.js）
│   ├── neuro-renderer.js      # 底部面板 13.9 万神经元实时放电渲染（WebGL）
│   ├── constants.js           # 常量
│   ├── education.js           # 科普教育内容
│   └── vendor/                # three.min.js + OrbitControls.js
├── data/
│   ├── connectome.bin.gz      # 压缩连接组二进制（M2/M3 直接复用）
│   ├── connections.csv.gz     # 连接表
│   ├── coordinates.csv.gz     # 神经元 3D 坐标（M2 点云可视化直接复用）
│   ├── classification.csv.gz  # 神经元分类（感觉/中央/驱动/运动）
│   ├── neurons.csv.gz         # 神经元表
│   └── neuron_meta.json       # 元数据
├── scripts/build_connectome.py # 数据预处理：从 FlyWire 公开数据生成上述二进制（19KB，可复跑）
├── ios/                       # ⭐ 已有 iOS 原生壳（SwiftUI WKWebView）——"网页项目包原生壳"的先例
├── css/main.css
├── tests/                     # Node/浏览器双端测试（tests.js 覆盖 fly-logic 纯函数）
└── server/                    # 可选的 caretaker 后端（与本 App 无关，不移植）
```

#### 2.3.2 运行原理（理解后才能正确移植）

```
用户交互(喂食/触碰/风吹/光照)
        │
        ▼
感觉神经元群(R1-R8 视觉 / ORN 嗅觉 / GRN 味觉 / 刚毛机械感受 / Johnstons 器风感)
        │  刺激注入
        ▼
sim-worker.js：LIF 仿真（139,255 神经元 × 270 万加权连接，膜电位累积→放电）
        │  运动神经元群放电输出
        ▼
行为决策（fly-logic.js）：放电累积量 + 内驱力 → 按优先级选行为状态
   优先级：startle > fly > feed > groom > brace > rest > phototaxis > explore > walk > idle
        ▼
果蝇身体动画（main.js / three.js）：走(三足步态)、理毛、进食、惊跳、飞行、休息…
```

**内驱力系统**（SPEC 定义，0.0~1.0 浮点，随时间变化）：
- **Hunger** 饥饿：约 +0.01/s 持续增长，进食后下降，驱动觅食；
- **Fear** 恐惧：触碰/风吹时尖峰，约 10s 衰减，影响惊跳阈值；
- **Fatigue** 疲劳：活动增强、休息恢复，影响速度与休息判定（阈值 0.7，暗环境 0.4）；
- **Curiosity** 好奇：随机波动，影响探索与停留（探索阈值 0.4）。

**关键行为阈值**（`fly-logic.js` 的 `BEHAVIOR_THRESHOLDS`，可直接作为 ArkTS 默认参数）：
`startle: 30, fly: 15, feed: 8, groom: 8, walk: 5, restFatigue: 0.7, exploreCuriosity: 0.4, phototaxisLight: 0.5`；觅食转向 = 朝向插值 `targetDir = facing + angleDiff * min(1, hunger)`。

**身体部件**（原版 2D 画布绘制；我们的 3D 模型应包含对应结构）：头（含 2 复眼、2 触角）、胸、腹、6 足（3 对，三足步态）、2 翅（静止折叠/飞行展开）、舐吸式口器（进食时伸出）。

#### 2.3.3 我们复刻什么

- **本期（M0）**：行为状态机与内驱力模型（简化版，参数默认值直接沿用上表）；交互概念（后续投喂/触碰/光照）；科普文案思路（`education.js`）。
- **后续（M2/M3）**：`data/` 下的连接组二进制与坐标数据（MIT 许可直接随仓库使用）；`sim-worker.js` 的 LIF 算法移植为 ArkTS Worker。
- **不复刻**：Web 技术栈本身（three.js/OrbitControls/Canvas 2D），对应能力改用鸿蒙原生方案（见第 3、4 节）。

---

## 3. 鸿蒙移植方案

### 3.1 技术栈映射表

| flybrain（Web） | guoying（HarmonyOS 原生） |
|---|---|
| three.js 场景图 + WebGL | **ArkGraphics 3D**（`@kit.ArkGraphics3D` / `@ohos.graphics.scene`）：Scene / Node / Camera / Light |
| `<canvas>` / `Component3D`（自动模式） | **`Component3D` 组件**（自定义模式，传入 Scene 对象，API 12+） |
| OrbitControls（拖拽旋转/缩放视角） | ArkUI 手势（`PanGesture`/`PinchGesture`）→ 更新相机 position/rotation（自定义模式无内置手势，需自实现，见 4.2） |
| Web Worker（LIF 仿真） | ArkTS `Worker` / `TaskPool`（M3） |
| requestAnimationFrame 主循环 | `UIContext.createAnimator(iterations:-1).onFrame`（官方示例模式） |
| HTML/CSS UI | ArkUI 声明式：`Navigation`/`NavDestination` + 组件 |
| glTF 资产 | glTF（.glb）放入 `resources/rawfile/`，`$rawfile()` 加载（鸿蒙 3D 引擎**仅支持 glTF**） |

### 3.2 方案选型对比

| 方案 | 说明 | 结论 |
|---|---|---|
| **A. 原生 ArkTS + ArkGraphics 3D** | 官方 3D 场景引擎 + Component3D 组件，glTF 模型，全原生 UI | ✅ **本期采用**。符合"UI 参考官方框架、3D 参考官方文档"的要求，体验原生、后续 M2/M3 路线通顺 |
| B. ArkWeb 壳加载原版网页 | 把 flybrain（MIT）整站塞入 rawfile，`Web` 组件离线加载（仿其 ios/ 目录的 WKWebView 壳） | 备选快速通道：能用最快速度获得 100% 原版功能（含 13.9 万神经元实时仿真），但 WebView 性能与"原生复刻"目标不符。**列为 M1.5 可选并行验证**，不作为主线 |
| C. XComponent + OpenGL ES / C++ NDK | 自写渲染管线 | ✗ 造轮子，工作量大，官方已有高层 3D API，无需此方案 |

### 3.3 总体架构

```
┌─ UI 层（ArkUI 声明式）─────────────────────────────┐
│  Navigation                                        │
│   ├─ ScenePage     3D 场景主页（Component3D 全屏    │
│   │                + 悬浮控制条 + 手势）             │
│   ├─ SettingsPage  行为参数页（速度/行为开关等）      │
│   └─ AboutPage     关于 FlyWire 科普 + 开源致谢      │
├─ 渲染层（ArkGraphics 3D）──────────────────────────┤
│  SceneManager：Scene.load → 相机/光照创建 →         │
│  SceneOptions → Component3D 渲染                   │
│  FlyRenderer：果蝇节点变换（位置/朝向/翅膀）          │
├─ 行为层（纯 ArkTS，无 UI 依赖，可单测）───────────────┤
│  FlyConfig（默认参数） FlyBrain（内驱力）            │
│  FlyStateMachine（状态优先级链，对齐 fly-logic.js）   │
├─ 资源层 ──────────────────────────────────────────┤
│  rawfile/gltf/fly.glb（果蝇） scene.glb（场景/地面） │
└───────────────────────────────────────────────────┘
```

分层原则：**行为层是纯函数/纯类，不依赖 3D API**（原版 `fly-logic.js` 同样是纯函数，且有独立测试——照搬这一良好结构，后续可直接跑 Node 式单测）。

---

## 4. Demo 详细设计（M0）

### 4.1 功能清单与验收场景

1. 打开 App 进入 3D 场景：地面 + 平行光 + 环境光 + 相机，果蝇模型在场景中可见；
2. 果蝇默认"漫步"（wander）：随机转向前进、贴地、边界回转；
3. 底部控制条：行为切换（漫步/理毛/起飞飞行/休息）、速度 Slider、暂停/继续；
4. 手势：单指拖拽环绕视角、双指捏合缩放（自实现轨道相机）；
5. 内驱力简化版（本期内置默认值运转：疲劳累计→自动休息→恢复后继续活动）；
6. "关于"页：FlyWire/Nature 论文/flybrain 项目署名（合规，见第 6 节）。

### 4.2 3D 场景方案（官方 ArkGraphics 3D）

依据官方文档《ArkGraphics 3D场景搭建以及管理》与《Component3D》参考（API 12+，本项目 targetSdk 6.1.1(24) 满足）。一个 3D 场景 = **模型 + 相机 + 光源**；模型**仅支持 glTF（.gltf/.glb）**，纹理仅支持 JPEG/PNG。

**模式选择**：`Component3D` 传入 glTF 文件路径时是"自动场景模式"（框架自动建相机/光源/手势，但**参数不可控**）；传入 `Scene` 对象时是"自定义场景模式"（相机、光源、交互全部由开发者管理）。**本项目用自定义场景模式**——因为果蝇位置/朝向每帧要改、相机要跟随手势，必须拿到 Scene 对象操作节点。官方明确提示：自定义模式**没有内置相机控制器，不会自动响应拖拽/缩放手势**，需自行接入手势更新相机，这点写入实现注意事项。

**初始化骨架**（源自官方文档样例，按本项目改写）：

```typescript
import { Camera, Light, LightType, Scene, SceneNodeParameters,
         SceneResourceFactory, SceneOptions } from '@kit.ArkGraphics3D';

@Entry
@Component
struct ScenePage {
  private scene: Scene | null = null;
  private camera: Camera | null = null;
  private light: Light | null = null;
  @State sceneOpt: SceneOptions | null = null;

  aboutToAppear(): void {
    // 1. 加载场景（glb 放在 entry/src/main/resources/rawfile/gltf/ 下）
    Scene.load($rawfile('gltf/scene/scene.glb'))
      .then(async (scene: Scene) => {
        this.scene = scene;
        const rf: SceneResourceFactory = scene.getResourceFactory();
        // 2. 相机
        this.camera = await rf.createCamera({ name: 'camera' } as SceneNodeParameters);
        this.camera!.enabled = true;
        this.camera!.position.z = 5;            // 观察距离
        this.camera!.fov = 60 * Math.PI / 180;  // FoV
        // 3. 平行光（模拟太阳）——没有光场景是全黑的
        this.light = await rf.createLight(
          { name: 'sun' } as SceneNodeParameters, LightType.DIRECTIONAL);
        // 4. 交给 Component3D 渲染
        this.sceneOpt = { scene: this.scene!, modelType: ModelType.SURFACE } as SceneOptions;
      })
      .catch((err: string) => console.error('Scene load failed: ' + err));
  }

  build() {
    Stack() {
      if (this.sceneOpt) {
        Component3D(this.sceneOpt)
          .renderWidth('100%').renderHeight('100%')
      } else {
        LoadingProgress().width(48).height(48)
      }
      // …底部控制条 / 手势层
    }
  }
}
```

**相机手势（自实现轨道相机）**：在 `Component3D` 外层包 `Stack` + 手势：
- `PanGesture`：水平位移 → 相机绕场景中心方位角 θ 增减；垂直位移 → 俯仰角 φ（钳制 5°~85°）；相机位置 = 球坐标 (r, θ, φ)，`lookAt` 朝向场景中心；
- `PinchGesture`：缩放半径 r（钳制 2~15）；
- 更新 `camera.position` 即可触发重绘（官方文档的 Slider 控制相机 z 值示例即此机制）。

**逐帧驱动（果蝇动画）**：沿用官方 Component3D 自定义渲染示例的 `createAnimator` 模式——`this.getUIContext().createAnimator({ duration: 16, iterations: -1, ... })`，在 `onFrame` 回调里以 `Date.now()` 计算 delta time，更新果蝇节点的 position/rotation 与翅膀摆动，随后引擎自动重绘。

**场景内容（预设，简单即可）**：
- `scene.glb`：一个地面圆盘/方格平面 + 若干低多边形障碍物（石块/草丛，可选）；初版甚至可以只放"地面 + 背景色"；
- 光照默认参数：1 盏 `LightType.DIRECTIONAL`（暖白，强度中等，自上前方 45°）+ environment 环境资源（可选，`Component3D.environment()` 支持 glTF 环境）。

### 4.3 果蝇模型方案

要求：**简单即可**（用户明确），glb 格式，Y-up，面数建议 < 5 万三角面，体积 < 5MB（进入 rawfile 随包分发），身体结构尽量对应：头（复眼 2、触角 2）、胸、腹、6 足、2 翅。

| 途径 | 说明 | 建议 |
|---|---|---|
| A. 下载现成免费模型 | [Sketchfab](https://sketchfab.com) 搜 "fruit fly / Drosophila"（筛选 CC0/CC-BY 可下载 glTF）；Quaternius / Kenney 等 CC0 低多边形素材站（昆虫类目）；下载后用 Blender 检查朝向/缩放并导出 .glb | ⭐ **首选**，最快拿到带贴图的合格简模；注意保留作者署名（关于页致谢） |
| B. Blender 自制 | 胶囊体拉长做胸腹、球体做头、2 片薄椭圆做翅、6 根弯管做腿；纯色材质免贴图，10~30 分钟能完成 | 无合适下载资源时的兜底；也便于后续给翅/腿做骨骼动画 |
| C. 代码图元拼装 | `@kit.ArkGraphics3D` 支持代码建几何（`CubeGeometry`/`CustomGeometry`/`MeshResource` + `ShaderMaterial`，见 AR Engine 示例的用法） | 兜底的兜底；零资产依赖但观感最简 |

**动画策略（M0 不要求骨骼动画）**：
- 若下载的模型自带 glTF 动画（飞/爬循环），可直接用 `scene.animations` 播放（官方 `Animation` API 支持 onStarted/onFinished 回调）；
- 无动画时由代码驱动：整机节点 = 行为层输出的位置/朝向；翅膀子节点 = `rotation` 正弦摆动（频率随状态：飞行高频 ~180°/s、静止微颤）；腿部 M0 不单独动（简化），或整体微幅上下浮动模拟爬行颠簸。

### 4.4 果蝇行为控制方案（核心）

对齐 flybrain 的"内驱力 + 状态机"设计，M0 用**简化版**（无神经仿真，阈值直接判定），但**保持与原版相同的参数命名与优先级链**，M3 接入 LIF 仿真时只需把"阈值判定"替换为"放电累积量判定"，上层不变。

#### 4.4.1 行为状态机

```
            ┌────────────────────────────────────────────┐
            ▼                                            │
  ┌─────── IDLE(静止) ─── curiosity高 ──► WANDER(漫步) ──┤
  │            │                          ▲             │
  │        fatigue>0.7                    │ fatigue<0.4  │
  │            ▼                          │             │
  │         REST(休息,5~15s) ─────────────┘             │
  │                                                     │
  └── 用户点"起飞"或 fear>阈值 ──► TAKEOFF ──► FLY(空中  │
        正弦浮动+平滑转向) ──► 用户点"降落"或超时 ──► LAND ─┘
  WANDER 中周期性随机 ──► GROOM(理毛,2~5s) ──► 回 WANDER
```

优先级（沿用 `fly-logic.js`，M0 去掉 feed/startle 等需交互触发的项，留接口）：`fly > groom > rest > wander(explore/walk) > idle`。

#### 4.4.2 参数默认值表（"其他配置都用默认"即指此表，集中在一个类里）

```typescript
// behavior/FlyConfig.ets —— 默认值沿用 flybrain fly-logic.js / SPEC
export class FlyConfig {
  // 运动
  walkSpeed: number = 1.2;          // 场景单位/秒
  flySpeed: number = 3.0;
  turnRate: number = 1.5;           // 最大转向角速度 rad/s
  wanderTurnJitter: number = 0.5;   // 漫游随机转向抖动
  arenaRadius: number = 4.0;        // 场地半径（出界回转）
  // 内驱力
  fatigueGain: number = 0.01;       // 疲劳累计/s（活动时）
  fatigueRecover: number = 0.05;    // 疲劳恢复/s（休息时）
  restThreshold: number = 0.7;      // 休息阈值（fly-logic restFatigue）
  restWakeThreshold: number = 0.4;  // 醒来阈值（暗环境语义，M0 固定用）
  // 行为时长
  groomDuration: [number, number] = [2, 5];   // 秒（SPEC 行为表）
  restDuration: [number, number] = [5, 15];
  groomChance: number = 0.15;       // 漫游中每 10s 触发理毛概率
  // 动画
  wingFlapIdleDeg: number = 5;      // 静止翅微颤幅度
  wingFlapFlyHz: number = 9;        // 飞行翅拍频率（视觉近似，真实果蝇~200Hz）
  bobAmplitude: number = 0.02;      // 爬行颠簸幅度
}
```

#### 4.4.3 行为层与渲染层的接合

- `FlyBrain`（行为层）每帧 `update(dt)`：更新内驱力 → 按优先级切换状态 → 输出 `{ position, headingYaw, state }`；
- `FlyRenderer`（渲染层）拿到输出：`flyNode.position = ...`；朝向用绕 Y 轴旋转（headingYaw），飞行加俯仰；翅膀子节点按状态摆动；
- 场景坐标系约定：Y 向上，果蝇初始在原点，活动域为半径 `arenaRadius` 的圆内，贴地 y = 模型半高。

### 4.5 UI 设计框架（官方 ArkUI）

依据官方文档《ArkUI 概览》《ArkTS 声明式开发概述》《Navigation 导航》：页面设计为多个 `NavDestination`，通过 `Navigation` 容器以路由栈（`NavPathStack`）管理跳转/回退，实现功能解耦。

**页面结构（M0）**：

```
Navigation(NavPathStack)
 ├─ ScenePage（主页）：Stack{ Component3D 全屏；顶部标题栏(半透明)；底部悬浮控制条 }
 │    控制条：[行为SegmentButton: 漫步|理毛|起飞|降落] [速度Slider] [关于入口]
 ├─ SettingsPage：行为参数（M0 只读展示默认值 + 速度可调持久化）
 └─ AboutPage：FlyWire 科普 + 论文引用 + 开源致谢（flybrain MIT / 模型作者）
```

**要点**：
- 状态管理：场景页用 `@State`（sceneOpt/loading/当前行为），跨页参数用 `@Provide/@Consume('pathStack')`（官方 Navigation 示例模式）；
- 3D 页全屏：`Stack` 分层（3D 内容 + UI 覆盖层），控制条悬浮（`linearGradient` 半透明底），避让挖孔/手势条（`getWindowAvoidArea` 安全区 padding）；
- 深浅色：跟随系统（`ConfigurationConstant`，颜色走资源 `dark/` 目录，模板已有 color.json）；
- 组件全部用官方基础组件（Text/Button/Slider/Toggle/SegmentButton），不引第三方 UI 库；
- 注意：**Component3D 在 DevEco 预览器中不支持渲染，必须真机验证**（官方文档明示）。

### 4.6 工程目录规划

```
entry/src/main/ets/
├── entryability/EntryAbility.ets      # 已有（模板）
├── pages/
│   ├── Index.ets                      # Navigation 根容器（改造模板页）
│   ├── ScenePage.ets                  # 3D 场景主页
│   ├── SettingsPage.ets
│   └── AboutPage.ets
├── scene/                             # 渲染层
│   ├── SceneManager.ets               # Scene.load/相机/光照/手势相机
│   └── FlyRenderer.ets                # 果蝇节点与翅膀动画
├── behavior/                          # 行为层（纯逻辑，可单测）
│   ├── FlyConfig.ets
│   ├── FlyBrain.ets                   # 内驱力 + 状态机（对齐 fly-logic.js）
│   └── FlyTypes.ets                   # 行为枚举等
└── common/
    └── MathUtil.ets                   # normalizeAngle 等纯函数（翻译自 fly-logic.js）
entry/src/main/resources/rawfile/
├── gltf/scene/scene.glb               # 预设场景（地面）
└── gltf/fly/fly.glb                   # 果蝇模型
```

---

## 5. 关键风险与对策

| # | 风险 | 对策 |
|---|---|---|
| 1 | Component3D 自定义模式无内置手势相机，官方预览器不支持 3D 预览 | 按官方示例自实现轨道相机；**全流程真机调试**（hdc 安装） |
| 2 | 3D 引擎仅支持 glTF/glb、纹理仅 JPEG/PNG；模型朝向/单位不合 | 模型入库前过 Blender：转 Y-up、缩放到场景单位（果蝇体长≈0.5 场景单位）、导出 .glb |
| 3 | 逐帧改节点属性的渲染触发机制与帧率表现未知 | 先做"相机 Slider"最小验证；用 `createAnimator` 官方模式驱动；性能不行再降频/降面数 |
| 4 | 下载的模型许可不清 | 只用 CC0/CC-BY，关于页留署名；拿不准就走 Blender 自制（途径 B） |
| 5 | Scene.load 沙箱/路径限制 | 模型一律放 `resources/rawfile/` 用 `$rawfile()` 加载（官方相对路径方式） |
| 6 | M2 大数据（13.9 万神经元）渲染压力 | 届时用点云 + LOD + 分批加载；数据文件放 rawfile 随包或按需下载，gz 解压放 TaskPool |

---

## 6. 数据与开源许可合规

| 来源 | 许可 | 义务 |
|---|---|---|
| snedea/flybrain 代码 | MIT | 保留版权与许可声明（About 页 + 打包 LICENSE 附本） |
| flybrain 数据文件（源自 FlyWire Codex 公开数据） | 随仓库 MIT 分发；上游数据要求署名 | About 页引用论文：Dorkenwald et al., *Nature* 634, 124–138 (2024)，注明数据来自 FlyWire (flywire.ai / codex.flywire.ai) |
| google/neuroglancer | Apache-2.0 | 仅作架构参考，不分发其代码则无义务；若引用代码需附声明 |
| 下载的果蝇模型 | 视来源（CC0/CC-BY） | About 页致谢作者；禁用不明许可模型 |

---

## 7. 里程碑与验收标准（M0 Demo）

| 步骤 | 内容 | 验收 | 状态（2026-09-15） |
|---|---|---|---|
| M0.1 | 3D 空场景跑通：scene.glb（仅地面）+ 相机 + 平行光，真机显示 | 真机可见地面与光照 | ✅ 代码完成，待真机确认画面 |
| M0.2 | 轨道相机：Pan 旋转 / Pinch 缩放 | 手势流畅，无跳变 | ✅ 代码完成，待真机确认手感 |
| M0.3 | 果蝇模型入库并静态显示 | 模型比例/朝向正确，光照正常 | ✅ 程序化模型已生成打包，待真机确认 |
| M0.4 | 行为层状态机 + 逐帧驱动（漫步/理毛/休息/起飞/飞行/降落） | 行为按默认参数自动切换，边界回转正常 | ✅ 代码完成，待真机确认 |
| M0.5 | UI：控制条（行为/速度/暂停）+ Settings + About（含署名） | 页面跳转正常，深浅色正常 | ✅ 代码完成 |
| M0.6 | 构建签名打包（E 盘工具链 hvigorw，流程见 AGENTS.md） | signed HAP 安装真机，运行无崩溃 | ✅ signed HAP 已生成并安装到手机 |

**M0 完成定义**：真机安装后打开即见"果蝇在预设 3D 场景中自主活动"，可切换行为、调速度、转视角，About 页有完整署名。

---

## 8. 参考资料汇总

**开源项目**
- FlyBrain（复刻蓝本，MIT）：https://github.com/snedea/flybrain （在线版 https://flybrain.app ）
- worm-sim（FlyBrain 上游，线虫版）：https://github.com/heyseth/worm-sim
- neuroglancer（FlyWire 官方查看器内核，Apache-2.0）：https://github.com/google/neuroglancer
- 果蝇连接组项目导航：https://github.com/cobanov/awesome-fly
- FlyWire 官网 / 数据浏览器：https://flywire.ai / https://codex.flywire.ai
- FlyWire 论文：https://doi.org/10.1038/s41586-024-07558-y （Nature 634, 124–138, 2024）

**HarmonyOS 官方文档**
- ArkGraphics 3D 场景搭建以及管理（模型加载/相机/光源/交互）：https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkgraphics3d-scene
- Component3D 组件参考（SceneOptions/自动与自定义模式）：https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-basic-components-component3d
- @ohos.graphics.scene 模块参考：https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-scene
- 官方 3D 示例工程（Graphics3D）：https://gitcode.com/HarmonyOS_Samples/Graphics3D
- ArkUI 概览 / 声明式开发：https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkui-overview
- Navigation 导航（NavDestination/NavPathStack）：https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-navigation-architecture

**模型素材（候选）**
- Sketchfab（筛选 CC0/CC-BY 可下载）：https://sketchfab.com/search?q=fruit+fly&type=models
- Quaternius 免费 CC0 低多边形模型：https://quaternius.com
- Kenney assets（CC0）：https://kenney.nl/assets

---

## 9. 实施记录（M0 已完成，2026-09-15）

本章记录 M0 的实际落地方式，与正文设计有出入之处以本章为准。

### 9.1 实际代码结构（全部已提交进工程）

```
entry/src/main/ets/
├── common/Math3D.ets          # 向量/四元数工具 + lookAt（相机注视）+ normalizeAngle/clamp
├── behavior/FlyTypes.ets      # FlyState 枚举（7 态）、FlyPose、状态中文名表
├── behavior/FlyConfig.ets     # 全部行为默认参数 + flyConfig 全局单例
├── behavior/FlyBrain.ets      # 内驱力（疲劳）+ 状态机 + 边界回转（纯逻辑，无渲染依赖）
├── scene/SceneManager.ets     # Scene.load(world.glb)、createCamera/createLight、轨道相机、getNodeByPath
├── scene/FlyRenderer.ets      # 姿态写入节点：position/rotation + 翅膀按状态拍动
├── pages/Index.ets            # Navigation 根容器（@Provide('nav') + PageMap 路由表）
├── pages/ScenePage.ets        # 3D 主页：Component3D + 手势 + 控制条 + createAnimator 帧循环
├── pages/SettingsPage.ets     # 速度倍率调节（preferences 持久化）+ 参数默认值只读表
└── pages/AboutPage.ets        # 项目介绍/论文引用/开源致谢（合规署名）
tools/gen_world_glb.mjs        # ⭐ 程序化模型生成脚本（Node 零依赖，见 9.2）
entry/src/main/resources/rawfile/gltf/world.glb   # 生成产物（45,836 字节，已随包安装验证）
```

### 9.2 模型方案（最终采用：程序化生成，非下载/Blender）

正文 4.3 的三个途径中，最终采用**途径 C 的升级版**：编写 `tools/gen_world_glb.mjs`（零依赖 Node 脚本）
直接产出 glTF 2.0 二进制（.glb），彻底规避第三方素材版权问题。

- 场景：地面圆盘（r=5.5）+ 8 块环状石块（共享椭球网格，节点缩放摆放）；
- 果蝇：胸/腹/头/双复眼/双触角/六足/双翅共 15 个子节点，挂在名为 `fly` 的根节点下；
  朝向 +Z，根节点位于地面接触点，体长约 0.7 场景单位；
- 运行时驱动点：`fly`（整体位置+朝向）、`fly/wing_left`、`fly/wing_right`（翅膀轴心，绕 Z 摆动）；
- 材质：纯色 PBR（metallic=0），无纹理（规避纹理格式限制），总面数 < 5 千；
- 自校验：脚本内置 GLB 头/长度/accessor 越界检查；
- 重新生成：`node tools/gen_world_glb.mjs`（改参数后重跑即可）。

### 9.3 关键实现决策（与正文设计的差异/细化）

1. **相机朝向**：正文担心的"欧拉角顺序不确定性"已消除——参考华为官方 Graphics3D 示例
   （`HarmonyOS_Samples/Graphics3D` 的 `utils/CalcUtils.ets`，Apache-2.0）确认 `Node.rotation`
   直接接受 **Quaternion**，采用官方同款"构造正交基→旋转矩阵转四元数"的 lookAt 方案
   （`common/Math3D.ets`，已保留来源声明）。轨道相机 = 球坐标(yaw/pitch/radius) + lookAt，
   PanGesture 改 yaw/pitch，PinchGesture 改 radius。
2. **场景组织**：地面+石块+果蝇合并在**单个 world.glb** 中（Component3D 一次只渲染一个 Scene，
   不支持多 glb 合并）；相机与光源不用 glTF 内嵌（KHR_lights_punctual 支持性存疑），
   改用官方 createCamera/createLight API 动态创建（文档样例同款）。
3. **节点查找（踩坑修复）**：glTF 加载后，顶层节点之上存在引擎包裹层——实测 `scene.root` 名为
   `'rootNode_'`，我们的 `'fly'` 并非其直接子节点，因此 `getNodeByPath('fly')` 返回空
   （这正是首版"3D 场景加载失败"的根因）。最终改为**按名字深度优先搜索**
   （`Node.children` 容器 `count()/get(i)` 遍历，官方文档推荐做法），
   并在找不到时用官方文档提供的遍历方式打印节点树辅助诊断（SceneManager.findByName/dumpTree）。
4. **帧驱动**：`UIContext.createAnimator({duration:16, iterations:-1}).onFrame` 驱动
   `FlyBrain.update(dt)` → `FlyRenderer.apply(...)`，dt 以真实时钟差计算并钳制 ≤50ms
   （防切后台大步长瞬移）。属性修改自动触发 3D 重绘（官方 Slider 调相机示例同机制）。
5. **避坑**（首轮构建实际踩到并修复）：ArkTS 对象字面量必须有显式类型标注
   （`arkts-no-untyped-obj-literals`）；`AnimatorOptions/AnimatorResult` 需从 `@kit.ArkUI` 导入。
6. **状态机**：与正文 4.4 一致（漫步/理毛/休息/起飞/飞行/降落 + 保留 Idle），疲劳阈值 0.7 进休息、
   0.4 醒来，参数全部集中在 `FlyConfig`（语义沿用 flybrain fly-logic.js）。
7. **光照方向**：DIRECTIONAL 光默认朝 -Z 照射，而初始相机位于 -Z 侧，直用会导致看到纯黑背面；
   已用四元数组合 `quatY(π-0.5)·quatX(-π/4)` 把光转向相机一侧、俯角 45°（SceneManager.init）。
8. **相机跟随**：注视点每帧向果蝇位置平滑插值（钳制在场心 ±1.6 内），果蝇始终保持在画面中；
   默认俯角 41°、半径 5.6。主页启动时会恢复持久化的速度倍率（与设置页共用 preferences）。

### 9.4 构建与安装结果

- 构建命令（`<DEVECO_HOME>` 为本地 DevEco Studio 安装目录）：
  `DEVECO_SDK_HOME=<DEVECO_HOME>\sdk` + `"<DEVECO_HOME>\tools\hvigor\bin\hvigorw.bat" --mode module -p product=default -p buildMode=debug assembleHap`
- **BUILD SUCCESSFUL**，产物 `entry\build\default\outputs\default\entry-default-signed.hap`（338 KB，
  使用本地自建调试签名；签名配置不入库，需在本机 DevEco 中生成，见 README）；
- 已通过无线调试 `hdc install -r` 安装到真机（com.zhuhao.guoying）；
- 应用名已改为「果蝇大脑」（AppScope + entry string 资源）。

### 9.5 真机验证结果（2026-09-15 已通过）

通过 hdc 无线调试安装并启动（`aa start`），用 `snapshot_display` 截屏 + `uitest uiInput click`
模拟点击做了全链路验证：

1. ✅ 场景渲染：绿色地面圆盘 + 8 块石丘 + 平行光，背景浅灰；
2. ✅ 果蝇可见且结构正确：红复眼、棕褐胸腹、六足、双翅；
3. ✅ 行为状态机端到端运转：截屏实测观察到 漫步 → 休息（疲劳触发）→ 起飞（按钮触发）的完整切换；
4. ✅ UI：控制条/标题/设置/关于正常渲染，速度 Slider 调节并跨启动持久化（实测记住 0.25x）；
5. ✅ 相机注视点跟随果蝇，起飞后镜头随动；
6. ⚠️ 已知事项：
   - 冷启动到场景就绪约 10~20 秒（引擎初始化 + glTF 解析），期间显示加载动画，属可接受范围；
   - 手势（单指旋转/双指缩放）未自动化验证，需人工试玩确认手感；
   - 石块造型仍偏"圆丘"，后续可换更立体的低多边形岩石；
   - `设置/关于` 页面的 Navigation 跳转已编译进 PageMap，未逐一截图验证。

### 9.6 M1 展望（下一步）

按正文路线：投喂/触碰/风吹/光照交互 + 饥饿/恐惧内驱力（flybrain SPEC 交互表）→
连接组点云脑可视化（coordinates.csv.gz 直接可用）→ sim-worker.js LIF 移植到 TaskPool。

---

## 10. M1/M2/M3 实施记录（2026-09-15 已全部完成并真机验证）

### 10.1 M1 —— 交互与内驱力 ✅

- **内驱力**：饥饿（+0.008/s，初始 0.55）、恐惧（触碰/强风上升，0.1/s 衰减）、好奇（随机游走）、疲劳（已有）。
- **新行为状态**：惊吓 Startle（僵 0.3s→背向刺激逃离 1.4s）、进食 Feed（4s 吃完一份，饥饿-0.48）、
  趴伏 Brace（弱风贴伏）、觅食 Seek（走向最近食物，超时 14s）。优先级链对齐 fly-logic.js：
  `startle > fly > feed > groom > brace > rest > phototaxis > seek > wander`。
- **交互工具栏**：触碰（点果蝇附近触发）/ 投喂（点击地面放食物，最多 5 份）/ 聚光（光斑移到点击处，
  趋光目标）/ 吹风（弱风→趴伏、强风→惊吓）/ 光照·亮暗黑（三档循环：黑暗时休息阈值降为 0.4）。
- **实现要点**：
  - 屏幕点击→地面坐标：不用 raycast，直接用已知相机参数（eye/target/fov）手工反投影
    与 y=0 平面求交（SceneManager.groundPoint），稳定且版本无关；
  - 食物/光斑是 world.glb 预埋节点（food_0..4、lightspot，初始藏于 y=-10），运行时激活/移动/缩放；
  - 覆盖层必须 `hitTestBehavior(HitTestMode.Transparent)` 才能让点击穿透到 Component3D
    （并按 y 区间忽略控制条/顶栏区域的穿透），这是实际踩过的坑；
  - 光照档位通过 `light.intensity` 乘系数（首帧记录默认强度）。
- **真机验证**：投喂→觅食→进食（饥饿 100%→56%）、状态标签/内驱力文字（饿/怕/累）、
  光照切换均实测通过。

### 10.2 M2 —— 真实连接组 3D 大脑可视化 ✅

- **数据管线**：`tools/gen_brain_glb.mjs` 读取 flybrain 的 coordinates.csv（按 root_id 去重）
  与 classification.csv（super_class 分组），把 **139,255 个真实神经元坐标**归一化成
  一个 ~1.6 半径的脑形点云，每神经元一个小三角形（双面+自发光），按 5 组分 mesh：
  视觉 77,873 / 感觉 16,938 / 中央 44,254 / 运动 110 / 内分泌 80（与 FlyWire 数量一致）。
  产物 `rawfile/gltf/brain.glb`（11.6MB）。原始数据文件存 `tools/data/`。
- **BrainPage**：主页"大脑"按钮进入。独立 Scene+相机+lookAt 轨道、自动慢速自旋（可停）、
  分组图例 chips（显示数量，点击开关该组 `node.visible`）、深色背景、数据来源署名。
- **真机验证**：加载约 5/5 组全部命中，点云渲染清晰（蓝视觉叶/橙感觉/紫中央），自旋与图例正常。

### 10.3 M3 —— 端侧 LIF 神经仿真（涌现行为）✅

- **数据**：flybrain `connectome.bin.gz`（解压 31MB）→ `rawfile/connectome.bin`。
  二进制格式（小端）：uint32 神经元数 + uint32 边数 + 2,698,236×(pre,post,weight) + 每神经元
  (region:uint8, group:uint16)。权重按最大绝对值归一到 ±0.15。
- **BrainWorker.ets**（`@kit.ArkTS` Worker）：忠实移植 flybrain sim-worker.js 的
  泄漏积分放电模型（leak 0.95 / 阈值 1.0 / 不应期 3 / 权重缩放 0.15 / 10Hz tick），
  含按群重排（CSR）+ 群门控（只更新活跃群，冷却 20 tick 自动休眠）。
- **ConnectomeDriver.ets**（主线程）：加载连接组 → 初始化 Worker；把 App 状态映射为对
  **真实感觉神经群**的持续刺激（食物气味→OLF_ORN_FOOD，触碰→MECH_BRISTLE+OLF_ORN_DANGER，
  风→MECH_JO，光照→VIS_*，饥饿/疲劳→DRIVE_* 群）；把运动群放电汇成行为累积量
  （步行 VNC_CPG、进食 MN_PROBOSCIS、理毛 MN_HEAD+ABDOMEN、惊吓 MECH_BRISTLE，EMA 平滑）。
- **涌现行为**：FlyBrain 涌现模式开启后，放电累积量按 fly-logic 语义触发行为
  （机械感受群→惊吓、舐吸运动群→觅食意图、头/腹运动群→理毛、步行 CPG 调制步速），
  与原有内驱力逻辑并联（混合模式，弥补运动群稀疏导致的静默）。
- **接入踩坑**（重要）：
  1. Worker 必须在 `entry/build-profile.json5` 的 `buildOption.sourceOption.workers` 注册；
  2. ThreadWorker 路径格式为 `entry/ets/worker/BrainWorker.ets`（**不含 src/main**）；
  3. 31MB ArrayBuffer 必须 postMessage 走 transfer（第二参数传转移列表），否则报 10200006。
- **真机验证**：`ready N=139255 edges=2698236 groups=61`；LIF 稳定运行于 10Hz
  （单 tick 61~78ms，预算 100ms），每 tick 约 30+ 神经元放电，6~11 个功能群活跃
  （门控与信号传播正常）；UI 实时显示放电率（⚡N/s）。

### 10.4 遗留与后续优化

1. 冷启动场景加载 10~20s（引擎初始化），可加进度反馈/预热；
2. Component3D 背景色 clearColor 未见生效（呈灰白），后续可用 environment 资源换天空；
3. 石块造型简陋；果蝇无骨骼动画（M1+ 翅膀/颠簸为代码驱动）；
4. 连接组模式下单 tick 70ms 左右，若活跃群增多可能逼近 100ms 预算，可降为 7Hz 或做分帧；
5. 手势与触控的细微手感、深浅色全量适配待长期打磨；
6. M3 运动群数据稀疏（多数为 0），涌现行为是"混合驱动"——完全涌现需要等待上游数据完善
   或引入行为判读网络（可作为 M4 研究课题）。

---

## 11. UI 重构记录（2026-09-15，统一玻璃质感设计语言）

三项需求全部落地并真机截图验证：

### 11.1 沉浸式安全区

ScenePage 根 Stack 应用 `.ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM],
[LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])`（API 23+ 新属性），3D 场景
延伸到状态栏/导航条后面；顶栏/底栏用固定 padding 避让（top 54 / bottom 28）。

### 11.2 分类控制面板（参考 LiquidGlassPage 设计语言）

- **收起态**：底部（窄屏）/右栏（宽屏）一条玻璃胶囊——`控制 | 行为 | 交互 | 仿真`；
- **展开态**：点分类打开玻璃卡片面板（同槽位切换，遮罩点空白收起，animateTo 过渡）：
  - 行为：速度滑杆 + 漫步/理毛/起飞/降落；
  - 交互：工具选择（触碰/投喂/聚光）+ 吹风 + 光照三档；
  - 仿真：连接组开关 + 运行统计（放电率/活跃脑区/单步耗时）。
- **大屏适配**：新增 `common/BreakpointService.ets`（宽≥600vp 且非纵向高窗口 → 右栏布局，
  键 `fy_is_wide`），EntryAbility 首刷 + `windowSizeChange` 监听（getMainWindowSync + px2vp）。
- 玻璃卡片样式：半透明深底 `#59202026`/`#6614141A` + 0.5 `#33FFFFFF` 描边 + 16 圆角。

### 11.3 大脑状态小窗

顶栏右上角新增 🧠 徽章（仿真运行时带绿色指示点），点击弹出左上角小窗：
仿真状态、放电速率 ⚡/s、活跃脑区 a/61、单步耗时、脑规模（13.9万神经元·270万突触）、
「查看 3D 大脑 →」直达连接组可视化页；✕ 或点空白关闭。相应地
ConnectomeDrive 增补了 avgTickMs/activeGroups/totalGroups/neurons/edges 统计字段。

### 11.4 踩坑

- Stack 全屏覆盖层（顶栏/底栏/右栏）必须显式 `.height('100%')`，否则内容被 Stack
  默认居中对齐（表现为顶栏跑到屏幕中央）；
- `@Builder` 内组件树中不允许写 `const` 语句，动态值用方法内联调用（如
  `this.driver.getDrive().spikesPerSec`）；
- 模块级常量对象字面量（如 BorderOptions）必须显式类型标注。

---

## 12. 官方 HDS 导航与标题栏（2026-09-15 二次修订）

### 12.1 背景

11 章中「面板遮罩挡住 3D 手势」与「标题栏压住状态栏」两个问题需要一并根治，
且要求标题栏改用**官方 HDS 组件**（而非自绘）。

### 12.2 遮罩问题（拖拽冲突）

原设计在面板展开时铺一层全屏遮罩用于"点空白收起面板"，该遮罩吞掉了 3D 区域的手势，
导致必须先点屏幕关闭面板才能拖视角。**该交互在本应用不适用，已彻底移除遮罩**：
面板仅通过分类按钮开合（点分类展开/再点同分类收起），3D 视角拖拽在任何时刻都可用。
真机验证：行为面板保持展开状态下纵向滑动，相机俯仰正常变化。

### 12.3 标题栏改用官方 HDS（关键修正）

**迁移内容**：路由根容器 `Navigation` → `HdsNavigation`；子页面 `NavDestination` →
`HdsNavDestination`（含设置页、关于页、大脑页）。

**踩坑与关键结论**（此前编译失败的真实原因）：

1. `HdsNavDestination` **必须配套 `HdsNavigation` 使用**（只读子页面会误判为可独立使用）；
2. `systemMaterialEffect` **不在 `HdsNavigationTitleBarOptions` 顶层**，必须嵌在
   `style` 里 —— 即 `{ content: {...}, style: { systemMaterialEffect: {...} } }`。
   编译器给出的 "Object literal may only specify known properties, and
   'systemMaterialEffect' does not exist in type 'HdsNavigationTitleBarOptions'" 是决定性线索
   （网上流传的扁平结构写法从未被编译验证过，不可照抄）；
3. 页面级 `ignoreLayoutSafeArea` 会让 Hds 标题栏也顶到状态栏下面，需在 titleBar 上
   设 `avoidLayoutSafeArea: true` —— 标题栏**内容**避让安全区，材质背景仍沉浸延伸；
4. 3D 全屏页（大脑页）的覆盖层需自行加 `topAvoid + 52` 顶部内边距，避免说明文字
   压到标题栏区域（`fy_top_avoid` 由 EntryAbility 写入）。

**最终标题栏结构**（三页统一）：

```typescript
.titleBar({
  content: { title: { mainTitle: '设置' } },
  avoidLayoutSafeArea: true,
  style: {
    systemMaterialEffect: {
      materialType: hdsMaterial.MaterialType.IMMERSIVE,
      materialLevel: hdsMaterial.MaterialLevel.EXQUISITE
    }
  }
})
```

真机验证结果：设置页/大脑页标题栏位于状态栏下方、返回按钮正常显示、顶栏具玻璃材质光感；
场景页顶栏用 `fy_top_avoid` 动态避让（`top: this.topAvoid + 6`），底栏用
`fy_bottom_avoid` 避让导航条。自绘 `GlassTitleBar.ets` 已删除。

**布局自适应**：`BreakpointService` 仍负责宽窄屏分流——≥600vp 且非纵向高窗口时，
控制区从底部移到**右侧竖排栏**（CategoryRail：控制/行为/交互/仿真 纵向堆叠）；
竖屏（含平板竖屏）保持底部胶囊栏。

---

## 13. 交互与显示修复（2026-09-15 第三轮）

### 13.1 缩放能力增强 + 缩放滑杆 + 视角追踪

| 项 | 实现 |
|---|---|
| 缩放范围 | `SceneManager` 的 `minRadius 2.2 → 1.0`、`maxRadius 11.0 → 22.0`（缩放倍率提升约 2.2× / 2×） |
| 缩放滑杆 | 新增「视角」分类面板：缩放滑杆（min~max 全量程）+ 重置视角 / 最远 / 最近 三个快捷按钮 |
| 视角追踪 | 同面板加 `Toggle` 开关（默认关闭）；开启后相机锁定果蝇**第一视角**（相机贴果蝇头部、朝其前进方向看），由 `setFlyPose()` 每帧写入位姿驱动 |

**踩坑**：`minRadius` 初值设成 0.55 时画面变成纯色——相机钻进了模型内部
（果蝇体长 0.7 单位）。最终取 1.0（≈模型最大尺寸 1.4 倍），既贴近又不穿模。

**注视点钳制**：原 `followFly` 把注视点钳在 ±1.6，果蝇跑到场地边缘时相机就对不上它；
改为钳到 ±4.0（与活动半径同量级）并加快平滑系数（0.08→0.12）。

### 13.2 关于页内容避让标题栏

现象：关于页正文第一行被 HDS 标题栏压住。修法与 3D 页一致——用 EntryAbility 写入
AppStorage 的 `fy_top_avoid` 给内容加顶部内边距（`top: this.topAvoid + 52`）。

### 13.3 仿真面板数据不刷新（关键 bug）

**现象**：仿真面板「活跃脑区 0/61」「单步耗时 0 ms」固定不变，而同屏状态行的
`⚡N/s` 却会变。

**根因**（两个叠加）：
1. `@Builder` **参数传值不建立状态依赖**——`this.StatRow('活跃脑区', \`${this.connActive} / ${this.connTotal}\`)`
   把值在传参时固化成快照，后续 `@State` 变化不会让 Builder 内部的 `Text(value)` 重建；
2. `driver` 是普通成员（非 `@State`），其字段变化对 UI 不可观测。

**修复**：
- 新增 `@Builder SimStats()`，内部**直接引用** `@State`（`this.connSpikes` 等），不再经参数传值；
- 帧循环里把 driver 的统计字段搬进 `@State`（`connSpikes/connActive/connTotal/connTickMs/connReady`）；
- 放电率加 **EMA 平滑**（单 tick 放电数在 0~90 间剧烈波动，直接 ×10 会显示成 0 或几百）；
- 用 `connReady` 区分「未就绪」与「就绪但值为 0」，避免首帧显示 0 像 bug。

**验证**：面板数值实测从 `8 / 61 · 69 ms` 变化到 `10 / 61 · 70 ms`（DATA-CHANGED: true）。

### 13.4 新增易错总结文档

本轮及此前各轮踩到的坑已系统整理为 **`docs/ArkTS-ArkUI易错总结.md`**（29 条，
按「编译错误 / 运行时行为错误 / 官方 HDS 组件坑 / 3D 渲染坑 / 工程经验」五类，
每条含现象 → 原因 → 正确写法）。
`AGENTS.md` 的编码前置要求已改为指向该文档，形成"踩坑 → 补录 → 不再重犯"的闭环。

### 13.5 追踪视角双模式 + 面板收起按钮（第四轮）

**1. 视角追踪支持第一人称 / 第三人称切换**

`SceneManager` 增加 `followPerson`（0 第一人称 / 1 第三人称），追踪开启后在「视角」面板
出现两个切换按钮：

| 模式 | 相机位置 | 用途 |
|---|---|---|
| 第一人称 | 果蝇**头部**（前方 0.30、高 0.36），朝前进方向看 | 体验果蝇视角 |
| 第三人称 | 果蝇**后上方**（距离 `0.85+radius×0.28`、高 `0.42+radius×0.10`），注视果蝇本体 | 观察果蝇动作（距离随缩放滑杆变化） |

**踩坑**：第一人称初版把相机放在身体后方 0.36 处"从后往前看"，结果果蝇躯干（体长 0.7）
把画面完全填满。正确做法是**把相机放到头部位置朝前看**——身体在相机背后，自然不会挡住视野。

**2. 面板收起按钮改为文字并加大点击区**

原来的折叠指示是一个 16fp 的 chevron 图标，点击目标过小。改为文字按钮：
`Text('收起'/'展开')` + `padding(18/9)` + 圆角胶囊底 + 行高 52，视觉与触控都清晰。

**真机验证**：面板收起按钮点击后面板收拢回胶囊条；追踪开关 → 人称按钮出现 →
第一人称（看到前方场景）/ 第三人称（看到果蝇全身）切换均正常。
