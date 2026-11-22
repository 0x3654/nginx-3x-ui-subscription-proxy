# syntax=docker/dockerfile:1
# Пин минорного тега базового образа (multi-arch manifest).
# Slim-вариант: fat тащит gcc/make/perl для сборки модулей, которые нам не
# нужны (lua-resty-http — чистый Lua, копируется файлами) и распаковывается
# в ~488 МБ против ~190 МБ у slim. Ядро 1.31.1 -> 1.31.8 закрывает 12 nginx-CVE
# 2026 года (ноябрьская пачка F5 в их числе):
#   1.31.2: CVE-2026-42530 (HTTP/3 use-after-free), CVE-2026-42055 (HTTP/2/gRPC
#           upstream buffer overflow), CVE-2026-48142 (charset overread)
#   1.31.3: CVE-2026-42533 (map+regex overflow), CVE-2026-60005 (slice/cache
#           memory disclosure), CVE-2026-56434 (SSI use-after-free)
#   1.31.6: CVE-2026-90439 (HTTP/3 heap overflow c OpenSSL)
#   1.31.7: CVE-2026-15176 (alias+rewrite), CVE-2026-93479 (variable eval),
#           CVE-2026-95101 (HTTP/3 body injection), CVE-2026-97629 (TLS session
#           ticket forgery), CVE-2026-97205 (AIO/SSI use-after-free)
# Плюс OpenSSL 3.5.6 -> 3.5.9 и PCRE2 10.47 -> 10.49.
ARG OPENRESTY_TAG=1.31.8.1-0-alpine

# --- Стадия 1: lint-гейт — синтаксическая проверка lua (фейл = фейл сборки) ---
FROM openresty/openresty:${OPENRESTY_TAG} AS lint
RUN apk add --no-cache luajit
COPY src/config_fetcher.lua /tmp/config_fetcher.lua
RUN luajit -bl /tmp/config_fetcher.lua >/dev/null

# --- Стадия 2: зависимости (git не попадает в финальный образ) ---
FROM openresty/openresty:${OPENRESTY_TAG} AS deps
RUN apk add --no-cache git \
    && git clone --branch v0.18.0 --depth 1 https://github.com/ledgetech/lua-resty-http.git /tmp/lrh \
    && mkdir -p /out/resty \
    && cp /tmp/lrh/lib/resty/*.lua /out/resty/

# --- Финальный образ ---
FROM openresty/openresty:${OPENRESTY_TAG}
ARG GIT_REV=unknown
LABEL org.opencontainers.image.title="nginx-3x-ui-subscription-proxy" \
      org.opencontainers.image.description="Nginx/OpenResty proxy that merges 3x-ui subscriptions from multiple servers into one endpoint" \
      org.opencontainers.image.source="https://github.com/0x3654/nginx-3x-ui-subscription-proxy" \
      org.opencontainers.image.revision="${GIT_REV}" \
      org.opencontainers.image.licenses="MIT"

ARG SITE_PORT=443
ARG SERVERS

# Рантайм-конфигурация (esh рендерит nginx.conf при старте)
ENV SITE_HOST=localhost \
    SITE_PORT=${SITE_PORT} \
    SERVERS=${SERVERS} \
    SUB=sub \
    TLS_MODE=off \
    FETCH_TIMEOUT_MS=2000 \
    VERIFY_UPSTREAM_TLS=on

EXPOSE ${SITE_PORT}/tcp

RUN apk add --no-cache esh tini su-exec ca-certificates

# lua-resty-http из deps-стадии
COPY --from=deps /out/resty/ /usr/local/share/lua/5.1/resty/

# Конфигурация Nginx и lua-обработчик
RUN rm /usr/local/openresty/nginx/conf/nginx.conf
COPY src/nginx.conf.esh /usr/local/openresty/nginx/conf/
COPY src/config_fetcher.lua /etc/nginx/lua/

# pid и temp-файлы nginx — в /tmp, чтобы работала непривилегированная ветка
RUN sed -i 's|^worker_processes 1;|worker_processes 1;\npid /tmp/nginx.pid;|' /usr/local/openresty/nginx/conf/nginx.conf.esh \
    && sed -i 's|^http {|http {\n    client_body_temp_path /tmp/client_body;\n    proxy_temp_path /tmp/proxy;\n    fastcgi_temp_path /tmp/fastcgi;\n    uwsgi_temp_path /tmp/uwsgi;\n    scgi_temp_path /tmp/scgi;\n|' /usr/local/openresty/nginx/conf/nginx.conf.esh \
    && chmod -R 755 /usr/local/openresty/nginx/conf/ /etc/nginx/lua/ \
    && chown -R 65534:65534 /usr/local/openresty/nginx/conf /etc/nginx/lua

# tini как PID 1 (reaping зомби, корректные сигналы).
# TLS-режиму master-процессу нужен root для чтения ключей (workers nginx
# сбрасывает сам); plain HTTP стартует целиком от 65534 через su-exec.
ENTRYPOINT ["/sbin/tini", "--"]
CMD ["/bin/sh", "-c", "esh -o /usr/local/openresty/nginx/conf/nginx.conf /usr/local/openresty/nginx/conf/nginx.conf.esh && if [ \"$TLS_MODE\" = \"off\" ]; then chmod 666 /proc/self/fd/1 /proc/self/fd/2; exec su-exec 65534:65534 nginx -g 'daemon off;'; else exec nginx -g 'daemon off;'; fi"]

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget -q -O /dev/null "http://127.0.0.1:${SITE_PORT}/healthz" \
        || wget --no-check-certificate -q -O /dev/null "https://127.0.0.1:${SITE_PORT}/healthz" \
        || exit 1
