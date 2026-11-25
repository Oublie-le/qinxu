# 开发与代码管理

## 名称

- 产品：琴序；工程、可执行文件及 scheme：`QinXu`。
- 应用模块：`Sources/QinXuApp`；入口：`QinXuApp.swift`；主界面：`PracticeHomeView.swift`。
- SwiftPM 的 Mac 预览可执行产品为 `QinXuPreview`，打包后仍是 `QinXu.app`；避免与 iOS 测试目标产品 `QinXu` 同名。
- 音乐核心：`Sources/QinXuCore`；核心测试：`Tests/QinXuCoreTests`；应用层测试：`Tests/QinXuAppTests`。
- 开发 Bundle ID：`com.ifeng.QinXu`；macOS 预览：`com.ifeng.QinXu.mac`。

`PianoScore` 等音乐领域名称继续保留，表示钢琴乐谱，不是旧产品名。旧数据目录 `PianoPractice` 只用于兼容迁移。

## 日常验证

```sh
bash scripts/prepare-resources.sh
bash scripts/verify.sh
bash scripts/build-macos.sh
```

项目脚本会在当前进程优先使用 `/Applications/Xcode.app`，不改系统全局 `xcode-select`。

第一次构建先准备固定版本模型、公版教材与乐谱字体。下载脚本按 SHA-256 校验，模型、PDF、字体二进制只作为本地构建输入；源码、下载脚本和许可提交。

验证脚本检查工程是否与源码一致，校验本地资源及 plist，执行真实自动化测试；存在 iOS SDK 时继续构建模拟器应用。CI 使用 `--require-ios`，禁止把缺失 iOS SDK 当作成功。

新添或移动应用 Swift 文件后运行 `python3 scripts/generate_project.py`。工程由脚本生成，不直接修改 `project.pbxproj`；生成器已支持 `--check` 无写入检查。

代码覆盖数据由 SwiftPM 生成在 `.build` 内。覆盖率用于寻找未测分支，不能代替实琴和真实音频测试。

## 界面渲染检查

```sh
QINXU_PREVIEW_DIR="$PWD/.local-build/previews" swift test --filter PracticeRenderingTests
```

使用 macOS 的 `NSHostingView` 在内存中渲染项目自身的视图，不读取桌面。自动检查曲库、琴谱、键盘、练习详情及教材阅读器，包含 667 × 375、844 × 390 手机横屏和 iPad 尺寸，并输出 PNG 供检查。它验证共享视图的 macOS 排版，不代表 iPad / iPhone 的 UIKit 布局、触摸和系统弹窗已经验收。

采用此方式是因为 [Apple ImageRenderer](https://developer.apple.com/documentation/swiftui/imagerenderer) 不包含部分由原生平台视图合成的内容，如滚动容器。

## Git 约定

仓库使用本地 Git。`main` 保存经过本机验证的开发基线；后续功能在 `codex/功能名` 分支施工，测试通过再合并。首个提交保留更名前的实现，之后记录命名、修复与测试成果。

```sh
git status --short --branch
git log --oneline --decorate -8
git switch -c codex/next-feature
```

提交包含源码、测试、原创样谱、工程生成器和开发记录。构建产物、缓存、Xcode 用户状态和个人签名信息不进入版本库。每次交付更新 `docs/STATUS.md`，如实记录尚未执行的验收。

远程 `origin`：`https://github.com/Oublie-le/qinxu.git`。用户已授权公开推送源码、提交历史和运行 GitHub Actions。功能先在 `codex/` 分支通过检查，再合入 `main`；无需强制推送或改写既有历史。

远程 CI 除共享代码测试与 iOS 构建外，还在两类模拟器执行 `UITests/QinXuUITests.swift`。本地执行方式为 `bash scripts/test-ios.sh iPhone` 或 `iPad`，需要完整 Xcode 和已安装的 iOS 运行时。测试日志与带截图的 `.xcresult` 存在 `.local-build/results`，CI 附件保留 14 天。构建与模拟器通过仍不代表实琴、麦克风和真机签名已验证。

## 本机 iPad 验证

环境准备和安装步骤见 `IPAD_SETUP.md`；目标 iPad 9 / iPadOS 18.0.1。实琴结果单独记入 `DEVICE_TESTS.md` 与 `STATUS.md`，不要把模拟器或合成音频作为设备验收。

应用资源打包遵循平台布局：iOS 将模型包、`Books`、`Fonts` 等复制为根级资源，禁止创建名为 `Resources` 的自定义根目录；Mac 把 SwiftPM 的资源 bundle 放进 `Contents/Resources`。见 [Apple Bundle Structures](https://developer.apple.com/library/archive/documentation/CoreFoundation/Conceptual/CFBundles/BundleTypes/BundleTypes.html)。
