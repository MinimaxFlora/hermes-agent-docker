# 安全策略

## 支持范围

本仓库只维护最新正式 Release 对应镜像的构建流程。旧版本镜像保留在 Registry 中，但不再接收构建侧修复。

## 报告问题

### 本仓库（工作流、脚本、发布配置）

请通过 GitHub 的[私密安全公告](https://github.com/MinimaxFlora/hermes-agent-docker/security/advisories/new)报告，**不要**公开提交 Issue。请在报告中包含：

- 受影响的 workflow / 脚本与 commit；
- 复现步骤与影响范围；
- 如涉及凭据，请说明凭据类型，但不要粘贴真实 Token。

### 上游 Hermes Agent

镜像内的应用代码、Dockerfile 与运行时依赖来自 [NousResearch/hermes-agent](https://github.com/NousResearch/hermes-agent)。应用层漏洞请遵循上游的 [SECURITY.md](https://github.com/NousResearch/hermes-agent/blob/main/SECURITY.md)。

## 凭据处理

- Docker Hub Token 仅存放于 GitHub Actions Secret，不写入仓库、镜像或日志。
- 工作流使用最小权限：`contents: read`，仅发布作业需要 `packages: write`。
- 若怀疑 Token 泄露，请立即在 Docker Hub 撤销并重新生成，然后更新 Secret。
- GHCR 使用仓库内置的 `GITHUB_TOKEN`，无需长期凭据。

## 镜像使用建议

- Dashboard 默认只监听 `127.0.0.1`，请勿在未加认证的情况下暴露到公网。
- 定期执行 `docker pull` 获取最新镜像，并及时更新容器。
- 生产环境建议固定到不可变版本标签或 digest，并在升级前阅读上游发布说明。
