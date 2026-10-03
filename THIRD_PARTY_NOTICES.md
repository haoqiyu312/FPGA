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
