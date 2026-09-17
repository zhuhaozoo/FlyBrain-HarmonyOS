# 果蝇大脑 · FlyBrain for HarmonyOS

> 把 2024 年 FlyWire 的**完整成年果蝇脑连接组**（139,255 个神经元 / 2,698,236 条神经元间连接，
> 由约 5,000 万个化学突触按「前→后」聚合而来）跑在鸿蒙手机上：在 3D 场景里观察果蝇的自主活动，
> 端侧的 LIF 神经仿真实时放电，行为由手写状态机驱动、并受真实连接的信号传导调制
> （**混合驱动**，见「已知限制」）。

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-HarmonyOS-blue.svg)](https://developer.huawei.com/consumer/cn/)
[![API](https://img.shields.io/badge/API-23%2F24-green.svg)](https://developer.huawei.com/consumer/cn/)

---

## 这是什么

2024 年，FlyWire 联盟在《Nature》发表了**首张完整的成年果蝇全脑接线图** —— 139,255 个神经元、
约 5,000 万个化学突触的完整连接组（FAFB v783）。随后开源社区出现了把它跑在浏览器里的实时仿真项目
[snedea/flybrain](https://github.com/snedea/flybrain)：神经元用泄漏积分放电（LIF）模型在 Web Worker
里实时仿真，行为状态由运动群的**累积放电量**判读、内驱力作为兜底。

本项目把这一体验**复刻到鸿蒙上，做成原生 App**（ArkTS / ArkUI / ArkGraphics 3D 重写，13.9 万神经元
在手机端实时放电）。一处必须说清楚的差别：上游的运动群累积放电判读依赖较完整的运动神经元数据，
而 FlyWire 的这份数据是**脑**（运动神经元极少，见「已知限制」），因此本项目采用**混合驱动** ——
行为骨架来自内驱力与状态机，连接组的放电只作调制（步速 / 惊吓 / 理毛 / 觅食意图四路）。

---

## 功能

### M0 —— 3D 场景与行为状态机 ✅

- 预设 3D 场景（地面圆盘 + 8 块石丘 + 平行光），程序化生成的果蝇模型（15 个子节点、< 5 千面）
- 轨道相机（拖拽改 yaw/pitch、捏合缩放），相机注视点平滑跟随果蝇
- 行为状态机 7 态：漫步 / 理毛 / 休息 / 起飞 / 飞行 / 降落 / 空转，参数集中在 `FlyConfig`

### M1 —— 交互与内驱力 ✅

- **内驱力系统**：饥饿、恐惧、好奇、疲劳，随时间与交互变化
- **新增行为**：惊吓（僵直→逃离）、进食、趴伏、觅食，优先级链沿用上游顺序
  `startle > fly > feed > groom > brace > rest > phototaxis > seek > wander`
  （上游为 `… > explore > walk > idle`，本项目末尾对应 seek / wander / idle）
- **交互工具**：触碰 / 投喂（最多 5 份食物）/ 聚光（趋光目标）/ 吹风（弱风趴伏、强风惊吓）/ 光照三档
- 点击选点用已知相机参数手工反投影求交，不依赖 raycast，稳定且与引擎版本无关

### M2 —— 真实连接组 3D 大脑可视化 ✅

- 读取真实神经元坐标与分类，把 **139,255 个神经元**归一化成脑形点云（~1.6 半径）
- 按 5 组功能分区着色并可单独显隐（`classification.csv` 的 `super_class` 统计）：
  视觉 77,873 / 感觉 16,938 / 中央 44,254 / 运动 110 / 内分泌 80
- 独立页面，自动慢速自旋（可停）+ 分组图例

### M3 —— 端侧 LIF 神经仿真（实时放电 + 行为调制）✅

- **BrainWorker**（ArkTS Worker）忠实移植上游 `sim-worker.js` 的 LIF 模型，常量与 tick 流程逐条对齐：
  泄漏 0.95 / 阈值 1.0 / 不应期 3 / 权重缩放 0.15 / 10Hz tick，含按群重排（CSR）+ 群门控
- **ConnectomeDriver** 把 App 状态映射为对**真实感觉神经群**的持续刺激
  （食物气味 → 嗅觉食物群、触碰 → 刚毛 + 嗅觉危险群、风 → Johnston 器、光照 → 视觉群、
  饥饿/疲劳 → 驱动群），再把运动群放电汇总成四路调制量
- 真机实测：`ready N=139255 edges=2698236 groups=61`，LIF 稳定运行在 10Hz
  （单 tick 61~78 ms，预算 100 ms），每 tick 约 30+ 神经元放电
  （`groups=61` 是运行时段数：元数据共 63 群，其中 2 群（未细分驱动/运动）神经元数为 0，
  群数按「最大群号 + 1」计算；63 群中实际有神经元的是 32 群）

### M4 —— 场景丰富化与玩法 ✅

昼夜循环（日月升落 + 星空 + 天空穹顶）、河流与河岸卵石、树木与树上果实、果蝇生命值/死亡重生、
捕食者青蛙（会跳跃接近 + 蓄力预警 + 舌头弹射）、石块/卵石/树干的步行碰撞、停栖收翅。
设计与实施记录（含与设计稿的全部偏差）：[`docs/场景与玩法设计-M4.md`](docs/场景与玩法设计-M4.md) §8。

### M5 —— 生态与多智能体 （P1 代码完成，待真机验证）

- P1 多果蝇地基：同屏 1/3/6 只（默认 3）、共享食物世界（先到先得争食）与共享世界状态（风/光/光斑）、
  个体参数扰动 ±10%、个体互斥、独立大脑（每只一个 BrainWorker，上限 3）
- 设计稿与后续阶段（信息素场、青蛙饱食度、BrainMount 统一大脑、多岛场景切换）：
  [`docs/生态体系与多智能体设计-M5.md`](docs/生态体系与多智能体设计-M5.md)；
  实施记录见开发文档第 14 章

---

## 技术栈

| 项 | 内容 |
|---|---|
| 平台 | HarmonyOS（Stage 模型） |
| SDK | compatibleSdkVersion `6.1.0(23)` / targetSdkVersion `6.1.1(24)` |
| 语言 / UI | ArkTS + ArkUI 声明式范式 |
| 3D | ArkGraphics 3D（`Component3D` + glTF/glb） |
| 并发 | ArkTS Worker（`@kit.ArkTS` ThreadWorker）+ `postMessage` transfer 零拷贝 |
| UI 组件 | 官方 UIDesignKit（`HdsNavigation` / `HdsNavDestination` 沉浸材质） |
| 持久化 | `@kit.ArkData` preferences |
| 包名 | `com.zhuhao.guoying` |

---

## 快速开始

### 环境要求

- **DevEco Studio** 6.1.1 或更高（本项目在 `6.1.1.280` 上开发验证）
- **HarmonyOS SDK** API 23 / 24
- 一台**鸿蒙真机**：`Component3D` 在 DevEco 预览器中**不支持渲染**，必须真机运行

### 1. 配置签名（必做）

> ⚠️ 仓库里的 `build-profile.json5` **不含签名配置**（`signingConfigs`），
> 因为其中会包含本机绝对路径与签名口令。直接拉取工程会因缺少签名而无法构建。

在 DevEco Studio 中生成自己的签名：

1. 用 DevEco Studio 打开本工程；
2. `File → Project Structure → Signing Configs`；
3. 勾选 **Automatically generate signature**（需登录华为开发者账号），等待自动生成；
4. 点击 `Apply / OK` —— IDE 会把 `signingConfigs` 以及 `products[].signingConfig`
   写回 `build-profile.json5`。

签名配置属于本机信息（含本机绝对路径与签名口令），**请勿提交到版本库**。

### 2. 构建

在 DevEco Studio 中直接 `Build → Build Hap(s)`；或用命令行：

```bash
# <DEVECO_HOME> 为 DevEco Studio 安装目录，例如 Windows 下的 "D:\DevEco Studio"
export DEVECO_SDK_HOME="<DEVECO_HOME>/sdk"      # Windows: set DEVECO_SDK_HOME=<DEVECO_HOME>\sdk

"<DEVECO_HOME>/tools/hvigor/bin/hvigorw.bat" \
  --mode module -p product=default -p buildMode=debug assembleHap
```

> 未设置 `DEVECO_SDK_HOME` 会报 `00303217`。
> 工程根目录**没有** `hvigorw` 包装脚本，请用 DevEco 自带的那个。

产物位于 `entry/build/default/outputs/default/entry-default-signed.hap`。

### 3. 安装到真机

```bash
hdc install -r entry/build/default/outputs/default/entry-default-signed.hap
```

无线调试与 USB 同时连接时，`hdc` 可能报 `need connect-key`，需用 `-t <设备序列号>` 指定目标设备。

---

## 数据管线（`tools/`）

资源由**零依赖 Node 脚本**生成：果蝇、青蛙、河流、天空等模型全部程序化生成；
场景中的**树木、岩石、草丛几何**导入自 Quaternius 的 **CC0 1.0（公有领域）**低多边形素材，
**v6 起新增的花/蘑菇/灌木/倒木/芦苇等静态配景**导入自 Kenney 的 **Nature Kit（同为 CC0 1.0）**
（源文件在 `tools/assets/`，贴图不入包，可放心商用，详见
[`THIRD-PARTY-NOTICES.md`](THIRD-PARTY-NOTICES.md) 第 4 节）：

```bash
# 生成 3D 世界（地面/河流/树木/青蛙/果蝇）→ rawfile/gltf/world.glb
# 需要 tools/assets/ 下的 CC0 源素材（已随仓库提供）
node tools/gen_world_glb.mjs

# 生成 139,255 神经元的脑点云 → rawfile/gltf/brain.glb
# 输入：tools/data/coordinates.csv 与 tools/data/classification.csv（需先解压 .gz）
node tools/gen_brain_glb.mjs
```

> 同一脚本还会产出 `rawfile/gltf/brain_mini.glb`（按 1/4 抽稀的约 3.5 万神经元点云，
> 供「大脑状态小窗」里的实时 3D 高亮演示用）。

#### 连接组数据（MaleCNS v1.0，雄性全中枢 · 现役）

包内现役数据为 **MaleCNS v1.0**（HHMI Janelia 等，雄性全中枢，CC BY 4.0 可商用）：
status=Traced 的 165,122 个神经元之间**全部 2,556 万条聚合连接**，不做任何瘦身——
“把完整连接组跑在鸿蒙手机上”是字面事实。真机实测：单步 76ms（预算 100ms）、
三只果蝇各挂一份完整仿真（独立 Worker + fd 分块读取 + 串行就绪）。
规划、契约与验收见 [`docs/升级迁移-MaleCNS全中枢连接组.md`](docs/升级迁移-MaleCNS全中枢连接组.md)：

```bash
python tools/fetch_malecns.py --out tools/data_malecns    # NeuPrint 导出（需免费 token，见脚本头注释）
node tools/build_connectome_malecns.mjs --report          # 看映射覆盖率报告
node tools/build_connectome_malecns.mjs                   # 默认 = 全量（2556 万边，无瘦身）
node tools/gen_neuron_groups.mjs --malecns tools/data_malecns/groups.json
node tools/gen_brain_glb.mjs --data tools/data_malecns --label "MaleCNS v1.0 雄性全中枢 (Janelia 2026)"
node tools/analyze_connectome.mjs --groups entry/src/main/ets/behavior/NeuronGroupsTable.ets
```

设置页内置「连接组模式」开关（默认 Lite 瘦身版 / 可选全仿真，热切换）；管线级低端机瘦身：`--min-weight 3 --top-k 300 --max-edges 4000000`（边数 −84%，单步耗时几乎
不变，但 Worker 内存约 206MB/只 → 50MB/只）。默认**不瘦身**。
`build_connectome_malecns.mjs --sample` 可用合成数据端到端自测管线（不触碰 rawfile）；
`gen_neuron_groups.mjs`（默认 legacy 模式）与 `analyze_connectome.mjs` 可随时还原/校验现役数据。

`tools/data/` 下随仓库分发了 FlyWire 派生数据的**压缩源文件**（`.gz`），
而生成脚本读取的是**解压后**的 `.csv`（解压产物不入库，见 `.gitignore`），因此首次运行前请先解压：

```bash
gunzip -k tools/data/coordinates.csv.gz tools/data/classification.csv.gz
```

连接组二进制同理（`connectome.bin.gz` → `connectome.bin`）：仓库已随包提供
`entry/src/main/resources/rawfile/connectome.bin`，仅在需要重新生成时才要解压。

> **数据可追溯到上游**：`tools/data/` 下的 4 个文件（`connectome.bin.gz`、`neuron_meta.json`、
> `coordinates.csv.gz`、`classification.csv.gz`）与 [snedea/flybrain](https://github.com/snedea/flybrain)
> 仓库中的同名文件**逐字节一致**，可用 `git hash-object <file>` 与该仓库 Contents API 返回的 blob sha 自行比对；
> 包内的 `connectome.bin`（32,796,605 字节）就是 `connectome.bin.gz` 的解压结果。
> 这些数据受 **CC BY-NC 4.0（非商用）** 约束，详见
> [`THIRD-PARTY-NOTICES.md`](THIRD-PARTY-NOTICES.md)。

---

## 工程结构

```
.
├── AppScope/                      # 应用级配置与图标
├── entry/
│   └── src/main/
│       ├── ets/
│       │   ├── behavior/          # 行为层（纯逻辑，无渲染依赖）
│       │   │   ├── FlyTypes.ets       # 状态枚举、姿态类型、食物项
│       │   │   ├── FlyConfig.ets      # 全部行为参数 + 全局单例
│       │   │   ├── FlyBrain.ets       # 内驱力 + 状态机 + HP + 边界/碰撞
│       │   │   ├── FlyAgents.ets      # 多果蝇协调器（实例驱动 + 个体互斥）
│       │   │   ├── FoodWorld.ets      # 共享食物世界（投喂 + 果实 + 认领争食）
│       │   │   ├── WorldState.ets     # 共享世界状态（光照/风/光斑）
│       │   │   ├── Obstacles.ets      # 静态障碍碰撞圆（石块/卵石/树干）
│       │   │   └── ConnectomeDriver.ets  # 连接组仿真驱动器（主线程侧）
│       │   ├── scene/             # 渲染层
│       │   │   ├── SceneManager.ets   # 场景/相机/光照/节点查找
│       │   │   ├── FlyRenderer.ets    # 姿态写入节点、翅膀收展与拍动
│       │   │   ├── EnvironmentController.ets  # 昼夜/日月星/树摆/风线
│       │   │   └── FrogController.ets # 捕食者青蛙状态机 + 舌头弹射
│       │   ├── worker/
│       │   │   └── BrainWorker.ets    # LIF 神经仿真（Worker 线程）
│       │   ├── common/
│       │   │   ├── Math3D.ets         # 向量/四元数/lookAt
│       │   │   └── BreakpointService.ets  # 多端断点
│       │   ├── pages/             # UI 层
│       │   │   ├── Index.ets          # HdsNavigation 路由根容器
│       │   │   ├── ScenePage.ets      # 3D 主页 + 控制面板
│       │   │   ├── BrainPage.ets      # 连接组大脑可视化
│       │   │   ├── SettingsPage.ets   # 设置
│       │   │   └── AboutPage.ets      # 关于（含开源地址与署名）
│       │   └── entryability/
│       └── resources/rawfile/     # connectome.bin、gltf/*.glb
├── docs/                          # 设计与踩坑文档
├── tools/                         # 零依赖 Node 生成脚本 + 数据
└── build-profile.json5
```

---

## 文档

| 文档 | 内容 |
|---|---|
| [`docs/果蝇大脑App开发文档.md`](docs/果蝇大脑App开发文档.md) | 主文档：背景、方案选型、架构分层、M0~M5 实施记录（含每轮真机反馈的修复记录） |
| [`docs/ArkTS-ArkUI易错总结.md`](docs/ArkTS-ArkUI易错总结.md) | **强烈推荐阅读**：40 条实战踩坑（编译错误 / 运行时行为 / HDS 组件 / 3D 渲染 / 工程经验 / 资源生成脚本 / 模型契约 / 跨层常量约定八类），每条含「现象 → 原因 → 正确写法」 |
| [`docs/场景与玩法设计-M4.md`](docs/场景与玩法设计-M4.md) | M4 场景与玩法设计（含实施记录、与设计稿的偏差、建模升级 v3/v4 说明） |
| [`docs/生态体系与多智能体设计-M5.md`](docs/生态体系与多智能体设计-M5.md) | M5 设计稿：多果蝇生态、统一大脑挂载、场景切换（**设计稿 + 科学边界声明**；实现进度见开发文档第 14 章与工程代码） |
| [`docs/升级迁移-MaleCNS全中枢连接组.md`](docs/升级迁移-MaleCNS全中枢连接组.md) | 数据升级迁移：FAFB 雌性全脑 → MaleCNS v1.0 雄性全中枢（设计 + 管线契约 + 实施进度） |

---

## 已知限制

- **必须真机运行**：`Component3D` 在 DevEco 预览器中不支持渲染；
- **冷启动较慢**：场景加载与引擎初始化约 10~20 s，暂无进度反馈；
- **仿真性能**：连接组模式下单 tick 约 61~78 ms，逼近 100 ms 预算（活跃群增多时可能需降频或分帧）；
  M5 起每只果蝇一个独立 BrainWorker（上限 3 个，各约 31 MB 连接组内存），数量越多 CPU/内存压力越大；
- **运动神经元数据极稀疏（决定了"不会真涌现"）**：FlyWire 这份数据是**脑**，其
  `neuron_meta.json` 里 motor 区合计只有 **76 个**神经元（口器 24 / 头部 40 / 腹部 8 / 步态节律 4），
  **腿 `MN_LEG_*`、翅 `MN_WING_*`、下行飞行 `DN_FLIGHT` 都是 0**（63 群中仅 32 群有神经元）——
  因为腿/翅的运动神经元在**腹神经索（VNC）**里，不在该数据集内。因此"走路/飞行"不可能从这份连接组涌现，
  本项目采用**混合驱动**：行为骨架为内驱力 + 状态机，连接组提供四路调制（步速/惊吓/理毛/觅食意图）。
  想更接近"涌现"，正确路径是引入 VNC 数据集（如 MANC/FANC）或改换神经元模型，
  **而不是"等上游数据完善"**；
- 青蛙没有碰撞（会跳过石块与树干）；果蝇与青蛙均无骨骼动画（翅膀收展/拍动、进食低头、颠簸为代码驱动）；
  果蝇/青蛙为程序化建模（低多边形），树/石/草丛/花/蘑菇/灌木等配景导入自 CC0 素材。

---

## 许可与数据合规

- **本项目代码**：[MIT License](LICENSE)。
- **随仓库分发的 FlyWire 派生数据**（`connectome.bin`、`brain.glb`、`tools/data/*`）：
  受 **CC BY-NC 4.0 非商用许可**约束 —— 官方指引见 https://flywire.ai/guidelines 。
  **若要商用，请先移除这些数据并改用商业许可的数据源。**
- **移植的第三方代码**（snedea/flybrain 等）与参考项目，见
  [`THIRD-PARTY-NOTICES.md`](THIRD-PARTY-NOTICES.md)。

## 致谢

- **FlyWire 联盟** —— 提供完整果蝇脑连接组这一里程碑数据
  （Dorkenwald, S., Matsliah, A., Sterling, A.R. et al. *Neuronal wiring diagram of an adult brain.*
  Nature 634, 124–138 (2024). https://doi.org/10.1038/s41586-024-07558-y ）
- **[snedea/flybrain](https://github.com/snedea/flybrain)**（MIT）—— 本项目的复刻蓝本，
  行为语义与 LIF 仿真移植自它
- **[heyseth/worm-sim](https://github.com/heyseth/worm-sim)** —— 连接驱动虚拟生物的开创性实践
- **[google/neuroglancer](https://github.com/google/neuroglancer)**（Apache-2.0）—— FlyWire 官方查看器内核
- **华为官方 Graphics3D 示例** —— 相机 `lookAt` 实现方式参考

> 本项目仅用于科普演示，不构成任何科学结论。
