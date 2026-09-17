# 赛博果蝇（果蝇大脑）数据升级迁移设计 —— MaleCNS v1.0 全中枢连接组

| 项目 | 内容 |
|---|---|
| 开源地址 | https://github.com/zhuhaozoo/FlyBrain-HarmonyOS |
| 前置版本 | M0~M5-P1（数据集：FlyWire FAFB 雌性全脑，2024；见《果蝇大脑App开发文档.md》） |
| 文档版本 | v1.0（2026-09-17） |
| 本文档范围 | 把端侧连接组仿真与脑可视化从「FAFB 雌性全脑 139,255 神经元」整体升级到「MaleCNS v1.0 雄性全中枢 166,691 神经元（脑 + 视叶 + 腹神经索）」：设计 + 数据管线 + 运行时改造 + 实施与验收。**本文档是升级的规划与契约；实现进度见 §8。** |

---

## 0. 一句话结论

**当前 App 不是基于 MaleCNS 做的**（现有数据是 2024 年 FlyWire 的 FAFB 雌性全脑）；本文档规划并实现向 **MaleCNS v1.0**（HHMI Janelia 主导、谷歌等合作，2026-06 发布 v1.0、2026-09 发 Cell 论文，**CC-BY 4.0 可商用**）的完整迁移。迁移后最大的能力变化：**腹神经索（VNC）入列，腿/翅/下行的真实运动群不再为 0**——此前"走路/飞行不可能从连接组涌现"这一最大科学短板（开发文档 §10.4 第 6 条）具备了被修正的数据基础。

---

## 1. 数据集调研

### 1.1 MaleCNS v1.0 是什么

| 项 | 内容 |
|---|---|
| 物种 / 性别 | 成年黑腹果蝇（*Drosophila melanogaster*），**雄性** |
| 覆盖范围 | **完整中枢神经系统（CNS）**：脑 + 两侧视叶 + 腹神经索（VNC，相当于脊髓） |
| 规模 | **166,691 个神经元**；突触量级为上亿（谷歌博客口径 1.25 亿） |
| 重建 | Fly EM Project（HHMI Janelia）联合剑桥 MRC LMB、Google Research，约十年工作 |
| 时间线 | 2026-02 前后研究预印本出现（FlyGM 等）；**2026-06 发布 v1.0**；2026-09 Cell 论文与公开发布 |
| 许可 | **CC-BY 4.0（署名即可，允许商用）** —— 比 FAFB 的 CC BY-NC 4.0（非商用）明显更宽松 |
| 访问 | male-cns.janelia.org（下载页：images/annotations/synapses/skeletons）；**NeuPrint** 数据集 `male-cns:v1.0`（逐细胞连通性查询/导出）；Clio（注释视图）；NeuronBridge；Cell Type Explorer |

### 1.2 与现役 FAFB 数据集对比（决定迁移收益与工作量的核心表）

| 维度 | FAFB / FlyWire（现役） | MaleCNS v1.0（目标） |
|---|---|---|
| 物种性别 | 雌性成虫 | 雄性成虫 |
| 神经元 | 139,255（脑） | 166,691（脑+视叶+VNC） |
| 突触 / 连接 | ~5,000 万突触 → 聚合 2,698,236 边 | ~1.25 亿突触 → 聚合后预计千万级边（**必须瘦身**，见 §4.5） |
| 运动神经元 | **几乎为 0**（腿 MN_LEG_*、翅 MN_WING_*、DN_FLIGHT 全部 0，位于 VNC 不在数据集） | **有真实 VNC 运动群**（腿/翅/下行通路在列） |
| 感觉群 | 脑内感觉群完整 | 感觉群完整 + VNC 内感觉/运动互连 |
| 数据格式 | snedea/flybrain 派生四件套（本项目 `tools/data/`） | NeuPrint 导出 / 官方下载包（需转换管线） |
| 许可 | CC BY-NC 4.0（非商用） | **CC BY 4.0（可商用）** |
| 我们的四件套对应物 | `connectome.bin.gz` / `neuron_meta.json` / `coordinates.csv.gz` / `classification.csv.gz` | 由新管线从 NeuPrint 导出生成同构产物（§4） |

