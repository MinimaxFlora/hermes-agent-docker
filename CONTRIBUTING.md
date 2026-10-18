# 贡献指南

感谢参与改进 Hermes Agent Docker 构建流程。本仓库只负责“同步上游 → 构建 → 发布”的自动化，不包含 Hermes Agent 应用代码；应用功能与缺陷请提交到[上游仓库](https://github.com/NousResearch/hermes-agent)。

## 提交前检查

```bash
npm ci
npm run lint
bash scripts/ci/install-actionlint.sh && .tools/actionlint -color
shellcheck scripts/*.sh scripts/ci/*.sh
python3 -m unittest discover -s tests -v
```

如果修改了 `package.json` 依赖，请同时提交更新后的 `package-lock.json`。

## 修改约定

- 工作流：保持最小权限，第三方 Action 固定到 commit SHA 并保留版本注释。
- Shell：使用 `#!/usr/bin/env bash` 与 `set -Eeuo pipefail`，通过 ShellCheck，不引入未声明的依赖。
- Python：仅使用标准库；新增逻辑需附带 `unittest` 用例。
- 文档：中文为主，命令可复制执行；更新行为时同步更新 README。
- 提交信息：使用 Conventional Commits（`feat:`、`fix:`、`ci:`、`docs:`、`chore:`）。

## Pull Request

1. 从 `main` 创建分支，保持改动聚焦。
2. 在 PR 描述中说明动机、行为变化与验证方式。
3. 确保 `Lint` 工作流全部通过。
4. 涉及发布行为的改动，请附上手动触发 `workflow_dispatch` 的验证链接或截图。

## 发布相关

- 不要提交任何真实凭据、Token 或 `.env` 文件。
- 修改标签规则、Registry 或镜像名属于破坏性变更，请在 PR 中明确说明迁移方式。
