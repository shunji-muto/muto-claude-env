#!/usr/bin/env bash
# Claude Code Web (Ubuntu container) 用の環境セットアップ。
# session-start hook などから呼ぶ想定。冪等に動作する。
#
# 依存: bash / curl / (pip があれば代替経路可)
# shunji-muto/muto-claude-env は public リポのため apm install に認証は不要。
# 任意の環境変数:
#   - CONTEXT7_API_KEY: Context7 MCP 用 (未設定でも続行、警告のみ)
set -euo pipefail

log() { printf '[claude-code-web-setup] %s\n' "$*"; }
warn() { printf '[claude-code-web-setup] WARN: %s\n' "$*" >&2; }

# 1. bun
if ! command -v bun >/dev/null 2>&1; then
  log 'installing bun'
  curl -fsSL https://bun.sh/install | bash
  # bun のデフォルト展開先を PATH に足す
  export BUN_INSTALL="${BUN_INSTALL:-$HOME/.bun}"
  export PATH="$BUN_INSTALL/bin:$PATH"
fi

# 2. apm CLI (Microsoft Agent Package Manager)
#
# 経路 1: microsoft/apm の install.sh を raw github から直接取得
#   - aka.ms/apm-unix はリダイレクト経路でプロキシ環境で崩れることがある (2026-07-22 実測)
#   - install.sh 自体は公開 (Content-Type: text/plain) なので token なしで取れる
# 経路 2: 失敗したら pip 経由で apm-cli を導入
if ! command -v apm >/dev/null 2>&1; then
  log 'installing apm CLI (direct raw github URL)'
  install_ok=0
  APM_INSTALL_SCRIPT="$(mktemp)"
  trap 'rm -f "$APM_INSTALL_SCRIPT"' EXIT

  if curl --fail --silent --show-error --location \
       --proto '=https' --tlsv1.2 \
       -o "$APM_INSTALL_SCRIPT" \
       https://raw.githubusercontent.com/microsoft/apm/main/install.sh; then
    # 一次検証: 先頭が shebang (#!) かつ HTML/HTTP header 混入が無いこと
    if head -n1 "$APM_INSTALL_SCRIPT" | grep -q '^#!'; then
      log 'running apm install.sh'
      sh "$APM_INSTALL_SCRIPT" && install_ok=1
    else
      warn 'apm install.sh looks corrupt (no shebang). skipping.'
    fi
  else
    warn 'failed to download apm install.sh via raw github.'
  fi

  # 経路 2: pip fallback
  if [[ "$install_ok" != "1" ]] && command -v pip >/dev/null 2>&1; then
    log 'trying pip install apm-cli as fallback'
    pip install --user apm-cli && install_ok=1
  fi
  if [[ "$install_ok" != "1" ]] && command -v pip3 >/dev/null 2>&1; then
    log 'trying pip3 install apm-cli as fallback'
    pip3 install --user apm-cli && install_ok=1
  fi

  # PATH 追加 (代表候補)
  export PATH="$HOME/.local/bin:/usr/local/bin:$PATH"

  if [[ "$install_ok" != "1" ]]; then
    warn 'all apm install paths failed.'
  fi
fi

if ! command -v apm >/dev/null 2>&1; then
  warn 'apm CLI installer ran but `apm` is still not on PATH.'
  warn 'Check https://github.com/microsoft/apm for manual install.'
  exit 1
fi

# 3. muto-claude-env 展開
# --global で ~/.apm/ にインストールし ~/.claude/agents/ ~/.claude/skills/ へ hoist させる。
# --force は既存 deploy との衝突 (Errno 17) を回避（冪等再実行のため）。
log 'installing shunji-muto/muto-claude-env'
apm install --global --force shunji-muto/muto-claude-env --target claude
log "installed agents: $(ls -1 "$HOME/.claude/agents" 2>/dev/null | wc -l | tr -d ' ')"
log "installed skills: $(ls -1 "$HOME/.claude/skills" 2>/dev/null | wc -l | tr -d ' ')"

# 4. env 警告 (fail はしない)
for var in CONTEXT7_API_KEY; do
  if [[ -z "${!var:-}" ]]; then
    warn "$var is not set. Some MCP servers may not work."
  fi
done

log 'done'
