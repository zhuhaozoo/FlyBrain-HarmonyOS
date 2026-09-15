# 果蝇大脑 · FlyBrain for HarmonyOS

> 把 2024 年 FlyWire 的**完整成年果蝇脑连接组**（139,255 个神经元 / 2,698,236 条突触连接）
> 跑在鸿蒙手机上：在 3D 场景里观察一只果蝇的自主活动，端侧的 LIF 神经仿真实时放电，
> 行为由真实连接的信号传导驱动。

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-HarmonyOS-blue.svg)](https://developer.huawei.com/consumer/cn/)
[![API](https://img.shields.io/badge/API-23%2F24-green.svg)](https://developer.huawei.com/consumer/cn/)

---

## 这是什么

2024 年，FlyWire 联盟在《Nature》发表了**首张完整的成年果蝇全脑接线图** —— 约 139,255 个神经元、
约 5,000 万个突触的完整连接组（FAFB v783）。随后开源社区出现了把它跑在浏览器里的实时仿真项目
[snedea/flybrain](https://github.com/snedea/flybrain)：神经元用泄漏积分放电（LIF）模型在 Web Worker
里实时仿真，果蝇的行为不是脚本写死的，而是从神经连接的信号传导中**涌现**出来的。

这些项目都是网页形态，普通手机用户访问门槛高。本项目把这一体验**复刻到鸿蒙上，做成原生 App** ——
用 ArkTS / ArkUI / ArkGraphics 3D 重写，13.9 万神经元在手机端实时放电。

---

## 功能

### M0 —— 3D 场景与行为状态机 ✅

- 预设 3D 场景（地面圆盘 + 8 块石丘 + 平行光），程序化生成的果蝇模型（15 个子节点、< 5 千面）
- 轨道相机（拖拽改 yaw/pitch、捏合缩放），相机注视点平滑跟随果蝇
- 行为状态机 7 态：漫步 / 理毛 / 休息 / 起飞 / 飞行 / 降落 / 空转，参数集中在 `FlyConfig`

### M1 —— 交互与内驱力 ✅

- **内驱力系统**：饥饿、恐惧、好奇、疲劳，随时间与交互变化
- **新增行为**：惊吓（僵直→逃离）、进食、趴伏、觅食，优先级链对齐上游
  `startle > fly > feed > groom > brace > rest > phototaxis > seek > wander`
- **交互工具**：触碰 / 投喂（最多 5 份食物）/ 聚光（趋光目标）/ 吹风（弱风趴伏、强风惊吓）/ 光照三档
- 点击选点用已知相机参数手工反投影求交，不依赖 raycast，稳定且与引擎版本无关

### M2 —— 真实连接组 3D 大脑可视化 ✅

- 读取真实神经元坐标与分类，把 **139,255 个神经元**归一化成脑形点云（~1.6 半径）
- 按 5 组功能分区着色并可单独显隐：
  视觉 77,873 / 感觉 16,938 / 中央 44,254 / 运动 110 / 内分泌 80
- 独立页面，自动慢速自旋（可停）+ 分组图例

### M3 —— 端侧 LIF 神经仿真（涌现行为）✅

- **BrainWorker**（ArkTS Worker）忠实移植上游 `sim-worker.js` 的 LIF 模型：
  泄漏 0.95 / 阈值 1.0 / 不应期 3 / 权重缩放 0.15 / 10Hz tick，含按群重排（CSR）+ 群门控
- **ConnectomeDriver** 把 App 状态映射为对**真实感觉神经群**的持续刺激
  （食物气味 → 嗅觉食物群、触碰 → 刚毛 + 嗅觉危险群、风 → Johnston 器、光照 → 视觉群、
  饥饿/疲劳 → 驱动群），再把运动群放电汇总成行为累积量
- 真机实测：`ready N=139255 edges=2698236 groups=61`，LIF 稳定运行在 10Hz
  （单 tick 61~78 ms，预算 100 ms），每 tick 约 30+ 神经元放电

### M4 —— 场景丰富化与玩法（设计完成，待实现）📋

昼夜循环、河流树木、生命值、捕食者青蛙等，详见
[`docs/场景与玩法设计-M4.md`](docs/场景与玩法设计-M4.md)。

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

签名写回后**不会被提交进仓库**，机制见下一节。

### 1.1 签名配置为什么不入库

HarmonyOS 的签名配置只能放在工程级 `build-profile.json5` 里（没有独立的本地签名文件，
官方排错指引 `00304035` 的做法也是「清空该字段后重新签名」），而这个文件本身要进版本库。
为了既让本地构建可用、又不把本机路径与签名口令推到公开仓库，本仓库用了一个 Git **clean filter**。

拉取仓库后**执行一次**即可：

```bash
node tools/setup-local-git.mjs
```

它做两件事（配置只写在本仓库 `.git/` 下，不进版本库，也不影响其它工程）：

| 机制 | 作用 |
|---|---|
| clean filter `strip-signing` | 提交时自动从 `build-profile.json5` 剔除 `signingConfigs` 与 `products[].signingConfig`，**工作区文件保持原样**，本地构建照常可用。并标记为 `required`，过滤失败时提交直接报错，不会退化成「原样提交」 |
| `pre-commit` 钩子 | 兜底扫描暂存区，命中签名凭据或本机隐私信息（Windows 用户目录绝对路径、HarmonyOS 证书目录下的实际路径、局域网 IP 等）就拦下提交 |

所以**不需要在每次提交前手动删签名配置** —— DevEco 反复写回签名信息也不会污染仓库。

提交前想确认这次确实没带上签名，可以看暂存区的版本：

```bash
git add -A
git diff --cached -- build-profile.json5     # 看不到 signingConfigs 即正常
```

也可单独跑一次全库扫描：

```bash
node tools/check-no-secrets.mjs --all
```

> `setup-local-git.mjs` 必须在本机跑一次：Git 出于安全考虑不允许把 filter 与钩子的定义随仓库分发，
> 所以这两项只能在本地安装。刚 `clone` 下来还没跑过的仓库是「没有防护」的，请先执行它再开始改代码。


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

所有资源均由**零依赖 Node 脚本程序化生成**，不含任何第三方版权素材：

```bash
# 生成 3D 世界（地面 + 石丘 + 果蝇模型）→ rawfile/gltf/world.glb
node tools/gen_world_glb.mjs

# 生成 139,255 神经元的脑点云 → rawfile/gltf/brain.glb
# 输入：tools/data/coordinates.csv 与 tools/data/classification.csv（需先解压 .gz）
node tools/gen_brain_glb.mjs
```

`tools/data/` 下随仓库分发了 FlyWire 派生数据的**压缩源文件**（`.gz`），
而生成脚本读取的是**解压后**的 `.csv`（解压产物不入库，见 `.gitignore`），因此首次运行前请先解压：

```bash
gunzip -k tools/data/coordinates.csv.gz tools/data/classification.csv.gz
```

连接组二进制同理（`connectome.bin.gz` → `connectome.bin`）：仓库已随包提供
`entry/src/main/resources/rawfile/connectome.bin`，仅在需要重新生成时才要解压。

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
│       │   │   ├── FlyTypes.ets       # 状态枚举、姿态类型
│       │   │   ├── FlyConfig.ets      # 全部行为参数 + 全局单例
│       │   │   ├── FlyBrain.ets       # 内驱力 + 状态机 + 边界回转
│       │   │   └── ConnectomeDriver.ets  # 连接组仿真驱动器（主线程侧）
│       │   ├── scene/             # 渲染层
│       │   │   ├── SceneManager.ets   # 场景/相机/光照/节点查找
│       │   │   └── FlyRenderer.ets    # 姿态写入节点、翅膀拍动
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
| [`docs/果蝇大脑App开发文档.md`](docs/果蝇大脑App开发文档.md) | 主文档：背景、方案选型、架构分层、M0~M3 实施记录 |
| [`docs/ArkTS-ArkUI易错总结.md`](docs/ArkTS-ArkUI易错总结.md) | **强烈推荐阅读**：25 条实战踩坑（编译错误 / 运行时行为 / HDS 组件 / 3D 渲染），每条含「现象 → 原因 → 正确写法」 |
| [`docs/场景与玩法设计-M4.md`](docs/场景与玩法设计-M4.md) | M4 场景与玩法设计 |
| [`AGENTS.md`](AGENTS.md) | AI 编码助手协作规则（编码前置要求、构建约定） |

---

## 已知限制

- **必须真机运行**：`Component3D` 在 DevEco 预览器中不支持渲染；
- **冷启动较慢**：场景加载与引擎初始化约 10~20 s，暂无进度反馈；
- **仿真性能**：连接组模式下单 tick 约 70 ms，逼近 100 ms 预算；活跃群增多时可能需降频或分帧；
- **M3 运动群数据稀疏**：多数运动群放电为 0，因此"涌现行为"目前是**混合驱动**（内驱力 + 仿真），
  完全涌现需等上游数据完善或引入行为判读网络；
- 果蝇无骨骼动画（翅膀拍动、颠簸为代码驱动）；石块造型简陋。

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
