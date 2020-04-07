local _M = {
    -- 初始化锁的key
    INIT_LOCK_KEY = 'init_lock',

    -- redis config key;
    ROUTE_CONFIG_KEY = 'restab:route:config',
    GAME_CONFIG_KEY = 'restab:games:config',
    REDIS_NOTIFY_KEY = 'restab:update:notify',

    -- local config version key;
    ROUTE_CONFIG_VERSION_KEY = 'route:config:version',
    GAME_CONFIG_VERSION_KEY = 'game:config:version',

    -- 签名请求头
    SIGNATURE_HEADER = 'Signature',
    -- 实验测试请求同
    AB_FLAG_HEADER = 'AB_Flag',

    -- json请求头参数名
    REQUERST_BODY_NAME = 'requestBody',

    -- filter_fun_format
    FILTER_FUN_TEMPLATE =
        [[return function(args)
        local time,localtime = ngx.time, ngx.localtime
        local ngx,io,os,load,loadfile,loadstring,dofile,require,print
        return %s end]],
}
return _M
