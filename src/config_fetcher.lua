local http = require "resty.http"

-- Настройки из окружения (объявлены через env-директивы в nginx.conf)
local timeout_ms = tonumber(os.getenv("FETCH_TIMEOUT_MS")) or 2000
local verify_ssl = (os.getenv("VERIFY_UPSTREAM_TLS") or "on") ~= "off"

-- Получаем список серверов из переменной окружения
local servers_str = os.getenv("SERVERS")
if not servers_str then
    ngx.log(ngx.ERR, "No servers found in environment variable")
    ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
end

-- Разделяем строку на таблицу серверов
local servers = {}
for server in string.gmatch(servers_str, "[^%s]+") do
    table.insert(servers, server)
end

-- Запрос к одному апстриму; выполняется в собственном треде со своим
-- http-клиентом (клиент lua-resty-http не потокобезопасен), поэтому все
-- апстримы опрашиваются параллельно и общий бюджет равен самому медленному,
-- а не сумме. Возвращает готовую запись агрегации.
local function fetch_one(url)
    local entry = {
        config = nil,
        upload = 0, download = 0, total = 0, expire = 0,
        profile_title = nil, update_interval = nil, announce = nil,
        support_url = nil, web_page_url = nil,
    }

    local httpc = http.new()
    httpc:set_timeout(timeout_ms)
    local res, err = httpc:request_uri(url, {
        method = "GET",
        ssl_verify = verify_ssl,
    })

    if not res then
        ngx.log(ngx.ERR, "Error fetching from ", url, ": ", err or "unknown error")
        return entry
    end

    if res.status == 200 then
        -- Обрабатываем статистику
        local userinfo = res.headers["Subscription-Userinfo"]
        if userinfo then
            local upload = tonumber(string.match(userinfo, "upload=(%d+)"))
            local download = tonumber(string.match(userinfo, "download=(%d+)"))
            local total = tonumber(string.match(userinfo, "total=(%d+)"))
            local expire = tonumber(string.match(userinfo, "expire=(%d+)"))

            if upload then entry.upload = upload end
            if download then entry.download = download end
            if total then entry.total = total end
            if expire and expire > 0 then
                -- expire=0 means unlimited, use earliest real expiration date
                entry.expire = expire
            end
        end

        entry.profile_title = res.headers["Profile-Title"]
        entry.update_interval = res.headers["Profile-Update-Interval"]
        entry.announce = res.headers["Announce"]
        entry.support_url = res.headers["Support-Url"]
        entry.web_page_url = res.headers["Profile-Web-Page-Url"]

        local decoded_config = ngx.decode_base64(res.body)
        if decoded_config then
            entry.config = decoded_config
        else
            ngx.log(ngx.ERR, "Failed to decode base64 from ", url)
        end
    elseif res.status == ngx.HTTP_BAD_REQUEST or res.status == ngx.HTTP_NOT_FOUND then
        -- 3x-ui: неизвестный sub_id — 400 в v3.0.x, 404 после рефакторинга сабов в v3.4
        ngx.log(ngx.WARN, "No such client on ", url)
    else
        ngx.log(ngx.WARN, "Unexpected status ", res.status, " from ", url)
    end

    return entry
end

-- Опрашиваем все серверы параллельно, собирая результаты по порядку
local threads = {}
for i, base_url in ipairs(servers) do
    threads[i] = ngx.thread.spawn(fetch_one, base_url .. ngx.var.sub_id)
end

local entries = {}
for i, thread in ipairs(threads) do
    local ok, entry = ngx.thread.wait(thread)
    if ok and type(entry) == "table" then
        entries[i] = entry
    else
        ngx.log(ngx.ERR, "Fetch thread ", i, " failed: ", entry or "unknown error")
        entries[i] = { config = nil, upload = 0, download = 0, total = 0, expire = 0 }
    end
end

-- Агрегируем в исходном порядке серверов
local configs = {}
local total_upload = 0
local total_download = 0
local total_quota = 0
local expire_time = 0
local profile_title = nil
local update_interval = nil
local announce = nil
local support_url = nil
local web_page_url = nil

for _, entry in ipairs(entries) do
    if entry.config then
        table.insert(configs, entry.config)
        total_upload = total_upload + entry.upload
        total_download = total_download + entry.download
        if entry.total > 0 then
            total_quota = total_quota == 0 and entry.total or math.min(total_quota, entry.total)
        end
        if entry.expire > 0 then
            expire_time = (expire_time == 0 or entry.expire < expire_time) and entry.expire or expire_time
        end
        if not profile_title and entry.profile_title then
            profile_title = entry.profile_title
        end
        if not update_interval and entry.update_interval then
            update_interval = entry.update_interval
        end
        if not announce and entry.announce then
            announce = entry.announce
        end
        if not support_url and entry.support_url then
            support_url = entry.support_url
        end
        if not web_page_url and entry.web_page_url then
            web_page_url = entry.web_page_url
        end
    end
end

-- Возвращаем объединённые конфигурации клиенту
if #configs > 0 then
    -- Объединяем без добавления новой строки между конфигурациями
    local combined_configs = table.concat(configs)
    local encoded_combined_configs = ngx.encode_base64(combined_configs)

    -- Устанавливаем заголовки
    ngx.header.content_type = "text/plain; charset=utf-8"
    ngx.header.content_length = #encoded_combined_configs

    -- Устанавливаем агрегированные заголовки
    if profile_title then
        ngx.header["Profile-Title"] = profile_title
    end
    if update_interval then
        ngx.header["Profile-Update-Interval"] = update_interval
    end
    if announce then
        ngx.header["Announce"] = announce
    end
    if support_url then
        ngx.header["Support-Url"] = support_url
    end
    if web_page_url then
        ngx.header["Profile-Web-Page-Url"] = web_page_url
    end

    -- Устанавливаем агрегированную статистику
    if total_upload > 0 or total_download > 0 then
        ngx.header["Subscription-Userinfo"] = string.format(
            "upload=%d; download=%d; total=%d; expire=%d",
            total_upload,
            total_download,
            total_quota,
            expire_time
        )
    end

    ngx.print(encoded_combined_configs)
else
    ngx.status = ngx.HTTP_BAD_GATEWAY
    ngx.say("No configs available")
end
