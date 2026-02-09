---
name: auto-fix
description: 监控 GitHub Actions 部署结果和 ACK 集群运行状态，自动分析失败日志并修复代码，然后提交推送触发重新部署
---

# Auto Fix

监控 GitHub Actions 部署结果 + ACK 集群 Pod 运行状态，失败时自动分析日志、修复代码、提交推送，循环直到部署成功。

## 第一步：获取最新 workflow 运行状态

运行以下命令获取最新 workflow 状态：

```bash
gh run list --workflow=deploy.yaml --branch=main --limit=1 --json databaseId,status,conclusion
```

- 如果 status 不是 `completed`，每 30 秒重新查询一次，直到完成。
- 如果 conclusion 是 `failure`，继续**第二步**判断失败阶段。
- 如果 conclusion 是 `success`，跳到**第四步**检查集群。

## 第二步：判断失败发生在哪个阶段

通过 gh CLI 查询各 job 的状态来判断：

```bash
gh run view <run_id> --json jobs
```

检查 `Build & Push Image` job 的 conclusion：
- 如果 build job 不是 `success` → 失败在**构建阶段**，跳到**第三步 A**
- 如果 build job 是 `success` → 失败在**部署阶段**，跳到**第三步 B**

## 第三步 A：构建阶段失败 — 只看 CI 日志

构建失败意味着镜像没构建出来，新代码没有部署到集群，不需要查集群。

```bash
gh run view <run_id> --log-failed
```

拿到日志后分析失败原因，重点关注：
- Dockerfile 构建错误（依赖缺失、构建步骤问题）
- Docker 推送失败（ACR 认证、网络问题）
- 应用代码错误导致构建中断

分析完跳到**第五步**修复代码。

## 第三步 B：部署阶段失败 — CI 日志 + 集群诊断

构建成功但部署失败，根因可能在 CI 日志中（Helm 模板错误），也可能需要集群信息才能定位（Pod 启动失败、探针超时）。需要**同时收集两部分信息**。

**第一部分：CI 部署阶段日志**

```bash
gh run view <run_id> --log-failed
```

**第二部分：ACK 集群诊断信息**

```bash
# 1. Pod 状态概览
kubectl get pods -n default -l "app.kubernetes.io/name=bff-service" -o wide

# 2. 异常 Pod 的详细描述（重点看 Events 和 State）
kubectl describe pod <pod_name> -n default

# 3. 容器当前日志
kubectl logs <pod_name> -n default --tail=80

# 4. 容器上一次崩溃的日志
kubectl logs <pod_name> -n default --previous --tail=80

# 5. Helm release 状态
helm status bff-service -n default

# 6. 最近的集群 Events
kubectl get events -n default --sort-by='.lastTimestamp' --field-selector involvedObject.kind=Pod
```

**综合两部分信息**分析根因，重点关注：
- Helm 模板渲染错误（CI 日志可见）
- helm --wait 超时（CI 日志可见，但根因需要结合集群日志）
- Pod 启动失败、CrashLoopBackOff（集群日志可见）
- 探针健康检查失败导致 rollout 超时（集群 Events 可见）
- 镜像拉取失败 ImagePullBackOff（集群 Events 可见）

分析完跳到**第五步**修复代码。

## 第四步：CI 全部成功 — 检查 ACK 集群 Pod 健康

GitHub Actions 成功不代表应用正常运行。等待 60 秒让 Pod 完成启动，然后检查集群状态：

```bash
kubectl get pods -n default -l "app.kubernetes.io/name=bff-service" -o json
```

判断 Pod 是否健康：
- 所有 Pod 的 STATUS 为 `Running`
- 所有容器 READY（如 `1/1`）
- 没有频繁重启（restartCount ≤ 2）

如果 Pod 健康，再等 30 秒做二次稳定性检查。稳定则**告知用户部署成功，结束**。

如果 Pod 异常，收集第三步 B 中列出的 6 项集群诊断信息，分析根因，重点关注：
- 应用启动崩溃（代码错误、依赖缺失、配置错误）
- 健康检查失败（接口未就绪、路径不匹配、超时设置不合理）
- 资源不足（OOMKilled、CPU throttling）
- 环境变量 / Secret 配置缺失或错误
- 镜像拉取失败（地址错误、认证问题）

## 第五步：修复代码

根据分析结果修改对应的文件来修复问题。确保：

- 只修改必要的文件，不做无关改动
- 修复方案要从根本上解决问题

## 第六步：提交并推送

将修复提交到 git 并推送：

1. `git add` 修改的文件
2. `git commit -m "fix: <修复描述>"`
3. `git push`

## 第七步：等待新一轮部署

推送后回到第一步，等待新触发的 workflow 完成并检查结果。

## 约束

- 最多重复 3 轮修复。如果 3 轮后仍然失败，输出所有尝试的修复摘要，建议用户人工介入。
- 每轮修复前都要重新阅读最新的失败日志，不要假设错误和上一轮相同。
- 部署阶段失败时，必须同时收集 CI 日志和集群诊断信息，综合分析根因。
- GitHub Actions 成功后必须检查 ACK 集群 Pod 状态，不能仅凭 CI 成功就判定部署成功。
