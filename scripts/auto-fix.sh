#!/usr/bin/env bash
#
# 自动监控 GitHub Actions 部署结果 + ACK 集群运行状态，
# 失败时调用 Claude Code 分析并修复。
#
# 用法: ./scripts/auto-fix.sh [最大重试次数]
#
# 前置条件:
#   - gh CLI 已登录 (gh auth login)
#   - kubectl 已配置 ACK 集群 kubeconfig
#   - claude CLI 已安装
#   - 当前目录为项目根目录
#

set -euo pipefail

MAX_RETRIES=${1:-3}
POLL_INTERVAL=30             # GitHub Actions 轮询间隔（秒）
POD_CHECK_DELAY=60           # GH Actions 成功后等待 Pod 启动的时间（秒）
POD_STABLE_WAIT=30           # Pod 稳定性观察时间（秒）
WORKFLOW_FILE="deploy.yaml"
BRANCH="main"
HELM_RELEASE="bff-service"
K8S_NAMESPACE="default"
BUILD_JOB_NAME="Build & Push Image"
DEPLOY_JOB_NAME="Deploy to ACK"
REPO=$(gh repo view --json nameWithOwner -q '.nameWithOwner')

retry_count=0

log() {
  echo "[$(date '+%H:%M:%S')] $*"
}

# ========== GitHub Actions 相关 ==========

# 等待最新的 workflow run 完成，返回结论 (success/failure)
wait_for_workflow() {
  log "等待 GitHub Actions workflow 完成..."

  while true; do
    run_json=$(gh run list --workflow="${WORKFLOW_FILE}" --branch="${BRANCH}" --limit=1 --json databaseId,status,conclusion)
    status=$(echo "$run_json" | jq -r '.[0].status')
    conclusion=$(echo "$run_json" | jq -r '.[0].conclusion')
    run_id=$(echo "$run_json" | jq -r '.[0].databaseId')

    if [[ "$status" == "completed" ]]; then
      log "Workflow run #${run_id} 完成，结论: ${conclusion}"
      echo "$conclusion"
      return
    fi

    log "  状态: ${status}，${POLL_INTERVAL}s 后重新检查..."
    sleep "$POLL_INTERVAL"
  done
}

# 获取最新 workflow run ID
get_latest_run_id() {
  gh run list --workflow="${WORKFLOW_FILE}" --branch="${BRANCH}" --limit=1 --json databaseId -q '.[0].databaseId'
}

# 判断失败发生在哪个阶段，返回 "build" 或 "deploy"
get_failed_stage() {
  local run_id="$1"

  local jobs_json
  jobs_json=$(gh run view "$run_id" --json jobs)

  local build_conclusion
  build_conclusion=$(echo "$jobs_json" | jq -r ".jobs[] | select(.name == \"${BUILD_JOB_NAME}\") | .conclusion")

  if [[ "$build_conclusion" != "success" ]]; then
    echo "build"
  else
    echo "deploy"
  fi
}

# 获取失败 workflow 的日志
fetch_workflow_logs() {
  local run_id="$1"
  log "拉取 workflow run #${run_id} 的失败日志..."
  gh run view "$run_id" --log-failed 2>&1
}

# ========== ACK 集群相关 ==========

# 错误关键字模式
ERROR_PATTERN="Error|Exception|Traceback|FATAL|CRITICAL|panic|OOMKilled|CrashLoopBackOff|ImagePullBackOff|Failed|Errno|killed|timeout|refused"

# 智能日志截取：围绕错误关键字截取上下文，找不到则取最后 N 行
# 用法: smart_tail <全量日志> <总行数上限> <关键字前行数> <关键字后行数>
smart_tail() {
  local full_log="$1"
  local max_lines="${2:-120}"
  local before="${3:-20}"
  local after="${4:-100}"

  if [[ -z "$full_log" ]]; then
    echo "(无日志)"
    return
  fi

  # 查找最后一个匹配错误关键字的行号
  local match_line
  match_line=$(echo "$full_log" | grep -n -E "$ERROR_PATTERN" | tail -1 | cut -d: -f1)

  if [[ -n "$match_line" ]]; then
    # 找到关键字：取关键字前 before 行 + 关键字后 after 行，总数不超过 max_lines
    local total_lines
    total_lines=$(echo "$full_log" | wc -l | tr -d ' ')

    local start=$((match_line - before))
    [[ $start -lt 1 ]] && start=1

    local end=$((match_line + after))
    [[ $end -gt $total_lines ]] && end=$total_lines

    # 确保不超过 max_lines
    if [[ $((end - start + 1)) -gt $max_lines ]]; then
      end=$((start + max_lines - 1))
    fi

    echo "$full_log" | sed -n "${start},${end}p"
  else
    # 未找到关键字：取最后 max_lines 行
    echo "$full_log" | tail -"$max_lines"
  fi
}