### 1.3 神经元数量"各种说法"的口径对照（对内对外统一口径用）

3,016 = 2023 幼虫全脑；~2.5 万 = 2020 半脑 hemibrain；**139,255 = FAFB 雌性全脑（我们现役）**；
**166,691 = MaleCNS 雄性全中枢（升级目标）**；视频中的 ~16.5 万 = 各仿真作者预处理后实际运行的子集。
数字都"对"，口径不同；升级后 App 内所有口径（状态行/小窗/关于页）一律以运行时读到的
`neuron_count / edge_count / 数据集标签` 为准（§5.4），不再出现手写死数字。

### 1.4 科学边界（必须继续讲清楚，升级后依然成立）

MaleCNS 补齐的是**接线**（VNC 运动群有了真实神经元与连接），不等于**涌现出走路**：
LIF 放电要调制出步态，仍需要"群 → 行为语义"的映射设计与调参。本项目继续采用
**混合驱动**（状态机骨架 + 连接组调制），升级后调制通道从 4 路扩展为 6 路
（新增：腿群 → 步速/转向、翅群 → 振翅意图，见 §5.3）。 viral 演示（DOOMFLY 等）的性质
（仿真动力学涌现随机按键，非"果蝇在想"）的判断同样适用于本项目，文案不做夸大。

---

## 2. 升级带来的能力变化（用户可感知）

| 能力 | 现状（FAFB） | 升级后（MaleCNS） |
|---|---|---|
| 大脑点云页 | 脑形点云 | **脑 + 腹神经索全中枢点云**（形状更接近真实 CNS） |
| 活跃脑区明细 | 运动 4 群几乎恒静默 | 腿/翅/下行运动群真实放电，明细行有内容 |
| 行为调制 | 4 路（步速/惊吓/理毛/觅食） | **6 路**（+ 腿群调制步速与转向、翅群调制振翅意图） |
| 数据规模口径 | 13.9万 / 270万 | 16.6万 / 实际聚合边数（运行时显示） |
| 许可 | 数据 CC BY-NC（商用需移除） | **CC BY 4.0（商用合规压力解除，仅需署名）** |

---

## 3. 总体方案

### 3.1 核心决策

1. **替换而非并存**：`connectome.bin` / 脑点云整体换成 MaleCNS 产物；旧 FAFB 四件套保留在
   `tools/data/` 作为回退与对照（§9）。理由：App 叙事是"一只果蝇的大脑"，双数据集并存会
   把"群号语义/调参/UI 口径"全部翻倍，收益低。
2. **功能群 code 是稳定契约**：运行时的一切映射（感觉刺激注入、运动群读取、UI 标签）只认
   **群 code 字符串**（如 `MN_LEG_L1`、`OLF_ORN_FOOD`），不认数字群号。数字群号随数据集重排，
   code 跨数据集不变。**新数据集只要补全同 code 的群，运行时代码零改动即可工作**（§5.3 的
   6 路调制自动生效）。
3. **群表去硬编码 → 生成表**：`ConnectomeDriver` 里手写的 `GROUP_SIZES[63]` 与
   `NeuronGroups.ets` 里手写的 63 行表，改为**管线生成的 `NeuronGroupsTable.ets`**
   （继承 M5 设计稿"群号禁止手工硬编码"的原则）。现役 FAFB 表也改由生成物提供，
   **生成内容与现状逐行等价**（迁移前先做等价性验证，见 §4.7）。
4. **二进制格式不变**：`connectome.bin` 布局（u32 N + u32 边数 + 边×(pre,post,f32) + 每神经元
   (u8 region + u16 group)）原样沿用——`BrainWorker` 零改动，规模/群数全部数据驱动。
