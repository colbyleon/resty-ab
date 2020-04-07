local reqs = {
    {
        method = 'post',
        path = '/bag/query',
        headers = {
            ['Signature'] = '5ed92578b383292fa130edf87649e085',
            ['Content-Type'] = 'application/json'
        },
        body = '{"gameId":"11828", 	"version":"2.3.5", 	"playerId":"fesfa" }'
    },{
        method = 'post',
        path = '/bag/query',
        headers = {
            ['Signature'] = '8dd2a6e535e202461b0be0906d39ab38',
            ['Content-Type'] = 'application/json'
        },
        body = '{"gameId":"11828","playerId":"1503228191","version":"2.3.1","channel":"TAPS0N00202"}'
    }
}
function request()
    -- local req = reqs[math.random(1, #reqs)]
    local req = reqs[2]
    return wrk.format(req['mothod'], req['path'], req['headers'], req['body'])
end

-- local counter = 1000000

-- function response()
--     if counter == 100 then
--         wrk.thread:stop()
--     end
--     counter = counter + 1
-- end
