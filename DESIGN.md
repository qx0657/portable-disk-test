---
name: 移动硬盘测试
description: 以真实设备身份、SMART 和显式关联的测速成绩构成的原生 macOS 工作窗口。
colors:
  ground-light: "#FAFCFB"
  ground-dark: "#18211E"
  sidebar-light: "#EAF1EE"
  sidebar-dark: "#111A17"
  panel-light: "#F0F5F2"
  panel-dark: "#202E28"
  accent-light: "#246458"
  accent-dark: "#81CBB5"
  muted-light: "#50665E"
  muted-dark: "#B0C4BA"
  line-light: "#DCE6E0"
  line-dark: "#34453D"
  selected-light: "#24574C"
  selected-dark: "#2C6051"
  passed-light: "#286A49"
  passed-dark: "#87D5A3"
  attention-light: "#956015"
  attention-dark: "#F0C778"
  failed-light: "#B83D37"
  failed-dark: "#FF9F98"
  write-light: "#486E8B"
  write-dark: "#91B7D5"
  selected-text: "#FFFFFF"
typography:
  metric:
    fontFamily: "system-ui, -apple-system, sans-serif"
    fontSize: "26pt"
    fontWeight: 600
  device-title:
    fontFamily: "system-ui, -apple-system, sans-serif"
    fontSize: "23pt"
    fontWeight: 600
  benchmark-value:
    fontFamily: "system-ui, -apple-system, sans-serif"
    fontSize: "21pt"
    fontWeight: 600
  dialog-title:
    fontFamily: "system-ui, -apple-system, sans-serif"
    fontSize: "20pt"
    fontWeight: 600
  status-title:
    fontFamily: "system-ui, -apple-system, sans-serif"
    fontSize: "15pt"
    fontWeight: 600
  section-title:
    fontFamily: "system-ui, -apple-system, sans-serif"
    fontSize: "14pt"
    fontWeight: 600
  control-label:
    fontFamily: "system-ui, -apple-system, sans-serif"
    fontSize: "13pt"
    fontWeight: 500
  body:
    fontFamily: "system-ui, -apple-system, sans-serif"
    fontSize: "12pt"
    fontWeight: 400
  data:
    fontFamily: "system-ui, -apple-system, sans-serif"
    fontSize: "12pt"
    fontWeight: 500
  caption:
    fontFamily: "system-ui, -apple-system, sans-serif"
    fontSize: "11pt"
    fontWeight: 400
  micro:
    fontFamily: "system-ui, -apple-system, sans-serif"
    fontSize: "10pt"
    fontWeight: 400
  raw:
    fontFamily: "ui-monospace, SFMono-Regular, monospace"
    fontSize: "11pt"
    fontWeight: 400
rounded:
  speed-track: "2pt"
  series-badge: "5pt"
  volume-track: "3pt"
  table: "10pt"
  device-row: "12pt"
  panel: "14pt"
  device-icon: "16pt"
spacing:
  tight: "4pt"
  small: "8pt"
  compact: "10pt"
  control: "12pt"
  group: "16pt"
  relaxed: "18pt"
  panel: "20pt"
  section: "25pt"
  content: "28pt"
components:
  button-prominent:
    backgroundColor: "{colors.accent-light}"
  button-prominent-dark:
    backgroundColor: "{colors.accent-dark}"
  device-row-selected:
    backgroundColor: "{colors.selected-light}"
    textColor: "{colors.selected-text}"
    rounded: "{rounded.device-row}"
    padding: "13pt"
  device-row-selected-dark:
    backgroundColor: "{colors.selected-dark}"
    textColor: "{colors.selected-text}"
    rounded: "{rounded.device-row}"
    padding: "13pt"
  preparation-panel:
    backgroundColor: "{colors.panel-light}"
    rounded: "{rounded.panel}"
    padding: "{spacing.panel}"
  preparation-panel-dark:
    backgroundColor: "{colors.panel-dark}"
    rounded: "{rounded.panel}"
    padding: "{spacing.panel}"
  health-passed:
    textColor: "{colors.passed-light}"
    padding: "7pt 11pt"
  health-passed-dark:
    textColor: "{colors.passed-dark}"
    padding: "7pt 11pt"
  smart-search:
    width: "220pt"
    typography: "{typography.body}"
  raw-report:
    backgroundColor: "{colors.panel-light}"
    rounded: "{rounded.table}"
    padding: "{spacing.control}"
    height: "260pt"
    typography: "{typography.raw}"
  raw-report-dark:
    backgroundColor: "{colors.panel-dark}"
    rounded: "{rounded.table}"
    padding: "{spacing.control}"
    height: "260pt"
    typography: "{typography.raw}"
