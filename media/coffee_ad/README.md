# 咖啡商业广告牌演示素材

四张原始画面由内置 image_gen 工具生成，提示词完整保存在 `prompts.json`。网络下载不可用，本包没有采用此前推荐网站的视频，也没有使用第三方录音。主视觉为生成图片，视频采用慢速镜头运动；不是咖啡倒入杯中的实拍录像，也不是文生视频模型直接输出。

- `assets/coffee_hero.png`：无品牌的热咖啡主视觉，用于视频。
- `assets/poster01.png`：现磨咖啡广告。
- `assets/poster02.png`：冰拿铁新品广告。
- `assets/poster03.png`：咖啡与可颂、营业时间公告。

生成 SD 卡媒体与电脑预览：

```bash
/usr/bin/python3 tools/make_coffee_ad.py --output release/coffee_demo
/usr/bin/python3 tools/validate_coffee_ad.py release/coffee_demo
```

需要 Pillow 和 Noto Sans CJK SC；RVF2、AVI、GIF、WAV 生成不需要 ffmpeg。安装有 GStreamer 的 vp8enc/vorbisenc/webmmux 插件时，还会生成 WebM 电脑预览。脚本拒绝覆盖已有结果，重做时请指定新的输出目录。

18 秒、3 fps 的 RVF2 使用固定 RGB332 格式，并加入 4×4 有序抖动以改善照片渐变；配乐为脚本自行合成的 30 拍旋律与节奏。广告促销字幕由 `rtl/media_subtitles.v` 独立叠加，没有烧进视频像素。

最终包的操作与验证记录见 `docs/咖啡广告演示.md`。
