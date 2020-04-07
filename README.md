# 说明文档

## 运行环境搭建

### 安装 lua5.1 以及 安装luarocks

可直接参考 [官方安装文档](https://github.com/luarocks/luarocks/wiki/Installation-instructions-for-Unix)

安装lua

* First, ensure that you have development tools installed on your system, otherwise run the command below to install them

```shell
 -$ sudo apt install build-essential libreadline-dev
```

* Then to build and install Lua, run the following commands to download the package tar ball, extract, build and install it.

```shell
-$ curl -R -O http://www.lua.org/ftp/lua-5.3.4.tar.gz
-$ tar -zxf lua-5.3.4.tar.gz
-$ cd lua-5.3.4
-$ make linux test
-$ sudo make install
```

安装luarocks

```shell
-$ wget https://luarocks.org/releases/luarocks-3.2.1.tar.gz
-$ tar zxpf luarocks-3.2.1.tar.gz
-$ cd luarocks-3.2.1
```

* Run ./configure. (This will attempt to detect your installation of Lua. If you get any error messages, see the section "Customizing your settings", below.)
* Run make build.
* As superuser, run make install.

### 安装openresty

详见 [Openresty官网安装方法](http://openresty.org/cn/linux-packages.html)

## 部署

### 代码部署

git地址 http://git.ids111.com/idreamsky/yanfa/OperationForum/resty-ab  
从git拉取master分支代码到部署目录

### 配置修改

>配置文件不支持多环境管理，只能拉下代码后修改代码

* 修改 lua/config.lua 中的redis以及dlog的配置
* 监听的端口默认为8000，可以通过service/endpoint.conf进行修改

### 命令

```bash
# /root/workdir/resty-ab 为项目目录
# 启动命令
openresty -p /root/workdir/resty-ab -c service/nginx.conf

# 停止命令
openresty -p /root/workdir/resty-ab -c service/nginx.conf -s stop

# 重载命令(修改配置后不用停止)
openresty -p /root/workdir/resty-ab -c service/nginx.conf -s reload
```

## 依赖的库

路由器 [lua-resty-radixtree](https://github.com/iresty/lua-resty-radixtree "lua-resty-radixtree")  
获取全部请求参数 [lua-resty-reqargs](https://github.com/bungle/lua-resty-reqargs "lua-resty-reqargs")  
murmurhash2 [lua-resty-murmurhash2](https://github.com/bungle/lua-resty-murmurhash2 'lua-resty-murmurhash2')  
http请求 [lua-resty-http](https://github.com/ledgetech/lua-resty-http 'lua-resty-http')  

## 配置数据结构

```json
// routes
[
  {
    "routeId": 1,
    "routePath": "/bag/query",
    "dlogField":["version"],
    "tests": [
      {
        "testId": 1,
        "hosts": [],
        "ipList":[],
        "vars":[["gameId","==","11828"],["version",">","2.3.0"],["channel","==","TAPS0N00202"]],
        "filterFun":"args['gameId'] == '11828' and args['version'] <= '2.3.5'",
        "priority": 2,
        "hashField": "playerId",
        "divs": [
          {
            "rate": 90,
            "divFlag": "A10",
            "divType": 1,
            "serverAddr": "10.72.12.222:7023"
          },
          {
            "rate": 10,
            "divFlag": "A2",
            "divType": 2,
            "fixedResp": "{\"status\":0,\"data\":\"A1固定响应\"}"
          }
        ]
      },
      {
        "testId": 2,
        "hosts": [],
        "ipList":[],
        "vars":[["gameId","==","11828"]],
        "filterFun":"",
        "priority": 1,
        "hashField": "playerId",
        "divs": [
          {
            "rate": 100,
            "divFlag": "B001",
            "divType": 1,
            "serverAddr": "10.72.17.59:8000"
          }
        ]
      }
    ]
  },{
    "routeId": 2,
    "routePath": "/meddle/difficulty",
    "dlogField":["version"],
    "tests": [
      {
        "testId": 3,
        "hosts": [],
        "ipList":[],
        "vars":[["gameId","==","90115"]],
        "filterFun":"",
        "priority": 1,
        "hashField": "",
        "divs": [
          {
            "rate": 100,
            "divFlag": "C001",
            "divType": 1,
            "serverAddr": "10.72.12.222:9900"
          }
        ]
      }
    ]
  }
]
// games
{
    "11828": "123456"
}
```
