-- log阶段是不会阻塞请求的
-- timer.at启动数量是有限的，这里必须用缓冲队列来避免创建太多的timer，以及提高性能

-- 404或500不打dlog
local ngx_ctx = ngx.ctx
local uri = ngx_ctx.uri
if not uri then
    return
end


-- dlog 日志
local tablepool = require('tablepool')
local poolname = 'dlog'

local dlogger = require('utils.dlogger')
local config = require('config')
local dlog_url = config.dlog.url
local dlog_topic = config.dlog.topic

local function get_log_str()
    local game_id = ngx_ctx.game_id
    local test_id = ngx_ctx.test_id
    local div_type = ngx_ctx.div_type
    local server_addr = ngx_ctx.server_addr
    local div_flag = ngx_ctx.flag
    local dlog_field = ngx_ctx.dlog_field

    local args = ngx_ctx.args
    local player_id = args['playerId'] or ''

    local log_tab = tablepool.fetch(poolname, 12, 0)
    -- 通用dlog字段
    log_tab[1] = dlog_topic
    log_tab[2] = uri
    log_tab[3] = game_id
    log_tab[4] = player_id
    log_tab[5] = test_id
    log_tab[6] = div_type
    log_tab[7] = server_addr or ''
    log_tab[8] = div_flag or ''

    local log_tab_idx = 9

    -- 自定义dlog字段
    if dlog_field and type(dlog_field) == 'table' then
        for _, field in ipairs(dlog_field) do
            log_tab[log_tab_idx] = args[field] or ''
            log_tab_idx = log_tab_idx + 1
        end
    end

    -- local newval = ngx.shared.counter:incr('dlog', 1, 1)
    -- local msg = table.concat(log_tab, '|', 1, log_tab_idx - 1) .. '|' .. newval .. '\r\n'
    local msg = table.concat(log_tab, '|', 1, log_tab_idx - 1) .. '\r\n'

    tablepool.release(poolname, log_tab)

    return msg
end

if not dlogger.initted() then
    local ok, err =
        dlogger.init {
        dlog_url = dlog_url,
        -- 周期 2s
        periodic_flush = 2,
        -- 单台按一条100字节，2000qps算
        flush_limit = 200 * 1024
    }

    if not ok then
        ngx.log(ngx.ERR, 'failed to initialize the dlogger: ', err)
        return
    end
end

local msg = get_log_str()
-- ngx.log(ngx.WARN, msg)
local _, err = dlogger.log(msg)
if err then
    ngx.log(ngx.ERR, 'failed to log message: ', err)
    return
end
