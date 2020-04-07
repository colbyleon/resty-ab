local ngx_re_find = ngx.re.find
local resolver = require('resty.dns.resolver')
local lrucache = require('resty.lrucache')

local math = math
local sub_str = string.sub
local str_byte = string.byte
local tonumber = tonumber
local ngx_log = ngx.log
local ERR = ngx.ERR
local WARN = ngx.WARN

local cache, err = lrucache.new(1000)
if not cache then
    ngx_log(ERR, 'failed to create the cache: ', (err or 'unknown'))
end

local _M = {
    version = 0.01
}

local _is_addr = function(hostname)
    return ngx_re_find(hostname, [[^\d+?\.\d+?\.\d+?\.\d+$]], 'jo')
end

local function do_parse_dns(domain)
    local dns = '8.8.8.8'

    local r, err =
        resolver:new {
        nameservers = {dns, {dns, 53}},
        retrans = 5, -- 5 retransmissions on receive timeout
        timeout = 2000 -- 2 sec
    }

    if not r then
        return nil, 'failed to instantiate the resolver: ' .. err
    end

    local answers, err = r:query(domain, nil, {})
    if not answers then
        return nil, 'failed to query the DNS server: ' .. err
    end

    if answers.errcode then
        return nil, 'server returned error code: ' .. answers.errcode .. ': ' .. answers.errstr
    end

    local idx = math.random(1, #answers)
    return answers[idx].address
end

function _M.dns_parse(domain)
    if _is_addr(domain) then
        return domain
    end

    local ip = cache:get(domain)
    if ip then
        return ip
    end

    local err
    ip, err = do_parse_dns(domain)
    if err then
        ngx_log(WARN, string.format('domain = [%s] 域名解析异常 err: %s', domain, err))
    end

    cache:set(domain, ip, 3600)
    return ip
end

local function rfind_char(s, ch, idx)
    local b = str_byte(ch)
    for i = idx or #s, 1, -1 do
        if str_byte(s, i, i) == b then
            return i
        end
    end
    return nil
end

-- parse_addr parses 'addr' into the host and the port parts. If the 'addr'
-- doesn't have a port, 80 is used to return. For malformed 'addr', the entire
-- 'addr' is returned as the host part. For IPv6 literal host, like [::1],
-- the square brackets will be kept.
function _M.parse_addr(addr)
    local default_port = 80
    if str_byte(addr, 1) == str_byte('[') then
        -- IPv6 format
        local right_bracket = str_byte(']')
        local len = #addr
        if str_byte(addr, len) == right_bracket then
            -- addr in [ip:v6] format
            return addr, default_port
        else
            local pos = rfind_char(addr, ':', #addr - 1)
            if not pos or str_byte(addr, pos - 1) ~= right_bracket then
                -- malformed addr
                return addr, default_port
            end

            -- addr in [ip:v6]:port format
            local host = sub_str(addr, 1, pos - 1)
            local port = sub_str(addr, pos + 1)
            return host, tonumber(port)
        end
    else
        -- IPv4 format
        local pos = rfind_char(addr, ':', #addr - 1)
        if not pos then
            return addr, default_port
        end

        local host = sub_str(addr, 1, pos - 1)
        local port = sub_str(addr, pos + 1)
        return host, tonumber(port)
    end
end

return _M
