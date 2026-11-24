# 琴序 · QinXu

面向 iPad / iPhone 的本地钢琴练习应用。当前为首轮开发版本，优先完成 MIDI + MusicXML 的练琴闭环，另带 **实验性麦克风单音识别**。项目内也提供同一份 SwiftUI 界面的 macOS 开发预览，方便没有 Xcode 模拟器时验证交互。

## 当前功能

- 三首原创练习：右手识谱、双手和弦、节奏练习。
- 导入未压缩 `.musicxml` / `.xml`，解析音高、时值、声部和小节。
- 简化双谱表、当前音符和屏幕琴键高亮。
- 原生 Core MIDI 输入，设备选择、刷新，Note On/Off、延音踏板。
- 识谱模式：正确完成音组后前进，重复音必须重新按键。
- 节奏模式：一小节预备（4/4 为四拍）、固定速度、节拍声、错音/漏音/起音偏差反馈。
- 左右手筛选、调速、小节范围循环、完成记录保存在本机。
- 麦克风实验模式：C3–C6、单音、识谱模式；不支持和弦和踏板，不上传音频。

这里的“实现”指代码已加入；编译与验证结果见 [docs/STATUS.md](docs/STATUS.md)。未经过 iPad 真机连接和实琴验证的部分，不视为可发布。

## 在 iPad / iPhone 运行

1. 在 Mac 安装完整 **Xcode 16 或更新版本**，打开一次完成平台组件安装。
2. 打开 `QinXu.xcodeproj`，选择 `QinXu` scheme。
3. 模拟器可直接构建；真机在 Signing & Capabilities 选择自己的 Development Team，必要时修改 Bundle Identifier。
4. 连接 iPad / iPhone，选择该设备，点击 Run。真机需要允许开发者模式及信任本机。
5. 使用支持数据传输的 USB 连接或适配器连接 MIDI 钢琴，在应用选择「MIDI 钢琴」。

第一版以有线 MIDI 为验收路径。设备通过系统暴露的其他 MIDI 来源也会显示，但尚未专门验证蓝牙 MIDI。不要把普通 USB 充电口当作 MIDI 接口。

工程无需第三方 Swift 包或后端服务。`QinXuCore` 通过本地 Swift Package 链接进 iOS 应用；增加应用源文件后可执行 `python3 scripts/generate_project.py` 重新生成工程。

## 在 Mac 运行开发预览

需要 macOS 14+ 和 Swift 6 工具链；完整 Xcode 或合适的 Command Line Tools 均可。

```sh
bash scripts/build-macos.sh
open .local-build/QinXu.app
```

Mac 预览用于本机验证共享界面、MIDI 输入与练琴逻辑，不能代替 iOS SDK 编译、iPad 布局和硬件测试。屏幕琴键发送真实练习输入事件，但当前不合成钢琴音色。

## 自动化验证

```sh
bash scripts/verify.sh
# 要求 iOS 构建也通过（完整 Xcode 环境 / CI）：
bash scripts/verify.sh --require-ios

# 单独运行核心与应用层测试：
swift test
xcodebuild -project QinXu.xcodeproj -scheme QinXu \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

只有 Command Line Tools 时，验证脚本会明确标记 iOS 构建为 SKIP；加 `--require-ios` 则缺少 Xcode 也会返回失败。CI 配置在 `.github/workflows/verify.yml`，尚未推送或执行远程 CI。

## 曲谱支持范围

第一版支持 UTF-8、单钢琴 part、固定拍号/速度、1–2 个谱表，第一谱表高音谱号、第二谱表低音谱号。支持 divisions、普通音符/休止、和弦、多个 voice 的 backup/forward、弱起、按 duration 表达的连音节奏、连续延音线合并。

- `Resources/Scores` 有三首可编辑、可导入的 MusicXML 示例。
- 音高由 MusicXML 的 `step / alter / octave` 决定，不会把调号再次叠加。
- 谱面是练习用简化排版，不是原谱的出版级复刻；调号、连线、力度、连梁和部分文字会简化。复杂节奏显示以拍数标注辅助理解。
- 目前不支持 `.mxl` 压缩包、照片/PDF 识谱、反复跳转、装饰音、变速/变拍、移调/八度线、多乐器合奏。这些情况会明确报错，不会默默按错误谱子评分。官方 MusicXML PUBLIC DOCTYPE 会先安全去除；不加载任何外部 DTD。
- 导入上限为 5 MB、1000 小节、20000 个起音音符；本地最多保存 100 首导入曲谱和最近 200 次完成记录。

## 判定边界

识谱模式先检查音高与音组完成，节奏模式按用户设定的四分音符 BPM 检查起音。节奏命中窗口为 ±0.30 秒，窗口内超过 ±0.10 秒显示稍早/稍晚；这只是初版可调参数，不是音乐教学标准。

循环起点如果截断前一小节延续的音，会提示从该音起始小节开始。

按键时长提示是辅助反馈：MIDI 松键不等于踏板延音结束，也不直接评价音乐表现力。首版不评分指法、手型、触键技巧和艺术表达，不进行自由速度的自动跟随。

麦克风只用于逐个单音的实验：需安静环境、不踩踏板，并在相邻音之间留短暂停顿。同音连续重击、混响、和弦或背景音乐可能造成误判；合成信号测试通过不等于实琴准确率已经达标。

## 数据与开发资料

练习记录和导入曲谱保存在应用沙盒的 Application Support/QinXu/library.json；macOS 预览对应用户 Library/Application Support/QinXu。同一可访问容器内，旧版 `Application Support/PianoPractice/library.json` 会在首次读取时迁移并保留原文件；已有新目录数据时不会覆盖。iOS 更换 Bundle ID 后属于不同沙盒，不能直接读取旧应用的数据。默认没有账号、服务器、遥测、订阅或云端音频处理。

- [施工计划与验收标准](docs/PLAN.md)
- [当前进度与验证记录](docs/STATUS.md)
- [架构与数据流](docs/ARCHITECTURE.md)
- [开发、命名与 Git 约定](docs/DEVELOPMENT.md)
- [真机测试清单](docs/DEVICE_TESTS.md)

产品名：**琴序**；英文工程名：**QinXu**。意为按音符的顺序，逐步练好每一段。
