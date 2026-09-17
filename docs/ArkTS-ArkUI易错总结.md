# ArkTS / ArkUI 易错总结（果蝇大脑 App 实战）

> 来源：本项目（HarmonyOS 原生 3D 果蝇脑仿真 App）从 0 到 M4 全过程实际踩过并修复的错误，
> 按**编译错误 / 运行时行为错误 / 官方组件(HDS)坑 / 3D 渲染坑 / 工程经验 / 资源生成脚本坑 / 模型契约 / 跨层常量约定 / 性能冻结类**九类整理。
> 每条给出 **现象 → 原因 → 正确写法**，编号全局唯一。
> （v7.2 补录第 39、40 条：约束互相顶 / 只写 visible 隐藏不够稳。）
> 2026-09-15 建档，后续新增踩坑按既有格式补录。

---

## 一、编译错误类

### 1. ArkTS 对象字面量必须能对应显式声明的类型 ⭐ 最高频

**现象**：
```
10605038 ArkTS Compiler Error
Object literal must correspond to some explicitly declared class or interface
(arkts-no-untyped-obj-literals)
```

**常见触发点**（本项目全部踩过）：
```ts
// ❌ 1) 无类型标注的常量对象
const GLASS_BORDER = { width: 0.5, color: '#33FFFFFF' };

// ❌ 2) 变量用字面量初始化但未标注类型
const back = { x: -f.x, y: -f.y, z: -f.z };
const q = { x: 0, y: 0, z: 0, w: 1 };

// ❌ 3) 给声明了接口类型的常量赋嵌套字面量
const TITLE_BAR: HdsNavigationTitleBarOptions = {
  content: { title: { mainTitle: '设置' } },   // ← 嵌套层同样需要有类型依据
  ...
};
```

**正确写法**：
```ts
const GLASS_BORDER: BorderOptions = { width: 0.5, color: '#33FFFFFF' };
const back: Vec3 = { x: -f.x, y: -f.y, z: -f.z };
let q: Quaternion = { x: 0, y: 0, z: 0, w: 1 };
```

> 规律：ArkTS 比 TypeScript 严格得多，**任何**对象字面量都要有可推断的声明类型来源
> （变量标注、函数返回类型、参数类型、接口字段类型）。

### 2. `@Builder` 内不能写语句，只能写 UI 组件 ⭐

**现象**：
```
Only UI component syntax can be written here.
```
```ts
@Builder
SimSection() {
  const d = this.driver.getDrive();   // ❌ @Builder 里不允许 const/let 语句
  Column() { Text(`${d.spikesPerSec}`) }
}
```

**原因**：`@Builder` 的方法体是**UI 描述语法**，不是普通函数体，不能包含变量声明、赋值、
循环等语句。

**正确写法**：改为方法内联调用，或把逻辑抽到普通方法/私有 getter：
```ts
@Builder
SimSection() {
  Column() { Text(`${this.driver.getDrive().spikesPerSec}`) }  // ✅ 表达式内联
}
```
> 注意：这也埋下了第 8 条（状态不刷新）的伏笔——**能内联不代表会刷新**，见运行时错误第 8 条。

### 3. `AnimatorResult` / `AnimatorOptions` 需显式 import

**现象**：`Cannot find name 'AnimatorResult'` / `Cannot find name 'AnimatorOptions'`

**正确写法**：
```ts
import { AnimatorOptions, AnimatorResult } from '@kit.ArkUI';
```
> 项目里用它做逐帧驱动（`createAnimator({iterations:-1}).onFrame`），是最容易漏 import 的类型。

### 4. Worker 必须在模块 build-profile 里注册，且路径不含 src/main ⭐ 三连坑

**现象 1**：Worker 启动无任何报错，但 `postMessage` 时抛 `{"code":10200007}`（路径无效）
```ts
new worker.ThreadWorker('entry/src/main/ets/worker/BrainWorker.ets')  // ❌ 含 src/main
new worker.ThreadWorker('entry/ets/worker/BrainWorker.ets')          // ✅
```

**现象 2**：路径改对了仍报 `10200007` —— 因为 Worker 文件没被打包进 HAP。

**原因**：Worker 脚本必须在模块级 `build-profile.json5` 声明才会被单独编译打包：
```json5
// entry/build-profile.json5
"buildOption": {
  "sourceOption": {
    "workers": ["./src/main/ets/worker/BrainWorker.ets"]   // ← 这里才是 src/main 全路径
  }
}
```
> 注意两个路径格式**故意不同**：配置里用 `./src/main/...`，代码里用 `entry/ets/...`。

**现象 3**：注册后仍失败，报 `{"code":10200006}`（An exception occurred during serialization）
```ts
tw.postMessage({ type: 'init', buffer: ab });            // ❌ 31MB ArrayBuffer 序列化拷贝失败
const transfer: ArrayBuffer[] = [ab];
tw.postMessage({ type: 'init', buffer: ab }, transfer);  // ✅ 用转移（transfer）语义
```
**原因**：大 buffer 走默认的结构化克隆会失败/极慢，必须用 postMessage 第二参数转移所有权。

### 5. 删 import 前先全文搜引用

**现象**：`Cannot find module '../common/GlassTitleBar' or its corresponding type declarations.`

**原因**：改用官方 HDS 组件后删掉了自绘 `GlassTitleBar.ets`，但 `BrainPage.ets` 里
import 还在（该页当时并未实际使用，只是 import 未清理）。

**正确做法**：删除文件时，对工程 grep 该模块名，确认所有 import 都清理。

### 6. 模块级常量对象字面量同样要标注类型

见第 1 条第 3 点。HDS 标题栏配置是最典型的场景——**见第三条（HDS 坑）的完整案例**。

---

## 二、运行时行为错误类（编译通过但表现不对）

### 7. Stack 全屏覆盖层缺少 `height('100%')` → 内容全部居中重叠 ⭐

**现象**：顶部标题栏跑到屏幕正中央、底部控制条与标题重叠、所有控件"糊在中间"。

**原因**：`Stack` 的子组件默认按 `alignContent` 居中布局。覆盖层只写了 `.width('100%')`
没写 `.height('100%')`，高度退化为内容自适应，于是被 Stack 垂直居中。

**错误写法**：
```ts
Stack() {
  Component3D(...)           // 全屏
  Column() { /* 顶栏 */ }.width('100%')          // ❌ 高度自适应 → 被居中
  Column() { /* 底栏 */ }.width('100%')          // ❌ 同上
}
```
**正确写法**：
```ts
Column() { /* 顶栏 */ }.width('100%').height('100%').hitTestBehavior(HitTestMode.Transparent)
Column() { Blank() /* 底栏 */ }.width('100%').height('100%')
```
> 规律：**Stack 里的每个覆盖层都要显式撑满**，再用内部 `Blank()`/`justifyContent` 控制内容位置。

### 8. `@Builder` 参数传值不建立状态依赖 → 数值永不刷新 ⭐⭐ 最隐蔽

