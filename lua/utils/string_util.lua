-- string 工具类

local resty_md5 = require 'resty.md5'
local resty_str = require 'resty.string'
local match = ngx.re.match
local gsub = ngx.re.gsub
local re_split = ngx.re.split

local _M = {}

local function start_with(str, prefix)
    if not str or str == ngx.null then
        return false
    end

    if not prefix or prefix == ngx.null then
        return false
    end

    local m, err = match(str, '^' .. prefix, 'jo')
    if m then
        return true
    end
    return false
end

local function replace(raw, regex, replace_ment)
    return gsub(raw, regex, replace_ment, 'jo')
end

local function to_md5_hex(str)
    local md5 = resty_md5:new()
    md5:update(str)
    local digest = md5:final()
    return resty_str.to_hex(digest)
end

local function split(str, sep)
    return re_split(str, sep)
end

_M.start_with = start_with
_M.replace = replace
_M.to_md5_hex = to_md5_hex
_M.spilt = split
return _M
