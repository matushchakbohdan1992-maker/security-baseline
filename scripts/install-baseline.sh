#!/usr/bin/env bash
# Підключає проєкт до security-baseline.
#
# Використання (з кореня продукту або з --target):
#   bash /шлях/до/security-baseline/scripts/install-baseline.sh --owner <github-user> [--profile web,mobile,ai] [--target DIR] [--force]
#
# Що робить (нічого не видаляє; наявні файли не перезаписує без --force):
#   - .github/workflows/security.yml і dast.yml (виклик спільних перевірок)
#   - .github/dependabot.yml під знайдені в проєкті менеджери пакетів
#   - .pre-commit-config.yaml, .gitleaks.toml, .env.example, SECURITY.md
#   - дописує правила в .gitignore і CLAUDE.md (один раз, за маркером)
#   - кладе шаблони в docs/security/ (brief, інцидент, чекліст релізу)
#   - вмикає pre-commit хук, якщо pre-commit встановлено
set -euo pipefail

BASE="$(cd "$(dirname "$0")/.." && pwd)"
TPL="$BASE/templates/project"
DOCS="$BASE/templates/docs"
OWNER=""; PROFILE=""; TARGET="$PWD"; FORCE=0

while [ $# -gt 0 ]; do
  case "$1" in
    --owner)   OWNER="$2"; shift 2 ;;
    --profile) PROFILE="$2"; shift 2 ;;
    --target)  TARGET="$2"; shift 2 ;;
    --force)   FORCE=1; shift ;;
    -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
    *) echo "Невідомий параметр: $1" >&2; exit 2 ;;
  esac
done

[ -n "$OWNER" ] || { echo "Вкажіть --owner <ваш GitHub-логін або організація>" >&2; exit 2; }
[[ "$OWNER" =~ ^[A-Za-z0-9-]+$ ]] || { echo "Некоректний --owner: $OWNER" >&2; exit 2; }
TARGET="$(cd "$TARGET" && pwd)"
[ "$TARGET" != "$BASE" ] || { echo "Запускайте для продукту, а не для самого security-baseline" >&2; exit 2; }
cd "$TARGET"

has() { find . -path ./node_modules -prune -o -path ./.git -prune -o -path ./Pods -prune -o -path ./.build -prune -o \( "$@" \) -print -quit 2>/dev/null | grep -q .; }