**现象**：仿真面板的「活跃脑区 0/61」「单步耗时 0 ms」永远不变（实际值一直在变）；
而同屏的状态行 `⚡0/s` 却能刷新。

**原因**：`@Builder` 的参数是**值快照**。写成 `this.StatRow('放电速率', \`${this.connSpikes}\`)`
时，`this.connSpikes` 在**传参那一刻**求值；`@State` 变化只让调用点重新求值，
而 ArkUI 对 `@Builder` 的内容做了缓存，导致内部 `Text(value)` 一直渲染旧快照。

**错误写法**：
```ts
@Builder
StatRow(name: string, value: string) {      // ❌ 按值接收
  Row() { Text(name); Blank(); Text(value) }
}

// 调用处（值已在传参时固化）
this.StatRow('活跃脑区', `${this.connActive} / ${this.connTotal}`)
```

**正确写法**（二选一）：
```ts
// 方案 A：让 @Builder 内部**直接引用** @State（推荐）
@Builder
SimStats() {
  Row() { Text('活跃脑区'); Blank(); Text(`${this.connActive} / ${this.connTotal}`) }
      .width('100%')
}

// 方案 B：不用 @Builder，直接内联在 build() 的组件树里
```
> 判据：**凡是会随时间变化的数值，其 Text 所在的最近一层 @Builder 必须直接读 this.xxx**，
> 不能靠参数把值传进来。静态文案可以继续用参数传值。

### 9. 非状态对象的字段变化不会触发 UI 刷新

**现象**：面板/Section 里的数据不动，但数据源（driver）确实在更新。

**原因**：`private driver: ConnectomeDriver = new ConnectomeDriver();` 是**普通成员**，
其内部字段变化对 ArkUI 不可观测（不是 `@State`/`@Observed`）。

**正确写法**：把要驱动 UI 的值**搬运到组件的 `@State` 变量**上，在帧循环里同步：
```ts
@State private connSpikes: number = 0;
@State private connActive: number = 0;
@State private connTickMs: number = 0;

// 帧循环中：
const d = this.driver.getDrive();
this.connSpikes = Math.round(d.spikesPerSec);   // ✅ 写入 @State → 触发重建
this.connActive = d.activeGroups;
this.connTickMs = Math.round(d.avgTickMs);
```
> 配合第 8 条使用：搬进 `@State` 后，**还要保证读取点直接引用它**。

### 10. 单次采样值抖动剧烈 → 用 EMA 平滑再显示

**现象**：「放电速率」在 0 和几百之间跳（状态行时而 `⚡0/s` 时而 `⚡940/s`）。

**原因**：每 tick 的放电神经元数（0~90）本身波动极大，直接 ×10 当作"次/秒"显示必然抖动。

**正确写法**：指数滑动平均后再显示：
```ts
this.emaSpikes += (fired * 10 - this.emaSpikes) * 0.15;   // EMA
this.drive.spikesPerSec = this.emaSpikes;
```

### 11. 加载态兜底：统计字段在首帧必然是 0

**现象**：面板刚打开时显示 `0 / 61`、`0 ms`，看起来像 bug。

**原因**：Worker 的 stats 消息按 `STATS_INTERVAL`（本项目 20 tick ≈ 2 秒）才发一次；
UI 在收到第一条 stats 前读到的是初值 0。

**正确做法**：用独立的 ready 标志区分"未就绪"与"就绪但值为 0"，未就绪时显示加载文案：
```ts
if (this.connState === 2 && this.connReady) { this.SimStats() }   // 已就绪
else { Text('开启后：…') }                                        // 未就绪
```

### 12. 全屏遮罩会吞掉下层手势 ⭐

**现象**：面板展开后 3D 场景无法拖拽，必须先点一下屏幕关掉面板才能转视角。

**原因**：为了实现"点空白收起面板"铺了一层全屏 `Column().onClick(...)`，
它位于 3D 组件之上，把拖拽/捏合手势全部拦截。

**结论**：**沉浸式 3D 场景不适合全屏遮罩收起交互**。正确做法是移除遮罩，
面板只由自己的按钮/分类头开合，让 3D 区域手势始终可用：
```ts
// ✅ 面板开合只由分类按钮控制，不加全屏遮罩
this.GlassChip('行为', () => this.toggleCat('behavior'))
```
> 若确需遮罩，至少要用 `hitTestBehavior(HitTestMode.Transparent)` 并把 3D 区域让出来，
> 但本项目实测"不加遮罩"的手感最好。

### 13. 覆盖层必须显式声明点击穿透策略

**现象**：3D 场景收不到 onClick（点了没反应）。

**原因**：覆盖层默认拦截触摸。

**正确写法**：
```ts
Column() { /* 顶栏/底栏 */ }
  .hitTestBehavior(HitTestMode.Transparent)   // 自身区域可点，其余穿透
```
并在 3D 的 `onClick` 里按坐标区域过滤掉控件区：
```ts
if (y < this.topAvoid + 46) { return; }                            // 顶栏
if (!this.isWide && y > this.areaH - panelH - this.bottomAvoid) { return; }  // 底栏
```

---

### 26. 父容器的 `onClick` 会被已可点击的子节点吃掉 ⭐

**现象**：关于页「开源地址」卡片把 `onClick` 挂在 `@Builder` 返回的 `Column`（整卡可点）
上，真机点击**完全无响应** —— 连`onClick` 回调里的 `console.error/warn` 都没有输出，
hilog 里查不到任何痕迹（说明回调根本没被调用）。

**原因**：卡片内的 URL 用了 `.copyOption(CopyOptions.LocalDevice)`（长按复制），
`uitest dumpLayout` 显示该 `Text` 自身就是 `clickable:true / longClickable:true` ——
它已经是一个**消费点击手势的节点**。触摸落在它上面时被它自己消费，
不再冒泡给父 `Column` 的 `onClick`。外层又包在 `Scroll` 里，命中链路更不确定。

> 判据：**凡是给子元素加过 `copyOption` / 自身可点击属性（`Text`+`copyOption`、
> `Image`+`onClick`、`Button` 等），父容器的 `onClick` 就不可靠了。**

**正确写法**：把 `onClick` 直接挂在**真正要点的那个可见元素**上（本例是 URL 的 `Text`），
需要「整卡可点」时，在每个子节点上都挂同一个处理函数，或给容器配 `hitTestBehavior`：

```ts
@Builder
RepoCard() {
  Column() {
    Text('说明文字…').width('100%')
    Text(REPO_URL)
      .copyOption(CopyOptions.LocalDevice)   // 长按复制
      .onClick(() => { this.openRepo(); })   // ✅ 点击挂在文字本身上
  }
  .onClick(() => { this.openRepo(); })        // 容器上也挂，双保险
}
```

**验证方式**：hilog 里能看到目标能力被拉起
（本例 `A00000/com.huawei.hmos.browser`），而不是只靠"界面没变化"倒推。

---

### 27. 节点 `scale` 会传递给子节点，别用缩放代替建模高度 ⭐

