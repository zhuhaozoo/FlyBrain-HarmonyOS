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

2024 年，FlyWire 联盟（普林斯顿大学等）在《Nature》发表了**首张完整的成年果蝇（黑腹果蝇）全脑连接组**：**139,255 个神经元、约 5,000 万个化学突触**的完整接线图（FAFB 数据集，FAFB v783），是神经科学里程碑成果。随后开源社区出现了把它跑在浏览器里的实时仿真项目 **FlyBrain**（flybrain.app）：13.9 万神经元用泄漏积分放电（LIF）模型在 Web Worker 中实时仿真，**行为状态由运动群的累积放电量判读**（放置食物它会觅食，触碰它会惊跳，改变光照它会趋光），内驱力作为兜底。该项目在社交网络上走红，被认为是最直观体验"完整大脑数字化"的方式。

> **必须说清楚的边界**（2026-09-16 核对上游数据后补充）：FlyWire 这套数据是**脑**，
> 运动神经元极少（motor 区合计 76 个，腿/翅/下行飞行群为 0 —— 它们位于腹神经索 VNC，不在该数据集内）。
> 因此"运动群累积放电判读"在本项目里只能覆盖四路调制，行为骨架仍来自内驱力与状态机，
> 即**混合驱动**（见第 10.4 节第 6 条）。上游同理，其判读的也是脑内运动/上升神经元，而非腿部运动神经元。

这些项目都是网页（WebGL）形态，普通手机用户访问门槛高。本项目要做的，就是把这一体验**复刻到鸿蒙上，做成原生 App**，让更多人直观体会"一个完整大脑被完整画出来并跑起来"是什么感觉。

### 1.2 目标拆解

| 阶段 | 内容 | 状态 |
|---|---|---|
| **M0（本期 Demo）** | 预设 3D 场景（地面/光照/相机）+ 简单果蝇 glTF 模型 + 行为状态机（漫步/理毛/起飞/飞行/休息）+ 基础交互（视角拖拽缩放、行为切换、速度调节） | **本文档设计对象** |
| M1 | 交互丰富化：投喂、触碰、光照变化（趋光），内驱力（饥饿/恐惧/疲劳）系统，对齐原版 SPEC 的交互表 | 规划 |
| M2 | 真实连接组可视化：加载 FlyWire 派生数据（13.9 万神经元点云，分区着色），3D 大脑可视化页 | ✅（见第 10.2 节） |
| M3 | 端侧神经仿真：将 flybrain 的 `sim-worker.js` LIF 仿真移植为 ArkTS Worker，行为受连接组放电**调制**（混合驱动，非纯涌现） | ✅（见第 10.3 节） |
| M4 | 场景丰富化（河流/树木/日月星辰昼夜循环）+ 交互效果深化（投喂/聚光/吹风反馈）+ 玩法（果蝇生命值、捕食者青蛙） | ✅ 已实现：见《[场景与玩法设计-M4.md](./场景与玩法设计-M4.md)》§8 实施记录 |
| M5 | 生态与多智能体（多果蝇 / 信息素 / 青蛙饱食度 / BrainMount 统一大脑 / 场景切换） | 🚧 P1 多果蝇地基代码完成待真机验证：见《[生态体系与多智能体设计-M5.md](./生态体系与多智能体设计-M5.md)》与本文件第 14 章 |

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

### 10.3 M3 —— 端侧 LIF 神经仿真（实时放电 + 行为调制）✅

- **数据**：flybrain `connectome.bin.gz`（解压 31MB）→ `rawfile/connectome.bin`。
  二进制格式（小端）：uint32 神经元数 + uint32 边数 + 2,698,236×(pre,post,weight) + 每神经元
  (region:uint8, group:uint16)。权重按最大绝对值归一到 ±0.15。
  - **口径（2026-09-16 核对上游后修正）**：FlyWire 论文是 **139,255 神经元 / 约 5×10⁷ 个化学突触**；
    2,698,236 是上游 `scripts/build_connectome.py` 的 `aggregate_edges()` 把突触**按 (pre, post) 聚合**
    后的**边数**（并按 `nt_type` 赋正负号、以突触数当权重）。所以准确说法是"2,698,236 条神经元间连接"。
  - **可溯源性已核对**：`tools/data/` 下 4 个文件（`connectome.bin.gz` / `neuron_meta.json` /
    `coordinates.csv.gz` / `classification.csv.gz`）与 snedea/flybrain 仓库中的同名文件**逐字节一致**
    （`git hash-object` 与 GitHub Contents API 的 blob sha 相同；`connectome.bin.gz` 亦可直接比对
    SHA256 `fbf8d440…b1cc49`），包内 `connectome.bin`（32,796,605 字节）= 该 gz 的解压结果。
- **BrainWorker.ets**（`@kit.ArkTS` Worker）：忠实移植 flybrain sim-worker.js 的
  泄漏积分放电模型（leak 0.95 / 阈值 1.0 / 不应期 3 / 权重缩放 0.15 / 10Hz tick），
  含按群重排（CSR）+ 群门控（只更新活跃群，冷却 20 tick 自动休眠）。
- **ConnectomeDriver.ets**（主线程）：加载连接组 → 初始化 Worker；把 App 状态映射为对
  **真实感觉神经群**的持续刺激（食物气味→OLF_ORN_FOOD，触碰→MECH_BRISTLE+OLF_ORN_DANGER，
  风→MECH_JO，光照→VIS_*，饥饿/疲劳→DRIVE_* 群）；把运动群放电汇成行为累积量
  （步行 VNC_CPG、进食 MN_PROBOSCIS、理毛 MN_HEAD+ABDOMEN、惊吓 MECH_BRISTLE，EMA 平滑）。
- **调制的四路量**：FlyBrain 连接组模式开启后，放电累积量按 fly-logic 语义参与行为决策
  （机械感受群→惊吓、舐吸运动群→觅食意图、头/腹运动群→理毛、步行 CPG 调制步速），
  与内驱力逻辑并联（**混合驱动**，弥补运动群稀疏导致的静默）。
- **接入踩坑**（重要）：
  1. Worker 必须在 `entry/build-profile.json5` 的 `buildOption.sourceOption.workers` 注册；
  2. ThreadWorker 路径格式为 `entry/ets/worker/BrainWorker.ets`（**不含 src/main**）；
  3. 31MB ArrayBuffer 必须 postMessage 走 transfer（第二参数传转移列表），否则报 10200006。
- **真机验证**：`ready N=139255 edges=2698236 groups=61`；LIF 稳定运行于 10Hz
  （单 tick 61~78ms，预算 100ms），每 tick 约 30+ 神经元放电，6~11 个功能群活跃
  （门控与信号传播正常）；UI 实时显示放电率（⚡N/s）。
  - `groups=61` 是**运行时段数**：元数据共 63 群，其中 id 61/62（未细分驱动 / 未细分运动）
    神经元数为 0，群数按"最大群号 + 1"计算；63 群中真正有神经元的是 32 群。

### 10.4 遗留与后续优化

1. 冷启动场景加载 10~20s（引擎初始化），可加进度反馈/预热；
2. Component3D 背景色 clearColor 未见生效（呈灰白），后续可用 environment 资源换天空；
3. ~~石块造型简陋；果蝇无骨骼动画（M1+ 翅膀/颠簸为代码驱动）~~
   —— 已于 M4 解决：石块/树木/草丛导入 CC0 素材、果蝇翅膀改为可收展；
   仍未做：青蛙碰撞（会跳穿石块/树干）、骨骼动画（姿态仍为代码驱动）。
4. 连接组模式下单 tick 70ms 左右，若活跃群增多可能逼近 100ms 预算，可降为 7Hz 或做分帧；
5. 手势与触控的细微手感、深浅色全量适配待长期打磨；
6. M3 运动群数据稀疏（motor 区合计仅 76 个神经元：口器 24 / 头 40 / 腹 8 / 步态节律 4；腿、翅、
   下行飞行群均为 0），所以行为是"**混合驱动**"而非纯涌现。
   **修正（2026-09-16）**：这不是"等上游数据完善"能解决的 —— 腿/翅运动神经元位于**腹神经索（VNC）**，
   不在 FlyWire 脑连接组（FAFB）里，需要引入 VNC 数据集（如 MANC / FANC）接上下行神经元，
   或改换更接近生物物理的神经元模型，才谈得上让"走路/飞行"由连接组产生。

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

---

