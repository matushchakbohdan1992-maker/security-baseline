#!/usr/bin/env bash
# Витягує вбудовані semgrep-правила з reusable workflow в окремий файл
# (для локального запуску та тестів). Єдине джерело правил — security-scan.yml.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
out="${1:-$root/.cache/baseline-rules.yml}"
mkdir -p "$(dirname "$out")"
awk '/@@BASELINE_RULES_BEGIN@@/{f=1} f{print} /@@BASELINE_RULES_END@@/{f=0}' \
  "$root/.github/workflows/security-scan.yml" | sed -E 's/^ {10}//' > "$out"
echo "$out"
