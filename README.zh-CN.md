<div align="center">

<img src="skills_manager/assets/app_icon.png" width="96" height="96" alt="SkillDeck 图标" />

# SkillDeck

[English](README.md) · **简体中文**

统一管理你的所有Agent skills

[下载 macOS / Windows 版](https://skilldeck.cc) · [从源码运行](#从源码运行) · [命令行](#命令行) · [项目结构](#项目结构)

</div>

## 功能

- **常用 Agent，统一管理**：Claude Code、Codex、Cursor、Gemini CLI、GitHub Copilot 等常用 Agent 开箱即用，也可以添加自定义路径，接入更多工具。不必再逐个寻找 Agent 的 Skill 目录。
- **粘贴来源，选择安装**：粘贴 GitHub 仓库、本地文件夹路径，或 README 中的 `npx skills add` 命令，先查看其中有哪些 Skill，再选择安装。粘贴的命令只用于解析来源和选项，不会作为 shell 命令执行。也支持其他 Git 和 Well-known 来源。
- **按需启用，范围由你定**：选择哪些 Agent 可以使用某个 Skill，跨项目使用，或仅在指定项目启用。全局自动激活优先使用符号链接，必要时回退为复制；项目激活使用副本。文件该放在哪里，由 SkillDeck 处理。
- **已有 Skills，轻松接入**：发现 Agent 目录中已经安装的 Skills，纳入统一管理。遇到内容不同的副本，由你决定保留哪一份，不会直接覆盖。搜索、收藏、笔记和个人标签帮助你整理日常使用的 Skills。
- **中英对照，读懂 Skill**：按需翻译 `SKILL.md`，对照阅读原文与译文。翻译单独缓存，不改动 Skill 文件，Agent 使用的内容不会被译文替换。在线翻译使用你配置的服务。
- **跟着上游更新，保留自己的修改**：检查来源变化，在「更新」页更新单个或多个 Skills。支持本地草稿、修改合并、冲突处理和版本历史；在 App 外改过的文件也可以检查，并选择保留、恢复或导出。
- **让 Agent 帮你管理**：通过 `skilldeck` CLI 查询、安装、激活和检查更新，与桌面界面共用同一个工作区。删除和替换来源等操作仍需在 App 中批准，命令行不会绕过确认。

## 开始使用

从 **[skilldeck.cc](https://skilldeck.cc)** 下载适合你的 macOS 或 Windows 安装包。

1. **收集**：添加 Skill 来源，或把已经安装在 Agent 目录中的 Skill 纳入管理。
2. **整理**：阅读内容，添加收藏、标签和笔记。
3. **启用**：选择需要使用它的 Agent，以及全局或项目范围。
4. **维护**：按需检查更新；需要定制时，先编辑草稿，再发布到本地。

> [!TIP]
> **停用不等于删除。** 停用只取消 Agent 的可见入口，Skill 仍保留在工具箱里，可以再次启用。共享同一 Skill 目录的 Agent 会共享激活状态。

## 本地优先，修改有边界

- **工作区在本机**：Skill 内容、版本历史、收藏、标签和笔记由本地工作区管理；当前不提供云同步或团队工作区。
- **草稿不直接生效**：未发布的编辑不会改变 Agent 正在使用的版本。「发布」指应用到本地，不会推送到来源仓库；同一 Skill 的所有激活使用同一个已发布版本。
- **更新保留控制权**：检查更新不会自动应用；发生合并冲突时，保留当前生效版本，等待你处理。
- **变更可恢复**：安装、发布、更新和删除通过带有事务记录与恢复机制的工作区操作执行，而不是直接覆盖一组目录。
- **翻译不改原文**：网络翻译需要明确操作和配置，会将选定内容发送到所配置的服务；凭据由平台安全存储保管，译文缓存独立于 Skill 内容。

> [!IMPORTANT]
> SkillDeck 的工作区引擎不会执行 Skill 内容，但这不代表导入的指令或脚本可信。请在交给 Agent 使用前审阅来源和内容。删除 Skill、替换来源等操作具有破坏性，不能把版本历史当作独立备份。

## 命令行

在 App 的 **设置 → 命令行** 中检查命令行工具状态，并按提示配置 `PATH`。工具可用后：

```sh
skilldeck help
skilldeck status
skilldeck list --all
skilldeck list --favorite --json
skilldeck update --all --check
```

最后一条命令只检查更新，不应用更新。完整参数以 `skilldeck help <command>` 为准。

CLI 是桌面 App 的本地客户端，**不是独立的工作区引擎**。管理命令需要 App 运行；CLI 会尝试启动已安装的 App，也可用 `--no-launch` 禁止自动启动。`help` 和 `version` 不需要连接 App。

删除和替换来源等请求需要在 App 中批准，不能靠命令行参数跳过。不要在 App 运行时另起进程直接打开同一个 Workspace。

## 从源码运行

### 准备环境

使用 **Flutter 3.47.5 / Dart 3.13.4**，并安装对应平台的 Flutter 桌面开发工具链。先运行 `flutter doctor -v` 检查环境。

| 平台 | 构建依赖 |
| --- | --- |
| macOS | Xcode 及命令行工具、CocoaPods；原生构建工具 `clang`、`cmake`、`ninja`、`pkg-config` |
| Windows | Visual Studio 的 **Desktop development with C++** 工作负载、Windows SDK 和 C++ CMake tools；原生构建使用 Visual Studio 提供的 MSVC、CMake 与 Ninja，不要求 Unix 的 `clang` / `pkg-config` |

依赖解析还需要 Git 和网络连接。工作区会通过 Native Assets 编译仓库内固定版本的 libgit2，首次构建可能较慢。Linux 支持限于底层 `skills_workspace` 包，不是桌面 App 的发布目标。

### 启动桌面 App

在仓库根目录执行：

```sh
cd skills_manager
flutter pub get --enforce-lockfile
flutter run -d macos
```

Windows 将最后一行替换为 `flutter run -d windows`。保留已提交的依赖锁文件，不需要私有 UI 仓库或本机路径覆盖。

普通开发运行**不需要 `debug.json`、签名密钥或其他私有配置**。未设置 `SKILLDECK_UPDATE_FEED_URL` 时，App 自更新保持关闭。若自行配置更新源，只传入非秘密配置；不要把服务凭据写入源码或 `--dart-define`。

### 使用源码版 CLI

先保持桌面 App 运行，再从仓库根目录打开另一个终端：

```sh
cd packages/skilldeck_cli
dart pub get --enforce-lockfile
dart run bin/skilldeck.dart help
dart run bin/skilldeck.dart status --no-launch
```

### 检查修改

App（在 `skills_manager/` 中）：

```sh
dart format --output=none --set-exit-if-changed .
flutter analyze --fatal-infos --no-pub
flutter test --no-pub
```

工作区引擎（在 `packages/skills_workspace/` 中）：

```sh
dart pub get --enforce-lockfile
dart analyze --fatal-infos
dart test -j 1
dart test -j 1 integration_test
```

`-j 1` 用于避免原生编译与并行测试争用内存。翻译包使用 `flutter test` 而非 `dart test`，并另行保持 Flutter 3.29.3 兼容性。

> [!NOTE]
> 已配置 GitHub 托管 CI，但此快照尚未通过远程运行验证。仓库为私有状态时，运行会消耗所有者的 Actions 套餐分钟数，并可能产生费用；配置完成不代表测试通过或达到发布条件。

CI 按组件路径触发。PR 在 Linux 上执行快速检查（格式、严格分析、完整单元测试，以及 Workspace 代码生成和原生集成测试）。推送到 `main` 后增加 macOS arm64（`macos-15`）、Windows x64（`windows-2022`）及 Linux x64（`ubuntu-24.04`）验证。App 桌面 E2E 仅在 macOS 和 Windows 执行；Linux App 检查只覆盖单元测试与静态分析，不是交付目标。Workspace 桌面集成测试也会在 Linux 虚拟显示环境运行。macOS Intel 验证仍延期。

SDK 固定为 Flutter **3.47.5 / Dart 3.13.4**。翻译包及示例还会在 Flutter **3.29.3** 上分析、测试，并构建 Linux Debug 示例。主分支验证包含 Workspace 的 85% 覆盖率门槛、原生 ABI 检查，以及翻译示例的三平台 Debug 构建。

Workspace 和 App 工作流可在 Actions 页面手动选择 `quick` 或 `merge`；CLI 和翻译工作流的手动运行会验证全部支持的平台。**没有标签触发的发行构建、发行签名、公证、部署或发布任务**，也不需要私有 UI 凭证。macOS 测试仅使用本地 ad-hoc Debug 签名。过期 PR 运行会取消，主分支运行不会取消。不上传构建产物或私有日志。

可离线运行 `ruby .github/tests/workflow_policy_test.rb` 检查工作流策略，使用 `actionlint .github/workflows/*.yml` 检查工作流语法。标准 runner 架构见 [GitHub-hosted runners](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)。

## 项目结构

| 路径 | 职责 |
| --- | --- |
| [`skills_manager/`](skills_manager/) | Flutter 桌面 App：界面、设置、工作区编排与本地命令服务 |
| [`packages/skills_workspace/`](packages/skills_workspace/) | 事务型 Skill 生命周期、激活、SQLite 元数据及原生 Git 版本引擎 |
| [`packages/skills_translation/`](packages/skills_translation/) | 独立的 Markdown 翻译与内容寻址缓存 |
| [`packages/skilldeck_cli/`](packages/skilldeck_cli/) | `skilldeck` CLI 及 App 本地通信协议 |
| [`release/`](release/)、[`tool/`](tool/) | 构建与发布辅助工具；发布仍需单独配置签名和分发环境 |

理解模块边界可从 [Context Map](CONTEXT-MAP.md) 开始；工作区的术语与行为约束见 [Skill Workspace](CONTEXT.md)。
