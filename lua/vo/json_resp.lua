local cjson = require('cjson')
local new_table = require('table.new')

local _M = {}

local function new(status, msg, data)
    local obj = {
        status = status or 0,
        message = msg or '',
        data = data
    }
    return obj
end

function _M.ok(data, msg)
    local result = new(0, msg, data)
    return cjson.encode(result)
end

function _M.err(status, ...)
    local result = new(status, table.concat({...}, ' '))
    return cjson.encode(result)
end

return _M
