# 开发与代码管理

## 名称

- 产品：琴序；工程、可执行文件及 scheme：`QinXu`。
- 应用模块：`Sources/QinXuApp`；入口：`QinXuApp.swift`；主界面：`PracticeHomeView.swift`。
- 音乐核心：`Sources/QinXuCore`；核心测试：`Tests/QinXuCoreTests`；应用层测试：`Tests/QinXuAppTests`。
- 开发 Bundle ID：`com.ifeng.QinXu`；macOS 预览：`com.ifeng.QinXu.mac`。

`PianoScore` 等音乐领域名称继续保留，表示钢琴乐谱，不是旧产品名。旧数据目录 `PianoPractice` 只用于兼容迁移。

## 日常验证

```sh
bash scripts/verify.sh
bash scripts/build-macos.sh
```

验证脚本检查工程是否与源码一致，校验 plist，执行真实自动化测试；存在 iOS SDK 时继续构建模拟器应用。CI 使用 `--require-ios`，禁止把缺失 iOS SDK 当作成功。

新添或移动应用 Swift 文件后运行 `python3 scripts/generate_project.py`。工程由脚本生成，不直接修改 `project.pbxproj`；生成器已支持 `--check` 无写入检查。

代码覆盖数据由 SwiftPM 生成在 `.build` 内。覆盖率用于寻找未测分支，不能代替实琴和真实音频测试。

## 界面渲染检查

```sh
QINXU_PREVIEW_DIR="$PWD/.local-build/previews" swift test --filter PracticeRenderingTests
```

使用 macOS 的 `NSHostingView` 在内存中渲染项目自身的视图，不读取桌面。自动检查主界面、琴谱、键盘在 393 / 834 / 1194 点宽度下是否正常生成且存在可见内容，并输出 PNG 供检查。它验证共享视图的 macOS 排版，不代表 iPad / iPhone 的 UIKit 布局、触摸和系统弹窗已经验收。

采用此方式是因为 [Apple ImageRenderer](https://developer.apple.com/documentation/swiftui/imagerenderer) 不包含部分由原生平台视图合成的内容，如滚动容器。

## Git 约定

仓库使用本地 Git。`main` 保存经过本机验证的开发基线；后续功能在 `codex/功能名` 分支施工，测试通过再合并。首个提交保留更名前的实现，之后记录命名、修复与测试成果。

```sh
git status --short --branch
git log --oneline --decorate -8
git switch -c codex/next-feature
```

提交包含源码、测试、原创样谱、工程生成器和开发记录。构建产物、缓存、Xcode 用户状态和个人签名信息不进入版本库。每次交付更新 `docs/STATUS.md`，如实记录尚未执行的验收。

当前未配置远程仓库；本地 Git 提供历史与回退，不等同于异地备份。确定 GitHub / 私有服务仓库后再添加远程并推送。