**现象**：给树做的「一级摇摆」完全不生效 —— 树干绕根部摆动了，但树冠纹丝不动；
如果把树冠改成树干的子节点，树冠的位置又飞到天上去了。

**原因**：两件事叠加。
1. 一级摇摆要求**树冠挂在树干下**（树干转，树冠跟着转），做成兄弟节点则树干转不动树冠；
2. 但节点 `scale` 是**沿层级向下传递**的。原先树干写成 `scale: [s, h, s]`（用缩放代替真实高度），
   树冠一旦成为其子节点，`translation: [0, h, 0]` 会被再乘一次 `h`，位置严重错位。

**正确写法**：把高度**烘焙进网格**，节点不再靠缩放表达尺寸，子节点位移就是真实米数：

```js
// tools/gen_world_glb.mjs
const trunkMesh = addMesh(makeCylinderUp(0.055, 0.095, spec.h, 12), MAT_TRUNK); // 高度烘焙
const crown = addNode({ name: `crown_${ti}`, translation: [0, spec.h, 0], children: [...] });
const trunk = addNode({ name: `trunk_${ti}`, mesh: trunkMesh, children: [crown] }); // 不再带 scale
```

**判据**：只要某个节点既要用 `rotation` 当"摆动轴心"、下面又挂了子节点，
就**不要**给它加 `scale` —— 否则子节点会被一起缩放，位置全错。

> 附带教训：写生成脚本自查规则时要克制。我一开始加了「有 children 就不许有 mesh」的断言，
> 结果把树上合法的 `trunk（有网格）+ crown（有子节点）` 判成了错误 ——
> **glTF 允许一个节点同时带 mesh 与 children**，断言要针对真正的错误（如节点重名）而不是想当然的洁癖。

---

### 28. 类型收窄会让「第二次比较同一枚举」直接编译报错 ⭐⭐

**现象**：
```
10505001 ArkTS Compiler Error
Error Message: This comparison appears to be unintentional because the types
'FlyState.Wander | ... | FlyState.Drinking' and 'FlyState.Dead' have no overlap.
```

**原因**：函数开头写了这样一句之后

```ts
if (this.state === FlyState.Dead) {
  this.updateDead();
  return;
}
```

ArkTS 会把 `this.state` **收窄**成「不含 `Dead`」的联合类型。于是后面再写一次
`if (this.state === FlyState.Dead)` —— **哪怕中间调用了会改变 state 的方法**
（例如 `this.damage()` 内部可能把状态置为 `Dead`）—— 编译器仍按收窄后的类型
判定「两类型无重叠」，直接报 10505001。

**正确写法**（二选一）：

```ts
// 方案 A（推荐）：把判断收进方法 —— 方法调用不参与类型收窄
private isDead(): boolean {
  return this.state === FlyState.Dead;
}

if (this.isDead()) { this.updateDead(); return; }
this.damage(...);                 // 内部可能致死，但收窄不会发生
if (this.isDead()) { return; }    // ✅ 合法

// 方案 B：只比较一次，存成 boolean 复用
const dead = st === FlyState.Dead;
if (dead) { /* … */ } else { /* … */ }
env.setDeathDim(dead);            // ✅ 不再出现第二次比较
```

**判据**：同一个函数里要**多次**判断「是不是某个枚举值」时，不要用 `===` 反复比较字段，
改用 **getter/方法** 或 **局部 boolean**。
这是 ArkTS 与 TypeScript 的典型差异点：同类写法 TS 常常宽容放过，ArkTS 直接报错。

> 补充：`switch (this.state)` 的 case 分支 `break`（不 return）不会造成收窄，
> 只有「提前 return 的 if」才会。

---

### 29. glb 生成脚本的自查「只卡上限」，漏掉了几何整体缺失 ⭐⭐

**现象**：真机上 3D 场景加载失败（App 显示「3D 场景加载失败」），
但 hilog 里既没有 `Scene init failed`，也没有引擎报错。只有：

```
[FlyBrain] root name='rootNode_' path=''
[FlyBrain] tree: name='world' path='/rootNode_/'
[FlyBrain] tree: name='stone_1' path='/rootNode_/world/'
[FlyBrain] tree: name='stone_0' path='/rootNode_/world/'
[FlyBrain] tree: name='ground_inner' path='/rootNode_/world/'
[FlyBrain] tree: name='ground' path='/rootNode_/world/'
[FlyBrain] nodes found: fly=false, wingL=false, wingR=false, food=0, spot=false, extra=1
```

`world` 节点下只有 4 个子节点，而 glb 的 `scenes[0].nodes` 里写着 61 个 ——
**引擎把前 4 个场景根节点建完就静默停了**，剩下的 57 个连同它们的子树一个都没建。

**根因**：几何生成脚本里的展开函数只写了顶点、忘了写索引：

```js
function flatShade(g) {
  const out = new Geometry();
  for (let i = 0; i < g.indices.length; i += 3) {
    ...
    for (const p of [a, b, c]) out.addVertex(p[0], p[1], p[2], n[0], n[1], n[2]);
    // ❌ 少了 out.addTri(base, base + 1, base + 2);
  }
  return out;
}
```

结果岩石与鹅卵石共 5 个 mesh 变成「有 324 个顶点、索引为空」。
**索引 accessor 的 `count = 0` 是非法 glTF，引擎遇到它之后就不再继续建节点，而且是静默的。**

**为什么自查没拦住**：脚本末尾的自查只有两条 —— 「bufferView 不越界」和
「三角面数 **< 8 万（上限）**」。几何缺失时三角面总数只是**偏小**，照样通过，
于是脚本还打印了 `world.glb OK ... triangles=12624`，实际少算了 5 个 mesh 的全部几何。

**正确写法**：自查必须**上下限都卡**，并逐个 mesh 点名校验：

```js
// 逐个 mesh：索引与顶点都不能为空
for (let i = 0; i < meshes.length; i++) {
  const idxAcc = accessors[meshes[i].primitives[0].indices];
  const posAcc = accessors[meshes[i].primitives[0].attributes.POSITION];
  if (!idxAcc || idxAcc.count < 3) throw new Error(`mesh[${i}] 索引为空`);
  if (!posAcc || posAcc.count < 3) throw new Error(`mesh[${i}] 顶点不足`);
}
// 任何 accessor 的 count 都不能为 0
// 节点 translation/rotation/scale 必须是有限数值
//   （传四元数数组、序列化代码却按 .x/.y/.z/.w 读 ⇒ 会写成 [null,null,null,null]，同样非法）
// 三角面数下限
if (triTotal < TRI_MIN) throw new Error(`三角面 ${triTotal} 低于下限，可能有 mesh 缺少几何`);
```

**判据**：资源生成脚本的自查，**只能证明「没超预算」，不能证明「东西都在」**。
凡是"数量/规模"类指标，上下限都要卡；凡是应当存在的 mesh / 节点，都要**逐个点名**检查，
不要用"总数看起来还行"来替代。

