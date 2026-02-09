#!/usr/bin/env bash
#
# 自动监控 GitHub Actions 部署结果，失败时调用 Claude Code 分析并修复。
#
# 用法: ./scripts/auto-fix.sh [最大重试次数]
#
# 前置条件:
#   - gh CLI 已登录 (gh auth login)
#   - claude CLI 已安装
#   - 当前目录为项目根目录
#

set -euo pipefail

MAX_RETRIES=${1:-3}
POLL_INTERVAL=30       # 轮询间隔（秒）
WORKFLOW_FILE="deploy.yaml"
BRANCH="main"
REPO=$(gh repo view --json nameWithOwner -q '.nameWithOwner')

retry_count=0

log() {
  echo "[$(date '+%H:%M:%S')] $*"
}

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

# 获取失败 workflow 的日志
fetch_failure_logs() {
  local run_id
  run_id=$(gh run list --workflow="${WORKFLOW_FILE}" --branch="${BRANCH}" --limit=1 --json databaseId -q '.[0].databaseId')

  log "拉取 workflow run #${run_id} 的失败日志..."
  gh run view "$run_id" --log-failed 2>&1
}

# 调用 Claude Code 分析日志并修复代码
claude_fix() {
  local logs="$1"
  local prompt
  prompt=$(cat <<PROMPT
以下是 GitHub Actions 部署失败的日志:

\`\`\`
${logs}
\`\`\`

请分析失败原因，修改项目中的相关代码文件来修复这个问题。
修复后请用 git 提交更改并 push 到远程仓库。
提交信息格式: "fix: 修复描述"
PROMPT
)

  log "调用 Claude Code 分析并修复..."
  claude --print --dangerously-skip-permissions "$prompt"
}

# ========== 主流程 ==========

log "开始监控 ${REPO} 的部署流程 (最大重试: ${MAX_RETRIES})"

while [[ $retry_count -lt $MAX_RETRIES ]]; do
  conclusion=$(wait_for_workflow)

  if [[ "$conclusion" == "success" ]]; then
    log "部署成功!"
    exit 0
  fi

  retry_count=$((retry_count + 1))
  log "部署失败 (第 ${retry_count}/${MAX_RETRIES} 次尝试)"

  # 拉取失败日志
  failure_logs=$(fetch_failure_logs)

  if [[ -z "$failure_logs" ]]; then
    log "无法获取失败日志，退出"
    exit 1
  fi

  # 截取日志避免过长（保留最后 200 行）
  trimmed_logs=$(echo "$failure_logs" | tail -200)

  # 调用 Claude Code 修复
  claude_fix "$trimmed_logs"

  log "修复已提交，等待新一轮部署..."
  sleep 10  # 等待 GitHub Actions 检测到新 push
done

log "已达到最大重试次数 (${MAX_RETRIES})，退出"
exit 1
