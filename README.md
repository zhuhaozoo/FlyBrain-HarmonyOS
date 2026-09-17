# 赛博果蝇 · CyberFly for HarmonyOS

> 把 **MaleCNS v1.0** —— 首张**雄性果蝇完整中枢神经系统连接组**（HHMI Janelia 联合
> Google Research 等，2026；165,122 个 Traced 神经元之间 **2,556 万条聚合连接**，
> 约 1.25 亿个化学突触，**CC BY 4.0 可商用**）跑在鸿蒙手机上：**不做任何瘦身**，
> 三只果蝇各自挂一份完整的 LIF 神经仿真实时放电；在 3D 场景里观察它们漫步、觅食、
> 饮水、飞行、躲避青蛙捕食，行为由内驱力与状态机驱动、并受真实连接组的信号传导调制
> （**混合驱动**，六路调制，见「已知限制」）。

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-HarmonyOS-blue.svg)](https://developer.huawei.com/consumer/cn/)
[![API](https://img.shields.io/badge/API-23%2F24-green.svg)](https://developer.huawei.com/consumer/cn/)

---

## 这是什么

果蝇是连接组学的明星物种：2023 年有了幼虫全脑（3,016 神经元），2024 年 FlyWire 联盟在
《Nature》发表了**雌性成虫全脑连接组**（FAFB，139,255 神经元），2026 年 HHMI Janelia
联合 Google Research 等又公开了**首个雄性成虫完整中枢神经系统连接组 MaleCNS v1.0**
（166,691 神经元，脑 + 视叶 + **腹神经索**）——腹神经索正是腿/翅运动神经元的所在，
这让"连接组驱动的运动行为"第一次有了真实接线可言。开源社区此前出现了把它们跑在浏览器里的
实时仿真项目 [snedea/flybrain](https://github.com/snedea/flybrain)（基于 FAFB）。

**本项目（赛博果蝇）把 MaleCNS v1.0 完整连接组跑在鸿蒙手机上，做成原生 App**
（ArkTS / ArkUI / ArkGraphics 3D）：165,122 个 Traced 神经元、2,556 万条聚合连接，
用泄漏积分放电（LIF）模型在 Worker 线程实时仿真；行为骨架来自内驱力与状态机，
连接组放电做**六路调制**（步速 / 惊吓 / 理毛 / 觅食意图 / 左右腿群转向 / 翅群振翅意图）——
其中腿、翅、下行的运动群在 MaleCNS 里**首次拥有真实神经元**（FAFB 时代为 0）。
一处必须说清楚的边界：连接组是接线图，不是"会思考的大脑"——行为语义仍需映射与调参，
本项目不宣称"果蝇在思考"（科学边界详见开发文档与关于页）。

---

## 功能

### 基础 —— 3D 场景与行为状态机 ✅

- 3D 小生态：草地圆盘 + **蜿蜒河道**（含河床/浅水缘/睡莲/芦苇/两岸卵石）+ 树木 + 石块 +
  花/蘑菇/灌木/倒木等配景，昼夜循环（日月升落 + 星空 + 天空穹顶分时变色）
- 行为状态机 13 态：漫步 / 理毛 / 休息 / 起飞 / 飞行 / 降落 / 惊吓 / 进食 / 趴伏 / 觅食 /
  饮水 / 死亡 / 待机；优先级链对齐 flybrain：`startle > fly > feed > groom > brace >
  rest > phototaxis > seek > wander`
- **内驱力系统**：饥饿、恐惧、好奇、疲劳 + 生命值（饥饿掉血 / 进食回血 / 饮水回血 /
  晒太阳回血）、死亡与重生
- **软边界**：飞出活动半径不会被"墙"弹回，而是负面内驱力加速累积 + 随深度增强的向心转向，
  果蝇会自己折返；河道对步行是"两条岸线"（贴岸滑行，不再瞬移）
- **交互**：触碰 / 投喂（点地或一键投喂）/ 聚光（趋光 + 晒太阳回血）/ 吹风（弱风趴伏、
  强风惊吓、河面涟漪、风线掠过）/ 光照三档；风向还会让树与河岸植被摇摆

### 连接组仿真（MaleCNS v1.0，端侧 LIF）✅

- **完整连接组，无瘦身**：165,122 神经元 / 25,563,197 条聚合连接在 **Worker 线程**以
  10Hz LIF 实时放电（泄漏 0.95 / 阈值 1.0 / 不应期 3 / 权重 ±0.15 归一化 / 按群门控），
  rawfile 以 fd 分块在 Worker 内读取——主线程零大块工作，不卡 UI
- **功能群语义**：63+ 功能群（视觉 / 嗅觉 / 机械 / 温度 / 味觉 / 蘑菇体 / 中心体 /
  驱动群 / 下行 / **VNC 腿·翅·口器运动群** …），App 事件映射为对真实感觉群的持续刺激，
  运动群放电汇总为**六路调制量**回灌行为层
- **大脑可视化页**：164,908 神经元点云（脑 + 腹索真实形态），按 5 大区着色可独立显隐
- **大脑状态小窗**：放电速率 / 活跃脑区计数 / 单步耗时 / Top-8 活跃脑区明细 +
  数据集标签（Lite / 全仿真一目了然）
- **Lite / 全仿真双模式**（设置页可选，默认 **Lite**）：Lite 为 400 万边瘦身版
  （省内存省电），全仿真为 25,563,197 边完整连接组——切换后重启应用生效

### 生态与多智能体（M5）✅

- 同屏 **1 / 3 / 6 只**果蝇（默认 3），共享食物世界（先到先得争食：投喂 + 树上落果）、
  共享世界状态（风 / 光照 / 光斑）、个体参数扰动、个体互斥
- **独立大脑**：每只果蝇一个 BrainWorker 实例（上限 3），感觉刺激按各自处境注入；
  超出上限的个体自动退化为纯阈值驱动
- **捕食者青蛙**：跳跃接近 + 蓄力预警（0.8s 救援窗口）+ 舌头俯仰弹射 + 命中捕获，
  吹风可以救走被盯上的果蝇

### v7 —— 高精度果蝇模型 ✅

- 果蝇模型改用 **NeuroMechFly v1.0**（NeLy-EPFL，真实黑腹果蝇 CT 重建，**Apache-2.0**）：
  65 个分部件网格共 33.4 万三角面——头 / 复眼 / 三节触角 / **口器（喙 + 唇瓣）** /
  左右翅 / 平衡棒 / 五节跗节腿 ×6 / 腹节 A1A2~A6
- 运行时动画：双翅收拢贴背 ⇄ 外展拍动、**进食/饮水时口器下压点动**、
  **步行六腿交替摆动**（近似三角步态）、死亡翻面摊翅
- 相机：轨道环绕 / 捏合缩放 / 双指平移 / **视角追踪**（第一·第三人称）/
  **切换追踪目标**（多果蝇各自视角）

---

## 技术栈

| 项 | 内容 |
|---|---|
| 平台 | HarmonyOS（Stage 模型） |
| SDK | compatibleSdkVersion `6.1.0(23)` / targetSdkVersion `6.1.1(24)` |
| 语言 / UI | ArkTS + ArkUI 声明式范式 |
| 3D | ArkGraphics 3D（`Component3D` + glTF/glb） |
| 神经仿真 | ArkTS Worker（`@kit.ArkTS` ThreadWorker）+ fd 分块读取 + CSR 按群门控 LIF |
| 连接组 | MaleCNS v1.0（现役）/ FlyWire FAFB（legacy 管线保留） |
| UI 组件 | 官方 UIDesignKit（`HdsNavigation` / `HdsNavDestination` 沉浸材质） |
| 持久化 | `@kit.ArkData` preferences |
| 包名 | `com.zhuhao.guoying` |

---

## 快速开始

### 环境要求

- **DevEco Studio** 6.1.1 或更高（本项目在 `6.1.1.280` 上开发验证）
- **HarmonyOS SDK** API 23 / 24
- 一台**鸿蒙真机**：`Component3D` 在 DevEco 预览器中**不支持渲染**，必须真机运行
- 内存建议：Lite 模式 4GB+ 设备即可；**全仿真模式建议 8GB+**（三份完整 CSR ≈ 620MB）

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

多设备同时连接时，`hdc` 可能报 `need connect-key`，需用 `-t <设备序列号>` 指定目标设备。

---

## 数据管线（`tools/`）

零依赖 Node 脚本生成全部资源。**果蝇模型**来自 NeuroMechFly v1.0（Apache-2.0，见
`tools/assets/nmf_stl/` 与 `THIRD-PARTY-NOTICES.md`）；树木/岩石/草丛来自 Quaternius、
花/蘑菇/灌木/芦苇等配景来自 Kenney（均为 CC0 1.0，贴图不入包）：

```bash
# 装配 NeuroMechFly 高精度果蝇 + 蜿蜒河道场景 → rawfile/gltf/world.glb
node tools/gen_world_glb.mjs

# 脑点云（MaleCNS：--data 指向管线产物目录；FAFB legacy 数据为默认输入）
node tools/gen_brain_glb.mjs --data tools/data_malecns --label "MaleCNS v1.0 雄性全中枢 (Janelia 2026)"
# 同脚本产出 brain.glb（全神经元点云）与 brain_mini.glb（1/4 抽稀）
```

#### 连接组（MaleCNS v1.0 · 现役）

官方批量数据（免登录直链）→ 转换 → 管线 → 运行时产物，全流程可复现：

```bash
npm --prefix tools/data_malecns install apache-arrow lz4js   # Feather 读取依赖（一次性）
node tools/convert_malecns_feather.mjs                       # 官方 feather → neurons/connections.csv
node tools/build_connectome_malecns.mjs --report             # 映射覆盖率与边分布报告
node tools/build_connectome_malecns.mjs                      # 全量 connectome.bin（默认）
node tools/gen_neuron_groups.mjs --malecns tools/data_malecns/groups.json
node tools/analyze_connectome.mjs --groups entry/src/main/ets/behavior/NeuronGroupsTable.ets
```

> - 官方下载页：https://male-cns.janelia.org/download/（body-annotations / body-neurotransmitters /
>   connectome-weights 三个 feather 文件，约 1.1GB）；
> - `build_connectome_malecns.mjs --sample` 用合成数据端到端自测管线（不触碰 rawfile）；
> - 低端机可选瘦身：`--min-weight 3 --top-k 300 --max-edges 4000000`
>   （边数 −84%，单步耗时几乎不变，Worker 内存约 206MB/只 → 50MB/只）。

#### FlyWire FAFB（legacy，参考/回退用）

`tools/data/` 保留了 FAFB 派生数据的压缩源文件（`.gz`，与
[snedea/flybrain](https://github.com/snedea/flybrain) 逐字节一致，CC BY-NC 4.0 非商用），
配套 legacy 管线可随时回退：解压后按 `gen_neuron_groups.mjs`（默认 legacy 模式）→
`gen_brain_glb.mjs` → 重跑连接组即可还原（详见
[`docs/升级迁移-MaleCNS全中枢连接组.md`](docs/升级迁移-MaleCNS全中枢连接组.md) §9）。

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
│       │   │   ├── FlyConfig.ets      # 全部行为参数 + 全局单例（含连接组模式）
│       │   │   ├── FlyBrain.ets       # 内驱力 + 状态机 + HP + 软边界/河域/障碍
│       │   │   ├── FlyAgents.ets      # 多果蝇协调器（实例驱动 + 个体互斥）
│       │   │   ├── FoodWorld.ets      # 共享食物世界（投喂 + 果实 + 认领争食 + 避河避石）
│       │   │   ├── WorldState.ets     # 共享世界状态（光照/风/光斑）
│       │   │   ├── Obstacles.ets      # 静态障碍碰撞圆（石块/卵石/树干）
│       │   │   ├── RiverPath.ets      # 蜿蜒河道折线几何（水检测/推岸/饮水判定）
│       │   │   ├── NeuronGroups.ets   # 功能群查找工具（label/region/code→id）
│       │   │   ├── NeuronGroupsTable.ets  # 群表（生成器产物，按数据集切换）
│       │   │   ├── BrainGroups.ets    # 点云 5 分组表（生成器产物）
│       │   │   └── ConnectomeDriver.ets  # 连接组仿真驱动器（按 code 查群，六路调制）
│       │   ├── scene/             # 渲染层
│       │   │   ├── SceneManager.ets   # 场景/相机/光照/单遍节点收集
│       │   │   ├── FlyRenderer.ets    # 姿态写入、翅收展拍动、步行摆腿、口器动画
│       │   │   ├── EnvironmentController.ets  # 昼夜/日月星/树摆/风线/涟漪
│       │   │   └── FrogController.ets # 捕食者青蛙状态机 + 舌头俯仰弹射
│       │   ├── worker/
│       │   │   └── BrainWorker.ets    # LIF 神经仿真（Worker 线程，fd 分块读 rawfile）
│       │   ├── common/
│       │   │   ├── Math3D.ets         # 向量/四元数/lookAt
│       │   │   └── BreakpointService.ets  # 多端断点
│       │   ├── pages/             # UI 层
│       │   │   ├── Index.ets          # HdsNavigation 路由根容器
│       │   │   ├── ScenePage.ets      # 3D 主页 + 控制面板 + 大脑状态小窗
│       │   │   ├── BrainPage.ets      # 连接组点云可视化（表驱动图例）
│       │   │   ├── SettingsPage.ets   # 设置（速度/生态/同屏数/连接组模式）
│       │   │   └── AboutPage.ets      # 关于（开源地址、数据集口径、署名）
│       │   └── entryability/
│       └── resources/rawfile/     # connectome.bin（Lite）/ connectome_full.bin（全仿真）/ gltf/*.glb
├── docs/                          # 设计与踩坑文档
├── tools/                         # 零依赖 Node 生成脚本 + 管线 + 素材
│   ├── assets/                    # CC0/Apache-2.0 源素材（Quaternius/Kenney/NMF STL）
│   └── data/                      # FlyWire FAFB legacy 数据（.gz）
└── build-profile.json5
```

---

## 文档

| 文档 | 内容 |
|---|---|
| [`docs/果蝇大脑App开发文档.md`](docs/果蝇大脑App开发文档.md) | 主文档：背景、方案选型、架构分层、M0~v7 实施记录（含每轮真机反馈的修复记录） |
| [`docs/ArkTS-ArkUI易错总结.md`](docs/ArkTS-ArkUI易错总结.md) | **强烈推荐阅读**：40 条实战踩坑（编译错误 / 运行时行为 / HDS 组件 / 3D 渲染 / 工程经验 / 资源生成脚本 / 模型契约 / 跨层常量 / 性能冻结类九类），每条含「现象 → 原因 → 正确写法」 |
| [`docs/场景与玩法设计-M4.md`](docs/场景与玩法设计-M4.md) | M4 场景与玩法设计（含实施记录、与设计稿的偏差、建模升级 v3/v4 说明） |
| [`docs/生态体系与多智能体设计-M5.md`](docs/生态体系与多智能体设计-M5.md) | M5 设计稿：多果蝇生态、统一大脑挂载、场景切换（**设计稿 + 科学边界声明**；实现进度见开发文档第 14 章与工程代码） |
| [`docs/升级迁移-MaleCNS全中枢连接组.md`](docs/升级迁移-MaleCNS全中枢连接组.md) | 数据升级迁移：FAFB 雌性全脑 → MaleCNS v1.0 雄性全中枢（设计 + 管线契约 + 实施记录） |

---

## 已知限制

- **必须真机运行**：`Component3D` 在 DevEco 预览器中不支持渲染；
- **首启加载**：场景 + 连接组加载约 20~40s（全仿真模式下三份完整 CSR 在后台串行就绪，
  期间可正常把玩，仿真就绪后放电数据自动上线）；暂无加载进度条；
- **全仿真档资源占用较高**：三份完整 CSR ≈ 620MB（进程 PSS 实测约 2.5GB），建议 8GB 内存
  设备；Lite 档（默认）约 367MB，4GB 设备可用。两者单步耗时实测几乎相同（~60-80ms，
  预算 100ms——CSR 按行遍历使耗时只随放电神经元的边数增长，与总边数基本无关）；
- **仍非"真涌现"**：MaleCNS 补齐了腹神经索，六条腿/翅运动群首次有了真实接线
  （FAFB 时代为 0），调制升级为六路；但行为骨架仍是内驱力 + 状态机，
  连接组放电是调制而非决策——连接组是接线图，不等于"会思考的大脑"；
- **腿部动画是近似**：六腿为刚性段绕基节枢轴的小幅交替摆动（近似三角步态），
  非真关节链骨骼动画；口器动画为下压点动；翅膀收展/拍动为代码驱动；
- 青蛙没有碰撞（会跳过石块与树干）；地形为平面圆盘（无起伏）；
- 功能群映射：约 47% 神经元由规则表直接命名归群，其余按 superclass 兜底进
  GENERIC_*（管线 `--report` 可查，规则表可持续迭代）。

---

## 许可与数据合规

- **本项目代码**：[MIT License](LICENSE)。
- **随包分发的 MaleCNS v1.0 连接组数据**：**CC BY 4.0**（署名即可，允许商用）——
  来源 HHMI Janelia 等，https://male-cns.janelia.org/ ；
- **随包分发的 NeuroMechFly 果蝇重建网格**：**Apache License 2.0** ——
  NeLy-EPFL，https://github.com/NeLy-EPFL/NeuroMechFly ；
- **场景素材**：Quaternius「Ultimate Stylized Nature」与 Kenney「Nature Kit」均为
  CC0 1.0 公有领域（贴图不入包）；
- **仓库内 legacy 的 FlyWire FAFB 派生文件**（`tools/data/*`，仅供回退管线，不随包分发）：
  CC BY-NC 4.0 非商用 —— 详见 [`THIRD-PARTY-NOTICES.md`](THIRD-PARTY-NOTICES.md)。

## 致谢

- **HHMI Janelia（Fly EM Project）与 Google Research 等** —— MaleCNS v1.0
  雄性果蝇完整中枢神经系统连接组（166,691 神经元，脑 + 视叶 + 腹神经索，2026）
- **NeLy-EPFL「NeuroMechFly」**（Apache-2.0）—— 真实果蝇 CT 重建的分部件模型，
  本项目的高精度果蝇即基于它装配
- **FlyWire 联盟** —— FAFB 雌性全脑连接组（本项目的起点数据）
  （Dorkenwald, S., et al. *Nature* 634, 124–138 (2024)）
- **[snedea/flybrain](https://github.com/snedea/flybrain)**（MIT）—— 行为语义与
  LIF 仿真的复刻蓝本
- **[heyseth/worm-sim](https://github.com/heyseth/worm-sim)** —— 连接驱动虚拟生物的开创性实践
- **[google/neuroglancer](https://github.com/google/neuroglancer)**（Apache-2.0）—— FlyWire 官方查看器内核
- **华为官方 Graphics3D 示例** —— 相机 `lookAt` 实现方式参考

> 本项目仅用于科普演示，不构成任何科学结论。
