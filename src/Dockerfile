# syntax=docker/dockerfile:1
# Пин минорного тега базового образа (multi-arch manifest)
ARG OPENRESTY_TAG=1.31.1.1-3-alpine-fat

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

RUN apk add --no-cache esh tini

# lua-resty-http из deps-стадии
COPY --from=deps /out/resty/ /usr/local/share/lua/5.1/resty/

# Конфигурация Nginx и lua-обработчик
RUN rm /usr/local/openresty/nginx/conf/nginx.conf
COPY src/nginx.conf.esh /usr/local/openresty/nginx/conf/
COPY src/config_fetcher.lua /etc/nginx/lua/

# nginx работает целиком от непривилегированного пользователя: pid и temp-файлы
# в /tmp, порты >=1024 (SITE_PORT<1024 требует запуска с cap_net_bind_service)
RUN sed -i 's|^worker_processes 1;|worker_processes 1;\npid /tmp/nginx.pid;|' /usr/local/openresty/nginx/conf/nginx.conf.esh \
    && sed -i 's|^http {|http {\n    client_body_temp_path /tmp/client_body;\n    proxy_temp_path /tmp/proxy;\n    fastcgi_temp_path /tmp/fastcgi;\n    uwsgi_temp_path /tmp/uwsgi;\n    scgi_temp_path /tmp/scgi;\n|' /usr/local/openresty/nginx/conf/nginx.conf.esh \
    && chmod -R 755 /usr/local/openresty/nginx/conf/ /etc/nginx/lua/ \
    && chown -R 65534:65534 /usr/local/openresty/nginx/conf /etc/nginx/lua
USER 65534

# tini как PID 1 (reaping зомби, корректные сигналы)
ENTRYPOINT ["/sbin/tini", "--"]
CMD ["/bin/sh", "-c", "esh -o /usr/local/openresty/nginx/conf/nginx.conf /usr/local/openresty/nginx/conf/nginx.conf.esh && exec nginx -g 'daemon off;'"]

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget -q -O /dev/null "http://127.0.0.1:${SITE_PORT}/healthz" || exit 1
