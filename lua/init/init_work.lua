-- 只在0号worker上启动，windows上此方法不起作用
local id = ngx.worker.id()
if id ~= 0 then
    return
end

local config_shdict = ngx.shared.config

local constant = require('utils.constant')
local redis_c = require('utils.redis_util')
local red = redis_c:new()

local new_table = require('table.new')

local ROUTE_CONFIG_KEY = constant.ROUTE_CONFIG_KEY
local GAME_CONFIG_KEY = constant.GAME_CONFIG_KEY
local REDIS_NOTIFY_KEY = constant.REDIS_NOTIFY_KEY
local ROUTE_CONFIG_VERSION_KEY = constant.ROUTE_CONFIG_VERSION_KEY
local GAME_CONFIG_VERSION_KEY = constant.GAME_CONFIG_VERSION_KEY
local LISTEN_INTERVAL = 8 -- secs

-- redis stream 中的消息ID
local last_id = '0-0'

-- scopes 更新哪些配置
local function do_update(scopes)
    if scopes['games'] then
        local games, err = red:get(GAME_CONFIG_KEY)
        if err then
            ngx.log(ngx.log.ERR, 'Server 游戏秘钥更新失败 err: ', err)
        elseif games then
            config_shdict:set(GAME_CONFIG_KEY, games)
            config_shdict:incr(GAME_CONFIG_VERSION_KEY, 1, 1)
            ngx.log(ngx.WARN, 'Server 游戏秘钥更新完成 games=' .. games)
        else
            ngx.log(ngx.ERR, 'Server 游戏秘钥配置为空')
        end
    end

    if scopes['routes'] then
        local routes, err = red:get(ROUTE_CONFIG_KEY)
        if err then
            ngx.log(ngx.log.ERR, 'Server 路由更新失败 err: ', err)
        elseif routes then
            config_shdict:set(ROUTE_CONFIG_KEY, routes)
            config_shdict:incr(ROUTE_CONFIG_VERSION_KEY, 1, 1)
            ngx.log(ngx.WARN, 'Server 路由更新完成 routes=' .. routes)
        else
            ngx.log(ngx.ERR, 'Server 路由配置为空')
        end
    end
end

local function check_update()
    -- 监听Stream
    local rst, err = red:xread('count', 20, 'block', LISTEN_INTERVAL * 1000, 'streams', REDIS_NOTIFY_KEY, last_id)
    if not rst then
        if err then
            ngx.log(ngx.ERR, 'Redis 监听配置更新异常 err: ', err)
            return nil, err
        end
        return
    end

    -- 处理成易读的消息格式
    local msgs = rst[1][2]
    local msg_list = new_table(#msgs, 0)
    for _, msg in ipairs(msgs) do
        local msg_obj = new_table(0, 2)
        last_id = msg[1]
        local data = msg[2]
        for i = 1, #data, 2 do
            msg_obj[data[i]] = data[i + 1]
        end
        table.insert(msg_list, msg_obj)
    end

    ngx.log(ngx.WARN, '配置更新消息', require('cjson').encode(msg_list))

    -- 标记要更新的配置作用域，目前只有games和routes
    local scopes = {games = false, routes = false}

    -- 目前msg.type 只有 update，后续可能加上心跳 heart
    for _, msg in ipairs(msg_list) do
        if msg['type'] == 'update' then
            scopes[msg['scope']] = true
        end
    end

    do_update(scopes)
end

-- 初始化
local function init()
    -- 启动立即更新last_id
    local rst, err = red:xinfo('stream', REDIS_NOTIFY_KEY)
    if not rst and err then
        ngx.log(ngx.ERR, 'Redis 读取stream信息错误 err: ', err)
    end

    if rst then
        for i, v in ipairs(rst) do
            if v == 'last-generated-id' then
                last_id = rst[i + 1]
                break
            end
        end
    end

    -- 启动立即更新配置
    do_update({games = true, routes = true})

    -- 不用timer.every()是为了避免同时存在多个监听
    local function listen()
        local _, err = check_update()
        -- reload 后不要再继续监听了
        if not ngx.worker.exiting() then
            if err then
                -- 有时候会抽风，比如redis timeout
                ngx.sleep(LISTEN_INTERVAL)
            end
            ngx.timer.at(0, listen)
        end
    end

    -- 启动循环监听
    ngx.log(ngx.WARN, '启动配置更新监听')
    listen()
end

-- redis不可以在init_worker阶段使用，使用timer可以解决此问题
local ok, err = ngx.timer.at(0, init)
if not ok then
    ngx.log(ngx.ERR, '启动初始化任务失败 err: ', err)
end
