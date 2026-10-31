# security-baseline

Єдиний стандарт безпеки для всіх продуктів: веб і API, Mac і мобільні застосунки, ШІ-продукти та боти.
Кожен продукт підключається одним скриптом і далі автоматично отримує всі перевірки.
Нові правила, додані тут, одразу діють у всіх продуктах.

## Що отримує кожен продукт

| Етап | Що перевіряється | Інструмент | Де |
| --- | --- | --- | --- |
| Перед комітом | Ключі й токени, приватні ключі, `.env`, великі файли | gitleaks, pre-commit | Ваш Mac |
| Кожен PR і push | Ключі в нових комітах | gitleaks | GitHub Actions |
| Кожен PR і push | Вразливості в коді (OWASP Top 10, ін'єкції, авторизація) + власні правила для веб/mobile/ШІ | Semgrep | GitHub Actions |
| Кожен PR і push | Вразливі залежності (pip, npm, SwiftPM, Gradle, Go…) | OSV-Scanner | GitHub Actions |
| Кожен PR і push | Dockerfile, docker-compose, Terraform, Kubernetes | Trivy | GitHub Actions |
| Кожен PR | ШІ-рев'ю безпеки змін (опційно) | Claude (`claude-code-security-review`) | GitHub Actions |
| Щотижня | Повний повторний скан (нові CVE у старому коді) + оновлення залежностей | усе вище + Dependabot | GitHub Actions |
| Щомісяця / перед релізом | Задеплоєний сайт або API | OWASP ZAP | GitHub Actions |
| Завжди | Правила безпечного коду для Claude | `CLAUDE.md` | Claude Code |

Плюс шаблони: [security brief](templates/docs/SECURITY-BRIEF.md), [план інциденту](templates/docs/INCIDENT.md), [чекліст релізу](templates/docs/RELEASE-CHECKLIST.md).

## Встановлення (один раз)

1. Створіть на GitHub репозиторій `security-baseline` (приватний або публічний — секретів тут немає) і завантажте цей код.
2. Встановіть інструменти на Mac:
   ```bash
   brew install gh pre-commit
   gh auth login
   ```
3. Дозвольте своїм приватним репозиторіям використовувати перевірки стандарту:
   ```bash
   bash scripts/protect-repo.sh <ваш-логін>/security-baseline --baseline
   ```

## Підключення продукту (новий чи наявний)

```bash
cd ~/шлях/до/продукту
bash ~/шлях/до/security-baseline/scripts/install-baseline.sh --owner <ваш-логін>
#   профіль визначається автоматично; вручну: --profile web,mobile,ai
git add -A && git commit -m "Connect security-baseline" && git push
bash ~/шлях/до/security-baseline/scripts/protect-repo.sh <ваш-логін>/<продукт>
```

Скрипт нічого не видаляє і не перезаписує наявні файли (крім випадку з `--force`).
`.gitignore` і `CLAUDE.md` він лише доповнює, і робить це один раз.

Опційно в налаштуваннях репозиторію продукту (Settings → Secrets and variables → Actions):

| Що | Як увімкнути |
| --- | --- |
| ШІ-рев'ю PR | Секрет `ANTHROPIC_API_KEY` (окремий ключ із лімітом витрат) + змінна `ENABLE_AI_REVIEW` = `true` |
| DAST | Змінна `DAST_TARGET` = `https://staging.ваш-домен` (тільки ваш домен) |
| Скан Docker-образу | Розкоментуйте `image-ref` у `.github/workflows/security.yml` |

## Профілі

| Профіль | Додає |
| --- | --- |
| `web` | Semgrep `p/owasp-top-ten`; правила: платні API з фронтенду, секрети в `NEXT_PUBLIC_`/`VITE_`/`REACT_APP_`/`EXPO_PUBLIC_`, CORS `*` з credentials |
| `mobile` | Правила: токени в `UserDefaults`, вимкнений App Transport Security, cleartext HTTP в Android |
| `ai` | Правила: вивід LLM у `eval`/`exec`/shell, виклики LLM без `max_tokens`, токени Telegram-ботів у коді |

Базово для всіх: Semgrep `p/default` + `p/secrets`, gitleaks, OSV-Scanner, Trivy.

## Що блокує злиття

- gitleaks: будь-який знайдений секрет.
- Semgrep: знахідки рівня ERROR (WARNING лише у звіті).
- OSV-Scanner: вразливі залежності (виняток — `osv-scanner.toml` з причиною).
- Trivy: HIGH і CRITICAL у конфігураціях інфраструктури; CRITICAL з доступним виправленням в образі.

Тимчасово лише звітувати, не блокувати: `fail-on-findings: false` у `security.yml` продукту.

### Хибні спрацювання

| Сканер | Як додати виняток |
| --- | --- |
| gitleaks | fingerprint у `.gitleaksignore` + коментар, чому це не секрет |
| Semgrep | `# nosemgrep: <rule-id>` на рядку + пояснення, або шлях у `.semgrepignore` |
| OSV-Scanner | `[[IgnoredVulns]]` у `osv-scanner.toml` з `reason` і `ignoreUntil` |

## Вартість

| Що | Ціна |
| --- | --- |
| Усі сканери в CI | Безкоштовно (хвилини GitHub Actions: 2000 на місяць на приватних репо безкоштовного плану) |
| Dependabot | Безкоштовно |
| Захист гілки `main` на приватних репо | GitHub Pro (близько $4 на місяць) |
| Secret scanning / CodeQL на приватних репо | Не обов'язково: їх замінюють gitleaks і Semgrep. Платно $19 / $30 на розробника на місяць |
| ШІ-рев'ю PR | Оплата токенів Anthropic API за фактом |

## Як влаштовано всередині

- `.github/workflows/security-scan.yml` — спільні перевірки (reusable workflow). Власні правила Semgrep вбудовані сюди ж, тож працюють навіть із приватним репозиторієм стандарту.
- `.github/workflows/dast.yml` — OWASP ZAP проти задеплоєного сайту/API.
- `.github/workflows/ai-review.yml` — ШІ-рев'ю PR.
- `.github/workflows/self-test.yml` — самоперевірка стандарту: actionlint, тести правил, скан самого себе.
- `templates/project/` — файли, які копіюються в продукт.
- `templates/docs/` — шаблони документів.
- `scripts/` — встановлення, захист репозиторію, тести правил.
- `tests/rules/` — фікстури для правил (навмисно вразливий код; виключений із самоскану).

### Принципи безпеки самого стандарту

- **Усі сторонні GitHub Actions закріплені за повним SHA коміту.** Теги можна перезаписати: у березні 2026 так були скомпрометовані `trivy-action` і `setup-trivy`, і через них крали секрети з CI.
- **Сканери не отримують секретів:** кожен job має лише `contents: read`, `persist-credentials: false`.
- **Бінарники завантажуються з перевіркою SHA-256** (gitleaks, actionlint).
- **harden-runner у режимі audit** записує мережеву активність кожного job, щоб підозрілі з'єднання було видно.
- **ШІ-рев'ю лише для довірених PR:** за документацією Anthropic дія не захищена від prompt injection.

## Оновлення стандарту

- Продукти використовують `@main`, тому зміни тут одразу діють усюди. Перед злиттям у `main` має пройти `self-test`.
- Оновлення версій дій: Dependabot (`.github/dependabot.yml` цього репо) створює PR з новими SHA.
- Нове правило Semgrep: додати в `security-scan.yml` між маркерами `@@BASELINE_RULES_BEGIN/END@@`, додати фікстуру в `tests/rules/` з позначками `# ruleid:` / `# ok:`, потім запустити `python3 scripts/test-rules.py`.

## Локальна перевірка без CI

```bash
gitleaks git . --redact                      # секрети в історії
scripts/extract-rules.sh && semgrep scan --config p/default --config .cache/baseline-rules.yml .
osv-scanner scan --recursive .               # залежності
```

У Claude Code: `/security-review` перевіряє незакомічені зміни.
