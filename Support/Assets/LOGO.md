# 片刻图标

生成方式：内置 image_gen，透明背景，新图生成。2026-10-31。

文件：Logo.png（原始带透明通道图像）、AppIcon.icns（使用 macOS sips/iconutil 转换的多分辨率应用图标）。菜单栏用 AppKit 绘制同概念的单色简化标记。

提示词：

2026-10-31 v0.4.1：按用户要求改为黑底红色。由原图用 `work/recolor_icon.py` 程序化换色，形状、倒角和透明通道不变；原绿色版保留在 `work/icon-green-original/`。v0.4.2 再改为扁平纯黑底与纯红标记，去掉倒角与高光（`work/flatten_icon.py`）。下方为原始生成提示词。

Create one finished macOS app icon for FacePause, a quiet personal facial pulse wellness utility. Square 1024x1024 image, with an elegant rounded-square icon occupying most of the canvas and genuinely transparent outer corners. Deep near-black evergreen tile, softly beveled and very restrained light from upper left. Center a bold, extremely simple mint-white symbol combining two rounded pause bars with one short pulse wave joining their middle, suggesting a moment of calm and a heartbeat. The custom symbol must remain recognizable at 16 pixels: thick clean strokes, generous breathing room, symmetrical balance, no tiny details. Premium Apple-native utility icon, restrained matte enamel, almost flat, no busy 3D ornaments. No letters, no text, no heart outline, no medical cross, no face illustration, no mockup, no extra icons, no background scene. Deliver only the standalone application icon.
