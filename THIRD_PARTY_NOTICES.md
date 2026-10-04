# 第三方来源说明

## 板卡及工具参考模块

`rtl/vendor/tf_reference/` 的 SD SPI、异步 FIFO、SDRAM 访问等底层模块来自板卡赛题资料中的 `lab_ex4_tf` 参考工程。项目使用了这些底层模块，未使用参考顶层或参考文件解析器。

`rtl/vendor/hdmi_tx.vhd` 与 `rtl/vendor/enc_file/` 保留板卡参考工程中的 HDMI/DVI 编码、串行发送模块，其中部分为厂商加密 HDL；`prj/al_ip/video_pll/` 是 TD IP Generator 生成的 PLL。它们保留各自来源和原有声明，不在本仓库中另行指定授权。

自行实现的 FAT32/BMP 解析、图片控制、扫描显示及中文提示等逻辑位于 `rtl/`。TD 编译工具及其许可证需在使用者本机安装，仓库不包含这些软件或许可证。

## 中文字体

内置 UI 点阵位于 `rtl/osd_font16.v`，由 `tools/generate_osd_font.py` 从 Noto Sans CJK SC Regular 截取所需的 171 个字符，转换为 16×16 单色字形。字库不包含整套原始字体。

字体来源：Noto CJK（本机 fonts-noto-cjk 包）；Copyright 2010–2012 Google Corporation，SIL Open Font License 1.1。随附字体声明及许可证在 `docs/licenses/OSD_FONT_OFL.txt`。字库生成脚本不需要在 FPGA 编译时运行。

## 示例照片

四张示例照片来自 Pexels，页面及原图地址、转换参数见 `media/sources.json`。`media/originals/` 保留原图，`media/PIC01.BMP` 至 `PIC04.BMP` 是旋转/等比缩放/黑边填充后的上板素材。

## HDMI 音频协议与物理层

`rtl/vendor/hdmi_audio/` 中的加密 HDMI 1.4b 核、`hdmi_phy_warpper.v` 和 `lane_lvds_10_1.v` 来自赛题资料 `lab_ex5_i2s`，保持原始字节。协议编码和器件 DDR 串行发送复用该厂商 IP，不属于本项目自主算法。现工程不再实例化原 DVI 发射器。

`hdmi_test_audio.v`、`hdmi_video_stream.v` 和 `hdmi_audio_output.v` 为本项目实现。测试音直接在像素时钟域产生 PCM 和固定比率的 N/CTS，不使用参考例程的音频 PLL、I2S 音源/接收器及 ACR 周期测量模块。仓库不分发厂商说明文档或工具许可证。
