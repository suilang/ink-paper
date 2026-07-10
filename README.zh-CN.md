# Ink Paper

[English](README.md) | [中文](README.zh-CN.md) | [日本語](README.ja.md)

> 轻量、原生的 macOS 静态壁纸工具——能改系统就改系统，改不了就用底层窗口兜底。

Ink Paper 用 Swift + AppKit 实现两种互斥运行模式：优先写入系统桌面壁纸；在系统壁纸不可写或被锁定时，用铺在桌面底层的全屏窗口视觉上充当壁纸。第一版仅支持本地静态图片，菜单栏常驻，多显示器一屏一窗。

---

## 为什么做这个

换壁纸本该是一件小事，但在 macOS 上经常会卡住：

- **系统壁纸写不进去**：公司设备、配置描述文件、权限或系统状态异常时，常见壁纸工具只能报错或静默失败。
- **「假壁纸」又容易抢交互**：用普通窗口盖桌面，容易挡住 Dock、菜单栏或桌面图标点击。
- **多屏体验割裂**：外接屏插拔、分辨率变化后，窗口错位或只覆盖主屏。

Ink Paper 为此而建：

1. **能改系统就改系统**（模式 A），失败或不可用时再降级到底层窗口（模式 B），模式互斥、切换可回滚。
2. **底层窗口不抢交互**：不可成为 Key Window、点击穿透、层级在桌面层，Dock / 菜单栏 / 桌面图标照常可用。
3. **多屏一屏一窗**，跟随屏幕插拔与分辨率变化重建。
4. **原生实现、性能优先**，配置本地持久化，启动按上次状态恢复；失败给出可操作提示，不静默吞掉。

---

## 你能用它做什么

| 能力 | 说明 |
|------|------|
| **系统壁纸模式** | 直接设置 / 读取 macOS 系统静态壁纸 |
| **底层窗口模式** | 系统不可写时，用桌面底层全屏图窗口兜底 |
| **模式自动 / 手动** | 健康检查推荐模式，也可强制指定 |
| **多显示器** | 全屏共用一张图，或按显示器分别设置 |
| **缩放策略** | fill / fit / stretch / center |
| **菜单栏入口** | 常驻菜单栏，快速选图与开关 |
| **登录启动** | 可选登录时启动并恢复上次壁纸状态 |

> 本期不做：视频 / 动态 / 网页壁纸、Windows / Linux、在线图库、多图轮播调度等。详见 [技术需求文档](docs/technical-requirements.md)。

---

## 打开工程

```bash
open InkPaper.xcodeproj
```

或命令行构建：

```bash
xcodebuild -scheme InkPaper -project InkPaper.xcodeproj \
  -configuration Debug \
  -derivedDataPath .derivedData build
```

- 最低系统：macOS 13.0
- Bundle ID：`com.ink.InkPaper`

---

## 文档

| 文档 | 说明 |
|------|------|
| [docs/technical-requirements.md](docs/technical-requirements.md) | 产品约束与实现指引（英文） |
| [docs/impl/README.md](docs/impl/README.md) | 已落地代码行为（按模块拆分） |

---

## 开源协议

本仓库采用 [MIT License](LICENSE)。

可自由使用、修改与分发；须保留版权与许可声明。软件按「原样」提供，不附带任何明示或暗示担保。

---

## 赞助

如果本项目对您有帮助，欢迎请作者喝杯奶茶。

<p align="center">
  <img src="docs/assets/wechat-pay.png" width="180" alt="微信赞赏码" />
</p>

赞赏仅用于本项目维护与开发，不作他用。
