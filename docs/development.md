# 开发、验证与打包

在仓库根目录执行下列命令。个人电脑的安装位置、备份和设备状态写入不提交的 `LOCAL-USAGE.md`；公开文档不包含开发者的主目录或实物设备标识。

## 前置条件

- macOS 14+ 与兼容的 Swift / macOS SDK。
- Command Line Tools 提供的 `swift`、Clang、`make`，以及系统 `curl`、`tar`、`iconutil`、`codesign`。
- 首次完整打包需要联网下载固定版本 smartmontools 源码。

Swift Package manifest 为 5.9，已在 Apple Silicon Mac mini、macOS 27.0.1 上验证。没有声明 Intel 或所有较早 macOS 版本已经完成实机兼容测试。

## 独立检查

```bash
swift run DiskCoreChecks
swift run -c release DiskCoreChecks
```

这是独立可执行检查程序，不需要 XCTest / Testing 插件。一般开发选择与变更有关的一种构建配置检查即可，不必无故重复两套。

目前 38 组、211 个断言。夹具中的序列号、WWN 和 USB4 UID 已脱敏或合成；检查在临时目录验证读写，OCR 使用明确标注的合成标签。检查本身不读取外接实盘、不创建真实测速文件。

## 构建

```bash
swift build
bash scripts/build.sh
open "outputs/移动硬盘测试.app"
```

完整脚本将：

1. 下载并校验 smartmontools 7.5 源码归档，SHA-256 固定在脚本中。
2. 在项目 `work/` 下以 macOS 14 部署目标构建独立 `smartctl`。
3. release 构建应用，生成图标，复制品牌资源与来源记录。
4. 在 `.app` 中加入 smartctl 许可证及对应源码，执行本地 ad-hoc 签名和校验。

复用的读取组件按当前宿主架构编译，脚本不生成 universal binary。跨架构构建应使用相应环境或新的缓存，不能把旧宿主构建产物直接当作另一架构分发。

普通 `swift build` 的可执行文件可用于开发；完整应用打包会包含品牌资源与独立读取组件。若未打包组件，开发入口会尝试常见系统安装位置的 smartctl。

## 本地安装

先退出旧应用并按需备份用户资料，再运行：

```bash
bash scripts/build.sh --install
open "$HOME/Applications/移动硬盘测试.app"
```

安装目标为当前用户的 `~/Applications/移动硬盘测试.app`。脚本核对已有 bundle identifier，拒绝覆盖不同应用；相同标识会被替换。自动备份和关闭旧进程不属于脚本实现。

日常用户资料在 `~/Library/Application Support/PortableDiskTest/`，不是 `.app` 内的资源，也不是项目工作目录。调试中不要删除或重置真实记录。

## 只读命令行扫描

```bash
mkdir -p work
"outputs/移动硬盘测试.app/Contents/MacOS/PortableDiskTest" --scan-json > work/scan.json
```

它发现已连接的真实外接物理盘，输出原始设备数据。结果可能含序列号和唯一标识，不要直接提交或附到公开 Issue。

## 界面诊断

```bash
"outputs/移动硬盘测试.app/Contents/MacOS/PortableDiskTest" \
  --capture="$PWD/work/overview.png" --light
```

| 参数 | 用途 |
| --- | --- |
| `--capture=/absolute/path.png` | 捕获当前主窗口或活动 sheet，随后退出 |
| `--compact` | 960×720 最小窗口；默认 1180×820 |
| `--light` / `--dark` | 指定当前窗口的诊断外观 |
| `--page=smart` / `--page=speed` | 选择功能页 |
| `--device=diskN` | 捕获时选择当前发现的设备号 |
| `--purpose=quick` / `--purpose=large` | 捕获时选择测速目的 |
| `--empty-preview` | 捕获时预览无设备状态 |
| `--import-preview=/absolute/result.txt` | 捕获时预览文字成绩确认 sheet |
| `--label-editor-preview` | 捕获时预览料号补充 sheet |
| `--label-number-preview=型号或料号` | 捕获时在料号 sheet 预填未保存的检查值 |
| `--label-photo-preview=/absolute/label.png` | 捕获时在料号 sheet 验证本地 OCR |

模拟状态必须与 `--capture=` 组合使用，正常启动不预填这些检查值。捕获模式不写用户历史或补充记录，但真实设备捕获仍可能含私人标识。诊断图片默认保留在被忽略的本地目录，不随仓库公开。

OCR 验证要覆盖实际窗口中的识别完成、回填、确认和失败状态。当前实现对料号使用兼容的 Vision revision / CPU 路径，避免已在开发验证环境中观察到的识别引擎编译等待。

可选的 `python3 scripts/capture.py` 批量捕获常见 QA 状态，结果写入 `.impeccable/review/`。它默认使用应用自动选择的设备；需要指定时使用 `--device=diskN`，需要 ATA 专项捕获时使用 `--ata-device=diskN`。参数须按当前实际设备填写，不会假定某台开发电脑的设备号。

## 打包与发布准备

只构建 `.app` 并不会创建 GitHub Release。需要压缩包时，在构建后执行：

```bash
ditto -c -k --sequesterRsrc --keepParent \
  "outputs/移动硬盘测试.app" \
  "outputs/移动硬盘测试-macOS-arm64.zip"
codesign --verify --strict "outputs/移动硬盘测试.app"
```

上例文件名适用于 arm64 宿主；其他架构应相应命名。发布时核对 Info.plist 版本、二进制架构、签名、第三方许可证与对应源码。压缩包不应包含 `history.json`、`device-labels.json`、标签照片、实盘扫描或备份。

Git 源码发布与二进制 Release 是不同动作。提交前查看暂存文件，确认缓存、研究材料和私人数据被排除；不要为了分享截图直接加入带序列号的实盘捕获。

补充记录继续使用 version 1 和原有 `partNumber` 字段，字段值可以是无销售后缀的盘身 Model 或带后缀的 P/N。不要为这次格式放宽改名、清空或迁移用户旧记录。

## 维护注意事项

- SwiftUI 采用原生控件、系统字体、成对深浅色和文本状态，约定在 [DESIGN.md](../DESIGN.md)。
- 保持 `ViewState` 别名的工具链兼容用途。
- 核心身份与解析的变化应覆盖多设备、缺失、重复、断开和错误恢复，不用 UI 成功截图替代数据检查。
- 更改用户数据结构时保留旧记录并提供兼容处理；读入损坏文件不能默默覆盖。
- 更改 smartmontools 版本时同步源码 URL、SHA-256、构建参数和 [第三方说明](../THIRD_PARTY_NOTICES.md)。
- 厂商品牌标识保留原始资源与来源；不使用品牌 Logo 作为本应用的身份或暗示背书。
