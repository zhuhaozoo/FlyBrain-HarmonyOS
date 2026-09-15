# ArkTS / ArkUI 易错总结（果蝇大脑 App 实战）

> 来源：本项目（HarmonyOS 原生 3D 果蝇脑仿真 App）从 0 到 M3 全过程实际踩过并修复的错误，
> 按**编译错误 / 运行时行为错误 / 官方组件(HDS)坑 / 3D 渲染坑**四类整理。
> 每条给出 **现象 → 原因 → 正确写法**，编号全局唯一。
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
