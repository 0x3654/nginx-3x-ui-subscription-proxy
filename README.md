# nginx-3x-ui-subscription-proxy

**Languages:** [English](#english) | [Русский](#русский)

---

# English

> This is a fork of [apa4h/nginx-3x-ui-subscription-proxy](https://github.com/apa4h/nginx-3x-ui-subscription-proxy) with the following improvements:
>
> - Added support for subscription statistics aggregation (upload, download, total, expire)
> - Added support for Profile-Title, Profile-Update-Interval, Announce, Support-Url and Profile-Web-Page-Url headers
> - Per-server request timeout (2 s, `FETCH_TIMEOUT_MS`): a hung or dead upstream no longer stalls the client — the proxy answers with the remaining configs
> - All upstreams are fetched in parallel — total latency is the slowest server, not the sum of all
> - A subscription missing on one server (3x-ui returns 400 on v3.0, 404 since v3.4) is a warning, not an error
> - Upstream TLS verification on by default (`VERIFY_UPSTREAM_TLS=off` to restore the old behaviour)
> - Warn-level logs on stderr (`error_log /dev/stderr warn`), `/healthz` endpoint, docker-based smoke test suite (`tests/run.sh`)
> - Fixed expire=0 handling (treats as unlimited)
> - Uses local DNS resolver instead of hardcoded Docker DNS

A reverse proxy configuration for Nginx to dynamically handle and aggregate [3x-UI](https://github.com/MHSanaei/3x-ui) subscriptions from multiple servers.

### Flow
[![Flow](https://i.postimg.cc/pX59gV8h/temp-Image1-Z8b-SK.avif)](https://postimg.cc/8jDPvSZN)

## Overview

This project allows you to set up an Nginx-based reverse proxy that fetches and aggregates subscription configurations from multiple 3x-UI servers. It simplifies subscription management by unifying configurations in a single endpoint.

## Header Processing

The proxy processes and aggregates the following headers from 3x-UI servers:

### Subscription-Userinfo
Aggregates statistics from all servers:
- `upload`: Sum of upload traffic from all servers
- `download`: Sum of download traffic from all servers
- `total`: Minimum total quota from all servers (to ensure the client doesn't exceed any server's limit)
- `expire`: Minimum expiration time from all servers (treats `0` as unlimited)

### Profile Headers
Takes the first available value from servers:
- `Profile-Title`: Profile name from the first server that provides it
- `Profile-Update-Interval`: Update interval from the first server that provides it
- `Announce`: announcement text (base64-prefixed, as sent by 3x-ui; recognized by Happ and v2raytun)
- `Support-Url` / `Profile-Web-Page-Url`: support link and profile web page, shown by clients as buttons

### Resilience
- Upstreams are fetched in parallel, each capped at `FETCH_TIMEOUT_MS` (2 s by default); a timeout or error on one server never blocks the others.
- Unknown sub id on an upstream (400/404) is logged as a warning and skipped — the merge continues.
- Any other unexpected upstream status is logged as a warning too; the proxy returns `502` only when no server yielded a config.

## Important Notes

1. Each client must have the same **subscription ID** across all your servers.
2. Subscription encryption must be enabled on all 3x-UI servers.

## Quick Start

### Using the published image (Recommended)

```bash
git clone https://github.com/0x3654/nginx-3x-ui-subscription-proxy.git
cd nginx-3x-ui-subscription-proxy
cp .env.template .env
# Edit .env with your configuration
docker compose up -d
```

### Building from Source

```bash
git clone https://github.com/0x3654/nginx-3x-ui-subscription-proxy.git
cd nginx-3x-ui-subscription-proxy
cp .env.template .env
# Edit .env with your configuration
docker compose build
docker compose up -d
```

### For Developers

If you want to modify the source code or contribute:

**Project Structure:**
```
.
├── src/
│   ├── Dockerfile           # Production Dockerfile
│   ├── nginx.conf.esh       # Nginx configuration template
│   └── config_fetcher.lua  # Lua script for subscription aggregation
├── .github/workflows/
│   └── build.yml           # GitHub Actions for auto-build
├── docker-compose.yml      # Uses the ghcr.io image
└── README.md               # This file
```

**Local Development:**
```bash
# Clone repository
git clone https://github.com/0x3654/nginx-3x-ui-subscription-proxy.git
cd nginx-3x-ui-subscription-proxy

# Build image locally from source
docker build -t nginx-3x-ui-proxy:dev -f src/Dockerfile .

# Run with local build
IMAGE_NAME=nginx-3x-ui-proxy:dev docker compose up -d

# Or override image in docker-compose.yml:
# image: nginx-3x-ui-proxy:dev
```

**GitHub Actions:**
- Automatically builds and pushes to `ghcr.io/0x3654/nginx-3x-ui-subscription-proxy` on push to `main`
- Supports version tags (e.g., `v1.0.0`)
- Multi-arch support (amd64, arm64)

## Configuration

Edit the `.env` file and fill in the following variables:

| Variable | Description |
|----------|-------------|
| `TLS_MODE` | Enables or disables SSL. Default: `off`. When `on`, SSL certificates must be generated (e.g., via Certbot), and their paths must be specified in `PATH_SSL_KEY`. |
| `PATH_SSL_KEY` | Path to the directory containing your SSL certificate and private key (e.g., `/etc/letsencrypt/live/your_site/`). |
| `SITE_HOST` | Domain name for your Nginx server (e.g., `subserver.example`). |
| `SITE_PORT` | Port number where Nginx will listen for requests (e.g., `443`). |
| `SERVERS` | List of 3x-UI server URLs to aggregate subscriptions from (e.g., `https://server1.com/sub/ https://server2.com/sub/`). |
| `SUB` | Static part of the subscription path (e.g., `sub`). |
| `FETCH_TIMEOUT_MS` | Per-upstream request budget (connect+send+read), milliseconds. Default: `2000`. |
| `VERIFY_UPSTREAM_TLS` | Verify upstream TLS certificates. Default: `on`; set `off` for self-signed certs. |

### Subscription URL Format

Once configured, your subscription URL will look like:
```
https://subserver.example/sub/subscription_ID
```

Where:
- `subserver.example` is the domain from `SITE_HOST`
- `sub` is the static part from `SUB`
- `subscription_ID` is the unique client ID from 3x-ui

## Example Configuration

```dotenv
PATH_SSL_KEY=/etc/letsencrypt/live/example.com/
SITE_HOST=example.com
SITE_PORT=443
SERVERS="https://server1.com/sub/ https://server2.com/sub/"
SUB=sub
TLS_MODE=off
```

## SSL Certificate Setup (Manual Installation)

> **Note:** Certbot runs on your **host system**, not inside the Docker container. The container only mounts the generated certificates.

If `TLS_MODE=on`, you need to generate SSL certificates using Certbot.

### Prerequisites
- Domain name (e.g., `sub.example.com`) pointing to your server
- Port 80 open on your firewall (required by Certbot standalone)
- Certbot installed on your **host system** (not in container)
- Docker container stopped during certificate generation (port 80 must be free)

### Generate Certificate

1. **Stop the container if running:**
   ```bash
   docker compose down
   ```

2. **Generate certificate with Certbot (on host system):**
   ```bash
   sudo certbot certonly --standalone -d sub.example.com
   ```

   This will create certificates in:
   ```
   /etc/letsencrypt/live/sub.example.com/
   ├── fullchain.pem
   └── privkey.pem
   ```

3. **Update `.env` file:**
   ```dotenv
   TLS_MODE=on
   SITE_PORT=443
   PATH_SSL_KEY=/etc/letsencrypt/live/sub.example.com
   ```

4. **Update docker-compose.yml volumes:**
   ```yaml
   volumes:
     - /etc/letsencrypt/live/sub.example.com/fullchain.pem:/etc/nginx/ssl/fullchain.pem:ro
     - /etc/letsencrypt/live/sub.example.com/privkey.pem:/etc/nginx/ssl/privkey.pem:ro
   ```

5. **Start the container:**
   ```bash
   docker compose up -d
   ```

### Certificate Auto-Renewal

Certbot automatically renews certificates. To apply renewed certificates, restart the container:

```bash
# Add to crontab for weekly check (full path required)
0 3 * * * cd /path/to/nginx-3x-ui-subscription-proxy && docker compose restart nginx_proxy_sub
```

**Important:** Replace `/path/to/nginx-3x-ui-subscription-proxy` with actual path to your project directory.

Alternatively, use Certbot's built-in renewal hooks with docker-compose restart command.

## How It Works

- The proxy dynamically fetches subscription configurations from servers listed in `SERVERS`
- It listens on the domain and port specified in `SITE_HOST` and `SITE_PORT`
- SSL certificates are loaded from the path specified in `PATH_SSL_KEY`

## License

This project is licensed under the MIT License. See the `LICENSE` file for details.

## Contributing

Contributions are welcome! Feel free to open an issue or submit a pull request.

---

# Русский

> Это форк проекта [apa4h/nginx-3x-ui-subscription-proxy](https://github.com/apa4h/nginx-3x-ui-subscription-proxy) со следующими улучшениями:
>
> - Добавлена поддержка агрегации статистики подписок (upload, download, total, expire)
> - Добавлена поддержка заголовков Profile-Title, Profile-Update-Interval, Announce, Support-Url и Profile-Web-Page-Url
> - Таймаут 2 с на запрос к апстриму (`FETCH_TIMEOUT_MS`): зависший или мёртвый сервер больше не валит клиента — прокси отвечает оставшимися конфигами
> - Апстримы опрашиваются параллельно — итоговая задержка равна самому медленному, а не сумме всех
> - Отсутствие подписки на одном из серверов (3x-ui отдаёт 400 на v3.0, 404 начиная с v3.4) — предупреждение, а не ошибка
> - Проверка TLS-сертификатов апстримов включена по умолчанию (`VERIFY_UPSTREAM_TLS=off` для самоподписанных)
> - WARN-логи в stderr (`error_log /dev/stderr warn`), эндпоинт `/healthz`, docker-тестсьют (`tests/run.sh`)
> - Исправлена обработка expire=0 (трактуется как unlimited)
> - Используется локальный DNS резолвер вместо хардкода Docker DNS

Конфигурация обратного прокси-сервера Nginx для объединения подписок с нескольких серверов [3x-UI](https://github.com/MHSanaei/3x-ui) в одну.

### Схема работы

[![Схема работы](https://i.postimg.cc/pX59gV8h/temp-Image1-Z8b-SK.avif)](https://postimg.cc/8jDPvSZN)

## Описание

Этот проект позволяет настроить Nginx в качестве обратного прокси, который получает и агрегирует подписки с нескольких серверов 3x-UI. Это упрощает использование, например когда у вас несколько серверов в разных гео — будет только одна точка входа.

## Обработка заголовков

Прокси обрабатывает и агрегирует следующие заголовки от серверов 3x-UI:

### Subscription-Userinfo
Агрегирует статистику со всех серверов:
- `upload`: Сумма загруженного трафика со всех серверов
- `download`: Сумма скачанного трафика со всех серверов
- `total`: Минимальная квота из всех серверов (чтобы клиент не превысил лимит ни на одном сервере)
- `expire`: Минимальное время истечения из всех серверов (`0` означает unlimited)

### Заголовки профиля
Берет первое доступное значение от серверов:
- `Profile-Title`: Название профиля от первого сервера, который его предоставляет
- `Profile-Update-Interval`: Интервал обновления от первого сервера, который его предоставляет
- `Announce`: текст анонса (в base64-префиксом, как шлёт 3x-ui; понимают Happ и v2raytun)
- `Support-Url` / `Profile-Web-Page-Url`: ссылка поддержки и веб-страница профиля, клиенты показывают их кнопками

### Отказоустойчивость
- Апстримы опрашиваются параллельно, у каждого бюджет `FETCH_TIMEOUT_MS` (по умолчанию 2 с); таймаут или ошибка одного сервера не блокирует остальные.
- Неизвестный sub id на апстриме (400/404) — warning в лог, мердж продолжается.
- Прочие неожиданные статусы апстрима тоже логируются warning'ом; `502` возвращается только если ни один сервер не отдал конфиг.

## Важные замечания

1. У каждого клиента должен быть одинаковый **subscription ID** на всех ваших серверах 3x-UI.
2. Шифрование подписки должно быть включено на всех серверах 3x-UI.

## Быстрый старт

### Использование готового образа (Рекомендуется)

```bash
git clone https://github.com/0x3654/nginx-3x-ui-subscription-proxy.git
cd nginx-3x-ui-subscription-proxy
cp .env.template .env
# Отредактируйте .env с вашей конфигурацией
docker compose up -d
```

### Сборка из исходников

```bash
git clone https://github.com/0x3654/nginx-3x-ui-subscription-proxy.git
cd nginx-3x-ui-subscription-proxy
cp .env.template .env
# Отредактируйте .env с вашей конфигурацией
docker compose build
docker compose up -d
```

### Для разработчиков

Если вы хотите модифицировать исходный код или внести вклад:

**Структура проекта:**
```
.
├── src/
│   ├── Dockerfile           # Production Dockerfile
│   ├── nginx.conf.esh       # Шаблон конфигурации Nginx
│   └── config_fetcher.lua  # Lua скрипт для агрегации подписок
├── .github/workflows/
│   └── build.yml           # GitHub Actions для авто-сборки
├── docker-compose.yml      # Использует образ с ghcr.io
└── README.md               # Этот файл
```

**Локальная разработка:**
```bash
# Клонировать репозиторий
git clone https://github.com/0x3654/nginx-3x-ui-subscription-proxy.git
cd nginx-3x-ui-subscription-proxy

# Собрать образ локально из исходников
docker build -t nginx-3x-ui-proxy:dev -f src/Dockerfile .

# Запустить с локальной сборкой
IMAGE_NAME=nginx-3x-ui-proxy:dev docker compose up -d

# Или переопределить image в docker-compose.yml:
# image: nginx-3x-ui-proxy:dev
```

**GitHub Actions:**
- Автоматически собирает и публикует в `ghcr.io/0x3654/nginx-3x-ui-subscription-proxy` при push в `main`
- Поддерживает version теги (например, `v1.0.0`)
- Multi-архитектурная поддержка (amd64, arm64)

## Настройка

Откройте файл `.env` и укажите в нём следующие параметры:

| Переменная | Описание |
|------------|-----------|
| `TLS_MODE` | Включает или отключает SSL. По умолчанию `off`. Если `on`, необходимо сгенерировать SSL-сертификаты (например, через Certbot) и указать пути в `PATH_SSL_KEY`. |
| `PATH_SSL_KEY` | Путь к директории, содержащей SSL-сертификаты и приватный ключ (например, `/etc/letsencrypt/live/your_site/`). |
| `SITE_HOST` | Доменное имя для вашего сервера Nginx (например, `subserver.example`). |
| `SITE_PORT` | Порт, на котором Nginx будет принимать запросы (например, `443`). |
| `SERVERS` | Список URL серверов 3x-UI, с которых будут агрегироваться подписки (например, `https://server1.com/sub/ https://server2.com/sub/`). |
| `SUB` | Статическая часть пути подписки для прокси сервера (например, `sub`). |
| `FETCH_TIMEOUT_MS` | Бюджет на запрос к апстриму (connect+send+read), мс. По умолчанию: `2000`. |
| `VERIFY_UPSTREAM_TLS` | Проверять TLS-сертификаты апстримов. По умолчанию: `on`; `off` для самоподписанных. |

### Формат ссылки подписки

После настройки переменных окружения ваша ссылка на подписку будет выглядеть так:

```sh
https://subserver.example/sub/subscription_ID
```

Где:
- `subserver.example` — домен, указанный в переменной `SITE_HOST`.
- `sub` — статическая часть пути подписки, заданная в `SUB`.
- `subscription_ID` — уникальный идентификатор подписки клиента в 3x-UI.

## Пример конфигурации

```dotenv
PATH_SSL_KEY=/etc/letsencrypt/live/example.com/
SITE_HOST=example.com
SITE_PORT=443
SERVERS="https://server1.com/sub/ https://server2.com/sub/"
SUB=sub
TLS_MODE=off
```

## Настройка SSL сертификата (Ручная установка)

> **Примечание:** Certbot запускается на вашей **хост-системе**, не внутри Docker контейнера. Контейнер только монтирует сгенерированные сертификаты.

Если `TLS_MODE=on`, вам нужно сгенерировать SSL сертификаты с помощью Certbot.

### Требования
- Доменное имя (например, `sub.example.com`) направленное на ваш сервер
- Временно открытый порт 80 в вашем фаерволе (требуется для Certbot standalone)
- Установленный Certbot на вашей **хост-системе** (не в контейнере)
- Docker контейнер остановлен во время генерации сертификата (порт 80 должен быть свободен)

### Генерация сертификата

1. **Остановите контейнер если запущен:**
   ```bash
   docker compose down
   ```

2. **Сгенерируйте сертификат с помощью Certbot (на хост-системе):**
   ```bash
   sudo certbot certonly --standalone -d sub.example.com
   ```

   Это создаст сертификаты в директории:
   ```
   /etc/letsencrypt/live/sub.example.com/
   ├── fullchain.pem
   └── privkey.pem
   ```

3. **Обновите файл `.env`:**
   ```dotenv
   TLS_MODE=on
   SITE_PORT=443
   PATH_SSL_KEY=/etc/letsencrypt/live/sub.example.com
   ```

4. **Обновите volumes в docker-compose.yml:**
   ```yaml
   volumes:
     - /etc/letsencrypt/live/sub.example.com/fullchain.pem:/etc/nginx/ssl/fullchain.pem:ro
     - /etc/letsencrypt/live/sub.example.com/privkey.pem:/etc/nginx/ssl/privkey.pem:ro
   ```

5. **Запустите контейнер:**
   ```bash
   docker compose up -d
   ```

### Автоматическое обновление сертификатов

Certbot автоматически обновляет сертификаты. Чтобы применить обновлённые сертификаты, перезапустите контейнер:

```bash
# Добавьте в crontab для еженедельной проверки (требуется полный путь)
0 3 * * * cd /path/to/nginx-3x-ui-subscription-proxy && docker compose restart nginx_proxy_sub
```

**Важно:** Замените `/path/to/nginx-3x-ui-subscription-proxy` на фактический путь к вашей директории проекта.

Или используйте встроенные хуки обновления Certbot с командой docker-compose restart.

## Как это работает

- Прокси получает конфигурации подписок с серверов, перечисленных в `SERVERS`, объединяет и отдает клиенту все одной зашифрованной подпиской.
- Слушает запросы на домене и порте, указанном в `SITE_HOST` и `SITE_PORT`.
- Если `TLS_MODE=on`, то используются SSL-сертификаты, хранящиеся в `PATH_SSL_KEY`.

## Лицензия

Этот проект распространяется под лицензией MIT. Подробности в файле `LICENSE`.

## Внесение изменений

Приветствуются любые улучшения! Открывайте issue или отправляйте pull request.
