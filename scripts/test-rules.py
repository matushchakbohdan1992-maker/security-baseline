#!/usr/bin/env python3
"""Перевіряє вбудовані semgrep-правила на фікстурах у tests/rules.

Позначки у фікстурах (рядок над кодом):
    # ruleid: <id>   — на наступному рядку правило МАЄ спрацювати
    # ok: <id>       — на наступному рядку правило НЕ має спрацювати
Запуск: python3 scripts/test-rules.py   (потрібен semgrep у PATH)
"""
import json
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
FIXTURES = ROOT / "tests" / "rules"
MARK = re.compile(r"(?:#|//)\s*(ruleid|ok):\s*([\w-]+)")


def main() -> int:
    rules = subprocess.run(
        [str(ROOT / "scripts" / "extract-rules.sh")],
        check=True, capture_output=True, text=True,
    ).stdout.strip()

    expected, forbidden = set(), set()
    for f in FIXTURES.rglob("*"):
        if not f.is_file():
            continue
        lines = f.read_text().splitlines()
        for i, line in enumerate(lines):
            m = MARK.search(line)
            if not m:
                continue
            kind, rule = m.groups()
            key = (str(f.relative_to(ROOT)), i + 2, rule)  # наступний рядок, 1-based
            (expected if kind == "ruleid" else forbidden).add(key)

    # Фікстури виключені з самоскану репозиторію (.semgrepignore), тому
    # скануємо їхню копію поза репозиторієм.
    tmp = pathlib.Path(tempfile.mkdtemp(prefix="sb-rules-"))
    shutil.copytree(FIXTURES, tmp / "tests" / "rules")
    proc = subprocess.run(
        ["semgrep", "scan", "--metrics=off", "--json", "--quiet", "--no-git-ignore",
         "--config", rules, "tests/rules"],
        capture_output=True, text=True, cwd=tmp,
    )
    shutil.rmtree(tmp, ignore_errors=True)
    try:
        data = json.loads(proc.stdout)
    except json.JSONDecodeError:
        print(proc.stderr, file=sys.stderr)
        return 2
    for err in data.get("errors", []):
        print("semgrep error:", err.get("message", err), file=sys.stderr)

    found = set()
    for r in data.get("results", []):
        rule = r["check_id"].split(".")[-1]
        path = str(pathlib.PurePosixPath(r["path"]))
        found.add((path, r["start"]["line"], rule))

    missed = sorted(expected - found)
    false_pos = sorted(forbidden & found)
    for m in missed:
        print("MISSED   ", *m)
    for fp in false_pos:
        print("FALSE POS", *fp)
    print(f"expected={len(expected)} ok-marks={len(forbidden)} "
          f"missed={len(missed)} false_positives={len(false_pos)}")
    return 1 if (missed or false_pos or data.get("errors")) else 0


if __name__ == "__main__":
    sys.exit(main())
