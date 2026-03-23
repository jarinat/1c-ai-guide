# Настройка синхронизации GitHub → Google Drive

Этот документ описывает, как настроить одностороннюю синхронизацию содержимого
репозитория в личный Google Drive (My Drive) через GitHub Actions + rclone.

---

## Содержание

1. [Как работает синхронизация](#как-работает-синхронизация)
2. [Что синхронизируется, что исключено](#что-синхронизируется-что-исключено)
3. [Необходимые GitHub Secrets и Variables](#необходимые-github-secrets-и-variables)
4. [Шаг 1 — Подготовка rclone и OAuth-токена](#шаг-1--подготовка-rclone-и-oauth-токена)
5. [Шаг 2 — Создание GitHub Secrets](#шаг-2--создание-github-secrets)
6. [Шаг 3 — Первый запуск (dry-run)](#шаг-3--первый-запуск-dry-run)
7. [Шаг 4 — Переход в боевой режим](#шаг-4--переход-в-боевой-режим)
8. [Проверка корректности](#проверка-корректности)
9. [Риски и ограничения](#риски-и-ограничения)

---

## Как работает синхронизация

```
GitHub Actions (push → main)
        │
        ▼
rclone sync <workspace> <GDRIVE_DEST>
        │   --exclude-from .github/rclone-exclude.txt
        ▼
My Drive / <целевая папка>
```

- **Источник правды** — репозиторий GitHub (ветка `main`).
- **Цель** — папка в личном My Drive.
- **Режим** — `rclone sync`: добавляет новые файлы, обновляет изменённые,
  **удаляет лишние** из Drive (зеркалирование).
- **Направление** — строго одностороннее. Drive не влияет на репозиторий.

---

## Что синхронизируется, что исключено

### Синхронизируется (полезный контент)

| Путь | Описание |
|------|----------|
| `docs/` | Стандарты, плейбуки, шаблоны, индексы |
| `README.md` | Описание проекта |

### Исключено (инфраструктура репозитория)

Правила exclusions находятся в [`.github/rclone-exclude.txt`](rclone-exclude.txt).

| Паттерн | Причина исключения |
|---------|-------------------|
| `.git/**` | Git object store — внутренности VCS |
| `.gitignore` | Конфиг git, не нужен в Drive |
| `.gitkeep` | Технический placeholder-файл |
| `.github/**` | Workflows, этот файл настройки — CI/CD инфраструктура |
| `.githooks/**` | pre-commit хук (запускает check-version.ps1) — dev tooling |
| `.claude/**` | Настройки Claude Code — AI tooling |
| `.codex/**` | Настройки OpenAI Codex — AI tooling |
| `AGENTS.md` | Инструкции для AI-агентов — не контент правил |
| `CLAUDE.md` | Проектные инструкции для Claude — не контент правил |
| `scripts/**` | bump-version.ps1, check-version.ps1 — скрипты CI |
| `VERSION` | Технический артефакт версионирования |
| `.DS_Store`, `Thumbs.db` | OS-артефакты (защитное исключение) |
| `.idea/**`, `.vscode/**` | Конфиги IDE (защитное исключение) |
| `*.tmp`, `*.bak` | Временные файлы (защитное исключение) |

---

## Необходимые GitHub Secrets и Variables

### Secrets (Settings → Secrets and variables → Actions → Secrets)

| Имя | Обязателен | Описание |
|-----|-----------|----------|
| `RCLONE_CONF` | **Да** | base64-кодированный `rclone.conf` с OAuth-токеном Google Drive |
| `GDRIVE_DEST` | **Да** | Путь назначения, например `gdrive:1c-ai-guide` |

### Variables (Settings → Secrets and variables → Actions → Variables)

| Имя | По умолчанию | Описание |
|-----|-------------|----------|
| `DRY_RUN` | `false` | Установить `true` для тестовых прогонов при push |

> **Почему GDRIVE_DEST — Secret, а не Variable?**
> Путь в Drive раскрывает структуру вашего личного хранилища.
> Если это некритично — можете перенести в Variables.

---

## Шаг 1 — Подготовка rclone и OAuth-токена

### 1.1 Установить rclone локально

```bash
# macOS
brew install rclone

# Linux
curl https://rclone.org/install.sh | sudo bash

# Windows (PowerShell)
winget install Rclone.Rclone
```

### 1.2 Создать remote для Google Drive

```bash
rclone config
```

В интерактивном режиме:

1. Выберите `n` — New remote
2. Имя: `gdrive` (или любое другое, запомните)
3. Storage type: `drive` (Google Drive)
4. `client_id` и `client_secret` — оставьте пустыми (используется встроенный)
5. scope: `1` — Full access all files
6. root_folder_id: оставьте пустым
7. service_account_file: оставьте пустым
8. Edit advanced config: `n`
9. Use auto config: `y` — откроется браузер, авторизуйтесь в личном аккаунте
10. Configure this as a Shared Drive (Team Drive): `n` (у вас My Drive)
11. Confirm: `y`

### 1.3 Проверить доступ

```bash
rclone lsd gdrive:
```

Вы должны увидеть список папок в корне My Drive.

### 1.4 Создать целевую папку (если не существует)

```bash
rclone mkdir gdrive:1c-ai-guide
```

Замените `1c-ai-guide` на желаемое имя папки.

### 1.5 Экспортировать конфиг

```bash
# Путь к конфигу
rclone config file
# Обычно: ~/.config/rclone/rclone.conf (Linux/macOS)
#          %APPDATA%\rclone\rclone.conf (Windows)
```

### 1.6 Закодировать конфиг в base64

```bash
# Linux / macOS
base64 -w 0 ~/.config/rclone/rclone.conf

# Windows (PowerShell)
[Convert]::ToBase64String([IO.File]::ReadAllBytes("$env:APPDATA\rclone\rclone.conf"))
```

Скопируйте вывод — это значение для секрета `RCLONE_CONF`.

> **Важно:** `rclone.conf` содержит OAuth refresh token.
> Храните его только в GitHub Secrets. Никогда не коммитьте в репозиторий.

---

## Шаг 2 — Создание GitHub Secrets

1. Откройте репозиторий на GitHub
2. **Settings → Secrets and variables → Actions → New repository secret**

Создайте два секрета:

**`RCLONE_CONF`**
```
<вывод base64 из шага 1.6>
```

**`GDRIVE_DEST`**
```
gdrive:1c-ai-guide
```

Формат: `<имя_remote>:<путь_в_Drive>`
- Имя remote должно совпадать с тем, что вы указали в `rclone config` (шаг 1.2).
- Путь — относительно корня My Drive. Вложенные папки: `gdrive:Docs/1c-ai-guide`.

---

## Шаг 3 — Первый запуск (dry-run)

Перед первым боевым запуском убедитесь, что всё работает правильно.

### Вариант A — через workflow_dispatch

1. GitHub → Actions → **Sync to Google Drive**
2. **Run workflow** → установите `dry_run = true` → **Run workflow**
3. Откройте запуск и изучите логи:
   - Должны быть видны файлы, которые будут скопированы
   - Никаких реальных изменений в Drive не происходит
   - В секции **Sync to Google Drive** workflow summary — проверьте список

### Вариант B — через переменную репозитория

1. **Settings → Secrets and variables → Actions → Variables → New variable**
2. Имя: `DRY_RUN`, значение: `true`
3. Сделайте любой push в `main` — сработает автоматически в dry-run режиме

### Что проверить в логах dry-run

```
# Файл должен быть в списке:
INFO  : docs/01-standards/bsp/index.md: Would copy

# Служебные файлы НЕ должны появляться:
# .github/**, .git/**, scripts/**, CLAUDE.md, AGENTS.md, VERSION
```

---

## Шаг 4 — Переход в боевой режим

### Убрать dry-run при push

1. Если установлена переменная `DRY_RUN=true` — удалите её или установите `false`
2. Следующий push в `main` запустит реальную синхронизацию

### Разовый боевой запуск через workflow_dispatch

1. Actions → **Sync to Google Drive** → **Run workflow**
2. `dry_run = false` → **Run workflow**

---

## Проверка корректности

### Проверить, что служебные файлы не попали в Drive

```bash
# Локально
rclone ls gdrive:1c-ai-guide | grep -E "\.(git|github|githooks|claude|codex)"
# Вывод должен быть пустым

rclone ls gdrive:1c-ai-guide | grep -E "CLAUDE\.md|AGENTS\.md|VERSION"
# Вывод должен быть пустым
```

### Проверить, что удаление работает

1. Удалите файл из репозитория, сделайте commit и push в `main`
2. После завершения workflow проверьте, что файл исчез из Drive:
   ```bash
   rclone ls gdrive:1c-ai-guide/<путь_к_файлу>
   ```

### Проверить содержимое Drive

```bash
# Список всех файлов в целевой папке
rclone ls gdrive:1c-ai-guide

# Дерево папок
rclone lsd gdrive:1c-ai-guide --recursive
```

---

## Риски и ограничения

| Риск | Описание | Митигация |
|------|----------|-----------|
| **Случайное удаление** | `rclone sync` удаляет файлы в Drive, которых нет в репозитории | Делайте dry-run перед первым запуском; проверяйте exclude-правила |
| **Ручные изменения в Drive** | Файлы, изменённые вручную в Drive, будут перезаписаны при следующем sync | Drive — не источник правды; не редактируйте там |
| **Протухший OAuth токен** | Refresh token Google может истечь или быть отозван | Повторите шаги 1.2–1.6 и обновите секрет `RCLONE_CONF` |
| **Rate limits Google API** | При большом количестве файлов Google может throttle запросы | rclone автоматически делает retry; при проблемах уменьшите `--transfers` |
| **Секрет RCLONE_CONF** | Содержит OAuth refresh token — полный доступ к Drive | Используйте только GitHub Secrets; периодически ротируйте токен |
| **Расширение exclude-правил** | Слишком агрессивные правила могут исключить нужный контент | После изменений в `.github/rclone-exclude.txt` делайте dry-run |

### Что НЕ поддерживается

- **Двусторонняя синхронизация** — намеренно. Drive только получает данные.
- **Shared Drive** — используется только My Drive.
- **Google Drive for desktop** — не требуется, всё через API.
- **Инкрементальная синхронизация по diff** — rclone сравнивает размер/время файлов,
  не git diff. Это нормально и эффективно.

---

## Быстрый чеклист

- [ ] rclone установлен локально
- [ ] rclone remote настроен (`rclone lsd gdrive:` работает)
- [ ] Целевая папка создана в Drive
- [ ] Секрет `RCLONE_CONF` добавлен в репозиторий
- [ ] Секрет `GDRIVE_DEST` добавлен в репозиторий
- [ ] Первый dry-run прошёл успешно
- [ ] В логах dry-run нет служебных файлов
- [ ] `DRY_RUN` переменная удалена или выставлена в `false`
- [ ] Первый боевой запуск завершён
- [ ] Содержимое Drive проверено локально через `rclone ls`