> 排查手法备忘：把 glb 当成 zip 里的 JSON 读出来直接验证
> （读 12 字节头 → JSON chunk 长度 → 解析 → 逐个 mesh 统计
> `accessors[primitives[0].indices].count`），比在真机上反复试快得多。
> 本次就是靠"某个 mesh 的 tris 列为 0"一眼定位的。

---

### 30. 单面绕序的几何从「内部」看会被整片剔除 ⭐

**现象**：做天空穹顶（半径 35 的球壳，观察者在球内）后，背景色**一直不变**，
始终是组件的默认灰底 —— 看起来像"穹顶根本没加载"。加日志确认 `sky domes registered: 9/9`、
节点可见性也在切，但画面毫无变化。

**原因**：穹顶球只输出了一侧绕序。glTF 的三角形正面由**顶点绕序**决定（右手系逆时针为正面），
`normal` 只影响光照、**不决定可见性**。我把法线朝内、绕序却仍是"朝外"的，
于是从球内看全是背面 → 被背面剔除整片干掉 → 直接露出组件底色。

**正确写法**：让穹顶（任何"从内部观察"的包围几何）**两个绕序都输出**：

```js
// 每个四边形输出 4 个三角形（正反各 2 个）
g.addTri(a, a1, b);   g.addTri(b, a1, b1);
g.addTri(a, b, a1);   g.addTri(b, b1, a1);
```

这样无论引擎是否真正实现了 `doubleSided`、以及它对绕序的判定习惯如何，球内都必然可见；
若引擎支持 `doubleSided`，背向的那一面会被正常剔除，不会与正面打架。

**判据与排查思路**：
1. 需要"从内部看"的几何（天空球、室内盒、洞穴）不能只写一侧绕序；
   **法线朝内 ≠ 可见**，可见性由绕序决定，两者要一起改。
2. 同理：**"画面上看不出变化"不等于"代码没生效"** ——
   先加一行日志确认节点 Count / 可见性（本次正是靠 `sky domes registered: 9/9`
   才把怀疑对象从"没加载"锁定到"被剔除"）。

---

## 三、官方 HDS 组件（UIDesignKit）坑

### 14. `HdsNavDestination` 必须配套 `HdsNavigation` 使用 ⭐

**现象**：子页面用 `HdsNavDestination` 但根容器是 `Navigation`，标题栏行为异常/返回键缺失。

**正确写法**：路由根容器必须是 `HdsNavigation`，子页面才是 `HdsNavDestination`：
```ts
// 根页面 Index.ets
HdsNavigation(this.navStack) { ScenePage() }
  .navDestination(this.PageMap)
  .mode(NavigationMode.Stack)
  .hideTitleBar(true)

// 子页面
HdsNavDestination() { ... }
```
> 参考：`HdsNavigation` + `HdsNavDestination` 是配套组合，
> 只读子页面容易误判为可独立使用。

### 15. `systemMaterialEffect` 在 `style` 里，不在 titleBar 顶层 ⭐⭐

**现象**：
```
Argument of type '{ content: {...}; systemMaterialEffect: {...}; }' is not assignable
to parameter of type 'HdsNavigationTitleBarOptions'.
  Object literal may only specify known properties, and 'systemMaterialEffect' does not
  exist in type 'HdsNavigationTitleBarOptions'.
```

**原因**：`systemMaterialEffect` 属于 `TitleBarStyleOptions`，必须嵌在 `style` 下。
网上流传的扁平写法**从未被编译验证过**，照抄必失败。

**正确写法**：
```ts
.titleBar({
  content: { title: { mainTitle: '设置' } },
  avoidLayoutSafeArea: true,                  // 见第 16 条
  style: {
    systemMaterialEffect: {                   // ✅ 嵌在 style 内
      materialType: hdsMaterial.MaterialType.IMMERSIVE,
      materialLevel: hdsMaterial.MaterialLevel.EXQUISITE
    }
  }
})
```
> 排查技巧：**编译器说"某某属性不存在"时，先怀疑层级写错**（该属性属于子接口），
> 而不是怀疑 SDK 不导出。

### 16. 页面 `ignoreLayoutSafeArea` 会让 HDS 标题栏压住状态栏

**现象**：设置页/关于页标题与系统状态栏（时间、电量）重叠。

**原因**：页面根容器设了 `.ignoreLayoutSafeArea([SYSTEM],[TOP,BOTTOM])` 后，
HDS 标题栏也一并顶到状态栏下方区域。

**正确写法**：在 titleBar 上让内容避让（材质背景仍沉浸延伸）：
```ts
.titleBar({ content: {...}, avoidLayoutSafeArea: true, style: {...} })
```

**派生问题**：3D 全屏页（自绘覆盖层）没有 HDS 标题栏可避让，需自行用安全区高度补 padding——
由 EntryAbility 读取系统避让区写入 AppStorage，页面用 `@StorageProp` 消费：
```ts
// EntryAbility
const sysAvoid = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
AppStorage.setOrCreate('fy_top_avoid', ctx.px2vp(sysAvoid.topRect.height));
AppStorage.setOrCreate('fy_bottom_avoid', ctx.px2vp(navAvoid.bottomRect.height));

// 页面
@StorageProp('fy_top_avoid') topAvoid: number = 40;
@StorageProp('fy_bottom_avoid') bottomAvoid: number = 24;
  .padding({ top: this.topAvoid + 6, bottom: this.bottomAvoid + 12 })
```

### 17. `getWindowAvoidArea` 需在窗口创建后调用，并监听尺寸变化

**做法**：`onWindowStageCreate` 里 `windowStage.getMainWindowSync()` 之后读取，
并注册 `on('windowSizeChange')` 回调刷新断点与安全区（横竖屏切换、折叠屏展开、
分屏都会改变窗口尺寸）。

---

## 四、3D 渲染（ArkGraphics 3D）坑

### 18. glTF 顶层节点之上有引擎包裹层，`getNodeByPath` 直接找名字必失败 ⭐⭐

**现象**：`Scene.load()` 成功、相机光源都创建成功，但按节点名找不到模型节点
（本项目表现为「3D 场景加载失败」）。

**原因**：引擎加载 glb 后会包一层根节点（实测 `scene.root.name === 'rootNode_'`），
glTF 里的顶层节点不是 root 的直接子节点，`root.getNodeByPath('fly')` 返回 null。

**正确写法**：**按名字深度优先搜索**，而不是猜路径：
```ts
private findByName(root: Node, target: string): Node | null {
  if (root.name === target) return root;
  const stack: Node[] = [root];
  while (stack.length > 0) {
    const cur = stack.pop();
    if (!cur || !cur.children) continue;
    for (let i = 0; i < cur.children.count(); i++) {
      const ch = cur.children.get(i);
      if (!ch) continue;
      if (ch.name === target) return ch;
      stack.push(ch);
    }
  }
  return null;
}
```
并保留一棵树的打印能力用于诊断（官方文档也给了遍历打印的方法）。

### 19. `Node.rotation` 是四元数，不要用欧拉角硬算

