local planter_id = ngx.var.arg_planter_id
if planter_id == nil then ngx.exit(400) end
local result_capture = ngx.location.capture('/redis_get', {
        args ={
            key = 'mac_'..planter_id
        }
    })

local parser = require 'redis.parser' --require redis.parser
local res, err = parser.parse_reply(result_capture.body)

if res == nil then
    local mysql = require "resty.mysql"
    local db, err = mysql:new()
    if not db then ngx.exit(400) end
    db:set_timeout(1000)

    -- connect pool
    local ok, err, errno, sqlstate = db:connect {
        host = "127.0.0.1",
        port = 3306,
        database = "plant",
        user = "root",
        password = "1moodadmin",
        max_packet_size = 1024 * 1024 
    }

    if not ok then ngx.exit(400) end

    local sql_statement = "select planter_code from tp_planter where planter_id = "..planter_id
    res, err, errno, sqlstate = db:query(sql_statement)
    if (not res) or (res[1] == nil) then ngx.exit(400) end

    res =  res[1]["planter_code"]
	local set_stauts_capture = ngx.location.capture('/redis_set', {
		args= {
		    key= 'mac_'..planter_id,
		    val= res
		}
	})

end

ngx.say(res)
