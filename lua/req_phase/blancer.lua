-- 主要为了与后端建立长连接
-- 动态upstream,暂不支持负载均衡和健康检查

local balancer = require('ngx.balancer')

local server_ip = ngx.ctx.server_ip
local server_port = ngx.ctx.server_port

local ok, err = balancer.set_current_peer(server_ip, server_port)
if not ok then
    ngx.log(ngx.ERR, "failed to set the current peer: ", err)
    return ngx.exit(ngx.ERROR)
end
