local redis_c = require('utils.redis_util')
local constant = require('utils.constant')

local ROUTE_CONFIG_KEY = constant.ROUTE_CONFIG_KEY
local GAME_CONFIG_KEY = constant.GAME_CONFIG_KEY
local REDIS_NOTIFY_KEY = constant.REDIS_NOTIFY_KEY

ngx.req.read_body()
local data = ngx.req.get_body_data()

local red = redis_c:new()
local scope = ngx.var.scope

-- 使用管道
red:init_pipeline()

if scope == 'games' then
    red:set(GAME_CONFIG_KEY, data)
elseif scope == 'routes' then
    red:set(ROUTE_CONFIG_KEY, data)
end
-- 推送消息
red:xadd(REDIS_NOTIFY_KEY, 'maxlen', 20, '*', 'type', 'update', 'scope', scope)

local rst, err = red:commit_pipeline()

if not rst and err then
    ngx.say('配置更新失败 err: ', err)
else
    for _, value in ipairs(rst) do
        ngx.say(value)
    end
end
