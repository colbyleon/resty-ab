-- 调度器
-- 负责worker级别的配置更新
-- 路由功能

local new_table = require('table.new')
local nkeys = require('table.nkeys')
local cjson_safe = require('cjson.safe')

local str_util = require('utils.string_util')
local constant = require('utils.constant')
local SIGNATURE_HEADER = constant.SIGNATURE_HEADER
local ROUTE_CONFIG_KEY = constant.ROUTE_CONFIG_KEY
local GAME_CONFIG_KEY = constant.GAME_CONFIG_KEY
local ROUTE_CONFIG_VERSION_KEY = constant.ROUTE_CONFIG_VERSION_KEY
local GAME_CONFIG_VERSION_KEY = constant.GAME_CONFIG_VERSION_KEY
local REQUERST_BODY_NAME = constant.REQUERST_BODY_NAME

local config_shdict = ngx.shared.config
local current_route_verison
local current_game_verison

local router_moduler = require('utils.router')
local table_util = require('utils.table_util')

local _M = {}
-- 初始化，避免项目零配置时报错
local router = router_moduler.new({})
local games = {}

-- 配置的正确性由java服务来保证
local function update_route()
    local routes_str = config_shdict:get(ROUTE_CONFIG_KEY)
    -- 更新路由器
    local routes = cjson_safe.decode(routes_str)
    router = router_moduler.new(routes)
end

local function update_game()
    local games_str = config_shdict:get(GAME_CONFIG_KEY)
    -- 更新游戏秘钥
    games = cjson_safe.decode(games_str)
end

local function check_update()
    local last_route_ver = config_shdict:get(ROUTE_CONFIG_VERSION_KEY)
    -- 更新路由信息
    if current_route_verison ~= last_route_ver then
        update_route()

        current_route_verison = last_route_ver

        ngx.log(ngx.WARN, 'Worker [', ngx.worker.pid(), '] 路由器更新了')
    end

    local last_game_ver = config_shdict:get(GAME_CONFIG_VERSION_KEY)
    -- 更新游戏秘钥
    if current_game_verison ~= last_game_ver then
        update_game()

        current_game_verison = last_game_ver

        ngx.log(ngx.WARN, 'Worker [', ngx.worker.pid(), '] 游戏密钥更新了')
    end

    return true
end

--
-- 校验签名
-- boolean  校验ok
-- string   错误信息 or game_id
local function verify_sign(uri_args, all_args)
    local sign = ngx.req.get_headers()[SIGNATURE_HEADER]
    if not sign then
        return false, '请求头中没有带签名串'
    end

    local game_id = all_args['gameId'] or all_args['game_id']
    if not game_id then
        return false, '参数中没有带gameId'
    end

    local secret = games[tostring(game_id)]
    if not secret then
        return false, string.format('game_id = [%s] 没有配置 app_sercret', game_id)
    end

    -- 拼装签名参数
    local to_sign_tab

    local ct = ngx.var.content_type or ''
    if string.sub(ct, 1, 16) == 'application/json' then
        -- json 串直接装进 requestBody字段
        local request_body = ngx.req.get_body_data()
        to_sign_tab = table_util.merge_hash({[REQUERST_BODY_NAME] = request_body}, uri_args)
    else
        -- form格式默认就是全部参数
        to_sign_tab = all_args
    end

    -- key按字母排序
    local keys = new_table(nkeys(to_sign_tab), 0)
    for key, _ in pairs(to_sign_tab) do
        table.insert(keys, key)
    end
    table.sort(keys)

    -- 拼装签名串
    -- 为了性能，避免多余字符串gc，使用table组装
    -- 格式 key = value & secret
    local arr = new_table(4 * nkeys(to_sign_tab) + 1, 0)
    local arr_idx = 1

    for _, key in ipairs(keys) do
        local value = to_sign_tab[key]
        if type(value) == 'table' then
            arr[arr_idx] = key
            arr[arr_idx + 1] = '='
            arr[arr_idx + 2] = cjson_safe.encode(value) -- 表单数据类型是数组时要编成json后签名
            arr[arr_idx + 3] = '&'
            arr_idx = arr_idx + 4
        else
            arr[arr_idx] = key
            arr[arr_idx + 1] = '='
            arr[arr_idx + 2] = value
            arr[arr_idx + 3] = '&'
            arr_idx = arr_idx + 4
        end
    end
    arr[arr_idx] = secret

    local to_sign_str = table.concat(arr, '')
    local real_sign = str_util.to_md5_hex(to_sign_str)

    if real_sign ~= sign then
        return false, string.format('签名错误 to_sign_str: [%s] real_sign: [%s] error_sign: [%s]', to_sign_str, real_sign, sign)
    end
    return true, game_id
end

-- return test
local function do_route(uri, args, host, remote_addr)
    local opts = {
        host = host,
        remote_addr = remote_addr,
        vars = args
    }

    local ok, rst = pcall(router.match, router, uri, opts)
    if not ok then
        return nil, rst
    end
    return rst
end

_M.check_update = check_update
_M.verify_sign = verify_sign
_M.do_route = do_route

return _M

-- 改成直接写脚本
-- local function expresssion_match(expresssion)
--     -- 必定匹配
--     if expresssion == 'true' then
--         return true
--     elseif expresssion == 'false' then
--         return false
--     end

--     -- 捕获表达式中的变量
--     local it, err = ngx.re.gmatch(expresssion, '([a-z_]+)\\s*(?:==|~=|>|<|>=|<=)', 'joi')
--     if not it then
--         return nil, err
--     end

--     local args = ngx.ctx.args
--     local vars = new_table(0, 10)
--     -- 将变量写入存到tab，为了性能
--     while true do
--         local var, err = it()
--         if err then
--             ngx.log(ngx.ERR, '解析表达式变量错误 err: ', err)
--             return nil, err
--         elseif not var then
--             break
--         end
--         local var_name = var[1]
--         if not args[var_name] then
--             return nil, var_name .. '参数缺失'
--         end
--         vars[var_name] = true
--     end

--     -- 组装脚本,格式如下，拒绝字符串拼接
--     --
--     -- local version=tostring(ngx.ctx.args["version"])
--     -- local gameId=tostring(ngx.ctx.args["gameId"])
--     -- return gameId == '11828' and version > '2.3.3'
--     --
--     local script_tab = new_table(nkeys(vars) + 1, 0)

--     local tmp_tab = {'local ', nil, '=', 'tostring(ngx.ctx.args["', nil, '"])'}
--     for var, _ in pairs(vars) do
--         tmp_tab[2] = var
--         tmp_tab[5] = var
--         table.insert(script_tab, table.concat(tmp_tab, ''))
--     end

--     table.insert(script_tab, 'return ' .. expresssion)

--     local script = table.concat(script_tab, '\t')

--     ngx.log(ngx.INFO, '表达式脚本: ', script)

--     -- 加载脚本
--     local func, load_err = loadstring(script)
--     if load_err then
--         ngx.log(ngx.ERR, '加载脚本错误：', load_err)
--         return nil, '表达式错误: ' .. load_err
--     end

--     -- 执行脚本
--     local status, result = pcall(func)
--     if not status then
--         ngx.log(ngx.ERR, '脚本执行错误', result)
--         return nil, '表达式错误: ' .. result
--     end

--     return result
-- end