## 14. M5 实施记录：P1 多果蝇地基（2026-09-15，待真机验证）

按《生态体系与多智能体设计-M5.md》分阶段实施。§12 决策已拍板：默认 3 只、
投喂青蛙=隐含机制、场景切换入口=顶栏按钮、信息素场=纯后台数值。

### 14.1 P1 改动总览（多果蝇地基）

| 层 | 文件 | 改动 |
|---|---|---|
| 模型 | tools/gen_world_glb.mjs | 果蝇烘焙 **6 份**（fly_0..fly_5，全部节点名带序号后缀）；**网格跨果蝇共享**（数据只存一份），world.glb 653KB（仅 +6KB）、总面数几乎不变（22.3k） |
| 行为 | behavior/FoodWorld.ets 新增 | 共享食物世界：用户投喂+果实统一管理、`claimedBy` 争食认领（先到先得）、`update()` 每帧推进一次 |
| 行为 | behavior/WorldState.ets 新增 | 共享世界状态：光/风/光斑；`gustId` 让所有果蝇对同一阵风只反应一次 |
| 行为 | behavior/FlyAgents.ets 新增 | 多体协调器：全量创建 6 个 FlyBrain、`setActiveCount(1~6)`、每帧"世界→逐个体→个体互斥（间距<0.25 推开）" |
| 行为 | behavior/FlyBrain.ets | 构造改为 `(cfg, agentIdx, foods, world)` 注入；个体性格 `k∈[0.9,1.1]` + `turnBias`（种子驱动，参数扰动按设计稿 §2.4）；Seek/Feed 全程锁定认领食物；移除私有 foods/环境字段 |
| 行为 | behavior/FlyConfig.ets | +`agentCount=3`、`separateDist=0.25` |
| 场景 | scene/SceneManager.ets | `flyNode/wingLeft/wingRight` 三字段 → `flySets: FlyNodeSet[]`（按 `fly_${i}` 等后缀查找）；extraNodes 不再登记 head_pivot |
| 页面 | pages/ScenePage.ets | brains/renderers 数组化；帧循环改为"青蛙锁定最近活蝇→agents.update→逐体渲染"；设置数量轮询生效；状态行改群体摘要（👥N只 饿均/累均/⚡）；投喂/触碰/吹风/光照改走共享世界；"+"特效跟随吃完的那只 |
| 页面 | pages/SettingsPage.ets | 新增「同屏果蝇 1/3/6」选择（持久化 key `agentCount`） |

### 14.2 运行时契约变更（有意的契约演进）

- 果蝇节点名从 `fly`/`wing_left`/`head_pivot` 等 → `fly_0..fly_5`/`wing_left_0`/`head_pivot_0` 等；
  AGENTS.md 的契约说明已同步；REQUIRED 清单覆盖 0 号与 5 号两端。
- 连接组在 P1 仍是"同一份运动群放电喂给所有果蝇"（共享大脑语义），
  个体差异来自处境+性格；P4 换成逐体 BrainMount 接线。

### 14.3 真机验收点（P1）

1. 3 只果蝇同屏、出生圈错开、互不穿模（靠近会互相推开）；
2. 投喂后先到的果蝇开始吃，后来的转向别的食物（争食可观察）；
3. 设置页切 1/3/6 只即时生效（返回场景页即可见）；
4. 帧率与连接组 tick 不劣化（tick ≤78ms 红线）；
5. 青蛙攻击的是离它最近的那只；吹风时三只同时趴伏/惊吓（共享世界）。

### 14.4 P1.1 真机反馈修复（2026-09-16）

用户真机试玩后反馈三项，均已修复并装机验证：

| 问题 | 根因 | 修复 |
|---|---|---|
| 树在地盘外、落果够不到、果蝇绕树转圈 | 树距 5.0~5.6 + 冠内偏移，落果最远 ~6.1，而步行软边界 4.6、地盘仅 5.5 | 地盘 5.5→7.4、活动半径 4.6→6.0；落点双保险钳制（生成器 + FoodWorld.setFruitPosition 运行时兜底，河流弧上收到内岸 4.7） |
| 青蛙从未捕食成功 | 命中公式 `dist ≤ max(0.35, 舌长×0.25)`：舌长 2.0 时容差仅 0.5，舌头视觉拍到身上也必 miss | 改为 `dist ≤ 舌头锁定距离 + 命中容差 0.35`（果蝇不逃就必中，逃出才 miss，符合"吹风救援"设计） |
| 果蝇共用一个大脑 | P1 为省资源共享同一份运动群放电 | **每只果蝇一个 BrainWorker 实例**（各自完整 13.9 万神经元仿真、各自 31MB 连接组、感觉刺激按各自处境注入）；上限 3 个独立大脑（内存 ~93MB），同屏超出 3 只的个体退化为纯阈值驱动 |

附带修复：驱动器同步的并发竞态——toggleConnectome 与帧循环数量轮询同时调用 syncDriverCount
会起出超量 worker（实测 4 个）→ busy/pending 互斥 + 循环内重算 want 收敛；
个体互斥间距 0.25 → 0.5（须 ≥ 体长一半，否则聚光时叠罗汉，截图实锤）。

装机验证：3 个 worker 各自线程 ready（日志三连）、tick 64~78ms、
大脑小窗放电速率 1200/秒为三脑合计、地盘/河流/树木比例正常。

### 14.5 P1.2 第二轮真机反馈修复（2026-09-16）

| 问题 | 根因 | 修复 |
|---|---|---|
| 青蛙黑色瞳仁脱离本体飞出去 | captureBase 直接保存引擎 getter 返回的 **Vec3/Quaternion 对象引用**；引擎复用内部对象后，"基准位置"变成别的节点的坐标，瞳孔被写到满场乱飞 | 逐分量快照拷贝基准值；写回节点时也构造新对象。教训：**ArkGraphics 3D 的 getter 返回值只能当场读数，不能当引用保存**（与易错总结第 32/33 条同类的"引用/快照"陷阱，后续补录） |
| 仍然未观察到捕食成功、青蛙不移动 | 命中公式已修但青蛙是定点伏击，猎物路过窗口太短；且用户期望青蛙主动追猎 | 青蛙升级为"会跳的伏击手"：Idle 且冷却结束时，猎物进入 4.2 追击半径即向其跳跃接近（单跳 ≤0.9、抛物线 0.38s、落地休息 0.5~1.3s），距离 ≤1.0 就地蹲守蓄力；逃跑的果蝇仍甩得开，救援玩法保留 |
| 果蝇像蜜蜂、体型偏大 | 腹部粗壮带环纹（蜜蜂感主要来源）+ 体长 0.7 相对场景过大 | 整体缩到 **0.6 倍**（体长 ~0.42）；腹部额外收窄 0.85；翅膀只缩 0.75 —— 相对更长，还原果蝇"小身大翅"比例。同步缩放运行时尺寸常量：第一/第三人称相机偏移、死亡抬升、触碰/进食/晒太阳/互斥/命中半径、出生圈半径 |

装机情况：构建成功、已无线安装；启动时设备处于锁屏（10106102），等用户解锁后验证。
验证点：青蛙瞳孔贴在眼睛上；青蛙会跳向果蝇并成功捕食（舌头拍到即命中 -50 HP）；
果蝇体型明显变小、腹部不再臃肿；第一/第三人称追踪视角仍正确贴合小体型果蝇。

### 14.6 大脑状态小窗高度抖动修复（2026-09-16，用户反馈）

**现象**：小窗高度随放电数据频繁变化，底部「查看 3D 大脑」按钮上下跳动、点不中。

**根因**："活跃脑区明细"用 ForEach 渲染 0~8 行不定内容 + 汇总行条件显隐，
每 300ms 统计刷新都可能改变行数 → 面板高度抖动。

**修复（固定布局、只变数值）**：明细行数固定 5 行（不足补占位"—"、超出的截断），
每行固定高 16、汇总行常显；ForEach 键改用下标使行复用、文本原地更新；
@State 初值也填占位（避免首刷跳变）。同类原则：**数值面板一律定行数定行高，
只允许文字变化，不允许结构变化**。

### 14.7 P1.3 第三轮反馈修复（2026-09-16）