---

# Design System: 移动硬盘测试

## Overview

**Creative North Star: "森林步道导览"**

松绿、石白和有秩序的数据层级，形成适合长时间查看的原生 Mac 工具。稳定的设备身份是路径标记；概览、SMART 与测速是同一台设备的三个观察层次。界面以紧凑、清楚和舒适为准，不将设备检查包装成虚构分数。

本文件从已实现的 SwiftUI / AppKit 应用提取。主要依据是 `Sources/DiskApp/Views.swift`、`DeviceIdentityViews.swift`、`SMARTView.swift`、`SpeedView.swift`、`Main.swift` 与 `AppModel.swift`，并核对桌面及深色捕获。前言中的尺寸使用 macOS 逻辑点（pt），不是屏幕物理像素；字体由系统及中文回退字体解析。系统控件的边框、焦点和禁用外观由 macOS 管理，不虚构其固定色值。

**Key Characteristics:**

- 深浅色成对的松绿表面，少量蓝色区分测速写入。
- 原生双栏、分段选择、按钮与渐进披露；数据区保持平面。
- 等宽数字配合明确单位、来源与缺失状态。
- 多盘身份持续可见，历史与测速成绩只关联可靠身份。

## Colors

前言记录自适应 sRGB 配对；每个 `-light` / `-dark` 是同一语义角色的两种系统外观，不能混选。`Palette.adaptive` 按 Aqua / Dark Aqua 解析，写入色来自 `BenchmarkTable.writeColor`。

### Primary

- **松针强调色**（`accent-*`）：设备图标、容量已用轨、温度线、读取成绩轨和系统控件 tint。它表达操作与测量，不是健康结论。
- **林荫选中色**（`selected-*`）：左栏当前设备的实色底。选中行使用 `selected-text`，次级文字按实现降低到 86% / 90% 不透明度。

### Secondary

- **雾蓝写入色**（`write-*`）：只用于与读取并列的写入成绩轨；列标题与数字同时说明读写含义。
- **通过绿**（`passed-*`）、**关注琥珀**（`attention-*`）、**失败红**（`failed-*`）：分别表示 SMART 通过、明确关注事项和失败；未提供状态复用 `muted-*`。状态不能只靠颜色表达。

### Neutral

- **石白 / 深林底色**（`ground-*`）：主窗口与导入 sheet。
- **浅苔 / 阴林侧栏**（`sidebar-*`）：设备导航与自动更新设置。
- **柔石 / 林下容器**（`panel-*`）：指标区、测速准备、表头和原始报告。
- **灰绿辅助文字**（`muted-*`）：说明、字段名、时间和未知数据提示。
- **枝影分隔**（`line-*`）：细分隔与容量 / 成绩轨道底。

正文主色实际使用 SwiftUI `.primary`；其动态系统解析值没有被替换为自定义 hex。通过徽章底色是对应状态色的 9% 不透明度，不另建独立色板。

**The Semantic State Rule.** 状态色必须跟随真实状态；选中设备和测速的强调色不得被解读为健康通过。异常、未提供及部分读取始终附带文字解释。

## Typography

**Display Font:** 无独立展示字体；设备标题使用系统字体。
**Body Font:** SwiftUI `.system`，macOS San Francisco 与系统中文回退。
**Label/Mono Font:** 数字以 `.monospacedDigit()` 保持列宽；原始报告及 ATA 厂商字段使用系统 `.monospaced`。

**Character:** 原生、紧凑、以读数为重。没有字距装饰或大写标签系统，行高由系统字体管理；说明段落只在代码明确处增加行距（概览与测速为 3pt，空状态为 4pt）。

### Hierarchy

- **读数 / 设备标题**：对应前言 `metric` / `device-title`。温度等读数带基线对齐的小单位；设备型号最多两行。
- **测速 / 对话标题**：对应 `benchmark-value` / `dialog-title`。测速数值保留两位小数；空状态标题也复用对话标题尺度。
- **分区标题**：对应 `status-title` / `section-title`。SMART 页面标题另用 17pt semibold，测速介绍用 19pt semibold，均为已实现的局部层次，不扩成额外展示体系。
- **正文 / 字段值**：对应 `body` / `data`，字段值以 medium 与 muted 字段名区分。
- **辅助 / 微文案 / 原文**：对应 `caption` / `micro` / `raw`。微文案用于指标来源与 QD；不把主要操作或设备身份压成微文案。

