# AI 驱动的 CI/CD 自愈系统 — 简历写法参考

## 项目名称

> **AI 驱动的 CI/CD 全链路自愈系统**

## STAR 写法示例

### 背景

团队微服务部署到 Kubernetes 集群后，故障排查链路长且分散：GitHub Actions 构建日志在 CI 平台，运行时错误在集群 Pod 日志和 Events 中，需要人工逐层排查、切换工具、定位根因、修复代码、重新部署，故障恢复效率低。

### 方案

设计并实现了基于 LLM 的 CI/CD 全链路闭环自愈系统，覆盖从 CI 构建到集群运行的完整故障面：

- 通过 GitHub Actions Workflow 实现容器镜像构建、推送至阿里云 ACR，并通过 Helm Chart 部署到 ACK 集群
- 构建了**双层故障检测机制**：
  - **第一层（CI 层）**：通过 GitHub CLI 轮询 Workflow 状态，失败时自动拉取失败步骤日志
  - **第二层（运行时层）**：CI 成功后通过 kubectl 探测 Pod 健康状态（Running、Ready、重启次数），并引入**二次稳定性检查**防止启动后立即崩溃的误判
- Pod 异常时自动采集 **6 维诊断信息**：Pod 状态概览、Pod Events、容器当前日志、上次崩溃日志（`--previous`）、Helm Release 状态、集群 Events
- 将故障日志 + 项目代码上下文注入 LLM Agent，由其自动完成根因分析、代码修复、git 提交推送
- 推送触发新一轮 CI/CD 流水线，形成 **"双层检测 → 多维诊断 → 根因分析 → 代码修复 → 重新部署"** 的自动闭环
- 设置最大重试轮次兜底机制，超限后输出修复摘要供人工介入

### 亮点

- **双层检测架构**：解决了 "CI 成功 ≠ 部署成功" 的盲区问题，覆盖 CI 构建失败和运行时崩溃（CrashLoopBackOff、OOMKilled、探针失败等）两大类故障场景
- **6 维集群诊断**：自动采集 Pod Status / Events / 容器日志 / 崩溃日志 / Helm 状态 / 集群 Events，为 LLM 提供充足的上下文做出准确判断
- **二次稳定性检查**：Pod 首次检查通过后间隔 30 秒再次检查，解决了应用启动后短暂存活随即崩溃的误判问题
- **多故障面分类分析**：根据日志来源（CI / 集群）自动切换分析策略，覆盖应用代码、Dockerfile、Helm Chart、Workflow 配置、环境变量、资源配额六层故障面
- **双模式交付**：以 **Claude Code Skill**（交互式，可观察干预）和 **Shell 脚本**（非交互式，适合无人值守）两种形式交付，适配不同使用场景

## 技术栈关键词

```
LLM / AI Agent / Claude Code / Claude Code Skill / Prompt Engineering
GitHub Actions / CI/CD / Helm / Kubernetes / kubectl / 阿里云 ACK / ACR
FastAPI / Python / Docker
自动化 / 闭环 / 自愈 / 故障诊断 / 可观测性
```

## 面试准备建议

1. **突出系统设计而非工具调用**——你设计的是一个双层检测 + 多维诊断的闭环自愈架构，LLM 只是分析引擎，核心竞争力在于故障检测和诊断信息采集的工程设计
2. **用"双层检测"讲故事**——举一个实际例子："CI 绿了但 Pod 不断 CrashLoopBackOff，因为环境变量缺失导致应用启动报错，传统 CI 发现不了，我的第二层检测通过 kubectl 探测 Pod 状态并自动采集崩溃日志，LLM 定位到缺失的环境变量并修复了 Helm values"
3. **准备现场 demo**——演示两个场景：① CI 构建失败自动修复 ② CI 成功但 Pod 崩溃自动修复，展示双层检测的价值
4. **准备高频追问**：
   - "LLM 修复错了怎么办？" → 最大重试次数兜底 + 交互式 Skill 模式可人工干预
   - "为什么不直接在 GitHub Actions 里调 LLM？" → 本地执行可以访问完整项目上下文 + kubectl 集群权限
   - "二次稳定性检查的意义？" → 防止 Pod 启动后短暂存活随即 OOM/崩溃的误判
   - "6 维诊断为什么要这么多？" → 不同故障类型的根因分布在不同维度，如 OOMKilled 在 Events、代码报错在容器日志、调度失败在 describe
   - "Skill 和脚本两种模式的取舍？" → Skill 适合开发阶段可观察可干预，脚本适合集成到定时任务或 webhook 无人值守场景
