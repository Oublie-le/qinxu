# 实验性双手麦克风识音

## 范围与当前判断

目标设备为用户的 **iPad 9（A13）、iPadOS 18.0.1、电钢琴扬声器**。当前新增独立的“双手 · 实验”输入，使用真实多音模型，并可同时输出多个音符；原有 C3–C6 单音输入仍独立保留。它只用于识谱等待，不评节奏、物理松键时长或踏板。不能把已经接入模型等同于已达到可靠的双手陪练质量。

实录离线检查已发现较高漏音率，下面的测量不支持“可靠双手陪练”的结论。目标 iPad、实际电钢琴、房间声学、权限弹窗与持续运行仍需真机测试。当前适合较慢、不踩踏板的试用，用于发现问题；快速、轻声和弦可能漏音。模型不会读取谱面目标音，也不会用谱面补出没有声学证据的音。

## 模型与资源

- 来源：[Spotify Basic Pitch 官方仓库](https://github.com/spotify/basic-pitch)，固定到 `fa5997af0a8210982619003269994a1be25eddf3`。
- 原始模型：[nmp.mlpackage](https://github.com/spotify/basic-pitch/tree/fa5997af0a8210982619003269994a1be25eddf3/basic_pitch/saved_models/icassp_2022/nmp.mlpackage)。官方已经提供 CoreML 格式，无需 TensorFlow Lite 运行时。
- 许可：[Apache 2.0](https://github.com/spotify/basic-pitch/blob/fa5997af0a8210982619003269994a1be25eddf3/LICENSE)。完整许可和来源说明随应用资源复制；模型保持未修改。
- 模型包共 **269,600 字节**。三个文件的 SHA-256 固定在 `scripts/fetch-basic-pitch.py`。模型二进制位于被 Git 忽略的 `Sources/QinXuApp/Resources/BasicPitch.mlpackage`，不会提交构建产物。
- `python3 scripts/fetch-basic-pitch.py` 下载并校验；`--check` 只验证本地内容，不联网或更改文件。原始包在设备上由 CoreML 编译。缺失时明确禁止启动，不使用占位结果。
- 原生模型检查实际确认输入 `Float32 [1,43844,1]`，音符和起音输出分别为 `Float32 [1,172,88]`，覆盖 MIDI 21–108（A0–C8）。输出行有内存填充，读取使用真实 stride。
- 输入为 22,050 Hz、单声道，窗口约 1.988 秒；尺寸及默认起音/持续阈值来自[官方常量](https://github.com/spotify/basic-pitch/blob/fa5997af0a8210982619003269994a1be25eddf3/basic_pitch/constants.py)和[推理实现](https://github.com/spotify/basic-pitch/blob/fa5997af0a8210982619003269994a1be25eddf3/basic_pitch/inference.py)。应用的流式事件提取器不是完整的官方离线 MIDI 后处理器。

## 音频与时间规则

- 首次需要收满约 2 秒；之后在采样推进至少 200 ms 时分析最新窗口。固定容量的环形缓冲持续接收音频，推理最多一个任务，不积压旧窗口。
- AVAudioTime 的 sampleTime 用于连续性、窗口边界和重叠帧去重。hostTime 在启动时桥接至 `ProcessInfo.systemUptime`。回调到达时间不参与拼接与判音时间戳。缺少有效时间、采样中断或时间关系异常时停止，并要求重新开始。
- 使用 AVAudioConverter 转为模型采样率；窗口两端各弃 15 帧。逐音使用起音阈值 0.5、持续阈值 0.3，约 128 ms 最短确认、释放迟滞及重新起音处理。确认起音会回溯到声学起点，短暂保留较新的释放事件以维持跨窗顺序。
- 等待引擎单独容许最多 3 秒已知缓冲延迟；MIDI、单音输入默认仍为 250 ms，节奏模式不接受放宽。真正的采集时间保留，因此先弹松 C、隔一秒再弹 E 不会被同批到达误算成 C+E 和弦。暂停前、旧 run 的缓冲不能被新 run 评分。
- 每个事件投递前检查服务是否仍活动以及 generation；完成或切换输入导致同步停止后，同批尾部事件不再投递。音频设备改变、推理错误、取消启动、后台与暂停都清理采集状态。

## 2026-11-25 离线实录测量

样本来自 [MAESTRO 3.0.0 官方数据集](https://magenta.tensorflow.org/datasets/maestro)，2008 年 Scarlatti《Sonata K.525》，官方 test split。真实 Yamaha Disklavier 声学钢琴录音配有对齐 MIDI；**不是合成正弦波，也不是另一个模型的输出作为真值**。该数据集使用 CC BY-NC-SA 4.0，音频和 MIDI 仅保存在本机被忽略的评估目录，不打包到应用。

原始文件：`2008/MIDI-Unprocessed_09_R3_2008_01-07_ORIG_MID--AUDIO_09_R3_2008_wav--2`。WAV 为 11,845,452 字节，MIDI 为 6,879 字节。下载脚本从固定官方 ZIP generation 获取约 13 MB 的范围，验证原文件 SHA-256，避免下载整个 108 GB 数据集。曲目按官方 test split 中最短时长选择，没有按识别结果挑选。

在本机 Mac 上使用实际 CoreML 模型、应用相同的阈值和流式提取规则，回放 326 个重叠窗口。模型、音量、阈值没有根据该曲调参。时间及生命周期修复后重新测量；由于该文件也被用于检查集成，**它属于开发检查，不能作为独立盲测集或普遍准确率**。未验证它与上游训练数据的独立性。

分析区间为音频 0.174–66.811 秒，区间内真值 882 个起音，检测 584 个。以音高相同及起音容差做一对一最大匹配，不评分结束时刻。

| 起音容差 | 匹配 | 多报 | 漏报 | 精确率 | 召回率 | F1 |
|---|---:|---:|---:|---:|---:|---:|
| ±50 ms | 499 | 85 | 383 | 85.45% | 56.58% | 68.08% |
| ±100 ms | 508 | 76 | 374 | 86.99% | 57.60% | 69.30% |

最多同时跟踪 6 个音。Mac CPU 模型推理中位数 6.15 ms、p95 6.44 ms；在离线模拟的窗口调度中，检测起音到可投递的中位延迟约 407 ms、p95 499 ms，首次仍要等待约 2 秒音频。**这些不是 iPad 9 的延迟**，不包含真实麦克风输入、音频系统、线程调度或实际房间的影响。

精确机器可读数据见 `docs/evidence/polyphonic-maestro-2026-11-25.json`。这次结果明确显示漏音仍多，不能宣称目标设备上的准确率或生产可用。

复现命令（在装有 Apple SDK 的 Mac 上）：

```sh
python3 scripts/fetch-basic-pitch.py
python3 scripts/fetch-polyphonic-fixture.py
swiftc Sources/QinXuApp/Services/BasicPitchModel.swift Sources/QinXuCore/PolyphonicNoteTracker.swift scripts/evaluate-polyphonic.swift -o /tmp/qinxu-poly-eval
/tmp/qinxu-poly-eval Sources/QinXuApp/Resources/BasicPitch.mlpackage .local-build/polyphonic-evaluation/recording.wav .local-build/polyphonic-evaluation/predictions.json
python3 scripts/score-polyphonic-evaluation.py .local-build/polyphonic-evaluation/reference.midi .local-build/polyphonic-evaluation/predictions.json .local-build/polyphonic-evaluation/report.json
```

CoreML 编译器需要系统正常临时目录权限；沙盒中权限失败是运行环境限制，不能把缺模型或未推理当作通过。自动化另覆盖真实模型 shape/stride/静音、44.1/48 kHz 重采样、和弦/重击、无起音证据拒绝、连续采样/缺段、延迟回调不变、批中途停止、旧 run 和假和弦回归。自动化通过仍不代表实琴质量已验收。
