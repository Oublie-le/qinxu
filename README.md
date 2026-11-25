# 琴序 · QinXu

[源代码](https://github.com/Oublie-le/qinxu) · [自动构建与测试](https://github.com/Oublie-le/qinxu/actions/workflows/verify.yml)

面向 iPad / iPhone 的本地钢琴练习应用。当前开发版包含 MIDI + MusicXML 练习、原生曲库、拜厄中文练习目录和原书阅读，以及相互独立的**单音、多音麦克风实验模式**。iPhone 使用横屏，iPad 保留横竖屏；同一份 SwiftUI 代码也提供 macOS 开发预览。

## 当前功能

- 原生曲库、搜索、小封面、收藏、谱架、详情和真实练习记录；可导入本地封面图片。
- 三首原创练习：右手识谱、双手和弦、节奏练习。
- 拜厄 Op.101 中文重排练习谱：59 项练习覆盖 39 首原曲，可从教材目录进入分手练习和判音；第 1、2 首的主题与变奏分别列出。它不是出版社中文版，也不是完整 106 首，准确范围与来源见[教材资源说明](Sources/QinXuApp/Resources/Books/Beyer/README.txt)。
- 保留公版拜厄完整 88 页外文 PDF（Peters/Ruthardt 1895 年版），供阅读和对照；PDF 本身不作为自动判音数据。用户没有小汤纸书，上海版小汤 1/2/3 的完整电子谱仍未取得、未内置，查询记录见[教材资源核验](docs/TEXTBOOK_SOURCES.md)。
- 导入未压缩 `.musicxml` / `.xml`，解析音高、时值、声部和小节。
- 使用 Bravura 音乐字体 glyph 的简化双谱表、当前音符和屏幕琴键高亮；不宣称出版级刻谱。
- 原生 Core MIDI 输入，设备选择、刷新，Note On/Off、延音踏板。
- 识谱模式：正确完成音组后前进，重复音必须重新按键。
- 节奏模式：一小节预备（4/4 为四拍）、固定速度、节拍声、错音/漏音/起音偏差反馈。
- 左右手筛选、调速、小节范围循环、完成记录保存在本机。
- 琴键按整首曲谱与所选手固定音域，音域至少三八度，可横向滚动且不随下一音移动；绿色提示待弹音，浅橙独立提示按谱面时值应保持的长音。
- 单音麦克风实验：C3–C6、逐音识谱，不支持和弦。
- 多音麦克风实验：本机 Basic Pitch CoreML 同时识别多个音，约 2 秒音频窗口；仅识谱等待，不评节奏或松键时长。实录开发检查仍有明显漏音，详见[多音识音说明与实测](docs/POLYPHONIC_MICROPHONE.md)。音频不上传。

这里的“实现”指代码已加入；编译与验证结果见 [docs/STATUS.md](docs/STATUS.md)。未经过 iPad 真机连接和实琴验证的部分，不视为可发布。

## 首次克隆：准备资源

模型、字体和 PDF 二进制不存入 Git。首次构建或测试前执行：

```sh
bash scripts/prepare-resources.sh
```

脚本下载固定版本的 Basic Pitch 模型、Bravura 字体和公版拜厄 PDF，校验 SHA-256 并保留许可。资源齐全后可离线构建；缺失资源不能当作完整安装包交付，验证脚本会拒绝通过。

拜厄中文练习用的 MusicXML、目录及来源锁定文件随源码保存，不需要从 PDF 识谱。可另用 `python3 scripts/import-beyer-ranote.py --fetch --check` 下载锁定的公开源数据并重建核验；这不是首次运行应用的必需步骤。

## 在 iPad / iPhone 运行

1. 在 Mac 安装完整 **Xcode 16 或更新版本**，打开一次完成平台组件安装。
2. 打开 `QinXu.xcodeproj`，选择 `QinXu` scheme。
3. 模拟器无需个人签名。真机先在 Xcode 登录开发账号并创建开发证书；可用下面的本地配置脚本保存 Team ID 和可选 Bundle ID，避免重新生成工程时丢失。
4. 连接 iPad / iPhone，选择该设备，点击 Run。真机需要允许开发者模式及信任本机。
5. 连接 MIDI 钢琴后选择「MIDI 钢琴」；需要尝试麦克风时，在设备页明确选择单音或双手实验模式。

```sh
python3 scripts/configure-ios-signing.py TEAM_ID
# 需要自定义应用标识时：
python3 scripts/configure-ios-signing.py TEAM_ID --bundle-id com.example.QinXu
```

脚本只写 Git 忽略的 `Config/LocalSigning.xcconfig`，不保存账号凭证；共享默认标识为 `com.ifeng.QinXu`。目标 iPad 已完成签名、安装和启动；用户此前确认能打开。本次 59 项教材版本已通过真机 UI 测试，严格签名复核及恢复正常数据模式后的启动成功。MIDI 与多音麦克风的实琴质量分别验收。系统已连接的其他 MIDI 来源也会显示，但蓝牙 MIDI 未专门验证。

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

2026-11-25 最新 `verify.sh --require-ios` 通过 **107 项测试（65 项核心、42 项应用）**及 iOS Simulator 目标构建，拜厄源数据重建核验通过。当前版本在 iPad 上 **6 项 XCTest UI 测试全部通过**，包括拜厄第一课屏幕 C5 计分及琴键位置稳定；结果摘要已确认，截图已导出。严格签名复核与正常数据模式启动成功。这些结果不代替实琴准确率或物理麦克风长音验收，完整记录见 [docs/STATUS.md](docs/STATUS.md)。

只有 Command Line Tools 时，验证脚本会明确标记 iOS 构建为 SKIP；加 `--require-ios` 则缺少 Xcode 也会返回失败。CI 配置在 `.github/workflows/verify.yml`：执行共享代码测试和 iOS 编译，并分别在 iPhone、iPad 模拟器执行 UI 测试；结果与截图保存在每次运行的附件中。实际验收结果见 `docs/STATUS.md`。

具备完整 Xcode 和 iOS 模拟器运行时后，可运行真实触屏交互测试：

```sh
bash scripts/test-ios.sh iPhone
bash scripts/test-ios.sh iPad
```

测试自动选择本机已安装的对应模拟器，覆盖触屏判音、暂停／重启、横屏曲库、收藏搜索、导航暂停、记录空态及拜厄教材目录和原书阅读。使用独立临时曲库，不访问真实 MIDI 或麦克风。该测试入口仅在 Debug 构建中启用；本轮真机执行结果与模拟器构建结果分别记录。

## 曲谱支持范围

第一版支持 UTF-8、单钢琴 part、固定拍号/速度、1–2 个谱表，第一谱表高音谱号、第二谱表低音谱号。支持 divisions、普通音符/休止、和弦、多个 voice 的 backup/forward、弱起、按 duration 表达的连音节奏、连续延音线合并。

- `Resources/Scores` 有三首可编辑、可导入的 MusicXML 示例。
- 内置拜厄覆盖第 1–14、16–18、20–22、24–28、30–37、39–43、61 首；第 1、2 首按主题与变奏拆分，共 59 项。仅提取学生声部，部分反复按已核验的演奏顺序展开；未收入的课程及原因见[资源说明](Sources/QinXuApp/Resources/Books/Beyer/README.txt)。
- 音高由 MusicXML 的 `step / alter / octave` 决定，不会把调号再次叠加。
- 谱面是练习用简化排版，不是原谱的出版级复刻；调号、连线、力度、连梁和部分文字会简化。复杂节奏显示以拍数标注辅助理解。
- 目前不支持 `.mxl` 压缩包、照片/PDF 识谱、反复跳转、装饰音、变速/变拍、移调/八度线、多乐器合奏。这些情况会明确报错，不会默默按错误谱子评分。官方 MusicXML PUBLIC DOCTYPE 会先安全去除；不加载任何外部 DTD。
- 导入上限为 5 MB、1000 小节、20000 个起音音符；本地最多保存 100 首导入曲谱和最近 200 次完成记录。

## 判定边界

识谱模式先检查音高与音组完成，节奏模式按用户设定的四分音符 BPM 检查起音。节奏命中窗口为 ±0.30 秒，窗口内超过 ±0.10 秒显示稍早/稍晚；这只是初版可调参数，不是音乐教学标准。

循环起点如果截断前一小节延续的音，会提示从该音起始小节开始。完成一遍后，至少间隔一秒并等待已接受音符的谱面长音提示结束，再进入下一遍；等待期间仍处理松键事件，双手麦克风停止或暂停会取消待重启循环。

长音提示按被接受音符的采集起点、谱面时值与当前速度计算，与下一待弹音和检测到的声音分别显示。它不延迟识谱前进，也不代表实际按键或踏板状态；麦克风余音不等于新的按键。

按键时长提示是辅助反馈：MIDI 松键不等于踏板延音结束，也不直接评价音乐表现力。首版不评分指法、手型、触键技巧和艺术表达，不进行自由速度的自动跟随。

单音模式需逐音弹奏、相邻音留短暂停顿；多音模式可以输出和弦，但仍建议慢速、不踩踏板试用。Basic Pitch 在一段带 MIDI 真值的真实钢琴录音开发检查中，882 个起音漏掉 383 个（±50 ms 容差），不能称为可靠双手陪练，也不是目标 iPad 的准确率。混响、踏板、轻音及连续重击仍待实测，详见[多音识音说明](docs/POLYPHONIC_MICROPHONE.md)。

## 数据与开发资料

练习记录和导入曲谱保存在应用沙盒的 Application Support/QinXu/library.json；macOS 预览对应用户 Library/Application Support/QinXu。内置教材从应用资源读取，不复制到导入曲库；最近选曲和收藏通过稳定课次 ID 恢复。同一可访问容器内，旧版 `Application Support/PianoPractice/library.json` 会在首次读取时迁移并保留原文件；已有新目录数据时不会覆盖。iOS 更换 Bundle ID 后属于不同沙盒，不能直接读取旧应用的数据。收藏与封面单独保存在 `library.presentation.json`，写入失败保留原状态，损坏或新版本文件先保留恢复副本。默认没有账号、服务器、遥测、订阅或云端音频处理。

- [施工计划与验收标准](docs/PLAN.md)
- [当前进度与验证记录](docs/STATUS.md)
- [架构与数据流](docs/ARCHITECTURE.md)
- [开发、命名与 Git 约定](docs/DEVELOPMENT.md)
- [真机测试清单](docs/DEVICE_TESTS.md)

产品名：**琴序**；英文工程名：**QinXu**。意为按音符的顺序，逐步练好每一段。