1. **大脑小窗不随控制面板关闭**：toggleCat 里的 `brainPopup = false` 移除——切行为/交互/视角/仿真面板时小窗保持打开；
2. **脑区明细 5 行 → 8 行**：显示放电最强的前 8 群（GROUP_DETAIL_LINES=8，占位补齐不变）；
3. **捕食改为"命中即捕获"**（设计稿 §4.2 叼走的简化落地）：此前命中只扣 50 HP，果蝇进食回血后几乎永生，数量不减。现在舌头命中 = 果蝇被拖到青蛙嘴边（+0.28 前方）致死，尸体隐藏 5 秒后原点重生——数量肉眼可见减一；死亡提示对任意个体生效（原只显示 0 号）；关于页死亡统计改为全群累计（FlyAgents.totalDeaths）。

### 14.8 迷你 3D 大脑实时演示（2026-09-16，用户需求）

大脑状态小窗内新增实时 3D 大脑演示：活跃脑区在 3D 点云上高亮。

- **资源**：`tools/gen_brain_glb.mjs` 扩展产出 `brain_mini.glb`（2.7MB）——真实 FlyWire
  神经元坐标按 1/4 抽稀（约 3.5 万），每个脑区两套材质：dim（暗灰微光）+ hi（脑区本色高亮），
  dim/hi 节点共享同一份 mesh；节点名 `mini_dim_0..4` / `mini_hi_0..4`。
- **高亮机制**：每 300ms 把 drivers[0] 的逐群放电率按 `brainRegionOf()`（群号→5 大脑区映射，
  视觉归 optic、驱动借位 endocrine，隐喻标注）汇总，合计 >2 次/秒 的脑区亮 hi、其余显示 dim
  —— 只写 Node.visible，规避运行时改材质的口径风险（与天空穹顶同款模式）。
- **渲染**：小窗内嵌第二个 Component3D（懒加载：首次点开 🧠 才 Scene.load），固定机位 +
  慢速自旋（主帧循环里旋转 root），点击小窗 3D 区域跳转全屏大脑页。
- **同页双 Component3D**（世界 + 迷你脑）为首次使用，真机验证点：二者同时渲染是否正常、
  迷你脑加载是否拖慢主场景。

### 14.9 迷你大脑两处修复（2026-09-16，用户反馈）

1. **明细行不刷新**：ForEach 键改成纯下标后，ArkUI 对相同键的行不重渲染，8 行文本冻结在
   占位符 —— 键改回"下标+内容"，行高固定所以依旧不抖（易错总结第 8 条同源：ArkUI 的缓存/复用）；
2. **高亮从不变化**：绝对阈值（>2 次/秒）下视觉/感觉区常亮。改为相对主导判定：
   脑区合计 ≥ 最大脑区合计 ×25% 且 >2 才亮；说明行实时显示"主导脑区：X / 全脑静默"。
   另加 mini 节点命中数日志（mini brain nodes found: N/10）便于诊断。

---

## 15. 2026-09-16 修复与更新：停栖收翅 / 障碍碰撞 / 飞行行为 / 关于页链接

本章记录 2026-09-16 的四项改动：**① 停栖收翅、② 静态障碍碰撞、③ 自发短飞 + 被咬后挣脱起飞、
④ 关于页新增「其他作品友情链接」**（其中 ①② 来自用户真机反馈）。

### 15.1 停栖收翅（渲染层）

- **原因**：模型里翅根轴心 `wing_left_i / wing_right_i` 的**基准姿态就是"飞行展开"**，
  而 `FlyRenderer` 只在绕 Z 轴（上下拍动）上加振幅 —— 于是任何状态下看起来都是张开的翅膀。
- **修法**：把"收/展"作为独立的一个自由度（绕 Y 后掠），与拍动（绕 Z）分离：

  ```
  停栖（漫步/理毛/休息/进食/趴伏/饮水…）：左翼绕 Y −83°、右翼 +83°，双翅后掠贴在腹背两侧
  起飞 / 飞行 / 惊吓：展开（fold → 0）并快速拍动（与 M4 行为一致）
  降落：随降落过程自动收拢；死亡：摊开贴地（原有表现保留）
  ```

  实现要点：`FlyRenderer.fold`（0=展开 / 1=收拢）按 `wingFoldRate`（6/s，约 0.17s 走完）平滑逼近目标，
  四元数按 `Ry(±foldYaw) · Rz(±拍动角)` 组合 —— 先拍动再收展，收翅后的拍动自然变成"贴背轻颤"。
  dt 由行为层累计时间的差值推算（帧率无关），切后台大步长时按一帧处理。
- **参数**（`FlyConfig`）：`wingFoldYaw = 1.45`（约 83°）、`wingFoldRate = 6.0`。
- 数值核对：展开时翼尖在 x = ±0.324、收翅后翼尖落到 (±0.087, −0.286)（贴住腹背两侧），
  翼根弦与胸部相交的那一小段位于胸内（胸顶 0.248 > 翅面 0.243），不会露出穿模。

### 15.2 静态障碍碰撞（"步行不可穿石/穿树"）

- **原因**：静态场景几何只送入渲染，**没有任何碰撞数据通道**，行为层对石块一无所知。
- **修法**：生成脚本在静态几何旁多产出一个**无网格、无子节点的标记节点** `blocker_i`：
  `translation` = 圆心、`scale.x` = 阻挡半径。运行时按名字读入，不做任何几何推算：

  ```
  gen_world_glb.mjs  →  blocker_0..26（translation=圆心, scale.x=半径）
  SceneManager.init  →  blockerNodes[]（按序号收集，不硬编码个数）
  ScenePage          →  Obstacles.add(x, z, r)（共享实例，与 FoodWorld / WorldState 同寿命）
  FlyBrain.applyBoundary → 贴地时 Obstacles.resolve(...)：径向推出 + 沿切向绕行（rad/s × dt）
  ```

- **阻挡圆覆盖范围（27 个，统一连续编号）**：

  | 编号 | 对象 | 半径取法 |
  |---|---|---|
  | 0–7 | 场内石块 | 岩石变体归一化后的水平外接半径 × 水平缩放最大值（略偏保守） |
  | 8–23 | 河岸卵石（内外两圈各 8） | 同上（卵石很小，多数半径 0.11~0.66） |
  | 24–26 | 树干 ×3 | **只取贴地那一段树干**（最低 12% 高度内顶点的最大半径，实测 0.06），圆心按该段顶点的水平中心补偿 |

  树干这条最关键：**不能用树冠半径**（果蝇本该能从树冠下走过），也**不能把 blocker 挂在 `tree_i / trunk_i` 下**
  ——它是顶层节点，否则碰撞圆会跟着树的摇摆一起动。另外 bark 网格的包围盒中心 ≠ 树干轴心
  （枝条不对称），生成脚本会从烘焙后的顶点里现算贴地段中心并补偿（本树实测偏移 0.07）。
  生成脚本末尾新增断言：`blockerCount` 必须等于 8+16+3=27，跳号/漏加会直接中止。

- **行为**：只作用于**贴地**个体（`!isAirborne() && y < 0.3`）——飞行巡航高度 1.15 直接从石块/卵石上方越过；
  推出方向取径向、转向取"与当前朝向夹角更小的那一侧切向"，表现是**沿石壁滑走**而不是原地顶住。
- **参数**（`FlyConfig`）：`bodyRadius = 0.10`（体型 0.6 后体宽约 0.08）、`obstacleTurn = 2.2`（rad/s）。
- **投喂落点同样避让**：`FoodWorld.placeFood` 先经 `Obstacles.pushOut(x, z, bodyRadius)` 再落点 ——
  否则食物会被埋进石头里，果蝇够不到、只会顶着石壁干等 `seekTimeout`（14s）。
  （这是碰撞生效后才出现的连带问题：碰撞之前果蝇能穿过石头吃到它。）
- **新增/改动文件**：`behavior/Obstacles.ets`（新）、`FlyBrain.ets`、`FlyAgents.ets`、`FoodWorld.ets`、
  `scene/SceneManager.ets`、`scene/FlyRenderer.ets`、`behavior/FlyConfig.ets`、`pages/ScenePage.ets`、
  `tools/gen_world_glb.mjs`（+ `REQUIRED` 增补 `blocker_0/7/23/26` + 数量断言）、`world.glb` 重新生成
  （22342 三角面不变，节点 305 → 332，体积 653.7 → 655.9 KB）。
- **真机自查**：hilog 里 `[FlyBrain] nodes found: … blockers=27` 即标记节点全部建好；
  若为 `0` 或明显偏小，说明该 glb 未重新生成（或引擎未建无网格节点），此时果蝇仍会穿模。

### 15.3 行为层：自发短飞 + 被咬后"挣脱起飞"（2026-09-16 追加）