**做法**：需要"让相机看向某点"时，用正交基构造旋转矩阵再转四元数（官方 Graphics3D 示例
的 `lookAt` 做法），比猜测欧拉角顺序可靠得多：
```ts
const f = vec3Normalize(vec3Sub(center, eye));    // 前
const right = vec3Normalize(vec3Cross(f, up));    // 右
const camUp = vec3Cross(right, f);                // 上
const back: Vec3 = { x: -f.x, y: -f.y, z: -f.z };
// 旋转矩阵 → 四元数（trace 分支法）
cam.position = eye;
cam.rotation = q;
```

### 20. DIRECTIONAL 光默认朝 -Z，与相机背对会全黑

**现象**：模型正面全黑，只能看到剪影。

**原因**：平行光默认方向 -Z，而初始相机若也在 -Z 侧，看到的就是背光面。

**正确写法**：用四元数组合把光转向相机一侧并给俯角：
```ts
light.rotation = quatMul(quatY(Math.PI - 0.5), quatX(-Math.PI / 4));
```

### 21. 相机最近距离不能小于模型尺寸

**现象**：缩放滑杆拉到最小（0.6）时画面变成纯色、看不到果蝇。

**原因**：minRadius 设得比模型体长还小（果蝇体长 0.7，min 设了 0.55），相机钻进模型内部。

**正确写法**：minRadius 取值应 ≥ 模型最大尺寸的 1.2 倍左右（本项目最终 1.0），
既足够贴近看清复眼，又不会穿模。

### 22. 程序化生成 glb 时要注意「Y-up + 朝向约定 + 节点命名」

**做法**（本项目用零依赖 Node 脚本 `tools/gen_world_glb.mjs` 生成模型）：
- 统一 Y 轴向上，模型朝向 +Z（根节点置于地面接触点，便于运行时只改 position/rotation.y）；
- 需要独立动画的部件**各自命名为独立节点**（`fly` / `wing_left` / `wing_right`），
  运行时按第 18 条的名字搜索拿到引用；
- 静态场景元素可以在脚本里"烘焙"变换（旋转/缩放/平移直接写进顶点），减少运行时节点数；
- 生成后务必自校验（GLB 头长度、accessor 越界、节点树结构打印）。

---

## 五、其他工程性经验

### 23. 大资源入包会显著增大 HAP

本项目 `connectome.bin`（31MB）+ `brain.glb`（11.6MB）使 HAP 达到 ~45MB，
安装/更新耗时明显。后续可考虑：资源按需下载 + 沙箱缓存、gz 压缩入包 + 运行时解压。

### 24. 真机调试要素（本项目实践）

- `Component3D` **在 DevEco 预览器中不支持渲染**，必须真机；
- 无线调试 + USB 同时连接时 hdc 会报 `need connect-key`，需用 `-t <设备序列号>` 指定目标；
- 状态栏遮挡类问题只能靠**截图对照**发现（`snapshot_display` + `file recv`），
  UI 树 dump（`uitest dumpLayout`）拿不到视觉重叠；
- 锁屏状态下 `aa start` 会失败（`10106102`），需先 `power-shell wakeup` 并由用户解锁，
  自动化脚本应做"轮询等待解锁"。

### 25. 用 dump 验证 UI 时要过滤噪声文本

`uitest dumpLayout` 会把 Slider 的内部值、状态栏时间等一并导出，
做断言前要按正则过滤（如只取包含 `次/秒`、`/ 61` 的文本），否则容易误判。

---

## 六、资源生成脚本坑（gen_world_glb / 素材导入）

### 31. 按材质名过滤外部素材时，正则要对着真实名字写（"Leaves" 不含 "Leaf"）⭐

**现象**：导入 Quaternius 树模型时按 `/Leaf/i` 过滤树叶 primitive，结果树叶几何为空，
生成脚本直接报"缺少树干或树叶几何"。

**原因**：材质名是 `NormalTree_Leaves` —— **"Leaves" 里并不包含子串 "Leaf"**（Leaf≠Leav）。
同理，想排除法线贴图写了 `!/Normal/i`，结果所有贴图名都带 `NormalTree` 前缀全部被排除。

**正确写法**：
- 过滤前先 dump 一遍真实名字（`json.materials.map(m => m.name)`）再写正则，
  本例应为 `/Leav/i`；
- 排除法线贴图用后缀锚定 `/_Normal/i`，不要裸写可能命中名字前缀的关键词；
- 找不到目标材质时**宁可报错中止**（本项目的 REQUIRED 思路），不要静默回退到空几何。

### 32. 合并几何把索引写坏，"数量类"自查全部放行 ⭐⭐

**现象**：静态装饰件合并节点（刚毛 ×8→1 等）后，真机渲染必然是垃圾；幸而生成后
用线框预览发现背板环变成了 3 倍面数的怪环。`accessor.count`、面数上下限、bufferView
越界等全部自查**都通过了**。

**原因**：`addTri(a, b, c)` 一次压入**三个**索引，合并函数却写成了逐元素
`addTri(base + indices[i])` —— 每次只传一个值，后两个参数是 `undefined`，
索引数膨胀 3 倍且全部指向顶点 0。第 29 条已经证明过"count 类自查只能证明没超预算，
不能证明内容正确"，这次是它的又一个变种：**索引损坏用 count 永远查不出来**
（NaN/undefined 写进 Uint16Array 会静默变 0，仍然"在范围内"）。

**正确写法**（两道防线）：
1. 序列化时对索引做**取值校验**（`Number.isFinite(v) && 0 <= v < vertCount`），
   NaN/undefined 在这里当场爆掉 —— 本项目已把这条加进生成脚本的序列化循环；
2. 生成后渲染一张正交线框预览图（`tools/preview_glb.mjs`）肉眼过一遍，
   形状不对一眼可见，比任何数值自查都直接。

### 33. 烘焙平移 + 节点平移叠加，同一部件的位置只能有一处来源 ⭐

**现象**：v3 起果蝇头部就悬空在身体上方 0.58~0.76（身体顶只到 0.43），
真机与截图里表现为"头球飘着"，一直没被发现；做线框预览才现形。

**原因**：头部网格生成时 `bakeTransform(..., [0, 0.335, 0])` 把高度烘进了顶点，
而挂载节点又通过 `head_pivot` 把它放回 y=0.335 —— **两次平移叠加**，头部被抬高 0.335。
同批的复眼/触角/口器都只用了节点定位，所以位置全对，唯独头球飞了。

**正确写法**：每个部件的位置**只允许一处来源**——要么烘进网格且节点零平移
（胸/腹的做法），要么网格以原点为中心、位置全靠节点平移（眼/口器的做法），不要叠加。
排查工具：正交线框预览（顶视+侧视），部件是否悬空/错位一眼可见。

---

### 34. 可驱动部件的「基准姿态」必须在建模时就定好 ⭐

**现象**：真机试玩反馈"果蝇的翅膀一直是展开的，无论漫步还是停栖"——
飞行的振翅姿态成了它的常态，看起来像一只永远在飞的虫子。