5. **尺寸预算**：聚合后边数控制在 **≤ 600 万**（bin ≈72MB、内存 CSR ≈72MB，约为现役 2.2 倍，
   真机可承受；超限用 §4.5 的两级瘦身），HAP 增量预期 +25~35MB。

### 3.2 数据流总览（升级后）

```
NeuPrint male-cns:v1.0（token）
   │  tools/fetch_malecns.py（参考脚本，导出 neurons.csv / connections.csv）
   ▼
tools/data_malecns/            # 中间数据（不入库，.gitignore）
   │  tools/build_connectome_malecns.mjs
   │   ├─ 功能群映射（规则表，附录 A）→ 每神经元 (region, group)
   │   ├─ 聚合 (pre,post) → 有符号权重 → 两级瘦身（§4.5）
   │   ├─ 输出 connectome.bin（格式不变）
   │   ├─ 输出坐标/分类 CSV（与旧四件套同格式，供 gen_brain_glb 直接消费）
   │   └─ 输出群表定义 → tools/gen_neuron_groups.mjs
   ▼
运行时资源（rawfile/connectome.bin + gltf/brain.glb / brain_mini.glb）
   + 生成表 ets/behavior/NeuronGroupsTable.ets、ets/behavior/BrainGroups.ets
   ▼
BrainWorker（零改动）/ ConnectomeDriver（按 code 找群）/ 脑点云页 / 状态行口径
```

---

## 4. 数据管线设计（tools/）

### 4.1 目录契约

```
tools/data_malecns/          # 中间数据，.gitignore（同 tools/data 的处理方式）
  neurons.csv               # bodyId,type,super_class,class,side,x,y,z（每神经元一行）
  connections.csv           # bodyId_pre,bodyId_post,weight[,nt_type]（已按神经元对聚合）
tools/fetch_malecns.py      # 从 NeuPrint 导出上述两份 CSV（参考脚本，需免费 token）
tools/build_connectome_malecns.mjs   # 主管线（零依赖 Node ≥18，可 --sample 自测）
tools/gen_neuron_groups.mjs # 由管线产物生成 ets 群表（legacy 模式可独立重放现役表）
tools/analyze_connectome.mjs# bin 分析器（校验 N/边数/群分布，新旧数据通用）
```

### 4.2 输入格式（管线接受的列名是"别名宽容"的）

- `neurons.csv`：id 列接受 `bodyId|root_id|id`；类型列接受 `type|cell_type`；分类列接受
  `super_class|superClass`、`class`；侧别 `side`；坐标 `x,y,z` 或 `somaLocation` 的 `(x,y,z)`。
- `connections.csv`：`bodyId_pre|pre`、`bodyId_post|post`、`weight|syn_count`；
  `nt_type` 可缺省（缺省时全部按兴奋性正权重处理，见 §4.6 权重口径）。

### 4.3 功能群映射（管线核心）

- **附录 A 的规则表**（有序，首条命中为准）：对每个神经元的 `type + class + super_class`
  拼接串做正则匹配，映射到 **稳定 code 的功能群**。规则覆盖五大感觉系（视/嗅/机械/温湿/味）、
  中央系（蘑菇体/中心体/侧角/食道下）、驱动系、运动系（VNC 的腿/翅/口器/头/腹运动神经元、
  下行 DN_*、上行 AN_*、步态节律）。
- **未命中兜底**：按 `super_class` 归入 `GENERIC_*`（感觉/中央/运动），保证 166,691 个神经元
  **每个都有群**；管线输出**覆盖率报告 + Top 未命中类型清单**，用于迭代规则表
  （`--report` 模式）。
