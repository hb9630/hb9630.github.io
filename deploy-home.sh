#!/usr/bin/env bash
#
# hb9630.github.io 个人主页 — 一键部署
#
# 用法：
#   GITHUB_TOKEN=ghp_xxx ./deploy-home.sh
#
# 说明：
#   - 首次运行自动创建 hb9630.github.io 仓库并启用 Pages
#   - 之后运行仅提交并推送 index.html 等变更
#   - token 仅用于本次操作，不写入任何文件
#
set -euo pipefail

OWNER="${GITHUB_OWNER:-hb9630}"
REPO="${REPO:-hb9630.github.io}"   # 用户主页仓库（Pages 根路径）
REMOTE="https://github.com/${OWNER}/${REPO}.git"
PAGES_URL="https://${OWNER}.github.io/"
API="https://api.github.com/repos/${OWNER}/${REPO}"

TOKEN="${GITHUB_TOKEN:-}"
if [ -z "$TOKEN" ]; then
  echo "错误：请通过环境变量提供 GITHUB_TOKEN" >&2
  exit 1
fi

cd "$(dirname "$0")"
HELPER='!f() { echo "username='"${OWNER}"'"; echo "password='"${TOKEN}"'"; }; f'

# 1) 仓库不存在则创建
code="$(curl -s -o /tmp/.repo-exists -w '%{http_code}' \
  -H "Authorization: token ${TOKEN}" "${API}")"
if [ "$code" = "404" ]; then
  echo "==> 创建仓库 ${OWNER}/${REPO}"
  curl -sf -X POST https://api.github.com/user/repos \
    -H "Authorization: token ${TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    -d "{\"name\":\"${REPO}\",\"description\":\"个人项目主页\",\"private\":false}" -o /dev/null
fi

# 2) 本地 git 仓库（仅首次）
if [ ! -d .git ]; then
  git init -q -b main
  git remote add origin "${REMOTE}"
fi

# 3) 提交（有变更才提交）
git add -A
if git diff --cached --quiet; then
  echo "==> 无变更，跳过提交"
else
  STAMP="$(date '+%Y-%m-%d %H:%M')"
  git -c user.name="${OWNER}" -c user.email="${OWNER}@users.noreply.github.com" \
    commit -q -m "deploy: ${STAMP}"
  echo "==> 已提交 $(git rev-parse --short HEAD)"
fi

# 4) 推送（若远端有新提交先拉取）
echo "==> 推送到 ${OWNER}/${REPO}"
if ! git -c "credential.helper=${HELPER}" push -q -u origin main 2>/dev/null; then
  echo "    远端有更新，先拉取再推送…"
  git -c "credential.helper=${HELPER}" pull -q --rebase origin main
  git -c "credential.helper=${HELPER}" push -q -u origin main
fi

# 5) 启用 Pages（已启用则忽略）
echo "==> 确认 Pages 已启用"
curl -s -X POST "${API}/pages" \
  -H "Authorization: token ${TOKEN}" \
  -H "Accept: application/vnd.github+json" \
  -d '{"source":{"branch":"main","path":"/"}}' -o /tmp/.pages-result
grep -q '"html_url"' /tmp/.pages-result || echo "    （已启用，无需变更）"

# 6) 等待上线
echo "==> 等待部署生效"
for i in $(seq 1 20); do
  sleep 5
  code="$(curl -s -o /dev/null -w '%{http_code}' "${PAGES_URL}")"
  if [ "$code" = "200" ]; then
    echo "--------------------------------------------------"
    echo "主页已上线：${PAGES_URL}"
    echo "--------------------------------------------------"
    exit 0
  fi
done
echo "警告：未能确认主页上线，请稍后检查 ${PAGES_URL}" >&2
exit 2
