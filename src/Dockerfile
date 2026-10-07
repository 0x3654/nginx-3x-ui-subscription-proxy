# Используем OpenResty на базе Alpine (пин минорного тега)
FROM openresty/openresty:1.31.1.1-3-alpine-fat

ARG SITE_PORT=443
ARG SERVERS

# Прокидываем переменные
ENV SITE_HOST=localhost
ENV SITE_PORT=${SITE_PORT}
ENV SERVERS=${SERVERS}
ENV SUB=sub
ENV TLS_MODE=off

# Выставляем порты
EXPOSE ${SITE_PORT}/tcp

# Устанавливаем esh
RUN apk upgrade && apk add --no-cache \
    esh git

# Устанавливаем Lua-библиотеку resty-http (пин релиза)
RUN git clone --branch v0.18.0 --depth 1 https://github.com/ledgetech/lua-resty-http.git && \
    mkdir -p /usr/local/share/lua/5.1/resty && \
    mv lua-resty-http/lib/resty/* /usr/local/share/lua/5.1/resty/ && \
    rm -rf lua-resty-http

# Копируем конфигурацию Nginx
RUN rm /usr/local/openresty/nginx/conf/nginx.conf
COPY src/nginx.conf.esh /usr/local/openresty/nginx/conf/

# Копируем конфигурацию Lua
COPY src/config_fetcher.lua /etc/nginx/lua/

# Устанавливаем права на файлы
RUN chmod -R 755 /usr/local/openresty/nginx/conf/ && \
    chmod -R 755 /etc/nginx/lua/

# Запускаем nginx со своей конфигурацией
CMD ["/bin/sh", "-c", "esh -o /usr/local/openresty/nginx/conf/nginx.conf /usr/local/openresty/nginx/conf/nginx.conf.esh && exec nginx -g 'daemon off;'"]
