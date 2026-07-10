# Ink Paper 实现文档索引

本目录描述**当前代码的实际行为**，与 `docs/technical-requirements.md`（产品约束）互补。  
改动实现行为时，请同步更新对应文档。

| 文档 | 内容 |
|------|------|
| [architecture.md](./architecture.md) | 模块划分、依赖方向、启动/退出流程 |
| [interaction-flow.md](./interaction-flow.md) | **交互动线专项**：选图/启用分离、反馈规范 |
| [config-store.md](./config-store.md) | 配置模型、持久化路径、硬约束 |
| [mode-engine.md](./mode-engine.md) | 模式决策、启用/停用、降级 |
| [system-wallpaper.md](./system-wallpaper.md) | 模式 A：系统壁纸读写与备份 |
| [overlay-wallpaper.md](./overlay-wallpaper.md) | 模式 B：底层窗口与渲染 |
| [display-registry.md](./display-registry.md) | 多屏枚举与变更监听 |
| [image-pipeline.md](./image-pipeline.md) | 图片校验、解码、缩放 |
| [health-checker.md](./health-checker.md) | 检查项 ID 与报告 |
| [settings-ui.md](./settings-ui.md) | 设置页与菜单栏 |
| [app-lifecycle.md](./app-lifecycle.md) | AppDelegate、激活策略、登录项 |

## 工程入口

- Xcode 工程：`InkPaper.xcodeproj`
- 源码根：`InkPaper/`
- Bundle ID：`com.ink.InkPaper`
- 最低系统：macOS 13.0
- 本地构建示例：

```bash
xcodebuild -scheme InkPaper -project InkPaper.xcodeproj \
  -configuration Debug \
  -derivedDataPath .derivedData build
```