- **code 集合 = 现役 63 code 的超集**：新增 VNC 专属 code（`MN_LEG_L1/R1...`、`MN_WING_L/R`、
  `DN_FLIGHT`、`AN_*` 等）补齐现役数据里为 0 的群；**现役 14 个关键刺激/读取群的 code
  一字不改**（`VIS_R1R6 / VIS_ME / VIS_LO / VIS_LPTC / OLF_ORN_FOOD / OLF_ORN_DANGER /
  MECH_BRISTLE / MECH_JO / DRIVE_HUNGER / DRIVE_FATIGUE / VNC_CPG / MN_PROBOSCIS /
  MN_HEAD / MN_ABDOMEN`）。

### 4.4 聚合与排序（与 BrainWorker 的 CSR 兼容）

- 边按 `(pre, post)` 聚合：`weight = Σ syn_count`，符号按 `nt_type`（兴奋 + / 抑制 −；
  缺省全正）。**输出前按 pre 升序排序**（与现役 bin 一致，worker 按行计数建 CSR）。
- 二进制布局逐字节沿用现役格式（§3.1 第 4 条）。

### 4.5 尺寸瘦身（可选；v7.1 起默认**全量不瘦身**）

真机实测推翻了“tick 成本随总边数增长”的担心：CSR 按行遍历使单步耗时只随**放电神经元的
边数**增长，与总边数基本无关（25,563,197 边全量与 400 万瘦身版同为 ~76ms/步）。
真正的代价是 Worker 内存（约 206MB/只，三只 ≈ 620MB）与包体（bin 311MB）。因此：

- **默认全量**：保留 165,122 个 Traced 神经元之间全部 25,563,197 条聚合连接——
  “完整连接组”口径成立；
- 瘦身两级保留为**低端机可选开关**：
  1. `--min-weight W`：聚合权重 < W 的边丢弃（弱连接在 ±0.15 归一化下贡献近零）；
  2. `--top-k K`：每个 pre 神经元只保留权重最大的 K 条出边；
  3. `--max-edges M`：仍超限时按权重全局降序截断并显著告警。
  报告给出瘦身前后：边数、权重直方图分位数、每群入边保留率。
- 配套的加载安全（v7.1）：rawfile 读取在 Worker 线程 fd 分块进行（主线程零大块工作）；
  多驱动器“上一个 ready 再加载下一个”（waitReady），避免 CSR 峰值叠加。

### 4.6 权重口径

现役数据：上游 build_connectome.py 以突触数当权重、按 nt_type 定符号；`BrainWorker` 读入后
按最大绝对值归一化到 ±0.15——**归一化在 worker 侧，管线只写有符号计数**，MaleCNS 管线照此办理。
MaleCNS 若导出无 nt 信息，先全正（报告注明），后续拿到 nt 分类可重跑管线无缝替换。

### 4.7 等价性验证（迁移前置门槛）

1. `tools/analyze_connectome.mjs` 读取现役 bin：必须输出 `N=139255 edges=2698236 maxGroupId=60`
   （实测已通过），并校验按 pre 有序、群号越界为零；
2. `gen_neuron_groups.mjs`（legacy 模式）生成的 `NeuronGroupsTable.ets` 与手写
   `NeuronGroups.ets` 的 63 行**逐字段一致**（id/code/zh/region/count 全等）；
3. 替换 MaleCNS 产物后：worker ready 消息的 `groups` 数 = 群表行数中"最大群号 + 1"；
   每群 neuron_count 总和 = N；抽查 14 个关键 code 的 count 与管线报告一致。

### 4.8 点云管线（gen_brain_glb.mjs 扩展）

- 消费新管线的同构 CSV，坐标归一化逻辑不变（VNC 坐标参与归一化，点云呈"脑+腹索"形）；
  提供 `--brain-only` 过滤（只画脑，作对照）。
- 顺带补齐两笔欠账：`brain_mini.glb`（1/4 抽稀小窗演示）从 `_dbg.mjs` 合入主脚本；
  新增生成 `ets/behavior/BrainGroups.ets`（点云 5 分组的名称/节点名/神经元数），
  `BrainPage` 改为表驱动（§5.4）。

---

## 5. 运行时改造

### 5.1 生成表模块（新增，均带"自动生成勿手改"头注释）

