# 本地 Topit 功能版本

遵循用户级 AGENTS.md。用户要求：只启动和验收正式安装的 `/Applications/Topit.app`；构建目录中的应用不能用于运行验收。

## 后续更新

- 禁止继续用 `CODE_SIGN_IDENTITY=-` / ad-hoc 签名安装新版本。临时签名的应用身份依赖代码哈希，会使本机授权在更新后失效。
- 保持 bundle ID `com.lihaoyun6.Topit` 和正式安装路径不变。读取本机 `Config/signing.local.json` 中固定的证书身份，用 `Scripts/build_update.py` 生成更新包。配置文件不入库，私钥不得复制到仓库、日志或更新包。
- 固定签名钥匙串不可用时，保留现有安装版；先完成构建和更新准备，再在普通聊天中说明阻塞点。不得悄悄回退为 ad-hoc 安装，也不得自行修改钥匙串信任设置。
- `Scripts/topit_update.py apply` 验证安装基线、文件哈希和签名后原位更新，先保留上一版归档，安装失败回退。仅第一次从临时签名迁移时使用显式 `--migrate-signer` 指纹；正常更新必须满足已安装版本的签名身份条件。
- 更新需要短暂退出并重开 Topit，不卸载，不修改偏好设置，不修改或重置 TCC 数据库。第一次签名身份迁移可能需要最后一次用户授权；不能承诺未经验证的零授权迁移。

## GitHub 开源发布

- 本 Fork 为 UnityX103/Topit，保留上游署名和 AGPL-3.0。`bash Scripts/test.sh` 运行全部自动检查；`bash Scripts/build_ci.sh` 只编译，不运行或发布未签名产物。
- 发布流程见 `docs/RELEASING.md`。版本与公开签名指纹位于 `Config/release.json`。本机执行 `Scripts/prepare_release.py --publish`，GitHub `Release` 校验通过后发布预发行版。
- 不导出本机签名私钥，不上传至 Secrets，不因公开仓库自动化安装本机 Runner。CI 不替代真实安装版输入/IME、窗口层级和遮挡刷新验收。