**问题**（用户观察）：果蝇几乎只在地面漫步，从不主动飞。

**排查结论（重要，先澄清归因）**：这**不是连接组涌现出来的行为**，而是手写状态机的入口缺失 ——
全工程里 `Takeoff` 只有两个入口：① `checkUrgent()` 里 `fear ≥ flyFear(0.8)`（恐惧需在衰减窗口内叠加：
触碰 +0.5、强风 +0.35，单次刺激不够）；② UI「起飞」按钮（且只作用于 0 号主果蝇）。
漫步分支没有任何"随机起飞"判定；`Startle` 逃窜结束直接回 Wander；
而连接组只调制四个通道（`connWalk` 步速 / `connStartle` 惊吓 / `connGroom` 理毛 / `connFeed` 觅食意图），
**没有任何群映射到起飞/飞行**。所以"神经元自主决定要飞"的说法目前不成立。

**改法 1：自发短飞**（`FlyBrain`，参数全在 `FlyConfig`）：

```
enterWander() 时把 flyTimer 重置为 randRange(flyCheckMin=25, flyCheckMax=45)
flyTimer 在 updateDrives 里持续倒计时（休息/理毛期间照走）
updateWander 里 flyTimer ≤ 0 → 重新随机 25~45s，并掷一次骰子：
    fatigue ≤ flyMaxFatigue(0.6) && fear ≤ flyMaxFear(0.3) && rand < flyChance(0.35)
    → enterState(Takeoff)，随后走既有 Takeoff → Fly(10~16s) → Land → Wander
```

即"闲逛够久（平均每 35s 掷一次、35% 命中）且不累不惊，就自己起飞巡游一段"，
约合每只果蝇 1~2 分钟飞一次。回到 Wander 即重置计时，所以不会刚落地又起飞。

**改法 2：被咬后挣脱起飞**（复活 M5P1.3 变成死代码的 `forceTakeoff`）：

```
hitByFrog()：拖到青蛙嘴边 → damage(frogHitDamage) →
    HP 归零 → 在嘴边毙命（数量可见地减一，保持 M5P1.3 的"捕食可见"）
    仍活着 → fear +0.6、刺激源记为青蛙、forceTakeoff = true、enterStartle()
             → 僵 0.3s → 背向青蛙逃窜 1.4s → 起飞（原 updateStartle 的收尾分支）
```

⚠️ **一处需要你拍板的行为回退**：为了让"挣脱起飞"真的能发生，`frogHitDamage` 从
"一咬必杀（=hpMax）"改为 **60** —— 满血（100）首咬剩 40 HP 逃脱，第二咬（40s 冷却后）必死。
若你想恢复 M5P1.3 的"一咬必死"，把该值改回 **100** 即可（代码无需改动，两个分支都在）。

**改动文件**：`behavior/FlyBrain.ets`（flyTimer / 自发短飞判定 / hitByFrog 分支）、`behavior/FlyConfig.ets`。

### 15.4 关于页新增「其他作品友情链接」

