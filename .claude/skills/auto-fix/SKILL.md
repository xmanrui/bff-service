---
name: auto-fix
description: 监控 GitHub Actions 部署结果，自动分析失败日志并修复代码，然后提交推送触发重新部署
---

# Auto Fix

监控 GitHub Actions 部署结果，失败时自动分析日志、修复代码、提交推送，循环直到部署成功。

## 第一步：获取最新 workflow 运行状态

运行以下命令获取最新 workflow 状态：

```bash
gh run list --workflow=deploy.yaml --branch=main --limit=1 --json databaseId,status,conclusion
```

- 如果 status 不是 `completed`，每 30 秒重新查询一次，直到完成。
- 如果 conclusion 是 `success`，告知用户部署成功，结束。
- 如果 conclusion 是 `failure`，继续下一步。

## 第二步：拉取失败日志

使用以下命令获取失败步骤的日志：

```bash
gh run view <run_id> --log-failed
```

其中 `<run_id>` 是第一步获取到的 `databaseId`。

## 第三步：分析报错原因

仔细阅读日志，结合项目代码（包括 `app/`、`Dockerfile`、`helm/`、`.github/workflows/` 等），分析失败的根本原因。区分以下几类错误：

- 应用代码错误（Python 语法、导入、逻辑错误等）
- Dockerfile 构建错误（依赖缺失、构建步骤问题）
- Helm chart 配置错误（模板语法、配置值问题）
- GitHub Actions workflow 配置错误（步骤配置、secrets 引用问题）

## 第四步：修复代码

根据分析结果修改对应的文件来修复问题。确保：

- 只修改必要的文件，不做无关改动
- 修复方案要从根本上解决问题

## 第五步：提交并推送

将修复提交到 git 并推送：

1. `git add` 修改的文件
2. `git commit -m "fix: <修复描述>"`
3. `git push`

## 第六步：等待新一轮部署

推送后回到第一步，等待新触发的 workflow 完成并检查结果。

## 约束

- 最多重复 3 轮修复。如果 3 轮后仍然失败，输出所有尝试的修复摘要，建议用户人工介入。
- 每轮修复前都要重新阅读最新的失败日志，不要假设错误和上一轮相同。
