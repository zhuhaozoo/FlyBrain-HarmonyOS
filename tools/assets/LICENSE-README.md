# tools/assets —— CC0 场景素材来源与许可说明

本目录存放 `tools/gen_world_glb.mjs` 生成 `world.glb` 时导入几何所用的**源素材**（glb），
来自两个免费低多边形素材库，许可均为 **CC0 1.0（公有领域）**——
可商用、可修改、可再分发，**无需署名**（本项目仍在关于页与 THIRD-PARTY-NOTICES.md 中致谢）。
素材内的**贴图不进入 world.glb**：生成脚本只提取几何（POSITION/NORMAL + indices），
Quaternius 素材的贴图仅用于生成期取平均色与按 alpha 裁剪透明叶片卡片
（Kenney Nature Kit 的模型本身不带贴图，是纯材质色，直接按材质名换成工程自己的材质色）。

## 1. Quaternius「Ultimate Stylized Nature」

| 文件 | 内容 | 来源页面（CC0 标识见页面 "Public Domain (CC0)" 链接） |
|---|---|---|
| `qn_trees.glb` | NormalTree_1..5 五个树变体（树干/树叶两个 primitive） | https://poly.pizza/m/etFGNvsiFv （Trees，Ultimate Stylized Nature Pack） |
| `qn_rock.glb` | 岩石 Resource_Rock_1（无贴图纯色） | https://poly.pizza/m/RtLRqYjfMs （Rock，Ultimate Stylized Nature Pack） |
| `qn_rock_large.glb` | 大岩石 Rock_Large_1 | https://poly.pizza/m/54jZKTAt5p （Rock Large，同系列） |
| `qn_rocks.glb` | 小岩石 Rock_3（无贴图纯色） | https://poly.pizza/m/OQvi8PIZ40 （Rocks，同系列） |
| `qn_grass.glb` | 草丛 Grass_Large_Extruded + Grass_Small | https://poly.pizza/m/UGTOzcO3P2 （Grass，同系列） |

- 作者主页：https://quaternius.com （Patreon 支持者维护的免费 CC0 素材库）
- 下载日期：2026-09-15（poly.pizza 的 Download GLB 按钮）

## 2. Kenney「Nature Kit」（v6 新增静态配景）

来源包：Nature Kit（2.1），下载自 OpenGameArt 的官方镜像页
https://opengameart.org/content/nature-kit （10.5 MB，与 kenney.nl 的
https://kenney.nl/assets/nature-kit 为同一套 CC0 素材；源 ZIP 不入库，只挑下列 12 个模型）。
这批模型**不带贴图**，材质名为 `grass` / `colorRed` / `woodBark` 等语义名，
生成脚本按材质名映射到工程自有材质色（不取色、不采样）。

| 文件 | 对应素材 | 用途 | 面数（导入后含双绕序） |
|---|---|---|---|
| `kn_flower_purpleA.glb` | flower_purpleA | 花（紫）×4 | 152 |
| `kn_flower_redA.glb` | flower_redA | 花（红）×4 | 152 |
| `kn_flower_yellowA.glb` | flower_yellowA | 花（黄）×4 | 152 |
| `kn_mushroom_red.glb` | mushroom_red | 蘑菇（红伞）×3 | 96 |
| `kn_mushroom_tan.glb` | mushroom_tan | 蘑菇（棕伞）×3 | 96 |
| `kn_mushroom_group.glb` | mushroom_redGroup | 蘑菇丛 ×2 | 288 |
| `kn_bush.glb` | plant_bush | 灌木 ×3 | 64 |
| `kn_bush_detailed.glb` | plant_bushDetailed | 灌木（精细）×3 | 208 |
| `kn_log.glb` | log | 倒木 ×2 | 400 |
| `kn_stump.glb` | stump_round | 树桩 ×2 | 112 |
| `kn_reed.glb` | grass_leafsLarge | 河岸芦苇 ×10 | 288 |
| `kn_lily.glb` | lily_large | 水面睡莲 ×4 | 172 |

- 作者：Kenney（https://kenney.nl ，素材页 https://kenney.nl/assets/nature-kit ）
- 下载日期：2026-09-16
- 许可原文：https://creativecommons.org/publicdomain/zero/1.0/

## 3. 通用说明

- 使用方式：修改生成脚本后运行 `node tools/gen_world_glb.mjs` 重新生成 world.glb；
  这些源文件仅是生成期的几何来源，**不会打包进 HAP**（打包的是生成出来的 world.glb）。

## 5. NeuroMechFly 果蝇重建模型（v7 起，tools/assets/nmf_stl/）

- 来源：NeLy-EPFL/NeuroMechFly（HHMI/EPFL 等，真实黑腹果蝇 CT 重建的分部件网格）
- 许可：Apache License 2.0（可商用；本工程已在关于页与开发文档署名）
- 文件：65 个分部件 STL（头/复眼/触角/口器 Rostrum+Haustellum/左右翅/平衡棒/
  腿五节 ×6/腹节 A1A2~A6/胸）+ nmf.sdf（部件拼装 pose）
- 用途：tools/gen_world_glb.mjs 按 SDF pose 装配成运行时果蝇（fly_i 契约节点）