| 文件 | 内容 |
|---|---|
| `ets/behavior/NeuronGroupsTable.ets` | `DATASET_LABEL`（数据集中文名）、`GROUP_ROWS`（id/code/zh/region/count）、由 `gen_neuron_groups.mjs` 生成 |
| `ets/behavior/BrainGroups.ets` | 点云分组表（zh/nodePath/count），由 `gen_brain_glb.mjs` 生成 |

### 5.2 `NeuronGroups.ets`（手写壳）

- 保留 `NeuronGroupInfo` 与 `groupLabel/groupRegion` 对外接口（调用方零改动）；
- 内部改为消费 `NeuronGroupsTable.GROUP_ROWS`；
- 新增 `findGroupByCode(code)` / `groupCountAt(id)` / `groupOffsetOf(id)` / `datasetLabel()`；
  code 未命中返回 -1（运行时对 -1 群一律跳过刺激/读取）。

### 5.3 `ConnectomeDriver.ets` 去硬编码

- 删除 `GROUP_SIZES[63]` 与 14 个 `G_*` 数字常量；偏移量改由群表计数前缀和现算；
- 刺激/读取目标全部经 `findGroupByCode` 解析（code 是稳定契约，跨数据集不变）；
- 调制通道 4 → **6 路**：`connWalk` 步速（`VNC_CPG` + 新增腿群 `MN_LEG_L/R*` 合计），
  新增 `connTurn`（左右腿群放电差 → 转向偏置）与 `connWing`（翅群 `MN_WING_L/R` → 振翅意图，
  叠加到 `FlyRenderer` 的 excited 振翅通道）；`FlyBrain.setConnectomeDrive` 签名同步扩展，
  阈值入 `FlyConfig`（`connTurnG / connWingG`）；
- `ConnectomeDrive` 增加 `dataset: string`，`ready` 后随 stats 一起供 UI 口径显示。

### 5.4 UI 口径动态化（消灭手写死数字）

- `ScenePage` 大脑小窗「脑规模」行：改由 `drivers[0]` 的 `neurons/edges/dataset` 动态拼接，
  并写入 AppStorage `fy_brain_label`；
- `BrainPage`：分组图例从 `BrainGroups.ets` 生成（名称/计数/节点名全部来自生成表）；
- `AboutPage`：「这是什么/科学数据来源」卡片改为引用 `fy_brain_label`（默认 FAFB 文案兜底），
  许可说明补 CC-BY 4.0 条目。

### 5.5 性能与回退

- `BrainWorker` 无改动（群数、内存全部随数据走）；tick 预算红线维持 ≤100ms，
  MaleCNS 首跑若超限，优先增大 §4.5 瘦身力度而不是改 worker；
- 回退：把 `tools/data/` 四件套重新走一遍 legacy 生成命令（两脚本都支持 `--legacy`）
  即可 5 分钟还原现役包体。

---

## 6. 实施阶段

| 阶段 | 内容 | 状态 |
|---|---|---|
| P0 代码与管线 | 本文档 + 全部代码：管线/生成器/分析器/运行时改造/UI 动态化（以 FAFB 等价内容自测） | ✅ 随本文档完成 |
| P1 取数 | 官方 flat-connectome 批量直链（免登录）下载三件套 + feather→CSV 转换 | ✅ 2026-09-17 完成 |
| P2 生成与验收 | 映射规则两轮迭代 → connectome.bin/群表/点云生成 → 分析器校验通过 | ✅ 2026-09-17 完成 |
| P3 行为调参 | 6 路调制阈值真机调参，更新易错总结/开发文档 | ⏳ 待真机 |

---

## 7. 验收标准

1. `analyze_connectome.mjs` 对新 bin：`N≈166,691`（以实际导出为准）、边数 ≤600 万、按 pre 有序、
   无越界群号；14 个关键 code 全部存在且 count>0（其中 8 个运动/下行群 FAFB 下为 0，
   MaleCNS 下应有真实数量）；