# 检查 Pod 健康状态，返回 "healthy" 或 "unhealthy"
check_pod_health() {
  local delay="${1:-$POD_CHECK_DELAY}"

  if [[ "$delay" -gt 0 ]]; then
    log "等待 ${delay}s 让 Pod 完成启动..."
    sleep "$delay"
  fi

  log "检查 ACK 集群中 Pod 状态..."

  local pods_json
  pods_json=$(kubectl get pods -n "${K8S_NAMESPACE}" -l "app.kubernetes.io/name=${HELM_RELEASE}" -o json 2>&1)

  # 检查是否有 Pod
  local pod_count
  pod_count=$(echo "$pods_json" | jq '.items | length')
  if [[ "$pod_count" -eq 0 ]]; then
    log "未找到任何 Pod"
    echo "unhealthy"
    return
  fi

  # 检查所有 Pod 是否 Running 且所有容器 Ready
  local not_ready
  not_ready=$(echo "$pods_json" | jq '[.items[] | select(
    .status.phase != "Running" or
    (.status.containerStatuses // [] | any(.ready == false)) or
    (.status.containerStatuses // [] | any(.restartCount > 2))
  )] | length')

  if [[ "$not_ready" -gt 0 ]]; then
    log "发现 ${not_ready} 个异常 Pod"
    echo "unhealthy"
    return
  fi

  # 再等一段时间观察是否稳定（防止刚启动就崩溃的情况）
  log "Pod 看起来正常，等待 ${POD_STABLE_WAIT}s 观察稳定性..."
  sleep "$POD_STABLE_WAIT"

  not_ready=$(kubectl get pods -n "${K8S_NAMESPACE}" -l "app.kubernetes.io/name=${HELM_RELEASE}" -o json | jq '[.items[] | select(
    .status.phase != "Running" or
    (.status.containerStatuses // [] | any(.ready == false)) or
    (.status.containerStatuses // [] | any(.restartCount > 2))
  )] | length')

  if [[ "$not_ready" -gt 0 ]]; then
    log "稳定性检查失败，${not_ready} 个 Pod 异常"
    echo "unhealthy"
    return
  fi

  echo "healthy"
}

# 收集 ACK 集群中的故障诊断信息
fetch_cluster_logs() {
  local diag=""

  log "收集 ACK 集群诊断信息..."

  # 1. Pod 状态概览
  diag+="========== Pod 状态 ==========
"
  diag+=$(kubectl get pods -n "${K8S_NAMESPACE}" -l "app.kubernetes.io/name=${HELM_RELEASE}" -o wide 2>&1)
  diag+="

"

  # 2. 异常 Pod 的详细描述（Events 等）
  local problem_pods
  problem_pods=$(kubectl get pods -n "${K8S_NAMESPACE}" -l "app.kubernetes.io/name=${HELM_RELEASE}" \
    --field-selector=status.phase!=Running -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)

  # 如果没有非 Running 的 Pod，取所有 Pod（可能是 CrashLoopBackOff 但 phase 仍是 Running）
  if [[ -z "$problem_pods" ]]; then
    problem_pods=$(kubectl get pods -n "${K8S_NAMESPACE}" -l "app.kubernetes.io/name=${HELM_RELEASE}" \
      -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)
  fi

  # 最多采集 3 个 Pod 实例的日志，同一 Deployment 的 Pod 崩溃原因通常相同
  local pod_count=0
  local max_pods=3

  for pod in $problem_pods; do
    if [[ $pod_count -ge $max_pods ]]; then
      diag+="(已达到最大采集数 ${max_pods}，剩余 Pod 省略)
"
      break
    fi
    pod_count=$((pod_count + 1))
    diag+="========== Pod 描述: ${pod} ==========
"
    diag+=$(kubectl describe pod "${pod}" -n "${K8S_NAMESPACE}" 2>&1 | tail -40)
    diag+="

"

    # 3. 容器日志（当前 + 上一次崩溃的）
    diag+="========== Pod 日志: ${pod} ==========
"
    local raw_logs
    raw_logs=$(kubectl logs "${pod}" -n "${K8S_NAMESPACE}" --tail=500 2>&1)
    diag+=$(smart_tail "$raw_logs" 120 20 100)
    diag+="

"

    diag+="========== Pod 上次崩溃日志: ${pod} ==========
"
    local raw_prev_logs
    raw_prev_logs=$(kubectl logs "${pod}" -n "${K8S_NAMESPACE}" --previous --tail=500 2>&1 || echo "")
    if [[ -n "$raw_prev_logs" ]]; then
      diag+=$(smart_tail "$raw_prev_logs" 120 20 100)
    else
      diag+="(无上次崩溃日志)"
    fi
    diag+="

"
  done

  # 4. Helm 部署时使用的 values
  diag+="========== Helm Values ==========
"
  diag+=$(helm get values "${HELM_RELEASE}" -n "${K8S_NAMESPACE}" 2>&1 || echo "(无法获取 Helm values)")
  diag+="

"

  # 5. Helm 渲染后的 K8s 资源清单
  diag+="========== Helm Manifest ==========
"
  diag+=$(helm get manifest "${HELM_RELEASE}" -n "${K8S_NAMESPACE}" 2>&1 || echo "(无法获取 Helm manifest)")
  diag+="

"

  # 6. Events
  diag+="========== 最近集群 Events ==========
"
  diag+=$(kubectl get events -n "${K8S_NAMESPACE}" --sort-by='.lastTimestamp' --field-selector involvedObject.kind=Pod 2>&1 | tail -30)

  echo "$diag"
}

# ========== Claude Code 调用 ==========

claude_fix() {
  local error_source="$1"  # "build" / "deploy" / "runtime"
  local logs="$2"
  local prompt

  if [[ "$error_source" == "build" ]]; then
    prompt=$(cat <<PROMPT
以下是 GitHub Actions 构建阶段失败的日志:

\`\`\`
${logs}
\`\`\`

错误发生在 CI 构建阶段（Docker 镜像构建/推送），请分析失败原因。
修复后请用 git 提交更改并 push 到远程仓库。
提交信息格式: "fix: 修复描述"
PROMPT
)

  elif [[ "$error_source" == "deploy" ]]; then
    prompt=$(cat <<PROMPT
GitHub Actions 构建成功，但在部署阶段失败。以下是两部分诊断信息：

=== 第一部分：GitHub Actions 部署阶段的错误日志 ===

\`\`\`
${logs}
\`\`\`

=== 第二部分：ACK 集群诊断信息（Pod 状态、Events、容器日志等）===

\`\`\`
${CLUSTER_DIAG}
\`\`\`

部署阶段失败的根因可能在 CI 日志中（如 Helm 模板错误），也可能需要结合集群信息才能定位（如 Pod 启动失败、探针超时）。
请综合两部分信息分析根因，修改项目中的相关代码文件来修复问题。
修复后请用 git 提交更改并 push 到远程仓库。
提交信息格式: "fix: 修复描述"
PROMPT
)

  else
    prompt=$(cat <<PROMPT
GitHub Actions 构建和部署均成功，但应用在 ACK 集群中运行异常。
以下是从集群中收集的诊断信息（包含 Pod 状态、Events、容器日志等）:

\`\`\`
${logs}
\`\`\`

请根据以上集群诊断信息，结合项目代码分析根因。常见原因包括：
- 应用启动崩溃（代码错误、依赖缺失、配置错误）
- 健康检查失败（接口未就绪、路径不匹配、超时）
- 资源不足（OOMKilled、CPU 限制过低）
- 环境变量/Secret 配置缺失或错误
- 镜像拉取失败（地址错误、认证问题）

定位根因后修改对应文件修复问题。
修复后请用 git 提交更改并 push 到远程仓库。
提交信息格式: "fix: 修复描述"
PROMPT
)
  fi

  log "调用 Claude Code 分析并修复 (错误来源: ${error_source})..."
  claude --print --dangerously-skip-permissions "$prompt"
}

# ========== 主流程 ==========

log "开始监控 ${REPO} 的部署流程 (最大重试: ${MAX_RETRIES})"

while [[ $retry_count -lt $MAX_RETRIES ]]; do
  conclusion=$(wait_for_workflow)

  if [[ "$conclusion" == "failure" ]]; then
    retry_count=$((retry_count + 1))
    run_id=$(get_latest_run_id)
    failed_stage=$(get_failed_stage "$run_id")

    if [[ "$failed_stage" == "build" ]]; then
      # ---- 场景 1: 构建阶段失败，只看 CI 日志 ----
      log "构建阶段失败 (第 ${retry_count}/${MAX_RETRIES} 次尝试)"

      ci_logs=$(fetch_workflow_logs "$run_id")
      trimmed_logs=$(echo "$ci_logs" | tail -200)
      claude_fix "build" "$trimmed_logs"

    else
      # ---- 场景 2: 部署阶段失败，CI 日志 + 集群诊断 ----
      log "部署阶段失败 (第 ${retry_count}/${MAX_RETRIES} 次尝试)"

      ci_logs=$(fetch_workflow_logs "$run_id")
      trimmed_ci_logs=$(echo "$ci_logs" | tail -200)

      log "同时收集 ACK 集群诊断信息..."
      CLUSTER_DIAG=$(fetch_cluster_logs | tail -300)
      export CLUSTER_DIAG

      claude_fix "deploy" "$trimmed_ci_logs"
    fi

  elif [[ "$conclusion" == "success" ]]; then
    # ---- 场景 3: CI 全部成功，检查集群 Pod 健康 ----
    log "GitHub Actions 成功，开始检查 ACK 集群 Pod 状态..."

    pod_status=$(check_pod_health)

    if [[ "$pod_status" == "healthy" ]]; then
      log "部署成功! Pod 运行正常。"
      exit 0
    fi

    # Pod 异常，收集集群诊断信息
    retry_count=$((retry_count + 1))
    log "Pod 运行异常 (第 ${retry_count}/${MAX_RETRIES} 次尝试)"

    cluster_logs=$(fetch_cluster_logs)
    trimmed_logs=$(echo "$cluster_logs" | tail -300)
    claude_fix "runtime" "$trimmed_logs"

  else
    log "未知 workflow 结论: ${conclusion}，退出"
    exit 1
  fi

  log "修复已提交，等待新一轮部署..."
  sleep 10
done

log "已达到最大重试次数 (${MAX_RETRIES})，退出"
exit 1
