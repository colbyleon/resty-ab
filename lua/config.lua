local _M = {}

-- redis配置
_M.redis = {
    -- 对应海豚admin的 restyab-(prod|pre) 库
    host = '10.72.12.222',
    port = 6379,
    database = 6,
    password = 'redis123456',
    -- timeout 不要调到10秒以下, 否则会有很多timeout错误
    timeout = 10000,
    pool_size = 10,
    keepalive = 30000
}

-- dlog 配置
_M.dlog = {
    url = 'http://10.72.12.222:8100/log',
    -- url = 'http://10.72.12.222:9901',
    -- url = 'http://dlog.uu.cc',
    topic = 'resty_ab'
}

-- 开启debug日志，目前没用
_M.debug = false

return _M
