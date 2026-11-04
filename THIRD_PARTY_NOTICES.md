# 第三方组件与素材声明

## 板卡参考 IP

`rtl/vendor/tf_reference/` 中的 SD SPI、异步 FIFO 和 SDRAM 模块来自赛题板卡资料的 `lab_ex4_tf` 参考工程。本项目复用底层接口模块，不使用参考工程的顶层和媒体解析流程。

`rtl/vendor/hdmi_tx.vhd`、`rtl/vendor/enc_file/` 与 `rtl/vendor/hdmi_audio/` 中的 HDMI/DVI 编码及物理层模块来自赛题资料，包含厂商加密 HDL；`prj/al_ip/video_pll/` 是 TD IP Generator 生成的 PLL。保留文件原有声明。安路 TD 及其器件许可证由使用者自行安装，仓库不包含软件和许可证。

## 字体

- `rtl/osd_font16.v` 使用 Noto Sans CJK SC Regular 中的项目所需字形，生成脚本为 `tools/generate_osd_font.py`。字体基于 SIL Open Font License 1.1，许可证见 [OSD_FONT_OFL.txt](docs/licenses/OSD_FONT_OFL.txt)。仓库不包含完整字体。
- `rtl/browser_ascii_font.v` 使用 DejaVu Sans Mono 的 ASCII 点阵子集，生成脚本为 `tools/generate_browser_font.py`。相关声明见 [BROWSER_FONT_LICENSE.txt](docs/licenses/BROWSER_FONT_LICENSE.txt)。

## 示例照片

`media/originals/` 保存四张 Pexels 原图；`media/sources.json` 记录来源页和转换信息。`media/PIC01.BMP` 至 `PIC04.BMP` 是供当前 720×720 播放器使用的无压缩 BMP 示例素材。

## HDMI 音频

`rtl/vendor/hdmi_audio/` 中的 HDMI 1.4b 音频传输核和串行发送模块来自赛题资料 `lab_ex5_i2s`。项目自己的音频缓冲与控制逻辑位于 `rtl/`。厂商文档和工具许可证不随仓库分发。