**原因**：模型里翅根轴心 `wing_left_i / wing_right_i` 的**基准姿态就是"水平展开"**，
而运行时只在这之上叠加"绕 Z 轴的拍动振幅"（`quatZ(±a)`）。
也就是说：模型把某一种**具体状态**（飞行/展翅）烘焙成了静止姿态，
运行时就再也回不到另一种状态（停栖收翅）——因为没有任何一个自由度能让它"收回去"。

**正确写法**：凡是**运行时需要切换两种以上姿态**的部件，
建模时先定好一个中性的**基准姿态**，并保留足够的旋转自由度：

```js
// 模型：翅根轴心放在翅根，翼面沿 ±X 展开（中性=停栖/展开都可用）
c.push(addNode({ name: `wing_left_${s}`, translation: P([-0.09, 0.405, -0.03]), children: [blade] }));
```

```ts
// 运行时：把"收展"和"拍动"拆成两个自由度，并做平滑过渡
const foldYaw = cfg.wingFoldYaw * this.fold;                 // 绕 Y 后掠 = 收翅
this.wingLeft.rotation = quatMul(quatY(-foldYaw), quatZ(-a)); // 先拍动、再收展
```

判据：**"这个部件将来要不要换姿态？"** 要 → 建模时就得给它一个可回到的基准位与旋转轴心，
不要直接把某个状态（展开/抬起/伸直）烘进网格。

> 同类隐患自查清单：翅膀（收/展）、腿（站立/飞行收腿）、口器（伸出/收回）、
> 树冠（静止/随风摆）。这些都是"建模时的姿态 = 运行时唯一姿态"的候选受害者。

---

### 38. SDF/link-pose 里往往没有「姿势」：站姿必须自己做关节链 FK，换数据源 ≠ 换姿态 ⭐⭐

（第 34 条自查清单里"腿（站立/飞行收腿）"的应验。）

**现象**：真机反馈"果蝇六条腿垂直下挂、像吊线木偶"。此前 v7.1 已把拼装数据从
nmf.sdf 换成 nmf_loco.sdf 并注释"带真实站姿"，但实测装配后前/后腿各节段长轴与
竖直方向只差 3°~10°——所谓 loco 站姿根本不存在，两份 SDF 拼出来的都是垂直垂腿。

**原因**（两层，均为实测结论）：
1. NeuroMechFly 导出的 SDF 里，`<link><pose>` 只是**零关节角绑定布局**：六条腿的
   各关节原点 x/y 完全相同、只有 z 递减（腿垂直下挂）；`nmf_loco.sdf` 的模型名甚至仍是
   `neuromechfly_noLimits`，link pose 与基础版几乎逐数相同。**真实站姿不在 SDF 里**
   （在他们论文的关节角优化结果里）。把"换了个 SDF 文件"当成"有了站姿"，是本次的根因。
2. 附带小坑：脚本里 `quatBetween` 返回的是**未归一化四元数**（既有 makeTube 管线
   依赖其现状，不能顺手改），而 `quatApply` 的旋转公式只对单位四元数成立——
   非 unit 四元数会把缩放混进方向（实测方向 dot 掉到 0.982），用前必须归一化。

**正确写法**（tools/gen_world_glb.mjs v7.2）：
1. 建模期做**关节链 FK 摆姿**：每条腿按 SDF 关节原点拆成 基节/股节/胫节/跗节 四级枢轴
   （网格按节段拆开、顶点存摆姿后世界坐标，枢轴保持零旋转）；给每节段一个目标朝向
   （前腿前伸/中腿外张/后腿后蹬/跗节近地，注意**场景系与世界系的轴对应**，本次就栽过
   把场景系方向直接当世界系方向用、前腿脚尖朝天），用
   `quatNorm(quatBetween(零位方向→目标))` 求各关节世界旋转，前向运动学逐节烘进顶点；
   摆姿后**重算全包络**——贴地面/前后居中必须用摆姿后的 bbox，否则果蝇整体悬空。
2. **烘顶点而非给枢轴带基准旋转**：运行时枢轴零旋转 = 基准站姿，动画偏移直接叠加，
   不依赖读取引擎侧的模型四元数（第 34 条判据的落地做法）。
3. 换/改姿势数据源时，先写个临时脚本用"最远点对近似长轴"量一遍各节段方向与竖直的
   夹角（本次 3°~10° 实锤垂腿），别信注释或文件名——半分钟的测量省一轮真机往返。
4. 非腿部件的姿势（双翅收拢贴背/头部俯仰/腹端下卷）此前同样是靠 nmf_loco 的 rpy 烘出
   的——回到零位 SDF 后这些也会摊平，需逐部件保留其 rpy 旋转再烘顶点。

---

## 七、模型契约（建模期就要定好的两件事：基准姿态 / 碰撞数据）

### 35. 静态几何不产出「碰撞数据」，行为层就只能穿模 ⭐⭐

**现象**：果蝇直接从石头中间穿过去。渲染完全正常，行为层也没有任何报错——
因为**行为层根本不知道石头在哪**：场景几何只被送进了渲染器。

**原因**：`world.glb` 里的石块只有"顶点 + 变换"，节点也没有碰撞体。
运行时若想自己做碰撞，只能靠"名字 + TRS"这几个可读通道，
而**半径这类纯数值没有地方放**（节点名不能塞数字、mesh 也读不到尺寸）。

**正确写法**：让**生成脚本**（它才知道真实尺寸）在几何旁多产出一个
**无网格、无子节点的标记节点**，把数值放进 `translation` 与 `scale`：

```js
// 半径 = 该变体归一化后的水平外接半径 × 水平缩放最大值（绕 Y 旋转后仍在圆内，略保守）
const r = rockGeoms[i % rockGeoms.length].radius * Math.max(sx, sz);
addNode({ name: `blocker_${i}`, translation: [s[0], 0, s[1]], scale: [r, 1, r] }, true);
```

```ts
// 运行时按名字读入（scale 是 Scale3，读得到），不猜几何、不复制常量：
SceneManager: blockerNodes[] ← findByName(root, `blocker_${i}`)   // 找不到就 break，不硬编码个数
ScenePage:    obstacles.add(node.position.x, node.position.z, node.scale.x);
```

配套约定：
- 把 `blocker_0 / blocker_N` 加进生成脚本的 `REQUIRED` 契约清单（改名即报错中止）；
- **编号必须连续**（运行时段号找不到就停）：脚本里用一个全局计数器统一发号，
  并在末尾断言总数（本项目 = 石块 8 + 卵石 16 + 树干 3 = 27），跳号/漏加直接报错；
- 无网格无子节点的节点是合法 glTF（与 `sun_pivot` 同类），但**务必加一行日志**确认引擎真的建了它
  （本项目 `[FlyBrain] nodes found: … blockers=27`）——为 0 时功能会**静默退化**成穿模；
- 半径宁可略保守（用外接圆而非内切圆）：果蝇保持一点距离，观感是"绕开石头"，不会露馅；
- **"半径"要按对象各自的语义取，不能一律用网格包围盒**：树的阻挡圆必须只取**贴地那一段树干**
  （本项目取最低 12% 高度内的顶点求最大半径），否则会把枝条/树冠一起算进去，
  果蝇连树冠下都走不进去；而且 bark 的包围盒中心 ≠ 树干轴心（枝条不对称），
  圆心要按贴地段顶点的水平中心补偿；
