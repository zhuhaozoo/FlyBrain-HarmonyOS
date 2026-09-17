# 第三方组件与数据声明（Third-Party Notices）

本项目（果蝇大脑 FlyBrain）自身代码以 **MIT License** 发布（见 `LICENSE`）。
但项目**移植/参考了第三方代码**，并**分发了第三方科学数据的派生文件**，
这些部分的版权与许可归原权利人所有，条款如下。分发本仓库或其派生作品时请一并保留本文件。

---

## 1. 代码移植与参考

### 1.1 snedea/flybrain —— MIT License

- 仓库：https://github.com/snedea/flybrain
- 许可：MIT License，Copyright (c) 2017 Seth Miller

本项目**移植/改写**了该项目的以下部分，相关源文件头部注释中已标注来源：

| 本项目文件 | 来源 |
|---|---|
| `entry/src/main/ets/worker/BrainWorker.ets` | 移植自 `js/sim-worker.js`（LIF 泄漏积分放电仿真） |
| `entry/src/main/ets/behavior/FlyConfig.ets`、`FlyBrain.ets` | 行为参数语义与优先级链沿用 `js/fly-logic.js` |
| `entry/src/main/ets/behavior/ConnectomeDriver.ets` | 神经群编号与刺激映射语义沿用 `neuron_meta.json` / `sim-worker.js` |

MIT 许可原文：

```
MIT License

Copyright (c) 2017 Seth Miller

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

### 1.2 heyseth/worm-sim —— MIT License

- 仓库：https://github.com/heyseth/worm-sim
- 定位：连接驱动虚拟生物的开创性实践，`snedea/flybrain` 的上游项目。
- 本项目**未复制其代码**，仅在设计思路上参考。版权与许可归原作者所有。

### 1.3 google/neuroglancer —— Apache License 2.0

- 仓库：https://github.com/google/neuroglancer
- 本项目**未复制其代码**，仅在"分块 / LOD"大数据渲染思路上参考。版权归 Google LLC 所有。

### 1.4 HarmonyOS_Samples/Graphics3D（华为官方示例）—— Apache License 2.0

- 来源：HarmonyOS 官方 3D 示例工程 `Graphics3D`
- 参考点：`utils/CalcUtils.ets` 的 `lookAt`（正交基 → 旋转矩阵 → 四元数）实现方式。
- 本项目 `entry/src/main/ets/common/Math3D.ets` 为**依据该思路独立编写**，未逐行复制；
  文件头已保留来源声明。版权归华为技术有限公司所有。

---

## 2. 科学数据（⚠️ 非商用许可，请注意）

### 2.1 FlyWire 完整果蝇脑连接组（FAFB v783）—— CC BY-NC 4.0

- 数据来源：FlyWire 联盟 https://flywire.ai ，在线浏览器 https://codex.flywire.ai
- 奠基论文：Dorkenwald, S., Matsliah, A., Sterling, A.R. et al.
  *Neuronal wiring diagram of an adult brain.* **Nature 634, 124–138 (2024)**.
  https://doi.org/10.1038/s41586-024-07558-y
- **数据许可：CC BY-NC 4.0（署名 — 非商业性使用）**，依据官方指引
  https://flywire.ai/guidelines —— "FlyWire's public release data is made available
  under license CC BY-NC 4.0"。

> ⚠️ **重要**：本项目**代码**是 MIT（允许商用），但仓库内随附的 **FlyWire 派生数据**
> 受 CC BY-NC 4.0 约束，**不得用于商业目的**。若你要将本项目用于商业场景，
> 必须自行移除下列派生数据并改用商业许可的数据源。

本仓库中包含的 FlyWire 派生文件：

| 文件 | 说明 |
|---|---|
| `entry/src/main/resources/rawfile/connectome.bin` | 完整连接组二进制（139,255 神经元 / 2,698,236 条边） |
| `entry/src/main/resources/rawfile/gltf/brain.glb` | 由神经元坐标生成的脑点云模型 |
| `tools/data/connectome.bin.gz` | 连接组压缩源文件 |
| `tools/data/coordinates.csv.gz` | 神经元 3D 坐标 |
| `tools/data/classification.csv.gz` | 神经元分类（super_class） |
| `tools/data/neuron_meta.json` | 神经群元数据 |

引用时请署名原始论文与 FlyWire 联盟（App 内「关于」页已包含该署名）。

### 2.2 关于 snedea/flybrain 的分发数据

上述 `tools/data/` 下的数据文件格式与内容源自 `snedea/flybrain` 仓库的 `data/` 目录
（该仓库以 MIT 分发）。数据的**原始权利人仍是 FlyWire 联盟**，因此上述 CC BY-NC 4.0
的非商用约束依然适用。

---

## 3. 本项目自有资产

以下资产由本仓库自带的零依赖 Node 脚本**程序化生成**：

| 文件 | 生成脚本 |
|---|---|
| `entry/src/main/resources/rawfile/gltf/world.glb`（果蝇、青蛙、河流、天空等） | `tools/gen_world_glb.mjs` |
| `entry/src/main/resources/rawfile/gltf/brain.glb` | `tools/gen_brain_glb.mjs`（数据仍受 2.1 约束） |

其中 `world.glb` 内的**树木、岩石、草丛几何**导入自第三方 CC0 素材（见第 5 节），
其余部分（果蝇、青蛙、河流、天空、日月星辰、特效）为程序化生成，属项目自有资产。

---

## 4. 第三方场景素材（CC0 1.0 公有领域）

`world.glb` 中树木 ×3、岩石与卵石、草丛的网格几何导入自 Quaternius
「Ultimate Stylized Nature」系列低多边形模型，许可为 **CC0 1.0（公有领域）**：
允许任意商用、修改、再分发，无需署名。源文件存于 `tools/assets/`
（明细与来源链接见该目录的 `LICENSE-README.md`），仅作生成期几何来源，不打包进 HAP，
素材贴图不随应用分发。

v6 起新增的静态配景（花 / 蘑菇 / 灌木 / 倒木 / 芦苇等）几何导入自 Kenney
「Nature Kit」低多边形素材包，许可同为 **CC0 1.0（公有领域）**，同样只在生成期参与建模。

- 作者：Quaternius（https://quaternius.com ，模型页 https://poly.pizza/u/Quaternius ）
- 作者：Kenney（https://kenney.nl ，素材页 https://kenney.nl/assets/nature-kit ）
- 许可原文：https://creativecommons.org/publicdomain/zero/1.0/

---

## 5. 依赖的开源库

| 库 | 用途 | 许可 |
|---|---|---|
| `@ohos/hypium` | 单元测试框架（devDependency） | Apache License 2.0 |
| `@ohos/hamock` | Mock 框架（devDependency） | Apache License 2.0 |
