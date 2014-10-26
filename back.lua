function trim (s)
    return (string.gsub(s, "^%s*(.-)%s*$", "%1"))
end

local planter_id = ngx.var.arg_user_id
local sign    = ngx.var.arg_sign

if planter_id == nil then ngx.exit(400) end
--[[
-- check if planter_id or sign is exists?
--if sign    == nil then ngx.exit(400) end

-- get mac_address of planter_id
local get_mac_capture  = ngx.location.capture('/get_mac', {
	args= {
	    planter_id = planter_id
	    }
	})

if get_mac_capture.status == 400 then ngx.exit(400) end
local mac = trim(get_mac_capture.body)

-- check if sign is vaild or not
local status_args    = ngx.req.get_uri_args() -- get GET params in table

-- sort the GET Params
local key_table = {}  
local status_json_table = {}
for key,_ in pairs(status_args) do  
    table.insert(key_table,key)  
end  
table.sort(key_table)

-- start md5 check sum
local md5_before = ''
-- create status_table for json encode
for _,key in pairs(key_table) do
    if not (key == 'sign') then
        --ngx.say(key..","..status_args[key]..",")
        md5_before = md5_before..key..','..status_args[key]..','
    end

    if not ( (key == 'sign') or (key == 'pid') ) then
        status_json_table[key] = status_args[key]
    end
end

-- add systime to status_table
status_json_table['time'] = os.time()

-- add mac address to md5 check sum
local resty_md5 = require "resty.md5"
local md5 = resty_md5:new()
--ngx.say("mac:"..mac)
md5_before = md5_before..'mac'..','..mac
--local ok = md5:update('mac,'..mac)
--ngx.say('md5_before:'..md5_before)
local ok = md5:update(md5_before)
if not ok then ngx.exit(400) end
local digest = md5:final()
--sign = '827CCB0EEA8A706C4C34A16891F84E7B'
local sign_lower = string.lower(sign)

local str = require "resty.string"
local md5_result = tostring(str.to_hex(digest))

--ngx.say("md5:"..md5_result)
--ngx.say("sign:"..sign_lower)

if not (md5_result == sign_lower) then ngx.exit(400) end

-- create json 
local cjson = require "cjson"
jsonString = cjson.encode(status_json_table)

--ngx.say(jsonString)


-- write status json formate to memory
local set_stauts_capture = ngx.location.capture('/redis_set', {
	args= {
	    key= 'status_'..planter_id,
        val= jsonString
	    }
	})

-- get command from memory
local get_command_capture  = ngx.location.capture('/redis_get', {
	args= {
	    key= 'command_'..planter_id
	    }
	})

local parser = require 'redis.parser' --require redis.parser
local res, err = parser.parse_reply(get_command_capture.body)

-- default command if command not exists in memory
if res == nil then
    -- ngx.say("not in mem")
	ngx.say("GPIO=000000&T1=0005&T2=0010&ADC1=100&ADC2=1734&ADC3=69&ADC4=0&ADC5=0END")
else
    -- ngx.say("in mem")
	ngx.say(res)
end
]]--
ngx.say("GPIO=111111&T1=0005&T2=0010&ADC1=100&ADC2=1734&ADC3=69&ADC4=0&ADC5=0END")
