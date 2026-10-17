# 自动测试与发布

本仓库是 [lihaoyun6/Topit](https://github.com/lihaoyun6/Topit) 的公开 Fork，保留 AGPL-3.0 许可证及原作者署名。区域置顶相关修改自 2026-10-17 起维护。

## CI

`.github/workflows/ci.yml` 在推送、Pull Request 和手动运行时执行：

- macOS 15 的 Apple Silicon、Intel 回归检查：区域几何与渲染、指针路由、焦点交接与生命周期、浮窗键盘焦点、双击 Control、快捷键迁移、更新协议、发布资产校验。
- 使用 `Package.resolved` 锁定的依赖编译 arm64 / x86_64 通用 Release，检查版本与架构。未签名的构建产物只用于编译检查，不安装、启动或发布。

本地运行：`bash Scripts/test.sh`。CI 不能代替真实应用输入框、中文输入法、源窗口层级和遮挡刷新等安装版验收。

## 固定签名的发布

本机固定签名证书私钥不导出，不上传 GitHub Secrets，不配置公开仓库的本机 Runner。GitHub 无需签名私钥即可验证签名。

1. 更新 `Config/release.json` 的版本、递增构建号，同时更新 Xcode 工程中的版本、构建号。`signer_sha1` 是公开证书指纹，必须保持既有签名身份。
2. 编写 `docs/releases/v版本号.md`，提交并推送所有源码到本 Fork 的 `main`。
3. 本机存在正式安装的 `/Applications/Topit.app` 和已配置的固定签名证书时运行：

   ```bash
   python3 Scripts/prepare_release.py --publish
   ```

   脚本要求工作区干净，在本机构建、固定证书签名，将 Git 提交号写入签名覆盖的 `Info.plist`，生成完整 ZIP、相对当前安装版的 `.topitupdate`、发布清单及 SHA-256。输出在忽略的 `dist/v版本号/`，不改变当前安装版。随后上传为草稿、推送对应标签，并触发 GitHub 的 `Release` 工作流。
4. GitHub 检查标签属于 `main` 历史，重新运行双架构回归及通用版本编译，核对资产哈希、固定证书、签名中的源码提交、版本、架构以及完整包和增量包的文件一致性。所有检查通过才把草稿发布为预发行版；失败则保留草稿。

签名必须在持有原证书的本机完成，当前流程不是无密钥的纯云端签名发布。GitHub 发布任务可在 Actions 中选择 `Release`，填写已准备好的 `vX.Y.Z` 标签重试，或运行：

```bash
gh workflow run release.yml --repo UnityX103/Topit --ref main -f tag=v0.1.22
```

不得将未经签名的 CI 产物替换为正式更新，不得为了发布改用 ad-hoc 签名。

## 下载和更新

完整 ZIP 用于首次安装，增量包只适用于清单记录的确切旧版本、旧文件哈希及同一签名身份。旧版会先归档，安装失败自动回退；应用路径及 bundle ID 保持不变。

```bash
python3 Scripts/topit_update.py apply /绝对路径/Topit-版本号.topitupdate --check
python3 Scripts/topit_update.py apply /绝对路径/Topit-版本号.topitupdate
```

更新后从 `/Applications/Topit.app` 重启。正常更新不使用 `--migrate-signer`，也不重置 macOS 权限。第一次安装或从其他签名身份迁移仍可能需要系统授权。

目前使用固定本地证书，并非 Apple Developer ID 公证发行。GitHub 签名校验通过不代表 Apple 公证，也不代表所有应用的后台输入兼容性都已验证。
