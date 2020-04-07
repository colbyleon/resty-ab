-- 参考 lua-resty-logger-socket 造的dlogger的轮子

local concat = table.concat
local timer_at = ngx.timer.at
local ngx_log = ngx.log
local ngx_sleep = ngx.sleep
local pairs = pairs
local is_exiting = ngx.worker.exiting
local new_tab = require('table.new')
local http = require('resty.http')

local DEBUG = ngx.DEBUG

local _M = new_tab(0, 5)

_M._VERSION = '0.01'

local config = require('config')
local debug = config.debug

-- user config
local dlog_url = ''
local flush_limit = 4096 -- 4KB
local drop_limit = 1048576 -- 1MB
local max_buffer_reuse = 10000 -- reuse buffer for at most 10000
-- times
local periodic_flush = nil
local need_periodic_flush = nil

-- internal variables
local buffer_size = 0
-- 2nd level buffer, it stores logs ready to be sent out
local send_buffer = ''
-- 1st level buffer, it stores incoming logs
local log_buffer_data = new_tab(20000, 0)
-- number of log lines in current 1st level buffer, starts from 0
local log_buffer_index = 0

local last_error

local exiting
local retry_send = 0
local max_retry_times = 3
local retry_interval = 100 -- 0.1s
local keepalive_timeout = 10000 -- 10s
local pool_size = 10
local flushing
local logger_initted
local counter = 0

local function _write_error(msg)
    last_error = msg
end

local function _prepare_stream_buffer()
    local packet = concat(log_buffer_data, '', 1, log_buffer_index)
    send_buffer = send_buffer .. packet

    log_buffer_index = 0
    counter = counter + 1
    if counter > max_buffer_reuse then
        log_buffer_data = new_tab(20000, 0)
        counter = 0
        ngx_log(DEBUG, 'log buffer reuse limit (' .. max_buffer_reuse .. ') reached, create a new "log_buffer_data"')
    end
end

local function _do_flush()
    local packet = send_buffer

    -- 发送日志了
    local req_param = {
        method = 'POST',
        body = packet,
        keepalive_timeout = keepalive_timeout,
        keepalive_pool = pool_size
    }
    local httpc = http:new()
    local res, err = httpc:request_uri(dlog_url, req_param)
    if err or not res or res.status ~= 200 then
        return nil, err
    end

    local bytes = #packet

    if debug then
        ngx.update_time()
        ngx_log(DEBUG, ngx.now(), ':log flush:' .. bytes .. ':' .. packet)
    end

    return bytes
end

local function _need_flush()
    if buffer_size > 0 then
        return true
    end

    return false
end

local function _flush_lock()
    if not flushing then
        if debug then
            ngx_log(DEBUG, 'flush lock acquired')
        end
        flushing = true
        return true
    end
    return false
end

local function _flush_unlock()
    if debug then
        ngx_log(DEBUG, 'flush lock released')
    end
    flushing = false
end

local function _flush()
    local err

    -- pre check
    if not _flush_lock() then
        if debug then
            ngx_log(DEBUG, 'previous flush not finished')
        end
        -- do this later
        return true
    end

    if not _need_flush() then
        if debug then
            ngx_log(DEBUG, 'no need to flush:', log_buffer_index)
        end
        _flush_unlock()
        return true
    end

    -- start flushing
    retry_send = 0
    if debug then
        ngx_log(DEBUG, 'start flushing')
    end

    local bytes
    while retry_send <= max_retry_times do
        if log_buffer_index > 0 then
            _prepare_stream_buffer()
        end

        bytes, err = _do_flush()

        if bytes then
            break
        end

        if debug then
            ngx_log(DEBUG, 'resend log messages to the log server: ', err)
        end

        -- ngx.sleep time is in seconds
        if not exiting then
            ngx_sleep(retry_interval / 1000)
        end

        retry_send = retry_send + 1
    end

    _flush_unlock()

    if not bytes then
        local err_msg =
            'try to send log messages to the log server ' .. 'failed after ' .. max_retry_times .. ' retries: ' .. err
        _write_error(err_msg)
        return nil, err_msg
    else
        if debug then
            ngx_log(DEBUG, 'send ' .. bytes .. ' bytes')
        end
    end

    buffer_size = buffer_size - #send_buffer
    send_buffer = ''

    return bytes
end