- 标记节点**只能挂顶层**：挂到会摇动的 `tree_i / trunk_i` 下面，碰撞圆就会跟着树摆一起动。

> 判据：**凡是"行为层需要知道、但几何里没写"的量（碰撞半径、可行走区、高度），
> 都要在生成期显式地"带出包外"**（标记节点 / 元数据文件），
> 而不是在运行时用常量去"猜"生成脚本里的数字——那种重复一旦不同步，就是静默的错。

---

### 36. ForEach 的 key 里必须包含内容，否则列表"永不刷新" ⭐⭐（同一坑踩了两次）

**现象**：大脑状态小窗里那 8 行「活跃脑区明细」的数值不再变化，**必须关掉小窗再打开才刷新**；
而同屏其它数值（放电速率、活跃脑区计数）是正常跳动的。

**原因**：这 8 行用 ForEach 渲染，key 只有下标：

```ts
ForEach(this.groupLines, (line: string, i: number) => {
  Text(line)…                                    // ❌ 内容来自 ForEach 传入的 item
}, (line: string, i: number) => `g${i}`)         // ❌ key 只有下标
```

ArkUI 的 ForEach **按 key 复用子节点**：key 不变 ⇒ 该行既不重建、也不更新内容，
文本就冻结在首次渲染的值上。给 `this.groupLines` 整体赋新数组确实让组件重建了，
但重建时 ForEach 发现 key 集合没变，直接跳过这些行 —— 所以"@State 没问题"也没用：
**这是 ForEach 自己的一层缓存，跟在不在 @State 里无关**。

**正确写法**（二选一）：

```ts
// 方案 A：把内容并进 key（本项目 14.9 用过；每次刷新都会重建该行）
}, (line: string, i: number) => `g${i}_${line}`)

// 方案 B：行数固定时干脆不用 ForEach —— 逐行调用，并在 @Builder 内直接读 @State（推荐）
@Builder
GroupLine(i: number) {                    // 只传下标（常量），值在内部读 @State
  Text(this.groupLines[i])…
}
Column() { this.GroupLine(0); this.GroupLine(1); /* …共 8 行… */ }
```

方案 B 同时满足两条要求：不会再被 ForEach 缓存冻结，也不会因重建引起高度抖动
（配合固定行高，见第 8/9 条与开发文档 14.6）。

**判据**：
1. 列表项**内容会随时间变化**时，先检查 ForEach 的 key 有没有含内容；
2. `@Builder` 只接收"下标/常量"这类稳定参数，**值一律在内部读 @State**；
3. 该现象与第 8 条（@Builder 传值不建立依赖）**表现一样、根因不同**，排查时两条都要过一遍。

---

## 八、跨层常量约定（生成脚本 ↔ 运行时）

### 37. 场景尺度是「生成脚本 ↔ 运行时」的成对常量，单改一处必然出假 bug ⭐⭐

**现象**（本次放大场地时一次性暴露的一类问题）：把地盘从 7.4 放大到 11.0 后，如果只改一边，
会出现一批"看着像新 bug、其实全是尺度不一致"的表现 ——
- 果蝇站在水面上/走到河里（脚本河流半径已放大，`FlyConfig.riverInner` 还是旧值，斥力算错位置）；
- 果蝇围着树/落果转圈却永远够不到（树距、落果钳制已外移，`arenaRadius` 软边界没跟着放大）；
- 相机拉到最远或平移到底时**天空被裁掉**（`SKY_RADIUS` 与 `maxRadius + panLimit` 的关系被破坏）；
- 青蛙追不上、舌头够不着（追击半径/舌长没跟着放大）；
- 生成的 `.glb` 直接报 `blocker 数量 27 ≠ 33`（blocker 数量断言与 REQUIRED 清单没同步）。

**原因**：同一个几何量被抄在两个地方（脚本里的建模常量 + 运行时的行为/相机常量），
它们之间**没有编译期约束**：脚本改完能自己跑通（自查只覆盖脚本内部一致性），
运行时也能编译通过（数值是合法的 number），错误只以"行为异常"的形式在真机上暴露，
而"行为异常"的表现形式（穿模、够不到、被裁）看起来又像完全不同的问题。

**正确写法**：
1. **每个尺度只留一个"出处"**：脚本里把会互相影响的数值放进同一段带注释的常量块
   （本次是 `ARENA_R` / `RIVER_RIN` / `RIVER_ROUT` / `FROG_R` / `SKY_RADIUS`），
   运行时在 `FlyConfig` 的场地几何段注释里**写明脚本行号与对象名**（"必须与脚本 1) 地面段一致"）；
2. **成对字段同一步改完**：脚本常量、`FlyConfig` 场地几何、`SceneManager` 相机限位、
   `FrogController` 作战半径、`EnvironmentController` 特效坐标，一次改完再生成；
3. **能自动断言的都断言**：脚本里加"谁的铺位压住谁"的生成期检查
   （本次是石块不进河流弧带/不压树根与青蛙出生点、河岸两圈的相邻净宽 ≥0.45），
   让错误在 `node tools/gen_world_glb.mjs` 阶段就抛出来，而不是留给真机观察；
4. 参考 `docs/模型与场景深度优化方案.md` 的"尺度对照表"，它把 26 处成对数值列全了。

**判据**：
1. 改动任何"场地大小/视角范围/作战半径"前，先搜出所有成对字段，列成表再动手；
2. **几何改了但尺寸相关的运行时数字没改** ⇒ 一定是这类 bug，不要往"行为逻辑/渲染"方向查；
3. 这类问题的成本集中在"发现"，所以宁可多写一条生成期断言。

---

### 39. 两个约束方向相反时，个体会被逐帧来回顶 —— 生成期必须检查"阻挡圆压没压住运行时推出来的线"⭐⭐

**现象**：真机反馈"果蝇一旦走到河滩上就被卡住、原地不动/抖动"（行走状态仍在跑，位置不前进）。

**原因**：运行时有两套**独立**的位置修正，各自都对，合起来打架：

```ts
// FlyBrain.applyBoundary：贴地进水 → 沿河道法向推到"水面外沿 + 0.05 = 中心线外 0.75"
this.river.pushOut(pose.x, pose.z, 0.05, rn);
// Obstacles.resolve：贴地撞阻挡圆 → 沿径向推离圆心
this.obstacles.resolve(this.pose, this.cfg.bodyRadius, ...);
```