**The Measured Number Rule.** 测量值使用等宽数字与真实单位。未知值显示 `—` 或“未提供”，不以零占位；厂商原始值不改写为健康百分比。

## Layout

AppKit 窗口默认内容尺寸是 **1180×820pt**，最小窗口是 **960×720pt**。已实现的默认高度取代早期方向稿中的 780pt。宽度通过可伸缩右侧内容消化；没有移动端断点或折叠侧栏。

- 顶部工具栏高 56pt，左侧为交通灯留出 92pt，右侧留 22pt；操作间距 12pt。
- 设备栏固定 232pt，右侧接 1pt 分隔；设备行横向外边距 10pt，行间距 7pt，底部设置区内边距 18pt。
- 右侧内容横向留白 28pt。设备头图标区为 70×70pt，标题和状态横向排列；分类分段选择宽 294pt，更新时间在右。
- 头部身份与分类控件保留在内容滚动区之外。概览 / SMART / 测速内容垂直滚动，主区段间距 25pt，底部留白 28pt。
- 概览四项指标等分并用 1pt 细线区隔；设备信息用两列 Grid（列间 34pt，行间 15pt）。指标一行显示，必要时缩至原字号的 70%。
- SMART 表格指标 / 当前值两列固定为 170 / 142pt，说明列伸展；行内边距为纵向 11pt、横向 12pt。搜索宽 220pt。
- 原始报告面板高 260pt，支持横纵滚动，长报告不撑大窗口。
- 测速准备容器内边距 20pt。成绩表用稳定的项目列与等分读写列；导入 sheet 内容宽 610pt、内边距 26pt。
- 料号补充 sheet 宽 620pt、内边距 28pt，默认高 440pt；冲突、不可编辑或保存失败时高 520pt，选择照片后高 600pt。目标身份在上，中段纵向滚动，底部取消 / 保存及保存来源固定可见。

这些是桌面密度约定。960pt 宽时保持同一信息架构，通过纵向滚动呈现较长内容，不删除数据以制造首屏完整。

## Elevation & Depth

自定义内容不使用投影、渐变、模糊或悬浮抬升。层次来自侧栏 / 底色 / 面板的色阶、分隔和留白。窗口阴影、sheet 层级、原生按钮及系统焦点外观由 AppKit / SwiftUI 提供；不要把平台行为误记为自定义阴影 token。

**The Quiet Surface Rule.** 数据面板保持平面；通过语义色阶与清晰对齐建立层次，保留系统控件自己的深度反馈。

## Shapes

圆角随结构规模变化：细轨使用 `speed-track` / `volume-track`，表格与原文使用 `table`，设备选中行使用 `device-row`，主要数据容器使用 `panel`，设备图标底使用 `device-icon`。健康标记使用真实 Capsule，不把它固化为固定半径。

容量轨高 6pt、成绩轨高 4pt；图表线宽 2pt。分隔线用于列和行，不把每个字段封装成独立卡片。图标使用系统 SF Symbols 及原生 Label，无 emoji 或字体字符模拟图标。

应用图标是 `scripts/make-icon.swift` 的原创 AppKit 矢量路径：松绿圆角方形、浅色外接 SSD、凹入接口与状态灯。栅格化按原生 iconset 尺寸输出；来源记于 `Resources/AppIcon.provenance.json`，不是图库素材或生成图片。

## Components

### Buttons

工具栏扫描 / 导出采用 `.bordered`、regular control size。测速打开 / 获取与最终保存采用 `.borderedProminent` 并继承强调色；不自定义系统按钮圆角、内边距、hover 或焦点环。Finder 小图标使用 `.plain` 并提供帮助文字。禁用状态由实际前提控制：扫描进行中、无已选设备、目标卷缺失 / 只读、没有可关联身份。

键盘：**⌘R** 重新扫描，**⌘E** 导出；导入 sheet 中 **Esc** 取消、**Return** 确认默认操作。系统编辑菜单提供复制、粘贴与全选；型号、字段值及原文按实现可选中复制。

### Chips

健康徽章采用 12pt medium、水平 11pt / 纵向 7pt 内边距、状态文字与 SF Symbol、9% 状态色 Capsule 底。通过显示“检查通过”，未知显示“未提供”，关注 / 失败显示“需关注”并保留不同状态色。侧栏用小圆点加状态文本，选中时圆点变白，语义仍由文字承载。

### Cards / Containers