2. 群映射覆盖率 ≥95%（未命中全部落入 GENERIC_* 且报告可解释）；功能群 code 与现役契约一致；
3. 真机：仿真开启 ready 日志规模正确；tick ≤100ms；大脑页显示"脑+腹索"点云且 5 组可显隐；
   小窗/状态行/关于页的规模口径全部来自运行时数据（无手写数字）；
4. 新增 6 路调制可观察：行走中腿群放电率上升时步速/转向有可感变化，振翅意图通道生效；
5. 回退演练：legacy 模式重生成后 App 行为与升级前一致；
6. 许可合规：关于页含 MaleCNS（CC BY 4.0）与 Janelia/Google 署名。

---

## 8. 实施记录（P0~P2 完成，2026-09-17）

**P1/P2 已由 AI 直接执行完毕**（发现 male-cns.janelia.org 提供免登录的 Google Storage
批量直链，无需 NeuPrint token；本机 Bash 可直连 GCS）。实际取数路径与规划略有差异：
下载的是官方 `flat-connectome` 三个 Feather 文件（annotations 14.5MB / neurotransmitters
43MB / connectome-weights 1.05GB），用 `tools/data_malecns/convert.mjs`（node +
apache-arrow + lz4js，流式逐批读取）转成管线的 neurons.csv / connections.csv——
比规划中的 NeuPrint 导出更快更省事；`fetch_malecns.py` 保留作为逐神经元查询的备选路径。

**P0 代码（随本文档完成）**：

- 管线：`tools/build_connectome_malecns.mjs`（流式读取 GB 级连接表；`--sample` 合成数据
  端到端自测通过；`--report` 覆盖率/瘦身报告）、`tools/gen_neuron_groups.mjs`（legacy/malecns
  双模式，legacy 产物与旧手写表逐字段等价）、`tools/analyze_connectome.mjs`、
  `tools/fetch_malecns.py`（NeuPrint 备选取数）；
- 生成表：`ets/behavior/NeuronGroupsTable.ets`、`ets/behavior/BrainGroups.ets`；
- 运行时：`ConnectomeDriver` 去硬编码 + 6 路调制；`BrainPage` 表驱动；`ScenePage/AboutPage`
  规模口径全部来自运行时数据；`gen_brain_glb.mjs` 合入 brain_mini 输出与 BrainGroups 生成。

**P2 生成结果（实测）**：

- neurons=165,122（status=Traced，与公开仿真的"16.5 万"口径一致）；聚合连接 2,556 万条，
  min-weight≥3 后 1,051 万，top-k(300) 后 991 万，按 600 万预算截断最弱边；
- connectome.bin 72.5MB（N=165,122 edges=6,000,000 groups=43，按 pre 有序，回读校验通过）；
- 群映射：规则直接命中 47%，其余按 superclass 兜底进 GENERIC_*；**六条腿运动群
  MN_LEG_L1/R1/L2/R2/L3/R3 = 78/75/79/79/74/72 全部激活**，翅 MN_WING_L/R = 7/7，
  MN_ABDOMEN 194 / MN_PROBOSCIS 12 / MN_HEAD 15，MECH_BRISTLE 5,084，MB_KC 4,064；
  motor 区合计 2,792（FAFB 时代仅 76）；
- brain.glb 13.8MB（164,908 神经元点云）、brain_mini.glb 3.4MB（41,229）；
- HAP 47MB → 91.7MB（bin 压缩后增量 ~40MB）。

**待 P3 真机调参**：感觉群规模比 FAFB 大（如 MECH_BRISTLE 1,927→5,084），自然放电率上升，
`connStartleG/connWalk/connTurnG/connWingG` 等阈值大概率需要真机回调；
`FlyConfig` 的 edge/conn 参数就是为此集中预留的。

---

## 9. 兼容与回退

