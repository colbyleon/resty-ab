-- 基于前缀树r3实现的高性能路由包
local radix = require('resty.radixtree')
local new_table = require('table.new')

local constant = require('utils.constant')
local FILTER_FUN_TEMPLATE = constant.FILTER_FUN_TEMPLATE

local _M = {}

local mt = {__index = _M}

--
local function generate_param(path, test)
    local vars = test['vars']
    local hosts = test['hosts']
    local remote_addrs = test['ipList']
    local filter_fun = test['filterFun']
    local priority = test['priority']

    local param = new_table(0, 7)
    param.paths = {path}
    param.metadata = test
    param.vars = vars

    -- 访问的域名
    if hosts and #hosts > 0 then
        param.hosts = hosts
    end

    -- 来源IP
    if remote_addrs and #remote_addrs > 0 then
        param.remote_addrs = remote_addrs
    end

    -- 过滤脚本配置，loadstring先返回第一层，调用后才是真正的函数，
    -- 加上return，隐藏一些全局变量，屏蔽一部分安全问题
    if filter_fun and filter_fun ~= '' then
        local func_str = string.format(FILTER_FUN_TEMPLATE, filter_fun)

        local fun, err = loadstring(func_str)
        if not fun or err then
            ngx.log(ngx.ERR, '实验配置失败,脚本错误 test_id: ', test['testId'], ' script: ', filter_fun, ' err: ', err)
            return nil, err
        else
            param.filter_fun = fun()
        end
    end

    if priority then
        param.priority = priority
    end

    return param
end

local function new(routes)
    local params = new_table(#routes * 5, 0)
    local p_idx = 1

    for _, route in ipairs(routes) do
        local path = route['routePath']
        local routeId = route['routeId']
        local dlogField = route['dlogField']
        local tests = route['tests']

        local testParams = new_table(#tests, 0)
        local success = true

        if tests and #tests > 0 then
            for _, test in ipairs(tests) do
                -- 实验配置失败时，整个 route 配置失败
                local param = generate_param(path, test)
                if param then
                    -- 传递参数
                    test['routeId'] = routeId
                    test['dlogField'] = dlogField
                    table.insert(testParams, param)
                else
                    -- 配置成功粒度为route级别
                    success = false
                    break
                end
            end
        else
            ngx.log(ngx.ERR, 'route_id=[', routeId, ']未配置默认实验')
            success = false
        end

        if success then
            for _, param in ipairs(testParams) do
                params[p_idx] = param
                p_idx = p_idx + 1
            end
        end
    end

    local rx = radix.new(params)

    return setmetatable({router = rx}, mt)
end

local function match(self, path, opts)
    return self.router:match(path, opts)
end

_M.match = match
_M.new = new
return _M