生成脚本把 16 颗河岸卵石摆在 **距河道中心线 0.75~1.05**、半径最大 0.66 —— 它们的阻挡圆
**内缘全部压在 0.75 这条推岸线上**（实测 16/16 内缘 < 1.05）。于是被推上岸的果蝇**正好落进
卵石阻挡圆**：水把它推向岸、卵石把它推向水，逐帧互相抵消，位置与朝向都在原地打转。
附带伤害：帧末位置可能落在水带内 ⇒ 触发落水扣血 ⇒ 死亡后重生到原点，而**原点也在水里**
（河道穿过场心，原点距中心线 0.392 < 半宽 0.7）⇒ 重生 → 落水 → 被推到同一段被压住的岸线，
"地图中央多了一只完全静止的果蝇"。

**正确写法**：

1. **凡是"运行时会把个体推到某条线/某个位置"的地方，生成期都要断言静态阻挡圆是否压住它**：
   本例是 `卵石内缘（到中心线距离 − 阻挡半径） ≥ 推岸线 + 0.35`（让出一条可行走沙滩带）：

   ```js
   const BEACH_LINE = RIVER_HALF + 0.35;          // 推岸线 0.75 之外再留 0.35
   const off = Math.max(offWant, BEACH_LINE + br); // 半径大的卵石整体外挪，内缘仍同一位置
   if (riverDist(px, pz) - br < BEACH_LINE - 1e-6) throw new Error('卵石压住可行走沙滩带');
   ```
   > 摆位时先算阻挡半径，再据此决定离河道多远；法向若取自局部折线段，摆完还要用
   > "到整条折线的最近距离"校正一次（曲线处两者有偏差，本项目实测差 0.02）。
2. **出生/重生点也要走同一套"可站立点"修正**（本项目 `FlyBrain.groundSpawnPoint()`：推离水域
   + 推出阻挡圆，迭代 2~3 轮），不要假设"原点/出生圈一定在陆地上"——**河道形状一改，
   原点就可能进水里**；
3. 约束冲突的最终兜底：给这类区域加**软边界压力**（久留 → 负面内驱力 + 背离该区域的转向偏置），
   即使将来又出现新的"两个约束顶着"的情形，个体也会自己走开，而不是永久卡死。

**判据**：写/改生成脚本的铺位逻辑时，先列出"运行时会对位置做哪些修正"，取其中**输出的那条线/那个点**，
逐个断言"没有静态阻挡圆压住它"。

---

### 40. 只写 `visible = false` 隐藏对象不够稳：容器节点 / 独立部件都要"移出视野或塌缩尺寸" ⭐⭐

**现象**：两处"该藏没藏"同时出现：
1. 预置 6 份果蝇模型都烘焙在原点，未上场的那几份只写了 `set.fly.visible = false`，
   真机上仍被画出来 —— 多份叠在原点，看起来就是**"地图中央多了一只完全静止的果蝇（像预置模型）"**；
2. 青蛙舌头收回分支只写了 `tongue.visible = false`，真机上出现过**"舌头一直保持伸出"**。

**原因**：`Node.visible` 是节点级标志，而"隐藏一棵子树"要靠引擎的可见性继承。
`fly_i` 这种**自己没有网格、只有子节点**的容器一旦继承不生效，就等于什么都没藏；
独立部件（舌头）在真机上也出现过该标志没兑现的情况。**只靠它，就有静默失效的风险**。

**正确写法**（双保险，与项目里"特效节点一律埋在 `translation.y = -10`"同款约定）：

```ts
// 1) 隐藏一份"预置模型"：既改可见性，也把根节点移出视野（位置一定会传递给子节点）
private hideFlyNode(node: Node): void {
  node.visible = false;
  node.position = { x: 0, y: HIDDEN_FLY_Y, z: 0 };   // -80，远在地面圆盘/天空穹顶之外
}

// 2) 隐藏一个独立部件：既改可见性，也把三轴缩放塌缩到 ~0（不用 0，避免退化矩阵）
tongue.visible = false;
tongue.scale = { x: S, y: S, z: S };   // S = 0.001
```

配套注意：
- 被"移出视野"的对象**重新启用时要恢复**：本项目由渲染器每帧写回正确位置/缩放，天然恢复；
- **多份相同预置模型叠在同一位置时，肉眼只看得到"一只"** —— 排查时不要因为"看着只有一只"
  就排除"多份都没被隐藏"这一假设（本项目就是 3 份叠在原点）。

**判据**：凡是"运行时按数量/状态显隐"的对象，隐藏动作不要只写一个 `visible`：
预置模型 → 移出视野；独立部件 → 塌缩尺寸；两者都要在"重新启用"路径上有确定的恢复写入。

---

## 九、性能/冻结类（v7 新增）

### 38. 大 rawfile 在主线程读取 → THREAD_BLOCK_3S 冻结被强杀 ⭐⭐

**现象**：connectome.bin 从 31MB（FAFB）涨到 48-72MB（MaleCNS）后，启动应用卡死数秒
然后被系统退出。hilog 抓到 `NotifyAppFault:THREAD_BLOCK_3S, processExit:1`。

**原因**：`resourceManager.getRawFileContent()` 虽然长得很像异步 API，但读取+分配
发生在调用线程（主线程）；之后 `buffer.slice()` 再拷贝一份同样在主线程。
FAFB 时代单次阻塞约 1s 侥幸低于 3s 阈值，48MB 后直接越线。多驱动器串行加载还会
把多次阻塞连成一段超长阻塞。

**正确写法**：
1. 主线程只调 `resourceManager.getRawFd(name)`（元数据，零读取），把
   {fd, offset, length} postMessage 给 Worker；
2. Worker 里用 `fs.readSync(fd, chunkBuf, {offset, length})` 分块（4-8MB）读入后解析；
3. 驱动器之间 `await setTimeout(80)` 让出主线程。

### 39. fs.readSync 传 Uint8Array 视图报 EINVAL；重复 getRawFd 后续 fd 失效 ⭐

**现象**（接上条的调试过程）：
1. `fs.readSync(fd, new Uint8Array(buf, done, n), {offset, length})` 报 13900020 EINVAL；
2. 三个 BrainWorker 用各自 `getRawFd` 拿到的 fd，第 2/3 个报 13900008。

**原因与正确写法**：
1. 该 API 版本的 readSync 只接受**纯 ArrayBuffer**（不接受视图）——按块新建
   ArrayBuffer 读取后用 `Uint8Array.prototype.set` 拷入目标 buffer；
2. 重复 `getRawFd` 会使先前获取的 fd 失效——**全进程只调一次**，fd 存入静态字段
   供所有 Worker 共享，且 Worker 侧**不要 close**（随进程存活）。

### 40. 同场景 130+ 次全树 DFS 节点查找也会拖冻主线程 ⭐

**现象**：场景节点从约 200 涨到 455 个后，SceneManager.init 在 `root name` 日志与
`nodes found` 日志之间卡数秒（与 rawfile 读取叠加直接触发冻结）。

**原因**：每个 findByName 都做一遍全树 DFS（每次 900+ 节点的 NAPI 遍历），
130+ 次查找 ≈ 十几万次引擎往返调用。

**正确写法**：场景加载后**一次**深度遍历把全部节点收进 `Map<string, Node>`，
此后所有按名查找都是 O(1) 哈希读取；需要新节点名时直接查表，不再新增遍历。