- 现役 FAFB 四件套与生成命令全部保留；`gen_neuron_groups.mjs`（默认 legacy）、
  `gen_brain_glb.mjs`（默认读 `tools/data/`）随时可还原整个数据层；
- 运行时对"表里不存在的 code / count=0 的群"一律静默跳过（与现役数据里 8 个 0 群共存的事实
  一致），因此**任何中间状态的群表都是可运行的**，不存在"半升级崩掉"的形态。

---

## 10. 风险与对策

| 风险 | 对策 |
|---|---|
| MaleCNS 导出体积远超预期 | §4.5 两级瘦身 + `--max-edges` 硬上限；先 `--report` 看分布再定参 |
| 细胞类型命名与规则表匹配率低 | 管线输出 Top 未命中类型清单，迭代附录 A；兜底 GENERIC_* 保证可运行 |
| 群数暴涨拖慢 worker 门控 | 功能群 code 集合是封闭集（~70），不是每细胞类型一群；门控粒度不恶化 |
| VNC 坐标系与脑不连续，点云畸形 | 归一化按整体包围盒；提供 `--brain-only` 对照；必要时按 neo 坐标分段缩放 |
| tick 超预算 | 边数预算与 `--min-weight` 调参优先；确需再动 worker（分帧/降频） |
| 数据口径宣传失实 | 全部 UI 口径来自运行时 `ready/stats`（§5.4），文档口径以 §1.3 对照表为准 |

---

## 附录 A：功能群映射规则表（初版，有序首中）

> 规则作用于 `type + ' ' + class + ' ' + super_class` 的小写拼接串；`re` 为正则，`code` 为
> 稳定功能群 code。运行前管线会打印每条规则的命中数，0 命中的规则在报告中高亮。

