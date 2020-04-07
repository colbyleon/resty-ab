local clone_table = require('table.clone')
local new_tab = require('table.new')
local nkeys = require('table.nkeys')

local _M = {}

local function merge_hash(tb1, tb2)
    if not tb2 then
        return clone_table(tb1)
    end

    if not tb1 then
        return clone_table(tb2)
    end

    local tab = new_tab(0, nkeys(tb1), nkeys(tb2))

    for key, value in pairs(tb1) do
        tab[key] = value
    end
    for key, value in pairs(tb2) do
        tab[key] = value
    end
    return tab
end

_M.merge_hash = merge_hash
return _M
