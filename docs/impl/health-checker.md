# 健康检查

## 源码

- `InkPaper/Health/HealthChecker.swift`

## 入口

- `ModeEngine.runHealthCheck(deep:)`
- 设置页「运行检查」/「深度检查」
- 菜单栏「运行诊断」（非深度，并打开设置）

## 结果

- `CheckItemResult`：`id` / `group` / `title` / `severity(pass|warn|fail)` / `detail`
- 摘要写入 `config.lastCheckReport` 与 `lastCheckAt`
- 可复制纯文本报告

## 已实现检查项

| ID | 组 | 要点 |
|----|-----|------|
| E01 | 环境 | macOS ≥ 13 |
| E02 | 环境 | GUI + 有屏幕 |
| E03 | 环境 | 显示器非空 |
| E04 | 环境 | 全局图可读（未配置则 warn） |
| A01 | 系统壁纸 | API 可用（有主屏） |
| A02 | 系统壁纸 | 读 Managed Preferences（`locked` / `override-picture-path` / `allowWallpaperModification`） |
| A03 | 系统壁纸 | 深度试写 + 回读；未执行时 warn |
| A04 | 系统壁纸 | 全局图校验 |
| B01–B05 | 底层窗口 | 能力、层级说明、穿透开关、窗口数、Space |
| R01–R05 | 资源 | 存在/可读/解码/限制/分屏完整性 |
| S01–S04 | 状态 | 偏好一致性、互斥、窗口同步、备份 |

## 与自动模式关系

任一 `A*` 为 `fail` → `systemModeWritable == false` → auto 倾向 overlay。
