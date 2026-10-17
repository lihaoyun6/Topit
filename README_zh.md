# 
<p align="center">
<img src="./Topit/Assets.xcassets/AppIcon.appiconset/icon_128x128@2x.png" width="200" height="200" />
<h1 align="center">Topit</h1>
<h3 align="center">将任意应用窗口强制置顶显示<br><br>
<a href="https://lihaoyun6.github.io/topit/"><img src="https://img.shields.io/badge/软件主页-blue" height="24" alt="软件主页"/></a></h3> 
</p>

> 公开功能分支：[UnityX103/Topit](https://github.com/UnityX103/Topit)，基于 [lihaoyun6/Topit](https://github.com/lihaoyun6/Topit)。区域置顶修改自 2026-10-17 起维护，沿用原项目 AGPL-3.0 许可证。[下载版本](https://github.com/UnityX103/Topit/releases) · [自动测试](https://github.com/UnityX103/Topit/actions/workflows/ci.yml) · [发布流程](docs/RELEASING.md)。

## 运行截图
<p align="center">
<picture>
  <source media="(prefers-color-scheme: dark)" srcset="./img/preview_zh_dark.png">
  <source media="(prefers-color-scheme: light)" srcset="./img/preview_zh.png">
  <img alt="xHistory Screenshots" src="./img/preview.png" width="816"/>
</picture>
</p>

## 安装与使用
### 系统版本要求:
- macOS 13.0 及更高版本  

### 安装:
可从[本 Fork 的 Releases](https://github.com/UnityX103/Topit/releases)下载。原作者的 Homebrew 配方安装上游版本，不包含这里的修改。目前发布包使用固定本地证书，未经 Apple Developer ID 公证。

### 使用:
- Topit 支持将任意多个窗口强制置顶显示, 并允许用户自由移动、缩放或与被置顶窗口进行自由交互.  
- 用法极其简单, 用户只需启动 Topit 并选择需要置顶显示的窗口, 然后点击 "立即置顶" 即可将其置顶. 

## 常见问题
**1. 为什么 Topit 会请求屏幕录制和辅助功能权限?**  
> Topit 需要使用屏幕录制和辅助功能权限来捕获并控制任意窗口, 如果不授予此权限将无法正常工作.  

**2. Topit 会很耗电吗?**  
> Topit 使用 ScreenCapture Kit 来进行低功耗窗口捕获. 但如果用户同时置顶太多窗口, 仍然可能出现明显的电量消耗.  

## 赞助
<img src="./img/donate.png" width="350"/>

## 致谢
[Sparkle](https://github.com/sparkle-project/Sparkle) @Sparkle  
[ChatGPT](https://chat.openai.com) @OpenAI  

## 本地区域置顶版本

- 点击窗口选择器中的「区域置顶…」，或使用菜单栏同名入口。默认全局快捷键为 `Command + Shift + T`，可在设置的快捷键页修改。
- 使用 `Command + Shift + T` 时直接框选鼠标所在窗口；通过选择器进入时先点击目标窗口，再拖动框选其中一部分。松开鼠标后只有选区生成实时置顶浮窗。按 `Esc` 取消；单击或小于 8 点的选区不会创建浮窗。
- 浮窗默认与源窗口交互，支持点击、拖动、滚动和键盘输入。按住 `Shift` 切换为浮窗编辑：拖动移动、从边缘等比缩放、显示关闭/冻结/复制按钮；`Shift + 右键` 可打开浮窗选项和透明度设置。松开 Shift 恢复源窗口交互。冻结时不发送输入。
- 冻结后成为静态截图并停止对应录屏流；点击「继续」恢复实时捕获，最高 30 fps。源窗口关闭后保留最后一帧，浮窗可手动关闭。「解除所有置顶」同时关闭区域浮窗。
- 连续轻按两次 `Control`，切换所有区域浮窗的自动隐藏模式，也可从「区域截取」或菜单栏菜单切换。开启后鼠标靠近浮窗时淡出，移开后显示；期间不能点击、输入、滚动或按 Shift 编辑浮窗，再双击 Control 才恢复交互。Control 组合键、长按以及两次轻按之间的点击或滚动不会触发。新建的区域沿用当前模式，重启后默认关闭。
- 点击区域浮窗时直接聚焦原窗口和原控件，键盘、中文输入法、回车、粘贴、撤销均由原应用处理。浮窗不创建本地输入框、不写回草稿、不重发键盘事件，从而避免双路输入导致重复字符。原窗口的输入焦点会改变，浮窗保持置顶；请求焦点时不调用 AXRaise。此能力依赖 macOS 私有窗口焦点接口，接口不可用会明确提示，兼容性以正式安装版验收为准。
- 仅显示选区，原窗口及其余区域保持原来的窗口层级。源窗口被其他窗口遮挡时仍可捕获；最小化、切换 Space 及受保护内容的行为取决于 macOS 和源应用。
- 此版本使用固定本地证书签名，通过增量更新包原位更新；首次从临时签名迁移时可能需要重新授权。为避免官方版本覆盖本地新增功能，禁用了本版本的官方更新器。

回归检查：`Tests/run-region-tests.sh`。使用 Xcode 构建 `Topit` scheme。


## 保留权限的本地更新包

更新不能再使用 ad-hoc 临时签名。每个版本使用同一证书、同一 bundle ID 和证书约束，通过 `Scripts/build_update.py` 生成 `.topitupdate` 增量包；`Scripts/topit_update.py` 验证安装基线、完整目标文件与旧版签名身份后原位应用，保存上一版 ZIP，安装失败回退。更新会短暂退出 Topit，随后只从 `/Applications/Topit.app` 重新启动，不卸载、不清除偏好和权限记录。

本机配置位于被 Git 忽略的 `Config/signing.local.json`。只记录证书指纹与钥匙串路径，私钥保留在系统钥匙串。示例为 `Config/signing.local.example.json`。签名失败时停止更新，不降级为临时签名。

第一次将现有临时签名迁移为固定证书签名时，生成和安装都需要显式 `--migrate-signer`；这次身份变更可能需要最后一次授权。迁移完成后，正常更新不得再使用这个参数，必须满足已安装应用的证书身份条件。若本地证书的钥匙串锁定或不可访问，先保留当前安装，等待用户在钥匙串访问中解锁；不自动更改证书信任。

生成首次迁移包（具体版本号和输出路径按本次发布填写）：

```bash
python3 Scripts/build_update.py --version 0.1.8 --build 18 --migrate-signer --output /absolute/path/Topit-0.1.8.topitupdate
python3 Scripts/topit_update.py apply /absolute/path/Topit-0.1.8.topitupdate --check --migrate-signer CERTIFICATE_SHA1
python3 Scripts/topit_update.py apply /absolute/path/Topit-0.1.8.topitupdate --migrate-signer CERTIFICATE_SHA1
```

后续常规更新，生成和安装均不再传入迁移参数；可用 `apply --check` 先校验，当前应用和进程保持原状。默认备份位置为 `~/Library/Application Support/Topit/Backups`。代码、签名和权限是否在实际版本更新后正确保留，需在完成首次证书迁移后做一次安装版更新验收。更新协议的单元检查为 `python3 Tests/UpdateProtocolTests.py`。

区域交互将真实键盘焦点交给源窗口，并通过 AXFocused 定位原文本控件；不调用 AXRaise，也不使用 AXPress 兜底。后台左键手势以 macOS 的 Command 点击语义发送，按下、拖动、松开保持一致；部分应用可能将链接等控件按 Command 点击处理。键盘事件仅由系统送往原应用，浮窗不生成键盘事件副本。指针转发分别设置全屏坐标和窗口内坐标，其中窗口内坐标依赖动态解析的系统 CGEventSetWindowLocation；系统不提供该接口时不发送坐标不确定的点击。部分应用对后台输入有自身限制，需以安装版的实际交互验收为准。设置入口使用独立窗口，并在打开时退出区域选择监听；输入回归检查为 `Tests/run-input-regressions.sh`。
