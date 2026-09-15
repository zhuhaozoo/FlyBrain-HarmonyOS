# 果蝇大脑工程协作规则（AI 编码助手必读）

## 编码前置要求（必做）

- **动手写或修改任何 ArkTS/ArkUI 代码之前，必须先通读一遍错误总结文档** `docs/ArkTS-ArkUI易错总结.md`（含编译错误 / 运行时行为错误 / 官方 HDS 组件坑 / 3D 渲染坑四类，共 25 条，每条均有现象 → 原因 → 正确写法）。已踩过的坑不允许再犯；新增踩坑后须按既有格式（现象 → 原因 → 正确写法）补录进该文档。
- **涉及 3D 场景/交互/仿真的改动，先看 `docs/果蝇大脑App开发文档.md`**（架构分层：行为层纯逻辑 / 渲染层 / UI 层）与 `docs/场景与玩法设计-M4.md`（后续场景与玩法设计）。

## 构建与验证

- **默认不编译构建**：代码修改完成后**不要**自行构建/编译/安装验证，通知用户自行构建即可；**仅当用户明确要求编译构建时**才执行。
- 用户明确要求构建时，用 DevEco Studio 自带的 hvigorw 构建 debug 包（工程根目录**并无** hvigorw 包装脚本）：

  ```
  # <DEVECO_HOME> 为 DevEco Studio 安装目录，例如 Windows 下 D:\DevEco Studio
  set DEVECO_SDK_HOME=<DEVECO_HOME>\sdk
  "<DEVECO_HOME>\tools\hvigor\bin\hvigorw.bat" --mode module -p product=default -p buildMode=debug assembleHap
  ```

  `DEVECO_SDK_HOME` 未设置会报 `00303217`。产物在 `entry\build\default\outputs\default\entry-default-signed.hap`，可通过 `hdc`（含无线调试）安装到真机。
- 构建报错时读取构建日志排查修复；若 IDE 构建异常（`00308018` 等），按下述血泪教训的修复流程处理（杀 hvigor node 进程 → 清 `C:\Users\<用户名>\.hvigor\daemon\cache` → 清工程 `.hvigor\cache` → 用户重新构建）。
- 不要启动或停止 hvigor daemon 进程，不要清理 `C:\Users\<用户名>\.hvigor` 等构建工具链的共享缓存（修复流程除外）——构建环境归用户管理；构建报错信息明确指引 stop-daemon 时（如 00303217 环境变量变更）可按指引停止由本次构建自己拉起的 daemon。

### ⚠️ 为什么不要自行构建（血泪教训）

如果本机同时存在**多套** DevEco Studio / hvigor 工具链，它们会**共用** `C:\Users\<用户名>\.hvigor` 的 daemon 缓存。任何一方运行构建都会写入共享缓存，可能污染另一方 daemon 的 worker 状态，导致 IDE 构建在 CompileArkTS 阶段崩溃（报 `00308018 The "paths[0]" argument must be of type string`，真实堆栈是 `OhModulesLockLoader` 中 `HVIGOR_PROJECT_ROOT_DIR` 为 undefined）。即使加 `--no-daemon` 也会写共享缓存。

修复方式：杀掉所有 hvigor node 进程 + 清空 `C:\Users\<用户名>\.hvigor\daemon\cache` + 清工程 `.hvigor\cache`，然后由用户重新构建。

> 结论：**构建环境归用户管理，AI 助手不要主动碰工具链缓存**，需要构建时由用户执行。
