# nginx-3x-ui-subscription-proxy

Это форк проекта [apa4h/nginx-3x-ui-subscription-proxy](https://github.com/apa4h/nginx-3x-ui-subscription-proxy) со следующими улучшениями:

- Добавлена поддержка агрегации статистики подписок (upload, download, total, expire)
- Добавлена поддержка заголовков Profile-Title и Profile-Update-Interval
- Исправление ошибки luarocks «main function has more than 65536 constants» путём клонирования репозитория и ручного перемещения файлов
  
## Обработка заголовков

Прокси обрабатывает и агрегирует следующие заголовки от серверов 3x-UI:

### Subscription-Userinfo
Агрегирует статистику со всех серверов:
- `upload`: Сумма загруженного трафика со всех серверов
- `download`: Сумма скачанного трафика со всех серверов
- `total`: Минимальная квота из всех серверов (чтобы клиент не превысил лимит ни на одном сервере)
- `expire`: Минимальное время истечения из всех серверов (чтобы клиент не использовал истекшую подписку)

### Заголовки профиля
Берет первое доступное значение от серверов:
- `Profile-Title`: Название профиля от первого сервера, который его предоставляет
- `Profile-Update-Interval`: Интервал обновления от первого сервера, который его предоставляет

Конфигурация обратного прокси-сервера Nginx для объединения подписок с нескольких серверов [3x-UI](https://github.com/MHSanaei/3x-ui?tab=readme-ov-file) в одну.

### Схема работы

[![Схема работы](https://i.postimg.cc/pX59gV8h/temp-Image1-Z8b-SK.avif)](https://postimg.cc/8jDPvSZN)

## Описание

Этот проект позволяет настроить Nginx в качестве обратного прокси, который получает и агрегирует подписки с нескольких серверов 3x-UI. Это упрощает использование, например когда у вас несколько серверов в разных гео, будет только одна точка входа.

## Важные замечания

1. У каждого клиента должен быть одинаковый **subscription ID** на всех ваших серверах 3x-UI.
2. Шифрование подписки должно быть включено на всех серверах 3x-UI.

## Инструкция по установке

### 1. Клонирование репозитория

```bash
git clone https://github.com/apa4h/nginx-3x-ui-subscription-proxy.git
cd nginx-3x-ui-subscription-proxy
```

>### 2. Копирование файла конфигурации окружения

>```bash
>cp .env.template .env
>```
> *Этот шаг можно пропустить*

### 3. Настройка переменных окружения

Откройте файл `.env` и укажите в нём следующие параметры:

| Переменная     | Описание                                                                                                                                                       |
| -------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `TLS_MODE`     | Включает или отключает SSL. По умолчанию `off`. Если `on`, необходимо сгенерировать SSL-сертификаты (например, через Certbot) и указать пути в `PATH_SSL_KEY`. |
| `PATH_SSL_KEY` | Путь к директории, содержащей SSL-сертификаты и приватный ключ (например, `/etc/letsencrypt/live/your_site/`).                                                 |
| `SITE_HOST`    | Доменное имя для вашего сервера Nginx (например, `subserver.example`).                                                                                         |
| `SITE_PORT`    | Порт, на котором Nginx будет принимать запросы (например, `443`).                                                                                              |
| `SERVERS`      | Список URL серверов 3x-UI, с которых будут агрегироваться подписки (например, `https://server1.com/sub/ https://server2.com/sub/`).                            |
| `SUB`          | Статическая часть пути подписки для прокси сервера (например, `sub`).                                                                                                             |

#### Формат ссылки подписки

После настройки переменных окружения ваша ссылка на подписку будет выглядеть так:

```sh
https://subserver.example/sub/subscription_ID
```

Где:

- `subserver.example` — домен, указанный в переменной `SITE_HOST`.
- `sub` — статическая часть пути подписки, заданная в `SUB`.
- `subscription_ID` — уникальный идентификатор подписки клиента в 3x-UI.

### 4. Запуск

Запустите приложение командой:

```bash
docker compose up -d
```

Это создаст и запустит контейнер Nginx с нужной конфигурацией.

## Как это работает

- Прокси получает конфигурации подписок с серверов, перечисленных в `SERVERS`, объединяет и отдает клиенту все одной зашифрованной подпиской.
- Слушает запросы на домене и порте, указанном в `SITE_HOST` и `SITE_PORT`.
- Если `TLS_MODE=on`, то используются SSL-сертификаты, хранящиеся в `PATH_SSL_KEY`.

## Пример файла конфигурации

Пример файла `.env`:

```dotenv
PATH_SSL_KEY=/etc/letsencrypt/live/example.com/
SITE_HOST=example.com
SITE_PORT=443
SERVERS="https://server1.com/sub/ https://server2.com/sub/"
SUB=sub
TLS_MODE=off
```

## Лицензия

Этот проект распространяется под лицензией MIT. Подробности в файле `LICENSE`.

## Внесение изменений

Приветствуются любые улучшения! Открывайте issue или отправляйте pull request.
