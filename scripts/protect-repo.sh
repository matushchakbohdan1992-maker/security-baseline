#!/usr/bin/env bash
# Вмикає захист репозиторію на GitHub через gh CLI.
#
# Використання:
#   bash protect-repo.sh <owner>/<repo>              # продукт
#   bash protect-repo.sh <owner>/security-baseline --baseline
#                                                    # сам стандарт: дозволити іншим вашим
#                                                    # приватним репо викликати його workflow
# Потрібно: gh auth login (з правами admin на репозиторій). Сумісно з bash 3.2 (macOS).
#
# Кожен крок незалежний: якщо функція недоступна на вашому тарифі GitHub,
# скрипт скаже про це і продовжить.
set -uo pipefail

REPO="${1:-}"; MODE="${2:-}"
[[ "$REPO" =~ ^[A-Za-z0-9-]+/[A-Za-z0-9._-]+$ ]] || { echo "Використання: $0 <owner>/<repo> [--baseline]" >&2; exit 2; }
command -v gh >/dev/null || { echo "Потрібен GitHub CLI: brew install gh && gh auth login" >&2; exit 2; }
gh auth status >/dev/null 2>&1 || { echo "Спочатку: gh auth login" >&2; exit 2; }

ok=0; warn=0
step() { # step "<опис>" <команда...>
  local desc="$1"; shift
  local out
  if out="$("$@" 2>&1)"; then
    echo "  ✅ $desc"; ok=$((ok+1))
  else
    local why
    why="$(printf '%s' "$out" | grep -oE '"message": ?"[^"]+"' | head -1 | sed -E 's/"message": ?"//; s/"$//')"
    echo "  ⚠️  $desc — ${why:-не вдалося}"; warn=$((warn+1))
  fi
}

info="$(gh api "repos/$REPO" --jq '[.private, .default_branch, .owner.type] | @tsv')" || { echo "Репозиторій $REPO недоступний" >&2; exit 1; }
PRIVATE="$(echo "$info" | cut -f1)"; BRANCH="$(echo "$info" | cut -f2)"
echo "🔒 $REPO (private=$PRIVATE, гілка $BRANCH)"

echo "Залежності:"
step "Dependabot alerts"           gh api -X PUT "repos/$REPO/vulnerability-alerts"
step "Dependabot security updates" gh api -X PUT "repos/$REPO/automated-security-fixes"

echo "GitHub Actions:"
step "Токен workflow лише на читання за замовчуванням" \
  gh api -X PUT "repos/$REPO/actions/permissions/workflow" \
     -f default_workflow_permissions=read -F can_approve_pull_request_reviews=false

if [ "$MODE" = "--baseline" ]; then
  if [ "$PRIVATE" = "true" ]; then
    step "Дозволити вашим приватним репо використовувати workflow стандарту" \
      gh api -X PUT "repos/$REPO/actions/permissions/access" -f access_level=user
  else
    echo "  ✅ Репозиторій публічний — workflow доступні всім вашим репо"
  fi
fi

if [ "$PRIVATE" = "false" ]; then
  echo "Публічний репозиторій (безкоштовні функції):"
  sa="$(mktemp)"
  printf '%s' '{"security_and_analysis":{"secret_scanning":{"status":"enabled"},"secret_scanning_push_protection":{"status":"enabled"}}}' > "$sa"
  step "Secret scanning + push protection" gh api -X PATCH "repos/$REPO" --input "$sa"
  rm -f "$sa"
  step "Приватні звіти про вразливості" gh api -X PUT "repos/$REPO/private-vulnerability-reporting"
  step "Схвалення workflow для всіх зовнішніх контриб'юторів" \
    gh api -X PUT "repos/$REPO/actions/permissions/fork-pr-contributor-approval" \
       -f approval_policy=all_external_contributors
fi

echo "Захист гілки $BRANCH:"
if [ "$MODE" = "--baseline" ]; then
  checks='[{"context":"Lint workflows + test rules"},{"context":"scan-self / Secrets (gitleaks)"},{"context":"scan-self / Code (semgrep)"}]'
else
  checks='[{"context":"scan / Secrets (gitleaks)"},{"context":"scan / Code (semgrep)"},{"context":"scan / Dependencies (osv-scanner)"}]'
fi
ruleset=$(cat <<JSON
{
  "name": "security-baseline",
  "target": "branch",
  "enforcement": "active",
  "conditions": {"ref_name": {"include": ["~DEFAULT_BRANCH"], "exclude": []}},
  "rules": [
    {"type": "deletion"},
    {"type": "non_fast_forward"},
    {"type": "pull_request", "parameters": {
      "required_approving_review_count": 0,
      "dismiss_stale_reviews_on_push": true,
      "require_code_owner_review": false,
      "require_last_push_approval": false,
      "required_review_thread_resolution": false}},
    {"type": "required_status_checks", "parameters": {
      "strict_required_status_checks_policy": false,
      "required_status_checks": $checks}}
  ]
}
JSON
)
tmp="$(mktemp)"; trap 'rm -f "$tmp"' EXIT
printf '%s' "$ruleset" > "$tmp"
existing="$(gh api "repos/$REPO/rulesets" --jq '.[] | select(.name=="security-baseline") | .id' 2>/dev/null || true)"
if [ -n "$existing" ]; then
  step "Ruleset оновлено" gh api -X PUT "repos/$REPO/rulesets/$existing" --input "$tmp"
else
  step "Ruleset: лише через PR, обов'язкові перевірки, без force push і видалення" \
    gh api -X POST "repos/$REPO/rulesets" --input "$tmp"
fi

echo
echo "Готово: $ok увімкнено, $warn з попередженнями."
if [ "$warn" -gt 0 ] && [ "$PRIVATE" = "true" ]; then
  cat <<'EOF'
Примітка: на приватних репозиторіях безкоштовного GitHub частина функцій недоступна
(захист гілок потребує GitHub Pro; secret scanning і CodeQL — платних Secret Protection /
Code Security). Ключі й код усе одно перевіряються в CI (gitleaks, semgrep) на кожен PR.
EOF
fi
