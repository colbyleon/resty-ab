-- 0、获取配置信息
--  0.1、配置获取失败，转内部 backup
--  0.2、无配置匹配，响应404
-- 1、获取参数
-- 2、请求校验
-- 3、参数传递
-- 4、策略匹配
-- 4、策略处理
--  4.1、请求加工 - 添加请求头
--  4.2、浏览分发 - 发到真实后端 - 或者响应固定数据

local reqargs = require('resty.reqargs')
local dispatcher = require('dispatcher')
local mmh2 = require('resty.murmurhash2')

local INTERNAL_SERVER_ERROR = ngx.HTTP_INTERNAL_SERVER_ERROR
local NOT_FOUND = ngx.HTTP_NOT_FOUND
local WARN = ngx.WARN
local ERR = ngx.ERR
local ngx_log = ngx.log

local tab_util = require('utils.table_util')
local constant = require('utils.constant')
local json_resp = require('vo.json_resp')
local dnsparser = require('utils.dnsparser')

local FLAG_HEADER = constant.AB_FLAG_HEADER

local uri = ngx.var.uri

-- 配置更新检查
dispatcher.check_update()

-- 从querystring以及body中获取参数,并设置参数到 ctx
local uri_args, body_data = reqargs()
local args = tab_util.merge_hash(uri_args, body_data)
ngx.ctx.args = args

-- 签名校验
local ok, rst = dispatcher.verify_sign(uri_args, args)
local game_id
if not ok then
    -- if false then
    ngx_log(WARN, '签名错误 err: ', rst)
    ngx.status = ngx.HTTP_FORBIDDEN
    ngx.say(json_resp.err(403, '签名异常'))
    return ngx.exit(ngx.HTTP_FORBIDDEN)
else
    game_id = rst
end

-- 取得路由, 实验匹配
local host = ngx.var.host
local remote_addr = ngx.var.remote_addr
local test, err = dispatcher.do_route(uri, args, host, remote_addr)

if err then
    -- 配置错误
    ngx.status = INTERNAL_SERVER_ERROR
    ngx.say(json_resp.err(INTERNAL_SERVER_ERROR, err))
    ngx.exit(INTERNAL_SERVER_ERROR)
elseif not test then
    -- 没有匹配上实验，
    -- 也可以是实验有配置错误导致实验整体失败，这种错误只允许出现在预发布时
    ngx.exit(NOT_FOUND)
end

local route_id = test['routeId']
local test_id = test['testId']
local hash_field = test['hashField']
local divs = test['divs']
local dlog_field = test['dlogField']

-- 槽位计算
local solt
if not hash_field or hash_field == '' then
    solt = math.random(99)
else
    local to_hash_val = args[hash_field]
    if not to_hash_val then
        ngx.say(json_resp.err(400, hash_field .. '参数缺失'))
        ngx.exit(ngx.HTTP_BAD_REQUEST)
    end

    solt = mmh2(to_hash_val) % 100
end

-- 槽位匹配分流
local matched_div
local solt_ceil = 0
for _, div in ipairs(divs) do
    -- 分流比例计算槽位上限 20:30:50 上限 20:50:100
    solt_ceil = solt_ceil + div['rate']

    if not matched_div and solt < solt_ceil then
        matched_div = div
    end
end

-- 没有槽位匹配，优先级最低的就是默认分流
if not matched_div then
    matched_div = divs[#divs]
end

local div_flag = matched_div['divFlag']
local div_type = matched_div['divType']
local content = matched_div['fixedResp']
local server_addr = matched_div['serverAddr']

-- 用于日志记录等
ngx.ctx.uri = uri
ngx.ctx.game_id = game_id
ngx.ctx.route_id = route_id
ngx.ctx.test_id = test_id
ngx.ctx.div_type = div_type
ngx.ctx.server_addr = server_addr or ''
ngx.ctx.flag = div_flag or ''
ngx.ctx.dlog_field = dlog_field

-- 直接响应固定数据
if div_type == 2 then
    ngx.say(content)
    ngx.exit(ngx.HTTP_OK)
end

-- proxy_pass
-- ngx.ctx.proxy_pass_to = server_addr
local domain, port = dnsparser.parse_addr(server_addr)
local ip = dnsparser.dns_parse(domain)
if not ip then
    ngx.exit(NOT_FOUND)
end

ngx.ctx.server_ip = ip
ngx.ctx.server_port = port

-- 向后端传递实验分流标志
if div_flag and div_flag ~= '' then
    ngx.req.set_header(FLAG_HEADER, div_flag)
end
