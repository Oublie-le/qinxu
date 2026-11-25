# iPad 验证环境

目标设备由用户确认：iPad 第 9 代，iPadOS 18.0.1；电钢琴通过扬声器发声。开发目标仍是原生 iOS 应用，Mac 只供共享代码预览。

## 本机准备

2026-11-25 已安装 `/opt/homebrew/bin/mas` 7.0.0 与完整 Xcode 27.2（27B52），许可与首次工具设置已完成，iOS 27.2 SDK 可用。iPad 已信任本机，开发者模式和调试通道已就绪；此前版本的开发签名、严格签名检查、安装与 `devicectl` 启动均已成功，用户确认能打开。账号认证由用户在系统界面完成，不保存到项目。

最新 `verify.sh --require-ios` 已通过 107 项测试（65 项核心、42 项应用）及 iOS Simulator 目标构建，拜厄源数据重建核验通过。当前 59 项教材版本在这台 iPad 上的 6 项 XCTest UI 测试全部通过，xcresult 摘要确认且截图已导出；严格签名复核通过，恢复正常数据模式后的 `devicectl` 启动成功。模拟器运行时在最近一次环境检查时仍在下载；真机测试不需要等待模拟器运行时。完整证据见 [STATUS.md](STATUS.md)，实琴与物理麦克风长音仍需另行验收。

```sh
bash scripts/check-ios-environment.sh
bash scripts/prepare-resources.sh
python3 scripts/generate_project.py
bash scripts/verify.sh --require-ios
open QinXu.xcodeproj
```

资源准备下载固定版本 Basic Pitch 模型、Bravura 字体和公版拜厄 PDF，逐个校验 SHA-256；资源许可随应用打包，下载文件不进入 Git。中文课次 MusicXML 与目录已随源码保存；需要重建核验时可另运行 `python3 scripts/import-beyer-ranote.py --fetch --check`。

## 安装到 iPad

以下是首次配置或更换设备时的步骤；当前目标 iPad 已完成此前版本的安装与信任，无需重复创建证书。

1. 用数据线连接、解锁 iPad，并信任此 Mac。
2. 配对后在 iPad 的「设置 → 隐私与安全性 → 开发者模式」开启，按系统要求重启并确认。
3. Xcode「Settings → Apple Accounts」添加自己的 Apple 账号；在账号/团队的「Manage Certificates」创建 Apple Development 证书。使用下方脚本将 Team ID 保存为本机配置，保留 Automatically manage signing。
4. Scheme 选择 QinXu，运行设备选择这台 iPad，Run。若个人账号提示 Bundle Identifier 冲突，换为自己的唯一标识；不要提交个人签名配置。
5. 如果 iPad 提示开发者不受信任，按系统指引在「设置 → 通用 → VPN 与设备管理」完成信任，然后重新打开。

个人签名配置只写入 Git 忽略的 `Config/LocalSigning.xcconfig`，不会进入共享工程或保存密码，重新生成工程也会保留：

```sh
python3 scripts/configure-ios-signing.py YOURTEAMID
# 如默认 Bundle ID 被其他团队占用，再设置自己的唯一标识：
python3 scripts/configure-ios-signing.py YOURTEAMID --bundle-id com.example.QinXu
```

## 麦克风验证路径

- 横放 iPad，选择「并肩 · 双手和弦」→ 开始练习页面。
- 点演奏输入图标，选择「双手 · 实验」，完成后开始练习，并允许麦克风。
- 先关闭踏板，以较慢速度弹奏。首次需收集约 2 秒音频；之后采用重叠窗口分析。该缓冲不是已测得的端到端延迟。
- 观察屏幕琴键、待弹音与正确/错音计数，记录实际和弦漏音、误音、同音重击和响应时间。麦克风仅提供识谱等待，不评节奏或物理松键时长。
- 键盘音域按整首曲谱与所选手固定，至少三八度；宽度不足时手动横向滚动，不应随目标音跳动。绿色为待弹，浅橙为按谱面时值应保持，橙色为检测到的声音；余音不等于新的按键。
- 开启小节循环后，末尾长音提示应保留至谱面时值结束，再开始下一遍；循环等待中松键仍更新声音状态，双手麦克风停止或暂停不得自行重启。
- 切后台、暂停或换输入后应停止录音。具体记录见 `DEVICE_TESTS.md`。

## 拜厄教材验证路径

- 在「曲谱 → 教材 → 拜厄钢琴基本教程」打开中文课次目录，当前 59 项练习覆盖 39 首原曲；第 1、2 首的主题与变奏分别列出，准确范围见[资源说明](../Sources/QinXuApp/Resources/Books/Beyer/README.txt)。
- 点课次进入详情，或点「练习」直接开始，可选择左右手；返回后确认收藏与最近选曲可恢复，课次不会重复出现在「已导入」中。
- 点「原书」查看完整 88 页外文公版 PDF。中文练习谱为公版原作重排，不是出版社中文版；外文 PDF 仅供对照，不作为判音数据。
- 小汤 1/2/3 尚未内置：用户没有纸书，完整电子谱仍未取得。可用来源的查询与缺口见 [TEXTBOOK_SOURCES.md](TEXTBOOK_SOURCES.md)。

参考：[Apple Xcode 要求](https://developer.apple.com/xcode/system-requirements)、[Apple 开发者模式说明](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device/)。
