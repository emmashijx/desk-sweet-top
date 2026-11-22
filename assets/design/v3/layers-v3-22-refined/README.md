# V3.22 · 透明蒙版精修

独立版本，原始 V3.22 PNG、主图和 PSD 未覆盖。保留原画 RGB、家具布局、门窗蓝色渐变及墙纸/木材纹理，仅修复轮廓蒙版及其接触阴影。

- `png-layers/`：27 张同尺寸透明 PNG，结构背景原样保留，家具边缘采用连续透明度而非二值蒙版。
- `home-sweet-home-v3-22-refined.psd`：同样的 27 个可编辑图层。
- `layer-manifest.json`：布局及裁切边界，花瓶/灯座/显示器底座保留完整边缘。
- `composited-preview.png`：新图层合成预览。
- `matte-report.txt`：各外轮廓组的精修统计。

使用锁定 V3.22 原画与已有干净底图，图像引导的透明蒙版精修以及窄边抗锯齿，不重新绘制家具。将叉齿分开处理，防止误切细金属件；灯罩、细杆与灯座分别处理。窗口、门、显示器、盘子内层保持无缝叠合。接触阴影独立保留，桌面接触阴影贴随对应家具。

可从项目根目录运行 `xcrun swift -O scripts/refine-room-mattes.swift` 重新导出，再运行 `zsh scripts/build-monitor-app.sh`。