- **内容**：条目为 **Mu水印**（液态玻璃水印 · 影像编辑），点击跳华为应用市场详情页。
- **跳转约定**（与另一个项目 MakePro 的「更多作品」面板保持一致，便于以后复用）：

  ```ts
  const MAKEPRO_BUNDLE: string = 'com.zhuhao.makepro';   // MakePro 的 bundleName（AppScope/app.json5）
  const want: Want = { uri: `store://appgallery.huawei.com/app/detail?id=${bundleName}` };
  context.startAbility(want);                            // 隐式 Want 拉起应用市场，无需额外权限
  ```

- **图标**：先在 `@Builder WorkLink` 里留了 48×48 的占位方块（`Text('Mu')` + `fy_divider` 底色），
  加好图标后把该占位 `Row` 换成 `Image($r('app.media.xxx')).width(48).height(48).borderRadius(12)
  .objectFit(ImageFit.Cover)` 即可（不预先引用不存在的资源，否则构建会直接失败）。
- **可扩展**：`WorkLink(name, desc, bundleName)` 是通用条目，以后加别的作品只需再写一行
  `this.WorkLink('名称', '简介', '包名')`。
- 顺带修正了关于页两处口径：「M0-M3 Demo」→「M0-M4」，"行为部分由放电驱动" → "行为受放电调制
  （骨架为内驱力与状态机，混合驱动）"。

### 15.5 大脑小窗明细不刷新 + 3D 视角可平移（2026-09-16 第二批用户反馈）

**① 小窗 8 行「活跃脑区明细」数值冻结（关掉小窗再打开才刷新）**

- **根因**：这 8 行由 `ForEach(this.groupLines, …)` 渲染，**key 只用了下标** `` `g${i}` ``。
  ArkUI 的 ForEach 按 key 复用子节点，key 不变就既不重建也不更新内容 —— 于是文本停在首次渲染的值上。
  这与第 8 条（@Builder 传值快照）**表现相同、根因不同**：`groupLines` 确实是 `@State` 且整体赋新数组、
  组件也确实重建了，但 `ForEach` 自己那层"按 key 跳过"的缓存让这 8 行被跳过。
  （这个坑 14.9 修过一次——当时把 key 改回"下标+内容"；后来做固定行高时又被改回纯下标，于是复发。）
- **修法（本次采用更不易复发的一种）**：**不再用 ForEach**。行数固定 8，直接逐行调用
  `this.GroupLine(0..7)`，而 `@Builder GroupLine(i)` 内部**直接读 `@State`** `this.groupLines[i]`。
  这样既没有 ForEach 缓存可踩，也不会因重建引起高度抖动（保持 14.6 的"定行数定行高"结论）。
- 已补录易错总结第 36 条（含"方案 A：key 并入内容 / 方案 B：固定行数不用 ForEach"两种写法与判据）。

**② 3D 视角只能绕中心转，无法平移**

- 现状：轨道相机只有 yaw/pitch/radius 三个自由度，注视点恒为 `{0, 0.30, 0}`，视野被锁在场心。
- **新增双指拖动平移**（与"单指旋转 / 双指捏合缩放"组成 3D 观察器的通行操作）：

  ```
  SceneManager.panByPixels(dx, dy, viewportH)
     世界单位/像素 s = 2 × radius × tan(fov/2) / viewportH
     位移 = right × (-dx × s) + forwardGround × (dy × s)   // "抓住地面拖动"的手感
     注视点钳制在离场心 ≤ panLimit(9.0) 的圆内，避免一键看到空场
  ```

- 手势冲突处理（都在 `Component3D.parallelGesture` 的 `GestureGroup(Parallel)` 内）：
  1. 单指 Pan 在 `event.fingerList.length > 1` 时**只同步基准值、不旋转**（否则双指平移会顺带把视角转了）；
  2. 双指 Pan 在 `pinchFingers`（捏合进行中）时**不平移**（捏合时两指中点也会移动，避免"缩放顺手把镜头带跑"）；
  3. 追踪模式（相机锁定果蝇）下平移直接忽略 —— `panByPixels` 内部也做了同样的判断。
- 「重置视角」按钮同时调用 `resetTarget()`，把平移过的注视点一并复位；面板提示文案更新为
  「单指拖动转视角 · 双指拖动平移 · 双指捏合缩放 · 滑杆精确缩放」。

**改动文件**：`pages/ScenePage.ets`（GroupLine 明细行、双指平移手势、重置视角、提示文案）、
`scene/SceneManager.ets`（`panByPixels` / `resetTarget` / `panLimit`）。

**真机验证点**：① 小窗 8 行数值应随仿真跳动（不必开关小窗）；② 双指拖动平移、单指旋转、
双指捏合缩放三者互不串扰；③ 追踪开启时双指拖动无效果（预期）。

### 15.6 仍未做

- 青蛙没有碰撞（它会跳过石头与树干；如果要做，可复用同一套 `blocker_i`：跳跃落点用 `Obstacles.pushOut` 推一下即可）。

---

## 16. 模型与场景深度优化（2026-09-16，v6）

### 16.1 背景与范围（用户拍板）

用户反馈三条：**果蝇与真实果蝇不像 / 场景缺乏丰富度 / 3D 可视范围太小**。调研后的结论与取舍：

1. **果蝇只能程序化建模**：全网没有可商用的 CC0 果蝇模型（Sketchfab 上只有 CC-BY 的高面数扫描件，
   40 万~150 万面，且不含运行时需要的命名节点与轴心），因此走"按形态学量化校正"的路线；
2. **可商用的 CC0 配景素材充足**（Kenney Nature Kit / Quaternius），但它们都是**静态道具**，
   只能作装饰（运行时驱动节点仍由脚本自建）；
3. **放大场地牵动 20 多处"生成脚本 ↔ 运行时"的成对数值**（河流半径、活动半径、相机限位、
   天空穹顶半径、青蛙作战半径、风线/涟漪坐标、blocker 断言等），必须成组同改 —— 这条已沉淀为
   易错总结第 37 条。

**本次做**：场地中等放大（地盘 7.4 → 11.0）、果蝇比例与部件校正、CC0 静态配景。
**本次不做**：地形起伏（地面仍是平面圆盘）、步行腿动画、果蝇骨骼/贴图。

### 16.2 尺度放大：成对常量与派生规则（S1）

**派生规则**：脚本里所有会互相影响的径向尺寸收在一处（`ARENA_R` / `ARENA_INNER_R` /
`RIVER_A0/A1` / `RIVER_RIN/ROUT` / `FROG_R/A` / `SUN_ORBIT` / `SKY_RADIUS`），
每个常量都注明"运行时哪个字段必须与它一致"；运行时 `FlyConfig` 的场地几何段也反向注明
"数值出处是脚本哪一段"。两侧同一步改完，不许只改一边。

| 对象 | 原值 | 现值 | 备注 |
|---|---|---|---|
| 地盘 / 内圈 | 7.4 / 4.4 | **11.0 / 6.6** | 圆盘分段 52/40 → 72/56（避免边缘折角） |
| 河流内/外半径 | 4.9 / 6.6 | **7.35 / 9.9** | 角度 20°~108° 不变 |
| 河岸卵石 | 内 8 / 外 8 | **内 6 / 外 10** | 内圈留缺口（果蝇要能走到水边），总数仍 16 |
| 树距（×3） | 5.0 / 5.6 / 5.3 | **7.5 / 8.4 / 7.95** | ≤8.4，留在步行软边界 9.0 内 |
| 树高（×3） | 1.50 / 1.28 / 1.16 | **1.88 / 1.60 / 1.45** | ×1.25 |
| 落果钳制 | 5.75 / 河弧 4.7 | **8.6 / 7.05** | = `riverInner − 0.3` |
| 草丛 | 14 个，r 1.1~4.2 | **28 个，r 1.6~6.3** | 同变体共享网格，三角面不增 |
| 场内石块 | 8 块 | **14 块**（r 2.6~8.9） | 避开河流弧带/树根/青蛙出生点 |
| 青蛙出生点 | 4.55∠64° | **6.8∠64°** | |
| 日月轨道 / 球径 | 9 / 0.55、0.40 | **13.5 / 0.82、0.60** | |
| 星空 | 30 颗 / r=12 | **40 颗 / r=18** | |
| 天空穹顶半径 | 35 | **56** | > 相机最远 34 + 平移上限 13.5 |
| 光斑盘 | 0.55 | **0.82** | 回血圈半径同比 0.35 → 0.52 |
| blocker 总数 | 27（8+16+3） | **33（14+16+3）** | 断言与 REQUIRED 首尾编号同步 |

运行时侧同步：`FlyConfig`（arenaRadius 9.0 / flyArenaRadius 10.8 / riverInner 7.35 / riverOuter 9.9 /
waterNearBand 0.75 / sunOrbitRadius 13.5 / frogX,Z=6.8∠64° / walkSpeed 1.35 / fleeSpeed 3.3 /
flySpeed 3.9）、`SceneManager`（radius 初值 8.0 / maxRadius 34 / panLimit 13.5 / farPlane 160 /
第一人称前视 9.0 / 第三人称后撤距离同比限幅 ≤6.0）、`FrogController`（追击 6.3 / 自身活动 9.6 /
舌长 4.4 / 单跳 1.2 / 蹲守距离 1.4）、`EnvironmentController`（涟漪半径 8.6 = 水带中线 /
风线车道 ±4.5 / 横扫 ±7.8 / 横穿时长 0.9→1.35）、`ScenePage`（缩放初值与重置 8.0）。

**新增的生成期断言**（把"尺度不一致"从真机观察提前到脚本阶段）：
- 河岸两圈相邻卵石的**净宽**：内圈 ≥2 处 > 0.6（保证能走到水边）、两圈最小净宽 ≥ 0.45；
- 石块铺位：不进河流弧带、离树根与青蛙出生点 ≥1.2、不出草地边缘；
- 草丛：不插进河里/树干里。

### 16.3 果蝇形态校正（S3）

按果蝇形态学的量化特征逐部件校正（**全部复用既有网格与节点名**，只有一处新增节点）：

| 部件 | 校正内容 | 依据 |
|---|---|---|
| 复眼 | 椭球 0.044/0.066/0.068 → **0.066/0.072/0.076**，位置 ±0.058 → **±0.070**，左右内缘只留 0.004 缝 | 果蝇是"接眼式"，复眼占满头侧（每眼约 750 小眼） |
| 触角 | 单段管 → **柄节/梗节/鞭节三段 + 芒（arista）**（末端节点 `antenna_*_club` 位置不变） | 果蝇触角为 3 节 + 羽状芒 |
| 胸部刚毛 | 手写 8 根 → **中背刚毛 6 行（沿体轴等距）+ 背中刚毛 2 对（更粗长）**，插入点按胸背旋转面算 | 中刚毛 6~8 行 + 2 对背中刚毛 |
| 腹部 | 背板 4 → **5 节**（每节"浅黄背板 + 后缘黑带"），新增节点 `abdomen_plates_i`；腹部底色 0x7a5228 → **0x9a7440** | 腹部背板 5~6 节、浅黄底 + 后缘黑带 |
| 腿 | 3 点折腿 → **5 点四节（基节/腿节→膝→胫节→跗节）+ 末端爪垫** | 腿为 coxa–femur–tibia–tarsus + 爪垫 |
| 体形 | 腹长 0.545 → **0.46**（缩短 ≈15%）、头长 0.18 → **0.20** | 翅/体长 ≈ 0.65（本次 ≈0.64） |
| 静止翅 | 模型侧翅根轴心 z −0.03 → **−0.10**、y 0.405 → **0.392**；渲染侧新增 `wingFoldPitch = 0.14` 与 `wingFoldYaw` 组合 | 静止时双翅平贴背部并超出腹末 |

**结果**：`world.glb` 三角面 22,386 → 24,302（同变体共享网格，新增部件只算一份），
网格 70 → 71（腹部背板）、材质 44 → 45（`abdomen_light`）、节点 368 → 374（`abdomen_plates_*`）。
**契约未变**：所有运行时按名字查找的节点名一个没改；`REQUIRED` 清单只同步了 blocker 编号区间。

### 16.4 静态配景（CC0 素材，S2）

素材：**Kenney「Nature Kit」（CC0 1.0）**，取 12 个变体存 `tools/assets/kn_*.glb`
（源 ZIP 不入库；明细与来源见该目录 `LICENSE-README.md`）。这批模型的特点决定了导入方式：

- **不带贴图**（纯材质色，材质名是 `grass` / `colorRed` / `woodBark` 这类语义名）
  ⇒ 不需要解码 PNG、不需要 alpha 裁剪卡片；按材质名映射到工程自己的材质色即可；
- **面数极小**（整只 32~200 面）⇒ 可以放心地按实例烘焙变换后合并；
- **含大量薄片**（草叶/花瓣）⇒ 三角面统一**输出双绕序**（易错总结第 30 条），
  否则从背面看会被整片剔除、出现"空洞"。

| 配景 | 数量 | 落点规则 |
|---|---|---|
| 花（紫/红/黄） | 各 4 | r 2.0~8.2 随机，避开树根/石块/青蛙出生点/其它配景 |
| 蘑菇（红/棕/丛） | 3 / 3 / 2 | r 2.2~8.4 |
| 灌木（普通/精细） | 各 3 | r 3.0~8.6（更靠外，做场地边界的"重量"） |
| 倒木 / 树桩 | 2 / 2 | r 3.5~8.2，互斥间距 1.0 |
| 芦苇 | 10 | **只长在河流内岸**（20°~108° 弧、r 6.6~7.05） |
| 睡莲 | 4 | **贴在水面上**（r = riverInner+0.9~2.3，y = 0.03） |

**实现要点**：1) 整只模型**一起归一化**（底面贴地 + xz 居中 + 高度缩放）——按材质分组归一化会
把花瓣与茎各自缩放、散架；2) 每个实例的变换烘焙进顶点，按（变体 × 材质）合并成
1 个 `props_*` 节点 + 1 个网格，**不注册进 `registerExtra`**（每帧零驱动成本）；
3) 配景**不参与碰撞**（不产生 blocker）——果蝇可以从花丛间穿过，这是刻意的；
4) 随机量用**独立种子** `0x6b0b01`，绝不复用既有元素的 RNG（否则会改变已有造型）。

**指标**（world.glb）：三角面 24,302 → **32,686**（+8.4k，配景按实例烘焙）、
网格 71 → **93**、节点 374 → **396**、材质 45 → **51**、文件 703 KB → **1.10 MB**。
脚本末尾会打印各变体"实际落位/预期"数量，拒绝采样连续失败（落位不足）能立刻看出来。

### 16.5 与设计稿的偏差

- 设计稿给河流径向 5.2~6.8、水面 y=−0.02；实现取更靠内的内半径并把水面抬到地面上方
  （y=0.012），否则地面圆盘会盖住水面、果蝇也够不到岸边。v6 放大后为 7.35~9.9（角度不变）。
- 设计稿未规定场地尺寸；v6 取"中等放大"（地盘 11.0、步行 9.0），既解决可视范围过小，
  又不至于让果蝇的移动显得空。
- 地面仍是平面圆盘（不做地形起伏），与设计稿一致。

### 16.6 真机验收点

① `blockers: 33`、`sky domes registered: 9/9`、帧率与连接组 tick 不劣化；
② 地面盖住全部树根与河岸；拉最远/平移到底时天空仍是整片色、不出现裁切；
③ 果蝇能走到水边饮水、能吃掉落果、不穿石块、不出草地、不站到水面上；
④ 风线与涟漪落在水带；青蛙追得上、舌头够得到；
⑤ 6 只果蝇不重叠；静止时双翅平贴背部且翼尖超出腹末；
⑥ 复眼明显占满头侧（不再像蜜蜂）、触角有分节与长芒、腹部有 5 节浅黄背板 + 黑带、腿有膝弯与爪垫；
⑦ 配景：花/蘑菇/灌木/倒木/树桩/芦苇/睡莲都能看到，且**没有浮空、没有陷进地面、没有落进水里**
（芦苇只在内岸、睡莲只在水面）；果蝇可以穿过花丛（不产生阻挡）。

---

## 17. 焦点果蝇切换 + 软边界压力（2026-09-16）

### 17.1 焦点果蝇：追踪镜头与行为按钮的目标可切换

- **新增概念**：`ScenePage.followIdx`（焦点果蝇，默认 0 号主果蝇）。追踪镜头（第一/第三人称）、
  顶部状态行、行为按钮（漫步/理毛/起飞/降落）、投喂落点（feedInFront）、觅食路径点
  （syncPathDots）全部作用于焦点果蝇 —— 看哪只、控哪只。
- **UI**：「视角」面板在追踪开启后新增「切换追踪目标 · 当前第 N 只」按钮，
  点击按**上场数量**循环（数量在点击时现读 `agents.getActiveCount()`，设置页改完回来立即正确）；
  下方注明"行为按钮与投喂落点也作用于这只果蝇"。
- **边界处理**：上场数量调小后帧循环把 `followIdx` 钳回 0 号；`getFocus()` 内部也有同样钳制，
  任何时刻都返回有效个体。青蛙索敌、触碰命中、群体摘要（👥N只 饿均/累均）不受焦点影响
  （青蛙永远咬最近的那只，摘要仍是全体）。
- **状态行双口径**（2026-09-16 追加）：**锁定视角开启时，状态行只显示焦点果蝇的个体状态** ——
  `🎯第N只 饿X% 累Y%`、⚡ 为它自己大脑的放电率（无独立大脑的个体不显示 ⚡）、❤ 为它本人的 HP；
  关闭锁定后恢复群体摘要（👥N只 饿均/累均 + 全体放电合计 + 最危急个体的 HP）。
  死亡提示覆盖层与场景压暗仍对任意个体生效（全局事件）。

### 17.2 软边界：去掉硬钳制，出界改为"负面压力 + 向心转向"

- **原问题**：`FlyBrain.applyBoundary` 在越过 `flyArenaRadius`（10.8）时直接钳位（硬墙），
  飞行撞上去就是"贴墙滑行"，观感生硬。
- **改法**（全部参数集中在 `FlyConfig` 的 `edge*` 段）：
  1. **硬钳制删除**。越过软边界（步行 9.0 / 飞行 10.8）就开始向心转向，出界越深转向越强
     （满深度时转向速率 ×(1+`edgeTurnBoost`=2.5)）。几何上最坏过冲有限：
     步行 ≈0.4、迎头直飞 ≈0.5（即 r 峰值 ≈11.3，草地盘 11.0），瞬态、随即折返；
  2. **出界负面压力**（`updateEdgeStress`，按出界深度线性升到满值，深度 =`edgeBand`=1.2）：
     饥饿增速 ×15、疲劳增速 ×11、恐惧 +0.25/s、掉血 6/s（满深度值）。
     力竭死亡原因新增 `FlyDeathCause.Lost`「迷失野外」（死亡文案/关于页统计自动生效）；
  3. **惊吓刺激源设在身体外侧**：出界期间持续把 `stimulusX/Z` 置于果蝇外侧 2 单位处，
     恐惧一旦触发惊吓，逃离方向必然朝向场心 —— "怕"本身就在把果蝇推回地图；
  4. **神经刺激语义**：饥饿/疲劳上升后经 `ConnectomeDriver.setEnvironment` 加重
     DRIVE_* 驱动群的持续刺激，连接组放电随之上升 —— "靠神经刺激自行保持在地图内"
     由既有管线兑现，不新增任何专用群或消息。
- **顺手修正**：原向心转向步长写死 `×0.016`（帧率相关，低帧率回转更慢），改为 `×dt`。
- **参数速查**：`edgeBand 1.2 / edgeHungerMul 14 / edgeFatigueMul 10 / edgeFearPerSec 0.25 /
  edgeHpDrain 6 / edgeTurnBoost 2.5`。想更"宽容"就调大 edgeBand 或调小后四项。

### 17.3 真机验收点

① 追踪第一/第三人称下点「切换追踪目标」，镜头跳到下一只果蝇；状态行显示它的状态与名字序号一致；
② 对第 2/3 只点「起飞/降落/理毛」生效的是当前追踪的那只；投喂落在它前方；
③ 飞行果蝇径直冲向场地边缘：不再撞墙停住，而是划一道弧线折返（最坏略越过草地盘边一点）；
④ 让它长时间赖在界外：状态行饿均/累均加速上涨，随后惊吓向场内逃窜；极端情形死亡文案为
「💀 迷失野外」，5 秒后原点重生；
⑤ 正常在场内活动时行为与改前一致（界内没有任何额外压力）。

### 17.4 真机反馈修复：食物不可达 / 岸边瞬移（2026-09-16）

**① 食物可能落在果蝇走不到的地方 → 绕圈死循环**

- 投喂 `placeFood` 原本只推石块不避河：点在水面上，食物落进河里，果蝇永远够不到；
  树上果实 `setFruitPosition` 完全没有避障：果实可能落在石块阻挡圆里，同样永远够不到。
- 表现是"绕着目标打转不休息"：seek 超时 14s → 回 wander → 饥饿仍高 → 立刻又锁定
  同一颗，无限循环。
- 修复：`placeFood` 补上河流弧带钳制（水面上收到内岸 `riverInner−0.2`）；
  `setFruitPosition` 补上 `obstacles.pushOut`（推出石块）。另加兜底：**觅食超时后把该食物
  对本体拉黑 `seekBanSeconds=6` 秒**（`FlyBrain.seekBanIdx/seekBanTimer`，
  `nearestFood` 过滤）——即使将来出现新的不可达情形，也只是换目标/先回去逛，不再绕圈。

**② 碰到岸边直接被"瞬移"**

- 原河域斥力是"径向拉回内岸"（`k = riverInner−0.05 / r`）：从河对岸走路回家、或降落在
  水域附近时，一帧内被拉过整条河（最宽 2.55 单位），观感就是瞬移。
- 修复（`applyBoundary` 河域段重写）：把河当作**两条弧形墙**——贴地个体按**更近的一岸**
  推出（内岸或外岸），再沿岸切向滑动（与绕石头同款手感，选与当前朝向夹角更小的切向）。
  从对岸回家 = 沿这一侧的岸滑到河的尽头再绕过去；判定条件从 `isGrounded()` 放宽为
  `!isAirborne() && y<0.3`（降落贴地末段也生效，不会一头扎进水里）。巡航高度照常过河。
- 附带修正：**落水扣血补上高度判断**（`y<0.3` 才扣）——原来巡航飞越河面也按落水
  扣 30 HP/s，跨一趟河白掉 ~20 HP。
- 自动降落防投河：`updateFly` 到点降落时若正下方是水域，先顺延（`phaseDuration` +
  0.2s 滚动）直到飞出水面再落；手动「降落」不受限，落进水里会被就近推上岸（滑行
  ≤1.28，属于用户明确指令的结果）。

### 17.5 品牌更名与真机反馈补测（2026-09-17）

- **应用名「果蝇大脑」→「赛博果蝇」**：AppScope / entry 的 string 资源（桌面名）、
  场景页顶部标题、关于页抬头（赛博果蝇 CyberFly）同步更新；大脑可视化页的页面标题
  「果蝇大脑」指该页内容本身，保留。Bundle 名 `com.zhuhao.guoying` 与开源仓不变。
- 软边界 / 岸边推岸滑动 / 食物避障（17.2~17.4）均已装机验证通过。

---

## 18. 数据集升级迁移：MaleCNS v1.0 全中枢连接组（2026-09-17，P0 代码完成）

**升级规划与实施记录见《[升级迁移-MaleCNS全中枢连接组.md](./升级迁移-MaleCNS全中枢连接组.md)》**，
本节只留结论备忘：

- 现役数据为 FlyWire FAFB 雌性全脑（139,255 神经元，2024，CC BY-NC）；升级目标为
  MaleCNS v1.0 雄性全中枢（166,691 神经元，含腹神经索，2026-06 发布，CC BY 4.0 可商用）；
- **核心契约：功能群 code 是稳定契约**（`OLF_ORN_FOOD` / `MN_LEG_L1` 等 14+ 个关键 code
  跨数据集不变），运行时全部经 code 查群号，数字群号不再硬编码——群表本体来自生成文件
  `behavior/NeuronGroupsTable.ets`（`tools/gen_neuron_groups.mjs`，legacy/malecns 双模式）；
- P0 已落地：连接组管线（`build_connectome_malecns.mjs`，`--sample` 合成数据端到端自测通过、
  `--report` 覆盖率报告）、bin 分析器（`analyze_connectome.mjs`，现役 bin 基准校验通过）、
  NeuPrint 取数参考脚本（`fetch_malecns.py`）、`ConnectomeDriver` 去硬编码 + 调制 4 → 6 路
  （新增腿群转向、翅群振翅意图，FAFB 下恒 0 无副作用）、`BrainPage` 表驱动
  （`behavior/BrainGroups.ets` 由 `gen_brain_glb.mjs` 生成）、brain_mini.glb 合入主脚本、
  场景页/关于页的规模口径全部改为运行时数据（消灭手写死数字）；
- P1（取数）起需要用户执行（NeuPrint 免费 token），操作序列见升级文档 §8。

---

## 19. 模型与场景大幅升级 v7：NeuroMechFly 高精度果蝇 + 蜿蜒河道（2026-09-17）

### 19.1 高精度果蝇模型（用户需求：口器与肢体的动作）

- **放弃程序化建模，改用现成高精度模型**：NeLy-EPFL「NeuroMechFly」v1.0（真实黑腹果蝇
  CT 重建，**Apache-2.0** 可商用）。65 个分部件 STL（共 33.4 万三角面）+ SDF 拼装 pose，
  存于 tools/assets/nmf_stl/（许可见该目录上级 LICENSE-README.md 第 5 节）。
- **装配**：gen_world_glb.mjs 新增 NMF 装配段 —— STL（米制局部坐标）×1000 + SDF link
  pose（毫米、旋转恒 0）拼装；世界系 x 前/y 左/z 上 → 场景系 (-y, z-h, x-c)×K；
  体长 3.10mm → 0.42 场景单位（K=0.1357）。顶点焊接 + 平均法线（平滑着色）。
- **契约不变**：fly_i / wing_left_i / wing_right_i / head_pivot_i 照旧；翅根铰点与头枢轴
  直接取 SDF 的 LWing/RWing/Head link 原点（真实关节位置）。口器（Rostrum+Haustellum）
  与六条腿（基节枢轴）为 v7 新增枢轴节点：mouth_pivot_i / leg_xx_pivot_i。
- **渲染器**（FlyRenderer）：模型基准姿态是“展翅”，fold 初值 1→0、死亡姿态改为保持平摊；
  新增步态近似（漫步/觅食时六腿交替摆动 0.15rad，对侧同相）与口器动画（进食下压伸出
  0.55+0.12sin、饮水 0.4、其余收起）。旧 DEAD_SPREAD 常量弃用。
- 面数预算 TRI_MAX 80k → 42 万（部件网格跨 6 只共享）；world.glb 6.85MB / 36.2 万面 /
  455 节点。

### 19.2 场景：蜿蜒河道 + 河岸植被（用户需求：河流从中间蜿蜒插过）

- **河道**：自西向东的 S 形 Catmull-Rom 样条（8 控制点 → 23 采样，半宽 0.7、沿程 0.85~1.25
  倍起伏），扫掠成河床/浅水缘/主水面三层条带（双绕序）。两岸卵石 ×16 沿折线布点
  （blocker 总数仍 33）；芦苇缩簇贴水线、睡莲漂在河面。
- **行为层**：新增 behavior/RiverPath.ets（折线距离/法向/推岸）；FlyConfig 以 riverPts
  （23 点扁平数组，与脚本 RIVER_SAMPLES 成对）+ riverHalfWidth 替代旧弧带四常量；
  FlyBrain 推岸=法向推到近岸+切向滑行（不再有跨河瞬移）；FoodWorld 果实/投喂避河同理。
- **植被**：河岸草甸 40 丛鲜绿湿生草（新材质 qn_grass_fresh）贴水线成带；树木 ×3、石块 ×14
  按河道距离重新铺位（生成期自检：石块/树根距河道 ≥RIVER_HALF+0.35、青蛙出生点移到
  北岸 5.46∠52.8°）。
- 真机截图验收（build-logs/s2~s12.jpeg）：蜿蜒河道路径、河岸带、青蛙新出生点、
  高精度果蝇（饮水/行走/被捕/重生）均确认。

### 19.3 已知待打磨（P3+）

- 腿部步态是枢轴小幅摆动的近似，非真关节链；口器动画只有下压伸出。
- 芦苇/草的材质色仍偏暗；场景地形仍是平面圆盘（无起伏）。
- 高模面数 36 万，低端机帧率如有压力，可对 STL 预减面后再入管线。

### 19.4 真机反馈修复（2026-09-17，v7.1）

| 问题 | 根因 | 修复 |
|---|---|---|
| 肢体垂直下落 | 误用 noLimits.sdf（碰撞调试布局：腿节垂直堆叠、伸到地下）当拼装姿态 | 换 locomotion_optimization.sdf 并应用各 link 的 rpy 旋转（头部俯仰/腹端下卷/翅收拢/跗节贴地）；体长基准改为排除翅膀的口器→腹末距离（2.69mm） |
| 河岸边转视角闪烁 | 河床 y=0.004 与内圈地面 y=0.004 完全共面 → z-fighting | 各层拉开：内圈 0.006 / 河床 0.014 / 浅水缘 0.021 / 水面 0.028（riverY 成对更新），睡莲抬到 0.036 |
| 青蛙舌头路径有误 | 舌头只沿水平本地 +Z 伸出，目标在空中时舌头贴地掠过其下方 | FrogController.update 增加目标高度参数；攻击时舌头按 atan2(目标高度-嘴高, 水平距离) 俯仰瞄准（上限 0.6rad） |
| 翅膀基准二次适配 | locomotion 站姿的网格基准是收翅贴背 | 渲染器 spread 语义：0=模型原姿（收翅/死亡）、1=绕竖轴外展 1.9rad+拍动；兴奋态半展 0.35；wingSpreadYaw/wingFoldRate 入 FlyConfig（旧 wingFoldYaw/Pitch 弃用） |

---

## 20. 真机反馈修复（2026-09-17，v7.2）：预置果蝇 / 青蛙舌头 / 河滩卡死

用户报的三件事（① 地图中央多了一只完全静止的果蝇、② 青蛙舌头一直保持伸出、
③ 果蝇走到河滩上就被卡住）：

### 20.1 河滩卡死（③，根因，同时解释了 ①）

**根因（数值实锤）**：v7 的蜿蜒河道穿过场心，而 `applyBoundary` 推岸会把贴地个体推到
**水面外沿 + 0.05 = 距河道中心线 0.75** 这条线上；生成脚本却把 16 颗河岸卵石摆在
`RIVER_HALF + 0.20 ± 0.15 = 0.75~1.05`，其**阻挡圆内缘全部压在 0.75 这条推岸线上**
（实测 16/16 内缘 < 1.05，14/16 内缘 < 0.85 = 推岸线 + 果蝇体半径）。于是果蝇一上岸就落进
卵石阻挡圆：

```
水约束：把果蝇推到距中心线 0.75（朝岸）
卵石约束：把果蝇推离卵石圆心（朝水）
```

两个方向的约束逐帧互相顶 → 位置来回弹、朝向被两边反复扭 → 表现为"卡在河滩上"。
更糟的是**帧末位置可能落在水带内** → 落水扣血（30/s）→ 饿死/淹死后 `respawn()` 又回到
**原点 (0,0)** —— 而原点距河道中心线只有 0.392 < 半宽 0.7，**就在水里**：重生即落水，
再被推到同一段被卵石压住的岸线上…… 于是"地图中央多了一只完全静止的果蝇"（用户以为是预置模型）。

**修复**（三层）：

1. **生成期（根因）**：河岸卵石的阻挡圆必须让出「可行走沙滩带」——
   内缘统一排在 `BEACH_LINE = RIVER_HALF + 0.35 = 1.05` 之外（半径大的卵石整体外挪，
   内缘仍在同一位置，视觉上照样贴着岸边），并加**生成期断言**
   （`河岸卵石内缘 x < 1.05：压住可行走沙滩带`）。实测修后左/右岸内缘 1.09 / 1.10。
   顺带修掉舌头网格的同类问题（见 20.2）。
2. **出生/重生点**：新增 `FlyBrain.groundSpawnPoint()` —— 推离水域（沿河道法向到近岸外侧 0.30）
   + 推出所有阻挡圆，迭代最多 3 轮；`spawnAt` / `respawn` 都走它。出生圈半径 0.6 → 1.6
   （0.6 的圈在穿过场心的河道上整圈都是水）。
3. **河滩软边界（用户要求的口径）**：新增 `beach*` 参数段与 `updateBeachStress()`，
   与出界压力同款"线性升到满值"，只是深度换成**停留时长**：

   | 项 | 值 | 说明 |
   |---|---|---|
   | `beachBand` | 0.55 | 河滩 = 水面外沿再往外 0.55（独立于饮水的 `waterNearBand`） |
   | `beachGrace` / `beachRamp` | 6 / 10 s | 前 6 秒零压力（路过/饮水不受罚），之后 10 秒线性到满值 |
   | `beachHungerMul` / `beachFatigueMul` | 5 / 7 | 饥饿/疲劳额外增速倍数（疲劳增益 > 休息恢复率 0.06，赖着走不掉） |
   | `beachFearAdd` / `beachFlyMaxWet` | 0.15 / 0.2 | 翅膀打湿 → **飞行能力下降**：受惊起飞门槛抬高、不自发起飞 |
   | `beachTurnBoost` | 1.6 | 背离河道的转向增强（满压力），"劝"它自己走上岸 |

   即"在河滩上待久了 → 越待越难受（饿/累加速、翅膀打湿飞不动）→ 自己走上岸"，不设禁止区。
4. **顺手修掉"站着不动"的观感来源**：`updateWaterProximity` 原来"喝完 → 原地再等 2 秒 → 又喝"，
   在河滩上表现为长时间站着不动。改为**一次临水只喝一次**（`drankHere`，离开水边才重置）。

### 20.2 青蛙舌头一直伸出（②）

- **只靠 `visible` 隐藏不够稳**：舌头收回分支原来只写 `tongue.visible = false`。
  现在**同时把三轴缩放塌缩到 0.001**（`TONGUE_HIDE_SCALE`），即使可见性没生效也只是一个点。
- **顺带修掉舌头网格被拉歪的旧问题**：`makeTongueUnit` 用了未归一化的
  `quatBetween(...)` 直接 `bakeTransform`，而该旋转公式只对**单位四元数**成立 ——
  实测原舌头网格是 `z∈[-0.54,1.55]、y∈±0.6` 的斜拉伸体（比青蛙身体还长）。
  归一化后是干净的单位圆柱（`z∈[0,1]、x/y∈±0.05`），运行时 `scale.z` 伸长才名副其实。
  （同一坑见易错总结第 38 条注 2。）

### 20.3 地图中央那只静止的果蝇（①，双保险）

除 20.1 的根因外，另加一层与项目既有约定一致的双保险：**预置的 6 份果蝇模型都在原点**，
未上场/被青蛙叼走的那几份若只写 `set.fly.visible = false`，真机上出现过"仍被画出来"的表现
（多份叠在原点 = 看起来只有一只静止的果蝇）。现在统一走 `ScenePage.hideFlyNode()`：
**可见性 + 把根节点移到 y = -80（移出视野）**，与场内特效节点埋在 y=-10 同款约定。

### 20.4 真机验收点

① 同屏只出现设置里配置的果蝇数量，**地图中央不再有静止果蝇**；
② 青蛙待机时看不到舌头；攻击时舌头沿口器正前方弹出、按目标高度上抬，收回后干净消失；
③ 把果蝇引到河滩上：**能沿沙滩带走过去**（不再原地抖），久留（>6s）后饿/累加速上涨、
翅膀打湿起来，随后自主走上岸；正常路过与饮水不受影响；
④ 河道与卵石外观仍贴岸（卵石内缘统一离水面外沿 0.35，形成一条天然沙滩带）；
⑤ 死亡重生的果蝇不再落进水里。

### 19.5 完整连接组（v7.1，2026-09-17）

恢复全量：165,122 个 Traced 神经元之间全部 **25,563,197 条聚合连接**（bin 311MB，
无 min-weight/top-k/max-edges 瘦身）。“把完整连接组跑在鸿蒙手机上”自此为字面事实。

- 性能依据：CSR 按行遍历使单步耗时只随放电神经元的边数增长——真机实测全量 25.56M 边
  与 400 万瘦身版同为 **~76ms/步**（预算 100ms）；放电速率 947/s、活跃脑区 17/43；
- 内存：Worker CSR 约 206MB/只 ×3（独立大脑）≈ 620MB，进程 PSS 峰值 ~2.5GB（8GB 设备实测通过）；
- 配套工程：rawfile 读取 Worker 化（fd 分块）+ 多驱动器串行就绪（waitReady）+ 场景节点
  单遍收集——三者合起来消除了启动冻结（易错总结第 38~40 条）；
- 口径：神经元 165,122/166,691 为 status=Traced 全集（其余 11,569 为神经胶质与孤儿片段，
  非“瘦身”）；连接为全部 Traced 神经元对的聚合（权重=突触数，按递质定符号）。
- 低端机可随时切回瘦身：`--min-weight 3 --top-k 300 --max-edges 4000000`。

### 19.6 连接组 Lite / 全仿真 双模式（v7.2，2026-09-18，用户拍板）

全仿真模式增加能耗与内存开销，故增加双档开关，**默认 Lite（瘦身版）**：

- **包内双数据文件**：`connectome.bin`（Lite，400 万边，48MB）+
  `connectome_full.bin`（全仿真，25,563,197 边，307MB）；管线 `--out-name` 参数分别产出；
- **设置页**：生态区新增「连接组模式」两档按钮（Lite（默认）/ 全仿真），偏好持久化
  （`connFull`），写入 AppStorage `fy_conn_full`；
- **热切换**：ScenePage 以 @StorageProp+@Watch 监听，切换时停掉全部驱动器并按新模式
  重建（读取在 Worker 线程，主线程安全；全仿真三驱动器串行就绪约 35~50s，期间可正常把玩）；
- **口径显示**：大脑小窗「数据集」行自动带「· Lite / · 全仿真」后缀，神经元/边数来自
  Worker 实测；
- ConnectomeDriver.start(context, full) 按 rawfile 名取 fd（按文件名缓存，互不干扰）。