-- Premature timer expiration happens when the Nginx worker process is trying to shut down
local function _periodic_flush(premature)
    if premature then
        exiting = true
    end

    if need_periodic_flush or exiting then
        -- no regular flush happened after periodic flush timer had been set
        if debug then
            ngx_log(DEBUG, 'performing periodic flush')
        end
        _flush()
    else
        if debug then
            ngx_log(DEBUG, 'no need to perform periodic flush: regular flush ' .. 'happened before')
        end
        need_periodic_flush = true
    end

    timer_at(periodic_flush, _periodic_flush)
end

local function _flush_buffer()
    local ok, err = timer_at(0, _flush)

    need_periodic_flush = false

    if not ok then
        _write_error(err)
        return nil, err
    end
end

local function _write_buffer(msg, len)
    log_buffer_index = log_buffer_index + 1
    log_buffer_data[log_buffer_index] = msg

    buffer_size = buffer_size + len

    return buffer_size
end

function _M.init(user_config)
    if (type(user_config) ~= 'table') then
        return nil, 'user_config must be a table'
    end

    for k, v in pairs(user_config) do
        if k == 'flush_limit' then
            if type(v) ~= 'number' or v < 0 then
                return nil, 'invalid "flush_limit"'
            end
            flush_limit = v
        elseif k == 'dlog_url' then
            if type(v) ~= 'string' or v == '' then
                return nil, 'invalid "dlog_url"'
            end
            dlog_url = v
        elseif k == 'drop_limit' then
            if type(v) ~= 'number' or v < 0 then
                return nil, 'invalid "drop_limit"'
            end
            drop_limit = v
        elseif k == 'max_retry_times' then
            if type(v) ~= 'number' or v < 0 then
                return nil, 'invalid "max_retry_times"'
            end
            max_retry_times = v
        elseif k == 'retry_interval' then
            if type(v) ~= 'number' or v < 0 then
                return nil, 'invalid "retry_interval"'
            end
            -- ngx.sleep time is in seconds
            retry_interval = v
        elseif k == 'keepalive_timeout' then
            if type(v) ~= 'number' or v < 0 then
                return nil, 'invalid "keepalive_timeout"'
            end
            keepalive_timeout = v
        elseif k == 'pool_size' then
            if type(v) ~= 'number' or v < 0 then
                return nil, 'invalid "pool_size"'
            end
            pool_size = v
        elseif k == 'max_buffer_reuse' then
            if type(v) ~= 'number' or v < 0 then
                return nil, 'invalid "max_buffer_reuse"'
            end
            max_buffer_reuse = v
        elseif k == 'periodic_flush' then
            if type(v) ~= 'number' or v < 0 then
                return nil, 'invalid "periodic_flush"'
            end
            periodic_flush = v
        end
    end

    if not dlog_url then
        return nil, 'dlog_url is necessary'
    end

    if (flush_limit >= drop_limit) then
        return nil, '"flush_limit" should be < "drop_limit"'
    end

    flushing = false
    exiting = false

    retry_send = 0

    logger_initted = true

    if periodic_flush then
        if debug then
            ngx_log(DEBUG, 'periodic flush enabled for every ' .. periodic_flush .. ' seconds')
        end
        need_periodic_flush = true
        timer_at(periodic_flush, _periodic_flush)
    end

    return logger_initted
end

function _M.log(msg)
    if not logger_initted then
        return nil, 'not initialized'
    end

    local bytes

    if type(msg) ~= 'string' then
        msg = tostring(msg)
    end

    local msg_len = #msg

    if debug then
        ngx.update_time()
        ngx_log(DEBUG, ngx.now(), ':log message length: ' .. msg_len)
    end

    -- response of "_flush_buffer" is not checked, because it writes
    -- error buffer
    if is_exiting() then
        exiting = true
        _write_buffer(msg, msg_len)
        _flush_buffer()
        if (debug) then
            ngx_log(DEBUG, 'Nginx worker is exiting')
        end
        bytes = 0
    elseif (msg_len + buffer_size < flush_limit) then
        _write_buffer(msg, msg_len)
        bytes = msg_len
    elseif (msg_len + buffer_size <= drop_limit) then
        _write_buffer(msg, msg_len)
        _flush_buffer()
        bytes = msg_len
    else
        --- this log message doesn't fit in buffer, drop it
        _flush_buffer()
        if (debug) then
            ngx_log(DEBUG, 'logger buffer is full, this log message will be ' .. 'dropped')
        end
        ngx_log(ngx.ERR, '消息丢弃')
        bytes = 0
    end

    if last_error then
        local err = last_error
        last_error = nil
        return bytes, err
    end

    return bytes
end

function _M.initted()
    return logger_initted
end

_M.flush = _flush

return _M
