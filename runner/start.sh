#!/bin/bash
set -euo pipefail

# 환경 변수 검증
if [ -z "${PAT_TOKEN:-}" ]; then
  echo "ERROR: PAT_TOKEN environment variable is not set"
  exit 1
fi

if [ -z "${RUNNER_NAME:-}" ]; then
  echo "ERROR: RUNNER_NAME environment variable is not set"
  exit 1
fi

# REPO_URL이 설정되어 있으면 사용, 없으면 기본값 사용
if [ -z "${REPO_URL:-}" ]; then
  echo "ERROR: REPO_URL environment variable is not set!"
  echo "Please set REPO_URL in your .env file or docker-compose.yml"
  exit 1  # 강제 종료
fi

# REPO_URL에서 owner/repo 추출
if [[ "$REPO_URL" =~ ^https://github.com/([^/]+)/([^/]+)(\.git)?$ ]]; then
  OWNER="${BASH_REMATCH[1]}"
  REPO="${BASH_REMATCH[2]}"
else
  echo "ERROR: Invalid REPO_URL format. Expected: https://github.com/owner/repo"
  exit 1
fi

cd /home/runner/actions-runner

echo "[$(date +'%Y-%m-%d %H:%M:%S')] Requesting new registration token for ${OWNER}/${REPO}..."

REG_TOKEN=$(curl -s -L \
  -X POST \
  -H "Accept: application/vnd.github+json" \
  -H "Authorization: Bearer ${PAT_TOKEN}" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  "https://api.github.com/repos/${OWNER}/${REPO}/actions/runners/registration-token" | jq -r .token)

if [ "$REG_TOKEN" = "null" ] || [ -z "$REG_TOKEN" ]; then
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: Failed to get registration token"
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] Check if PAT_TOKEN is valid and has 'repo' scope"
  exit 1
fi

echo "[$(date +'%Y-%m-%d %H:%M:%S')] Got token, configuring runner..."

# 기존 설정이 있으면 제거
if [ -f .runner ]; then
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] Removing existing runner configuration..."
  ./config.sh remove --token "${REG_TOKEN}" --unattended || true
fi

./config.sh \
  --url "${REPO_URL}" \
  --token "$REG_TOKEN" \
  --name "${RUNNER_NAME}" \
  --work "_work" \
  --unattended \
  --replace

if [ $? -ne 0 ]; then
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: Failed to configure runner"
  exit 1
fi

if [ -n "${PDNS_API_KEY:-}" ]; then
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] Exporting PDNS_API_KEY for GitHub Actions jobs..."
  echo "PDNS_API_KEY=$PDNS_API_KEY" >> .env
  export PDNS_API_KEY
fi

echo "[$(date +'%Y-%m-%d %H:%M:%S')] Starting GitHub Actions runner..."
exec ./run.sh