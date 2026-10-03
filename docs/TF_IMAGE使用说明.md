# TF卡图片播放器

工程：prj/TF_IMAGE.al；顶层：rtl/tf_image_top.v；最新下载文件：release/TF_IMAGE.bit。仓库仅保留当前TF_IMAGE主工程。

## 上板

1. TF卡格式FAT32，640×480、24位RGB、无压缩、正高度BMP放根目录。文件名自由，最多前32张，按目录项顺序播放。
2. 安全弹出读卡器，开发板断电后插入TF卡，再上电。
3. BitWriter删除旧列表项，添加release/TF_IMAGE.bit，选AL-LINK、PROGRAM_SRAM、1MHz，再Run。
4. 加载时显示黑色转圈及状态文字，完成后显示照片。
5. KEY1复位；KEY2下一张；KEY3上一张；KEY4开关轮播。SW1/SW2选择间隔，SW3选择轮播方向。
6. SW6拨上接通数码管，显示“01 OF 04”及实际总数；SW5拨下接通按键蜂鸣声。
7. 确认正常后选PROGRAM_FLASH、1MHz写入同一文件，断电重启验证。SRAM模式断电会丢失，配置按键会重新加载Flash程序。

文字透明叠加：左上角文件名、右上角序号、左下角轮播状态，开启轮播后才显示间隔和方向，约2秒自动隐藏；读卡失败显示具体错误及KEY1重试提示。音频播放尚未实现，蜂鸣声为按键提示音。

## 代码作用

- tf_image_top.v连接时钟、SD卡、解析、SDRAM缓存、屏幕提示和HDMI输出，处理启动复位、跨时钟总数同步及整帧切换。
- fat32_bmp_loader.v为自行编写的只读FAT32解析器，扫描根目录、验证BMP、统计并选择图片、跟随碎片化簇链，将BGR转换成RGB像素。
- image_key_control.v处理按键、轮播计时、方向及实际总数下的循环索引。
- image_status_osd.v产生英文点阵提示并按帧锁存状态；loading_spinner_rgb.v产生黑色背景十二点转圈。
- image_number_display.v驱动低有效共阳段及PNP位选；key_beeper.v处理每次按键短鸣。
- video_timing_registered.v产生已对齐的扫描位置与同步；图片和提示采用一致的视频延迟。
- rtl/vendor/tf_reference保留资料中的低层SD SPI、异步FIFO、SDRAM访问和视频读延迟；HDMI编码/串行发送沿用已验证参考模块。

SDRAM40MHz，移相输出延后12ns；SD逻辑50MHz，初始化SPI约200kHz，读卡12.5MHz；像素25MHz，串行125MHz。BMP自底向上的行顺序由缓存写地址翻转纠正。

格式、异常、测试和本次时序结果见自动扫描与屏幕提示.md。编译命令：bash prj/build_tf_image.sh。新版本已通过仿真和布局布线，实板显示仍需下载确认。
