local redis_config = require('config').redis
local host = redis_config.host
local port = redis_config.port
local pwd = redis_config.password
local db = redis_config.database
local timeout = redis_config.timeout
local pool_size = redis_config.pool_size
local keepalive = redis_config.keepalive

local redis_c = require('resty.redis')
local new_tab = require('table.new')

local _M = new_tab(0, 155)
_M._VERSION = '0.01'

local mt = {__index = _M}

local function is_redis_null(res)
    if type(res) == 'table' then
        for _, v in pairs(res) do
            if v ~= ngx.null then
                return false
            end
        end
        return true
    elseif res == ngx.null then
        return true
    elseif res == nil then
        return true
    end

    return false
end

function _M:connect_mod(redis)
    redis:set_timeout(timeout)
    -- redis:set_timeouts(500, 1000, 30000)
    local ok, err = redis:connect(host, port)
    if not ok then
        ngx.log(ngx.ERR, '连接redis失败', err)
        return false, err
    end

    -- 重用连接，减少重复认证和切库
    local count, _ = redis:get_reused_times()
    if not count or count == 0 then
        if pwd then
            local ok, err = redis:auth(pwd)
            if not ok then
                ngx.log(ngx.ERR, 'redis认证失败', err)
                return false, err
            end
        end
        if db then
            redis:select(db)
        end
    end
    return true
end

function _M.set_keepalive_mod(redis)
    return redis:set_keepalive(keepalive, pool_size)
end

function _M:init_pipeline()
    self._reqs = {}
end

function _M:commit_pipeline()
    local reqs = self._reqs
    if nil == reqs or #reqs == 0 then
        return {}, 'no pipeline'
    else
        self._reqs = nil
    end

    local redis, err = redis_c:new()
    if not redis then
        return nil, err
    end

    local ok, err = self:connect_mod(redis)
    if not ok then
        return nil, err
    end

    redis:init_pipeline()
    for _, vals in ipairs(reqs) do
        local fun = redis[vals[1]]
        fun(redis, unpack(vals, 2))
    end

    local results, err = redis:commit_pipeline()
    if not results or err then
        ngx.log(ngx.ERR, 'redis管道命令错误: ', err)
        return {}, err
    end

    if is_redis_null(results) then
        results = {}
        ngx.log(ngx.WARN, 'is null')
    end

    self.set_keepalive_mod(redis)

    for i, value in ipairs(results) do
        if is_redis_null(value) then
            results[i] = nil
        end
    end

    return results, err
end

local function do_command(self, cmd, ...)
    if self._reqs then
        table.insert(self._reqs, {cmd, ...})
        return
    end

    local redis, err = redis_c:new()
    if not redis then
        return nil, err
    end

    local ok, err = self:connect_mod(redis)
    if not ok or err then
        return nil, err
    end

    local fun = redis[cmd]
    local result, err = fun(redis, ...)

    if not result or err then
        return nil, err
    end

    if is_redis_null(result) then
        result = nil
    end

    -- 确认连接没有问题才放回连接池
    self.set_keepalive_mod(redis)

    return result, err
end

function _M:new()
    return setmetatable({_reqs = nil}, mt)
end

-- 动态增加redis的方法
local function cmd_index(_, cmd)
    -- 内部属性全部以 _下划线开头
    local captures, _ = ngx.re.match(cmd, '^_', 'jo')
    if captures then
        return nil
    end
    local function func(self, ...)
        return do_command(self, cmd, ...)
    end

    _M[cmd] = func
    return func
end

return setmetatable(_M, {__index = cmd_index})