四项指标共用单个淡色圆角容器，纵向内边距 19pt、横向 8pt；单项横向再留 14pt。测速准备容器复用相同表面与圆角，内部留白 20pt。正文状态、空间分区和设备信息直接置于底色，避免无意义套层。

### Inputs / Fields

SMART 搜索使用原生 `.roundedBorder` TextField，左侧带可见“搜索指标”标签，VoiceOver 名称为“搜索 SMART 指标”，帮助说明可按名称、值或说明搜索。空搜索结果显示“没有匹配的指标”。目标卷与保存设备使用原生 Picker；系统处理 hover、键盘与焦点状态。

### Navigation

侧栏每项是可聚焦的原生 Button，整个圆角行可点击。显示设备名、容量和介质类别；可靠身份缺失时保留 disk ID，避免多盘同名混淆。VoiceOver 标签组合名称、容量与健康状态，当前项具有 selected trait。右侧“概览 / SMART / 测速”是原生 segmented Picker，辅助名称为“设备信息分类”。

设备头持续显示真实型号、容量、观测到的连接方式与 `/dev/disk…`。切换设备时重建对应身份的详情；只对选中 ID 变化应用 **160ms ease-out**，开启系统“减少动态效果”后关闭这段动画。没有自定义悬停动画或循环装饰动画。

### Device data and availability

首次扫描显示 ProgressView 与发现文字；后台更新不阻塞界面。空设备状态提供插盘解释与重新扫描。发现失败保留上次数据，并在主区顶部标明可能是旧数据；更新时间持续可见。自动更新开关、暂停说明、历史读写错误与“本地读取 · 数据不上传”位于左栏底部。

SMART 解释区区分通过、失败、未提供与部分数据未读取；保留权限、不支持或读取失败等具体原因。历史断电等计数不直接升级成坏盘。厂商 ATA 属性和原始文本 / JSON 采用 DisclosureGroup 逐步展开，保留 Unknown 的原值。温度不足两次不绘制趋势；缺少可靠持久身份只显示当前数据，不保存跨会话记录。

容量轨与温度图有文字辅助标签，SMART / 测速行合并为可读的辅助元素；状态始终包含文字。数字、时间与容量使用等宽数字，原文可复制。

### Device identity and label confirmation sheet

“设备信息”中的产品系列与完整料号各占一行，值使用 12pt medium，来源以紧邻字段的 11pt muted 文字显示。来源不是健康徽章，也不在型号主标题旁增加系列标签。“识别依据与补充记录”通过 DisclosureGroup 展开匹配说明、官方资料链接，以及已确认补充的料号、来源和时间。

“补充料号…” / “编辑补充…”打开原生 sheet。目标区保留设备实际 Model、容量和绑定的物理序列号；输入有可见“完整料号 / P/N”标签，采用 `.roundedBorder`，打开时获得焦点。照片操作采用 `.bordered`，保存采用 `.borderedProminent` 并沿用 `Palette`；**Esc** 取消、**Return** 执行可用的默认保存操作。

中段容纳照片预览、识别进度、候选料号、字段说明及错误。保存必须通过格式和当前唯一身份校验；识别进行中、设备不可编辑或未勾选冲突确认时禁用保存。冲突以琥珀文字解释差异，并要求额外勾选“我已核对目标设备和标签，仍保存此补充料号”；修改输入后取消这次勾选。固定页脚持续显示“手动确认”或“标签确认”和本地保存说明，保持平静的原生松绿界面。

### Speed results and confirmation sheet

准备区明确展示目标卷、建议参数及 AmorphousDiskMark 安装状态。应用只打开工具，用户手动选择目标与启动测试；成绩由剪贴板或文本文件显式导入。空成绩状态说明本地保存与身份条件。

导入 sheet 展示成绩型号、卷名与读写表。目标设备列表只含可靠持久身份，初始值可为当前可靠设备；用户必须按“确认并保存”。型号不一致显示琥珀警告；目标为空时禁用保存，设备断开或身份不可靠时拒绝关联。此处的预选不是自动猜测或自动落盘。成绩表的条长只相对于同一份成绩的最大值，不表示理论接口上限。

`.impeccable/design.json` 的组件预览是无需框架的 HTML / CSS 说明性转译，用于展示这些规则；它不替代 macOS 的真实控件渲染或键盘实现。

## Do's and Don'ts

### Do:

- **Do** 成对维护深浅色语义，保留系统 `.primary` 正文与原生焦点反馈。
- **Do** 让设备身份、数据时间、单位与具体读取限制始终可查。
- **Do** 让状态同时有文字与图形，测量值使用等宽数字。
- **Do** 在保存测速成绩前保留目标设备确认，并只关联可靠身份。
- **Do** 尊重系统减少动态效果，保持原生键盘与 VoiceOver 语义。

### Don't:

- **Don't** 编造健康总分、接口速率、寿命结论或缺失指标；未知值不填零。
- **Don't** 把 USB4 产品名当作已观测连接，或把历史断电计数直接标为故障。
- **Don't** 在身份不可靠时跨会话保存，或静默猜测测速成绩属于哪块盘。
- **Don't** 将打开第三方测速工具写成已经启动测试；应用不会自动写入硬盘。
- **Don't** 给平面数据区增加自定义投影、装饰动画或非原生展示字体。


## 1.2.0 增量：品牌、身份来源与标签补充

沿用已有原生双栏、松绿与石白系统。闪迪设备额外显示官网下载且未修改的红 / 白 SVG 字标，浅色未选中为官方红，深色或选中为官方白；这只是被检测硬盘的品牌标识，不替换本应用的原创图标。详情宽 106pt、高 15pt，侧栏宽 86pt、高 11pt；保留原图比例与透明背景。资源来源与哈希记录于 `Resources/Brands/provenance.json`。

型号主标题只展示设备实际返回的 Model。产品系列只放在详情，来源依次为设备型号原文、已核实的官方规则、已确认的本地补充，并逐字段标明“设备报告 / 官方资料匹配 / 标签确认 / 手动确认”。完整料号以设备报告值优先，其次显示已确认的照片或手动补充；补充信息不改写原始 Model，也不按产品名或容量补全 SKU。

E82 匹配来自 SANDISK App 3.4.2 产品目录与官网，来源记录为 `Resources/ManufacturerCatalog.provenance.json`。USB 模式核对官方 VID / PID；PCIe 隧道模式必须同时匹配此盘自己的 USB4 外壳 ID 与 NVMe ID。E60 实盘的旧 PID 不在该目录，不能据此自动猜成 E60；没有其他可靠来源时系列显示“未确认”。

补充料号经用户确认后，按可靠且唯一的物理序列号保存在运行应用的 Mac 的 `~/Library/Application Support/PortableDiskTest/device-labels.json`，与原有 `history.json` 分开，原历史格式与关联逻辑保持不变。缺失 / 重复序列号、设备断开、身份变化或扫描失败时拒绝保存；文件不可读时保留原件。其他品牌支持手动补充。

照片识别使用本地 Vision，接受 PNG、JPEG、HEIC、TIFF，仅提取完整的闪迪 `SDSSDE…` 料号；不补猜 O / 0、I / 1 等模糊字符。单个候选填入后仍需核对确认，多个候选由用户选择，只有按“确认并保存”才落盘。照片与序列号不上传，照片不保存副本。

USB4 连接观察从此盘的 PCI 隧道定位到自己的外壳 UID，再关联 `system_profiler` 当前速率；系列匹配不等于带宽测量。不从商品名猜当前速率，也不把 USB4 扩展坞后的普通 USB 盘标成 USB4。

测速准备区增加原生三段目的选择（最大宽 350pt），在切换设备时保留用户本次选择。参数为 15pt semibold + 等宽数字，其下用 12pt 说明为何这样建议，11pt 说明测试范围。默认建议依据设备类型、观察到的总线 / USB 链接速率、可用空间及用途，不把产品名 USB4 当成当前带宽。空间不足下调文件；无挂载卷、只读、SMART 故障或设备温度警告时显示明确原因并禁用本应用的启动按钮。跨设备横向对比仍需手动统一参数。默认策略仅是本应用建议，不作为厂商标准或缓存耗尽证明。

本次记录为 1.2.0，目标机器为 开发验证用 Mac mini（Apple Silicon、macOS 27.0.1），日期为 2026-11-21。验证时核对了以下本地捕获（公开仓库不包含这些带设备标识的图片）：`.impeccable/review/` 中的 `identity-e82-light.png`（1180×820）、`identity-e60-dark-compact.png`（960×720）、`identity-editor-light.png`、`identity-editor-ocr-dark.png` 和 `identity-editor-conflict-light.png`。OCR 检查照片明确标注 SYNTHETIC，示例料号未保存到实际用户设备。没有新增随应用交付的栅格素材；已有 AppIcon 与官方 SVG 的来源记录继续有效，现有颜色、字体、布局 tokens 和组件预览保留。
