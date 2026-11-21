# 移动硬盘测试
<!-- impeccable:product-schema 1 -->

## Platform
macos

## Stack
原生 SwiftUI + AppKit，Swift Package Manager 构建；diskutil / smartmontools 采集真实设备数据，无服务器。Apple Silicon 优先，macOS 14+。

## Users
需要验收新买闪迪移动 SSD、日常检查多块外接硬盘的 Mac 用户；主要界面为简体中文。

## Product Purpose
插入硬盘即可看到容量、分区、连接方式、温度和 SMART；让设备能力限制、历史事件与真正的故障各自明确。

## Positioning
通用外接物理硬盘检测工具，以 SanDisk Extreme E60 与 Extreme Pro USB4 E82 为实机验证对象。不冒充厂商官方软件，不承诺所有 USB 桥接芯片都支持 SMART。

## Operating Context
开发验证用 Mac mini（Apple Silicon、macOS 27.0.1），日间桌面和长期查看场景。多盘并行展示，自动响应挂载变化、定时更新，界面不因读取而阻塞。

## Capabilities and Constraints
- 自动发现所有外接物理磁盘，排除内置盘和磁盘镜像；一块物理设备可有多个卷。
- NVMe / ATA SMART 统一概览，保留厂商原始字段和原始报告；未知信息显示未提供。
- 区分不支持、权限不足、读取失败和部分日志不可用，不把历史断电计数直接判为坏盘。
- 可导出报告；测速打开已安装的 AmorphousDiskMark，指导选择目标卷和参数，显式从剪贴板导入文字成绩并由用户确认归属。
- 测速建议按用途、介质、观察到的连接速率及可用空间调整，不声称是厂商标准或能必然耗尽 SSD 缓存。
- 主标题始终展示设备返回的真实 Model；产品系列只在详情中显示，区分“设备报告 / 官方资料匹配 / 标签确认 / 手动确认”。目前仅 E82 有已核实的闪迪官方硬件目录规则，E60 不自动推断；盘身型号和料号均按实际提供值保存，不根据名称、容量或官网补后缀。
- 支持手动录入与本地 Vision 标签照片识别；确认后按唯一物理序列号保存在 Mac 上，不上传照片或序列号、不改写设备 Model；无唯一身份、断开、扫描失败时禁止保存。其他品牌可手动补充，照片识别目前专注闪迪 SDSSDE 型号或料号，含容量的 Model 有效，销售后缀可选。
- 支持用户主动安全推出所选物理硬盘的全部卷；多卷先确认，正常卸载后再推出，占用时失败而不强制操作。成功前不提示拔线，断开重连重新核对设备。
- 默认采集只读；本应用不自行写入测速，不提供格式化、固件升级、擦除、自动点击第三方工具和全盘破坏性测试。
- 不声称 SMART 能证明全新、保证寿命或代替备份。

## Brand Commitments
名称“移动硬盘测试”。简洁而不简单，现代、舒适、原生 Mac 操作体验。延续现有视觉体系，保持清晰的原生交互。

## Evidence on Hand
开发验证用 Mac mini（Apple Silicon、macOS 27.0.1） 实接 E60（ATA over USB）与 E82（USB4 / NVMe），smartctl 7.5 已能读取两盘。E60 部分扩展 ATA 日志不受支持；E82 支持标准 NVMe 健康日志。

## Product Principles
真实数据优先；缺失值不填零；错误可恢复；测速显式触发；突出健康和使用程度而不把正常历史事件渲染成故障。

## Accessibility & Inclusion
支持键盘、VoiceOver、系统深浅色与减少动态效果，数据采用等宽数字，状态同时用文字表达。
