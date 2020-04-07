local reqargs = require('resty.reqargs')

local tab_util = require('utils.table_util')
local json_resp = require('vo.json_resp')
local constant = require('utils.constant')

local FILTER_FUN_TEMPLATE = constant.FILTER_FUN_TEMPLATE

-- 从querystring以及body中获取参数,并设置参数到 ctx
local uri_args, body_data = reqargs()
local args = tab_util.merge_hash(uri_args, body_data)
ngx.ctx.args = args

local filter_fun = args['filter_fun']
if not filter_fun then
    ngx.say(json_resp.err(400, '缺少filter_fun参数'))
    return
end

local script = string.format(FILTER_FUN_TEMPLATE, filter_fun)

local func, err = loadstring(script)
if not func or err then
    ngx.say(json_resp.err(400, '脚本加载错误: err: ', err))
    return
end

local ok, result = pcall(func())
if not ok then
    ngx.say(json_resp.err(400, '脚本执行错误: err: ', result))
    return
end

ngx.say(json_resp.ok(result))