| 序 | re（大小写不敏感） | code | 说明 |
|---|---|---|---|
| 1 | `(^|_)(r1r6|r[1-6]_?photoreceptor)` | VIS_R1R6 | 外周光感受器 R1-R6 |
| 2 | `(^|_)(r7|r8)` | VIS_R7R8 | R7/R8 |
| 3 | `medulla|mi[0-9]|tm[0-9]|tm[y]|intrinsic` + `optic` | VIS_ME | 髓质 |
| 4 | `lobula` | VIS_LO | 小叶 |
| 5 | `lobula.?plate|lptc|t4|t5` | VIS_LPTC | 小叶板 |
| 6 | `lc[0-9]|l?c(n|s|c)` | VIS_LC | 板层投射 |
| 7 | `orn.*food|fruit.?smell` | OLF_ORN_FOOD | 嗅觉食物（规则迭代入口） |
| 8 | `orn.*danger|co2` | OLF_ORN_DANGER | 嗅觉危险 |
| 9 | `local.*antennal|ln` | OLF_LN | 嗅觉局部中间 |
| 10 | `projection.*antennal|un=?pn|pn` | OLF_PN | 嗅觉投射 |
| 11 | `bristle|mechanosensory` | MECH_BRISTLE | 刚毛机械 |
| 12 | `johnston|jo[_-]` | MECH_JO | 江氏器 |
| 13 | `chordotonal` | MECH_CHORD | 弦音器 |
| 14 | `antennal.*mech` | ANTENNAL_MECH | 触角机械 |
| 15 | `warm|thermo.*warm` | THERMO_WARM | 温暖 |
| 16 | `cool|thermo.*cool` | THERMO_COOL | 冷 |
| 17 | `noci|pain` | NOCI | 痛觉 |
| 18 | `kenyon|mb.*intrinsic|mpr|apr` | MB_KC | 蘑菇体 |
| 19 | `anterior.*paired|apl` | MB_APL | APL |
| 20 | `mbon.*(app|reward)|appetitive.*mbon` | MB_MBON_APP | 食欲输出 |
| 21 | `mbon.*(av|avoid|punish)` | MB_MBON_AV | 厌恶输出 |
| 22 | `dan.*(rew|app)|ppl1|pam` | MB_DAN_REW | 奖赏多巴胺 |
| 23 | `dan.*(pun|av)` | MB_DAN_PUN | 惩罚多巴胺 |
| 24 | `lateral.?horn.*app|lh.*app` | LH_APP | 侧角食欲 |
| 25 | `lateral.?horn.*av` | LH_AV | 侧角厌恶 |
| 26 | `epg|ellipse` | CX_EPG | 中心体 EPG |
| 27 | `pfn` | CX_PFN | PFN |
| 28 | `fan.?shaped|fc[0-9]` | CX_FC | 扇形体 |
| 29 | `hd.*cell|head.?direction` | CX_HDELTA | 头方向 |
| 30 | `subesophageal.*(feed|sensory)` | SEZ_FEED | 食道下进食 |
| 31 | `subesophageal.*groom` | SEZ_GROOM | 食道下理毛 |
| 32 | `subesophageal.*water` | SEZ_WATER | 食道下水 |
| 33 | `gr[0-9a-z]*sweet|sugar` | GUS_GRN_SWEET | 甜味 |
| 34 | `gr[0-9a-z]*bitter` | GUS_GRN_BITTER | 苦味 |
| 35 | `gr[0-9a-z]*water` | GUS_GRN_WATER | 水味 |
| 36 | `descending` | GNG_DESC | 下行 |
| 37 | `clock|pdf` | CLOCK_DN | 生物钟 |
| 38 | `hunger|satiety` | DRIVE_HUNGER | 饥饿驱动 |
| 39 | `fear|threat` | DRIVE_FEAR | 恐惧驱动 |
| 40 | `fatigue|sleep` | DRIVE_FATIGUE | 疲劳驱动 |
| 41 | `curiosity|novelty` | DRIVE_CURIOSITY | 好奇驱动 |
| 42 | `groom.*drive` | DRIVE_GROOM | 理毛驱动 |
| 43 | `dn.*walk|walking.*descending` | DN_WALK | 下行步行 |
| 44 | `dn.*flight|flight.*descending` | DN_FLIGHT | 下行飞行（FAFB 为 0，MaleCNS 应有量） |
| 45 | `dn.*turn` | DN_TURN | 下行转向 |
| 46 | `dn.*back` | DN_BACKUP | 下行后退 |
| 47 | `dn.*startle` | DN_STARTLE | 下行惊吓 |
| 48 | `cpg|central.?pattern|gait` | VNC_CPG | 步态节律 |
| 49 | `mn.*leg.*l1|leg.*mn.*l1` | MN_LEG_L1 | 左前腿运动 |
| 50-54 | 同上 L1/R1/L2/R2/L3/R3 组合 | MN_LEG_* | 腿运动 ×6 |
| 55 | `mn.*wing.*l|wing.*mn.*l` | MN_WING_L | 左翅运动 |
| 56 | `mn.*wing.*r|wing.*mn.*r` | MN_WING_R | 右翅运动 |
| 57 | `mn.*proboscis|proboscis.*mn` | MN_PROBOSCIS | 口器运动 |
| 58 | `mn.*head|head.*mn` | MN_HEAD | 头部运动 |
| 59 | `mn.*abdomen|abdominal.*mn` | MN_ABDOMEN | 腹部运动 |
| 60 | `sensory`（super_class） | GENERIC_SENSORY | 兜底·感觉 |
| 61 | `motor`（super_class） | GENERIC_MOTOR | 兜底·运动 |
| 62 | `endocrine|secretory` | GENERIC_DRIVES | 兜底·内分泌/驱动 |
| 63 | 其余 | GENERIC_CENTRAL | 兜底·中央 |

> 新增 code 相对现役 63 群不改变任何既有 code 语义；`GENERIC_DRIVES` 沿用现役
> "未细分·驱动" 的 code。规则表在本文件维护，命中率为 0 的规则在 `--report` 中高亮后
> 再行删改，避免一次拍脑袋定死。
