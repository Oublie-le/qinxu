# iPad 验证环境

目标设备由用户确认：iPad 第 9 代，iPadOS 18.0.1；电钢琴通过扬声器发声。开发目标仍是原生 iOS 应用，Mac 只供共享代码预览。

## 本机准备

2026-11-25 已安装 `/opt/homebrew/bin/mas` 7.0.0，并打开免费 Xcode 的 App Store 页面。安装命令遇到 macOS 管理员认证；用户已自行开始安装，并确认 iPad 已信任本机。USB 枚举已看见 iPad。完整 Xcode 27.2（27B52）现已安装，许可与首次工具设置已完成，iOS 27.2 SDK 可用；模拟器运行时仍在下载。开发者模式、签名、实际部署须分别确认，不能把 USB 可见当作应用已安装。

Xcode 安装完后，首次打开并完成系统组件安装。Apple 要求的管理员密码与 Apple 账号认证只在系统界面完成，不保存到项目。

```sh
bash scripts/check-ios-environment.sh
bash scripts/prepare-resources.sh
python3 scripts/generate_project.py
bash scripts/verify.sh --require-ios
open QinXu.xcodeproj
```

资源准备下载固定版本 Basic Pitch 模型和公版拜厄 PDF，逐个校验 SHA-256；源文件与许可随应用打包。下载文件不进入 Git。

## 安装到 iPad

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
- 切后台、暂停或换输入后应停止录音。具体记录见 `DEVICE_TESTS.md`。

拜厄在「曲谱 → 教材」中可离线翻阅完整公版 PDF；它目前是阅读谱，不接自动判音。可判音的曲谱仍使用内置原创样谱或导入的受支持 MusicXML。

参考：[Apple Xcode 要求](https://developer.apple.com/xcode/system-requirements)、[Apple 开发者模式说明](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device/)。
