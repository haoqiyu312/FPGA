# 安路 FPGA TF 卡多媒体播放器

基于 HX4S20 开发板（EG4S20BG256），从 FAT32 TF 卡读取图片和预转换视频，经 SDRAM 帧缓存输出到 HDMI。

## OLED＋矩阵键盘版本

主版本固件为 [`release/TF_MEDIA_OLED.bit`](release/TF_MEDIA_OLED.bit)，工程为 `prj/TF_MEDIA_OLED.al`。OLED 显示中文文件菜单和播放状态，4×4 矩阵键盘控制选文件、图片缩放、轮播、字幕和频谱；HDMI 输出图片或视频。完整接线与按键说明见 [OLED 与矩阵键盘](docs/OLED与矩阵键盘.md)。

播放本机视频前，需转换成 720×720 RVF 格式。OLED 工程支持最高 5 fps；RVF2 音轨使用 12 kHz 单声道 μ-law。转换命令和格式说明见 [OLED 使用说明](docs/OLED与矩阵键盘.md)。

## TF 卡文件

- 文件系统：FAT32。
- 图片：720×720、24 位、无压缩 BMP。
- 视频：RVF1（无音频）或 RVF2（带音频）；MP4 等格式需先在电脑上转换。
- 字幕：与视频同名的 `.SRT` 文件。

TF 卡根目录可混放支持的图片和 RV 文件，OLED 菜单按目录顺序列出。单独的 WAV、MP3 等音频文件目前可显示在列表中，播放器不直接解码播放。

## 下载和操作

1. TF 卡设为 FAT32，将图片、RV 视频和可选同名 SRT 放在根目录。
2. 开发板断电后插卡，再上电。
3. 用 BitWriter 选择 AL-LINK、PROGRAM_SRAM、1 MHz，下载 `TF_MEDIA_OLED.bit`。
4. 使用矩阵键盘浏览并打开文件。详细按键表见 [OLED 与矩阵键盘](docs/OLED与矩阵键盘.md)。

HDMI 屏幕触控接口不能接入该开发板，本版本使用矩阵键盘操作。

## 其他固件

- [`TF_MEDIA_720_R2.bit`](release/TF_MEDIA_720_R2.bit)：原生 720×720 播放器，可作为不使用 OLED 菜单时的备用固件。使用方法见 [720 方屏说明](docs/720方屏使用说明.md)。
- [`TF_MEDIA_COFFEE.bit`](release/TF_MEDIA_COFFEE.bit)：咖啡广告场景演示固件，相关素材见 [咖啡广告演示](docs/咖啡广告演示.md)。

## 构建

需要安路 TD 6.2.1 和对应器件许可证：

```bash
TD_BIN=/你的TD安装目录/bin/td.sh bash prj/build_tf_media_oled.sh
```

工程文件位于 `prj/`，自编 RTL 和板卡接口逻辑位于 `rtl/`，媒体转换工具位于 `tools/`。字体及其他第三方组件声明见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
