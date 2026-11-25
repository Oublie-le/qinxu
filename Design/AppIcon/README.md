# 琴序应用图标

用户于 2026-11-25 选定的第一版图标：米白底、墨绿琴键框与朱砂键。
本目录的 `QinXu-selected-original.png` 是选中图片的逐字节副本，未重绘、裁切或改变配色。

- 原图：1254 × 1254，RGB PNG，无透明通道。
- SHA-256：`0db6782b4ab26ff7873f938d2b6ce2c75ed00676cb49774cc7c2f15a4e9a34e9`。
- 来源：本次对话中生成并由用户确认的图像 `exec-f0445f4f-d3e8-474f-83ca-2df085b51f40.png`。
- iOS 资产：`Sources/QinXuApp/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png`。
- 1024 资产 SHA-256：`12a1238f8777ce1941014610a9e66f04880df8c46af2a0dadec7efbf35407a09`。

唯一图像转换是用系统 `sips` 等比缩为 1024 × 1024；没有额外圆角遮罩或主题变体：

```sh
sips -z 1024 1024 Design/AppIcon/QinXu-selected-original.png \
  --out Sources/QinXuApp/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png
```

iOS 工程将该目录作为 asset catalog 编译，Debug / Release 均设置 `AppIcon`。
采用 Apple 支持的单张 1024 像素图标输入，由 Xcode 生成所需尺寸；深色/着色外观使用系统处理。
参考：[Apple：使用 asset catalog 配置应用图标](https://developer.apple.com/documentation/xcode/configuring-your-app-icon)。

Mac 仅为开发预览。`scripts/build-macos.sh` 调用 `scripts/create-macos-icon.sh`，
从同一图像生成各尺寸 `.icns` 并写入已忽略的 `.local-build/QinXu.app`；不提交编译产物。
PNG 是交付所需的设计源资产，不应像构建缓存或可执行二进制一样被忽略，否则新检出会缺少图标。
