# Desk Sweet Top

Home Sweet Home 是一个原生 macOS 桌面房间原型。它将一面墙和地板上的手绘家具作为可交互的桌面入口，而不是使用传统的应用图标列表。

![房间效果](assets/design/v3/layers-v3-22-refined/composited-preview.png)

## 当前版本

- 27 个独立图层，全屏无留白，家具保持等比缩放。
- 房间编辑器：导入或生成背景、添加/移动/调整家具、保存多套布置及切换布局。
- 显示器：浅雾蓝色选择器，Chrome/Safari，半屏/全屏，优先复用浏览器现有会话。
- 支持英文、简体中文和繁体中文，跟随 macOS 首选语言。

其余家具尚未接入具体交互功能。

## 本机运行

在安装 Xcode Command Line Tools 的 Mac 上，从仓库根目录执行：

```sh
zsh scripts/build-monitor-app.sh
open output/local-test/HomeSweetHome.app
```

首次运行可在编辑器中载入原始布局，保存后进入房间。点击显示器选择窗口模式与浏览器；`⌘E` 编辑布置，`⌃⌘F` 切换房间全屏，`⌘Q` 退出程序。

若需要自动调整浏览器窗口，macOS 可能会请求自动化和辅助功能授权。详情见 [本地测试指南](app/LOCAL-TEST.md)。

## 运行测试

```sh
output/local-test/HomeSweetHome.app/Contents/MacOS/HomeSweetHome --self-test
output/local-test/HomeSweetHome.app/Contents/MacOS/HomeSweetHome --capture-test output/local-test
output/local-test/HomeSweetHome.app/Contents/MacOS/HomeSweetHome --type-test output/local-test/monitor-typeset
```

测试使用模拟浏览器驱动，不修改真实浏览器会话。房间布局储存在本机，不随仓库上传。OpenSpec 变更记录位于 `openspec/`。

设计资产保留当前可编辑 PSD、透明 PNG 以及必要的原始素材。详见 [透明图层说明](assets/design/v3/layers-v3-22-refined/README.md)。
