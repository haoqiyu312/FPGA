# 项目上下文（供主机端 Codex 与技术文档使用）

最后更新：2026-11-03。本文保存项目长期背景，帮助不同设备上的 Codex 接续工作；它不是完整聊天记录。涉及当前操作、用户新反馈和 Git 状态时，应以最新对话、工作区和 GitHub 仓库为准。

## 项目概况

本项目是安路 EG4S20BG256 FPGA 上的 TF 卡媒体播放器。支持 BMP 图片、RV 视频及 RVF2 音频，通过 HDMI 输出；画面上有中文状态栏、文件菜单和字幕。板上按键控制播放。主要 RTL 在 `rtl/`，Tang Dynasty 工程在 `prj/`，约束在 `constraints/`，素材转换工具在 `tools/`，说明和排查记录在 `docs/`。

## OLED＋矩阵键盘版本

用户选择 SSD1306 128×64 I²C 3.3V OLED＋4×4 矩阵键盘，放弃 TFT 触控方案。独立工程 `prj/TF_MEDIA_OLED.al`，顶层 `rtl/tf_media_oled_top.v`，固件 `release/TF_MEDIA_OLED.bit`。GPIO/按键表见 `docs/OLED与矩阵键盘.md`。OLED 用 J1-1 SDA/D14、J1-2 SCL/G11；矩阵 R1–R4 用 J1-3–6，C1–C4 用 J1-7–10；VCC J1-29 3.3V，GND J1-12/30。
HDMI 菜单与播放状态文字由 OLED 显示；菜单期间 HDMI 黑屏，不再加载 DEFAULT.BMP。保留图片、RV 视频、HDMI 音轨、同名 SRT、频谱、缩放和轮播；独立音频仍只浏览。视频底边有随实际呈现帧推进的进度条，暂停时冻结，视频循环时重置。图片 S8 放大（50%→100%→200%），S12 缩小（200%→100%→50%），到边界停止；缩放提示在右下角约 1.8 秒后隐藏。启动固定等待约 100 ms，SD 初始化 SPI 时钟约 397 kHz。
按键映射：S2/S10 菜单上下，S6 打开/视频暂停，S4 返回/恢复；图片 S5/S7 切图、S1 轮播、S3 方向、S8/S12 缩放、S9/S11 间隔减/加 1 秒（1–20 秒）；视频 S1 字幕、S3 频谱、S13 重播；S16 复位并重扫，S14/S15 预留，板载 KEY1 保留备用。
当前 OLED bit 用 TD 6.2.1 Build 175876 完整 Routed：SWNS +1.062 ns、STNS 0、HWNS +0.024 ns、HTNS 0；LUT 16756/19600、寄存器 9195/19600、BRAM 64/64、PLL 2/4、DSP 8/29。最近的进度条/启动/缩放改动只完成完整构建与布线，未重新运行 RTL 仿真，也未上板验证。SHA-256：`605cfce9865e0a5cbab7cd14687cadbd6bfaea7d295112b92db93caf8f22ec15`。构建 `bash prj/build_tf_media_oled.sh`，打包 `python3 tools/package_media_oled.py`。
本次上传包括 OLED 候选源码和固件。工作区另有 2026-11-02 生成的旧 `TF_MEDIA_720_SPECTRUM.bit`，晚于该文件的共享 RTL 已改动，未纳入提交；要发布它须先重新构建和验证。已验证的 R2 仍是 720p 回退版本。

## 当前可用版本

用户于 2026-11-02 报告：新版原生 720×720 固件已能正常播放。这是实板反馈。对应版本为 `release/TF_MEDIA_720_R2.bit`，设备为 EG4S20BG256。其 JSON 构建记录在 `release/TF_MEDIA_720_R2.json`，SHA-256 为 `e967ab20d5fac5743d6d3111245a1897e839be651c135beebb25cc86a813a1d7`。

R2 的像素时钟为 48 MHz，输出 720×720 有效画面；存储时钟为 50 MHz。视频为 1 fps、音轨 12 kHz。图片、视频、音频、字幕、文件菜单和板上按键功能保留；**频谱图层暂时关闭**。此前确认正常的 640×480 回退固件是 `release/TF_MEDIA_SW4_R2.bit`，其 SHA-256 为 `9c891b2f9726e3194dbc17731f46701b798faa88559760c58e7731bba66894fb`。

屏幕型号尚未由 EDID 确认。用户描述的四寸 720×720 屏与 Waveshare 4inch HDMI LCD (C) 相符；R2 按该屏公开时序参数配置。背景、原因和限制见 [`docs/720黑屏排查与R2候选.md`](docs/720黑屏排查与R2候选.md)。用户现已确认 R2 能正常播放，所以该文档开头提到的“实板尚未验证”属于**构建时的历史记录**，后续引用时应以本段日期更新的用户反馈为准。

## 素材格式

- 图片：24 位、无压缩 BMP，尺寸 720×720。
- 视频：本项目使用自定义 RVF 格式；RVF1 无声，RVF2 可带音频。720 R2 建议视频帧率 1 fps、单声道 12 kHz μ-law 音频。MP4 不能直接放入卡中播放，需先转换。
- 可用转换工具：`tools/convert_image720.py`、`tools/convert_video.py`、`tools/convert_media720.py`。媒体及演示包的细节查阅根目录 `README.md` 和相关 `docs/` 页面。
- 不要把其他 640×480 工程的旧 RV 文件误认为 720 R2 素材；检查宽高、RVF 版本、帧率和音轨采样率。

## 工程与构建

- R2 工程：`prj/TF_MEDIA_720_R2.al`。
- 构建脚本：`prj/build_tf_media720_r2.sh`、`prj/build_tf_media720_r2.tcl`；最终保持时间修复脚本：`prj/fix_tf_media720_r2_hold.tcl`。
- 约束：`constraints/tf_media720_r2.sdc`。
- PLL 包装：`rtl/video_pll_48.v`、`rtl/memory_pll_50.v`。加密的厂商 HDMI/SDRAM 源码不要编辑。
- 本地工具版本：Tang Dynasty 6.2.1 SP1 build 178840。Linux 示例：

```bash
TD_BIN=/path/to/TD_6.2.1_SP1/bin/td.sh bash prj/build_tf_media720_r2.sh
```

编译报告、布线时序、RTL 仿真和实板反馈是不同的证据，文档中应分别标注。构建记录的最终布线余量：SWNS +0.151 ns、STNS 0、HWNS +0.037 ns、HTNS 0。素材转换相关 Python 检查 20 项通过；当时环境缺少 Icarus Verilog，新增 RTL 仿真未运行。用户之后确认固件实板正常播放。

## GitHub 与跨设备协作

仓库为 `https://github.com/haoqiyu312/FPGA.git`，主分支 `main`。2026-11-02 新版代码已推送，提交 `5b3076f`（`Fix native 720x720 display timing and playback`）。主机端在相同仓库执行 `git pull origin main` 后即可读取本文件和 R2 代码。若远端以后前进，以实际 `git status` 和远端状态为准，切勿强制推送覆盖他人更新。

项目协作习惯记录于 `AGENTS.md`。默认只做本地更改；只有用户明确要求上传时才提交和推送。上传失败时明确说明失败，并保留本地提交。

## 文档写作建议

写技术说明时，优先使用本文件、README 和具体功能文档中的已确认事实。把用户实板反馈、构建日志和推测分开表达。屏幕型号、HDMI_B 接线、采样相位稳定性等未独立确认的信息不要写成普遍保证。描述升级效果时可使用 `release/resolution_showcase720/` 的预览素材，但其中模拟的对比画面不是实板截图。
