# SnapLite

轻量的 macOS 菜单栏截图工具：区域 / 窗口 / 全屏 / 延时截图，外加**长截图**（手动滚动、自动拼接）。
原生 Swift + AppKit，零第三方依赖，安装包约 2 MB。

- 系统要求：macOS 14 及以上；编译只需 Command Line Tools（不需要 Xcode）。
- 默认快捷键：F1 区域、⌃⇧W 窗口、⌃⇧F 全屏、⌃⇧L 长截图（可在设置里改）。

## 构建与安装

```bash
Scripts/build-app.sh            # 生成 build/SnapLite.app
Scripts/build-app.sh --install  # 同时复制到 /Applications
```

第一次运行会请求「屏幕录制」权限；勾选后需要**重新打开应用**。

### 推荐：创建自签名证书，避免权限反复失效

默认使用 ad-hoc 签名，每次重新编译签名都会变，系统会把它当成新应用，已授予的权限失效。运行一次：

```bash
Scripts/make-signing-cert.sh
```

之后 `build-app.sh` 会自动用 "SnapLite Dev" 证书签名，重新编译不再丢权限。

## 使用

| 操作 | 说明 |
|---|---|
| 区域截图 | 拖拽选区或点击窗口确定范围后，**双击选区 / 回车 / 点 ✓** 才截图。工具条提供矩形框（R）、箭头（A）、画笔（P）、打码（M）、文字（T），8 种颜色，⌘Z 撤销。按住选区内部拖动可移动，拖动边缘或角可调整大小；在选区外拖拽可重选，Esc 取消。工具条上还有「钉在桌面」和「从此选区滚动截图」。|
| 钉图 | 把选区（含标注）作为浮动窗口钉在屏幕上：拖动移动、滚轮缩放、⌘0 恢复大小、⌘C 复制、⌘S 保存、Esc 关闭，右键有菜单。菜单栏可一键关闭全部钉图。|
| 窗口截图 | 悬停高亮，点击截取。透明背景、保留圆角。|
| 全屏截图 | 多显示器各出一张。|
| 延时截图 | 菜单栏 → 延时区域截图，倒计时后冻结画面再选区，适合截菜单和悬浮态。|
| 长截图 | 先框选可滚动区域，然后在选区内自己向下滚动，每次停下都会自动截帧拼接，点「完成」结束。|

输出：默认保存到系统临时目录（默认保留 7 天后自动删除，可改天数或改成自定义文件夹）并复制到剪贴板，格式、提示音、预览气泡都可在设置里改。菜单栏「打开保存目录」可直接进入当前目录。

## 长截图原理

1. 监听滚轮事件，停止滚动后等画面稳定再截一帧。
2. 把每行压缩成 64 个灰度桶，用截尾均值在相邻两帧之间搜索垂直偏移。
3. 在两帧同一位置相同、但按偏移平移后不同、且本身有内容的行，判定为吸顶 / 吸底固定元素，只保留一次。

算法在 `Sources/Stitching` 中是纯函数，离线校验：

```bash
swift run -c release stitch-check
```

## 目录

```
Sources/Stitching     拼接算法（纯 CoreGraphics，无 AppKit）
Sources/StitchCheck   拼接算法离线校验程序
Sources/SnapLite/App        入口、菜单栏、全局快捷键、偏好、权限、流程编排
Sources/SnapLite/Capture    ScreenCaptureKit 封装、窗口枚举、坐标换算
Sources/SnapLite/Overlay    全屏覆盖层与选区交互
Sources/SnapLite/Scrolling  长截图会话、滚动驱动、悬浮面板
Sources/SnapLite/Output     导出、剪贴板、提示音、预览气泡
Sources/SnapLite/Settings   SwiftUI 设置窗口、快捷键录制器
Scripts/                    打包、图标生成、自签名证书
```
