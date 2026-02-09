# Auto-Fix 排查链路

```
git push → 触发 GitHub Actions
                │
                ▼
        ┌── CI 完成了吗？──┐
        │  没有，每30s查一次  │
        └──────────────────┘
                │ 完成
                ▼
        ┌── 结论是什么？
        │
        ├── failure → 哪个阶段失败？
        │               │
        │               ├── build job 失败
        │               │   │
        │               │   │  信息源: CI 日志
        │               │   │  gh run view <id> --log-failed
        │               │   │
        │               │   │  排查方向:
        │               │   │  · Dockerfile 构建错误
        │               │   │  · 依赖安装失败
        │               │   │  · ACR 推送认证失败
        │               │   │
        │               │   ▼
        │               │  Claude 分析 → 修复 → push → 重新来
        │               │
        │               └── deploy job 失败
        │                   │
        │                   │  信息源: CI 日志 + 集群诊断（双源合并）
        │                   │
        │                   │  CI 日志:
        │                   │  gh run view <id> --log-failed
        │                   │
        │                   │  集群诊断 (6 维):
        │                   │  · kubectl get pods        (Pod 状态)
        │                   │  · kubectl describe pod    (Events)
        │                   │  · kubectl logs            (容器日志)
        │                   │  · kubectl logs --previous (崩溃日志)
        │                   │  · helm status             (Release 状态)
        │                   │  · kubectl get events      (集群 Events)
        │                   │
        │                   │  排查方向:
        │                   │  · Helm 模板渲染错误 (CI 日志)
        │                   │  · helm --wait 超时 (CI 日志 + 集群日志定位根因)
        │                   │  · Pod CrashLoopBackOff (集群日志)
        │                   │  · 探针失败致 rollout 超时 (集群 Events)
        │                   │  · ImagePullBackOff (集群 Events)
        │                   │
        │                   ▼
        │                  Claude 分析 → 修复 → push → 重新来
        │
        └── success → 检查 ACK 集群 Pod 状态
                        │
                        ├── 等 60s → 第一次检查
                        │   └── 通过 → 等 30s → 第二次检查 (稳定性)
                        │               ├── 通过 → 部署成功 ✓
                        │               └── 失败 ↓
                        │
                        └── Pod 异常
                            │
                            │  信息源: 集群诊断 (同上 6 维)
                            │
                            │  排查方向:
                            │  · 应用启动崩溃
                            │  · 健康检查失败
                            │  · OOMKilled / CPU 限制
                            │  · 环境变量/Secret 缺失
                            │  · 镜像拉取失败
                            │
                            ▼
                           Claude 分析 → 修复 → push → 重新来

整个循环最多 3 轮，超限人工介入
```

## 三种场景的信息源对比

| 场景 | CI 日志 | 集群诊断 | 原因 |
|---|---|---|---|
| 构建失败 | ✓ | ✗ | 镜像没出来，集群里没有新部署 |
| 部署失败 | ✓ | ✓ | CI 日志看到超时/报错，但根因往往藏在集群里 |
| CI 成功但 Pod 异常 | ✗ | ✓ | CI 视角一切正常，问题只在运行时 |