# ---------- автовизначення профілю ----------
if [ -z "$PROFILE" ]; then
  p=()
  if has -name package.json -o -name requirements.txt -o -name pyproject.toml -o -name go.mod -o -name '*.html'; then p+=(web); fi
  if has -name '*.xcodeproj' -o -name Package.swift -o -name '*.swift' -o -name build.gradle -o -name build.gradle.kts -o -name AndroidManifest.xml; then p+=(mobile); fi
  if grep -rqsIE --exclude-dir={node_modules,.git,Pods,.build,dist,build} \
       '(import openai|from openai|import anthropic|from anthropic|@anthropic-ai/sdk|"openai"|telegram|aiogram|ccxt|langchain|google\.generativeai)' . 2>/dev/null; then p+=(ai); fi
  [ ${#p[@]} -gt 0 ] || p=(web)
  PROFILE="$(printf '%s,' "${p[@]}")"; PROFILE="${PROFILE%,}"
  echo "Профіль визначено автоматично: $PROFILE (змінити: --profile)"
fi
[[ "$PROFILE" =~ ^(web|mobile|ai)(,(web|mobile|ai))*$ ]] || { echo "Некоректний --profile: $PROFILE" >&2; exit 2; }

created=(); skipped=()
put() { # put <src> <dst> [render]
  local src="$1" dst="$2"
  if [ -e "$dst" ] && [ "$FORCE" -ne 1 ]; then skipped+=("$dst"); return; fi
  mkdir -p "$(dirname "$dst")"
  if [ "${3:-}" = render ]; then
    sed -e "s/__OWNER__/$OWNER/g" -e "s/__PROFILE__/$PROFILE/g" "$src" > "$dst"
  else
    cp "$src" "$dst"
  fi
  created+=("$dst")
}

put "$TPL/.github/workflows/security.yml" .github/workflows/security.yml render
put "$TPL/.github/workflows/dast.yml"     .github/workflows/dast.yml render
put "$TPL/.pre-commit-config.yaml"        .pre-commit-config.yaml
put "$TPL/.gitleaks.toml"                 .gitleaks.toml
put "$TPL/.env.example"                   .env.example
put "$TPL/SECURITY.md"                    SECURITY.md
for f in SECURITY-BRIEF.md INCIDENT.md RELEASE-CHECKLIST.md; do
  put "$DOCS/$f" "docs/security/$f"
done

# ---------- .gitignore і CLAUDE.md: дописати один раз ----------
append_once() { # append_once <src> <dst> <marker>
  if [ -f "$2" ] && grep -qF "$3" "$2"; then skipped+=("$2 (вже містить правила)"); return; fi
  cat "$1" >> "$2"; created+=("$2 (доповнено)")
}
append_once "$TPL/gitignore.security" .gitignore "# --- security-baseline ---"
append_once "$TPL/CLAUDE.security.md" CLAUDE.md "## Безпека (security-baseline)"

# ---------- dependabot.yml під реальні менеджери пакетів ----------
# Сумісно з bash 3.2 і BSD-утилітами macOS (без mapfile та xargs -r).
dirs_of() { # dirs_of <find-expr...> → унікальні папки у форматі "/path", по одній на рядок
  find . -path ./node_modules -prune -o -path '*/node_modules' -prune -o -path ./.git -prune \
       -o -path ./Pods -prune -o -path ./.build -prune -o \( "$@" \) -print 2>/dev/null \
    | while IFS= read -r f; do dirname "$f"; done \
    | sed -e 's#^\.$#/#' -e 's#^\./#/#' | sort -u
}
eco_block() { # eco_block <ecosystem> <newline-separated dirs>
  local eco="$1" dirs="$2"
  [ -n "$dirs" ] || return 0
  echo "  - package-ecosystem: \"$eco\""
  echo "    directories:"
  printf '%s\n' "$dirs" | while IFS= read -r d; do echo "      - \"$d\""; done
  echo "    schedule: { interval: \"weekly\", day: \"monday\" }"
  echo "    open-pull-requests-limit: 10"
  echo "    groups:"
  echo "      security:"
  echo "        applies-to: security-updates"
  echo "        patterns: [\"*\"]"
}
if [ ! -e .github/dependabot.yml ] || [ "$FORCE" -eq 1 ]; then
  mkdir -p .github
  {
    echo "# Згенеровано security-baseline/install-baseline.sh"
    echo "version: 2"
    echo "updates:"
    eco_block github-actions "/"
    eco_block pip    "$(dirs_of -name requirements.txt -o -name 'requirements-*.txt' -o -name pyproject.toml -o -name Pipfile)"
    eco_block npm    "$(dirs_of -name package.json)"
    eco_block swift  "$(dirs_of -name Package.swift)"
    eco_block gradle "$(dirs_of -name build.gradle -o -name build.gradle.kts)"
    eco_block gomod  "$(dirs_of -name go.mod)"
    eco_block docker "$(dirs_of -name Dockerfile -o -name 'Dockerfile.*')"
  } > .github/dependabot.yml
  created+=(.github/dependabot.yml)
else
  skipped+=(.github/dependabot.yml)
fi

# ---------- pre-commit ----------
hook="не встановлено"
if [ -d .git ] && command -v pre-commit >/dev/null 2>&1; then
  pre-commit install >/dev/null && hook="встановлено"
fi

echo
echo "✅ security-baseline підключено до: $TARGET"
echo "   Профіль: $PROFILE · Власник: $OWNER"
[ ${#created[@]} -eq 0 ] || printf '   + %s\n' "${created[@]}"
[ ${#skipped[@]} -eq 0 ] || printf '   = пропущено (вже є): %s\n' "${skipped[@]}"
echo "   pre-commit хук: $hook"
cat <<EOF

Далі:
  1. Заповніть docs/security/SECURITY-BRIEF.md (можна разом із Claude).
  2. $( [ "$hook" = "встановлено" ] && echo "pre-commit готовий." || echo "brew install pre-commit && pre-commit install" )
  3. git add -A && git commit -m "Connect security-baseline" && git push
  4. Захист репозиторію на GitHub:
       bash $BASE/scripts/protect-repo.sh $OWNER/<назва-репозиторію>
  5. Опційно: ШІ-рев'ю PR — секрет ANTHROPIC_API_KEY + змінна ENABLE_AI_REVIEW=true;
     DAST — змінна DAST_TARGET=https://staging.ваш-домен.
EOF
