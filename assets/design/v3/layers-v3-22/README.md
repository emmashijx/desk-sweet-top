# V3.22 · 门窗瓷砖渐变

基于 V3.21 独立图层。顶部浅冰蓝瓷砖，中部雾蓝，底部深海蓝。只替换旧的 10（窗框和瓷砖）与 12（门框）图层的对应区域；其余 25 张透明 PNG 与 V3.21 逐文件完全一致。保留修复后的木质材质、墙纸、家具、窗景与光线。画布 1557 × 1010，27 个图层。

- `master-preview.png`：在锁定主图上合成渐变装饰。
- `composited-preview.png`：27 个图层实际叠合预览。
- `home-sweet-home-v3-22.psd`：完整 PSD。
- `png-layers/`：27 张同画布 PNG，保持 V3.21 编号与位置。
- `layer-manifest.json`：图层顺序与位置。

内置 ImageGen 生成渐变参考图，Swift 图层合成只采用门窗框图层的对应区域；不重绘其他图层。原始 V3.21 分层包保留。

## Prompt

Use case: precise-object-edit. Edit the exact repaired V3.21 Home Sweet Home Desktop room. Change ONLY the glazed BLUE DIAMOND CERAMIC mosaic strips tracing the arched upper window surround and the arched door surround. Preserve their exact positions, thickness, tile shapes and checkerboard rhythm, and all cream/gold molding, ornaments, pink door and window mullions; do not add tile area. On EACH arch independently, create a clearly visible top-to-bottom graduation of the physical tile colors: very top and crest are soft pale icy mist blue and pearl blue, middle arc is muted mid-tone cornflower/duck-egg blue, vertical lower jamb sections progressively deeper dusty ocean blue and deepest slate/navy blue at the bottom. Gradual transition of individual alternating ceramic diamond colors, retain subtle lighter/darker tiles in each zone, not an overlay on room and not uniform saturation. Light upper ends contrasting deep lower ends. Restrained cool blue, not vivid neon; softly glazed vintage Barcelona ceramic. All other parts identical to V3.21, especially repaired crisp natural wood grain, ivory wallpaper, gray-purple calm window landscape, book arrangement, flower lamp, clocks, map, plate player, trash bin and rug; preserve original neutral soft daylight and geometry. No other changes.
