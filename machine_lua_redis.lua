--
--  tool functions
--

function trim (s)
    return (string.gsub(s, "^%s*(.-)%s*$", "%1"))
end

function get_data_from_redis(key) 
    local redis_reslut  = ngx.location.capture('/redis_get', {
        args= {
            key = key
            }
        })

    if redis_reslut.status == 400 then return nil end

    local parser = require 'redis.parser' --require redis.parser
    local res, err = parser.parse_reply(redis_reslut.body)

    return res
end

function set_data_to_redis(key,value)
    local redis_status = ngx.location.capture('/redis_set', {
        args= {
            key= key,
            val= value
            }
        })

    if 200 == redis_status.status then
        return true
    else
        return nil
    end

end

function get_mac_with_plant_id(pid,redis)
    local mac_address,err = redis:get('mac_'..pid)

    if mac_address == ngx.null then
        local mysql = require "resty.mysql"
        local db, err = mysql:new()
        if not db then return nil end

        -- connect pool
        local ok, err, errno, sqlstate = db:connect {
            host = "127.0.0.1",
            port = 3306,
            database = "plant",
            user = "root",
            password = "1moodadmin",
            max_packet_size = 1024 * 1024 
        }

        if not ok then return nil end

        local sql_statement = "select planter_code from tp_planter where planter_id = "..pid
        local res, err, errno, sqlstate = db:query(sql_statement)
        if (not res) or (res[1] == nil) then return nil end

        mac_address =  res[1]["planter_code"]
        redis:set('mac_'..pid, mac_address)
    end


    return mac_address
end


function get_pid_with_mac_address(mac_address)
    local mysql = require "resty.mysql"
    local db, err = mysql:new()
    if not db then return nil end
    -- connect pool
    local ok, err, errno, sqlstate = db:connect {
        host = "127.0.0.1",
        port = 3306,
        database = "plant",
        user = "root",
        password = "1moodadmin",
        max_packet_size = 1024 * 1024 
    }

    if not ok then return nil end

    local sql_statement = "select planter_id from tp_planter where planter_code = \'"..mac_address.."\'"
    res, err, errno, sqlstate = db:query(sql_statement)

    if (not res) or (res[1] == nil) then return nil end
    local pid= res[1]["planter_id"]

    return pid
end

function parse_command(command_source)
    --sample "GPIO=111111&T1=0005&T2=0010&T3=2000&ADC1=100&ADC2=1734&ADC3=69&ADC4=0&ADC5=0&MD=0END"
    -- ADC1 _reserved 
    -- ADC2 -tmperuature
    -- ADC3 -humidity
    -- ADC4 -light power limit
    -- ADC5 -liquid alarm
    -- MD   -manual control option
    -- GPIO 
    local commad_parese_table = {}
    for k, v in string.gmatch(command_source, "(%w+)=(%w+)") do
        commad_parese_table[k]=v
    end

    return commad_parese_table
end

function create_command_string(pid, cmd_table)
--local out_str = string.format("PID=%0.10d&"..command_in_memory, tonumber(planter_id))
--    local cmd_defalut = "GPIO=111111&T1=0005&T2=0010&T3=2000&ADC1=100&ADC2=200&ADC3=600&ADC4=00600&ADC5=0&MD=0END"
      return string.format("PID=%0.10d&GPIO=%s&")
end

function is_md5_check_vaild(value,sign_to_compare)
    -- create md5 hash result
    local resty_md5 = require "resty.md5"
    local md5 = resty_md5:new()
    local ok = md5:update(value)
    if not ok then return nil end
    local digest = md5:final()
    local str = require "resty.string"
    local md5_result = tostring(str.to_hex(digest))

    local sign_lower = string.lower(sign_to_compare)
    if not (md5_result == sign_lower) then return nil end
    return true
end

local planter_id  = ngx.var.arg_pid
local sign        = ngx.var.arg_sign
local mac_addr    = ngx.var.arg_mac
local cmd_defalut = "GPIO=111111&T1=0005&T2=0010&T3=2000&ADC1=100&ADC2=200&ADC3=600&ADC4=00600&ADC5=0&MD=0END"
local cmd_not_def = "GPIO=011111&T1=0005&T2=0010&T3=2000&ADC1=100&ADC2=200&ADC3=600&ADC4=00600&ADC5=0&MD=0END"

-- check if planter_id or sign is exists?
if not sign then ngx.exit(400) end
if not planter_id then ngx.exit(400) end

local redis = require "resty.redis"
local red = redis:new()
--red:set_timeout(1000) -- 1 sec 
local ok, err = red:connect("127.0.0.1", 6379)
if not ok then ngx.exit(400) end

--
-- process 0:
-- first binding, return planter_id to planter
--

-- if get mac_addr from plant_machine and pid equls to 0
-- it means the first connect from the machine

if mac_addr and (tonumber(planter_id) == 0) then
    planter_id = get_pid_with_mac_address(mac_addr)

    if not planter_id then ngx.exit(400) end

    local out_str = string.format("PID=%0.10d&"..cmd_defalut, tonumber(planter_id))
    ngx.say(out_str)

    return
end

--
-- process 1:
-- check if sign is vaild or not
--

local status_args    = ngx.req.get_uri_args() -- get GET params in table
local key_table = {}  
local status_json_table = {}
-- sort the GET Params
for key,_ in pairs(status_args) do  
    table.insert(key_table,key)  
end  
table.sort(key_table)
-- create value for md5 check and create status_table for json encode
local value_for_md5_check = ''
for _,key in pairs(key_table) do
    -- sign is for compare
    if not (key == 'sign') then
        value_for_md5_check = value_for_md5_check..key..','..status_args[key]..','
    end

    -- remove sign and pid from status table for saving memory
    if not ( (key == 'sign') or (key == 'pid') ) then
        status_json_table[key] = status_args[key]
    end
end

-- get mac_address of planter_id
local mac = get_mac_with_plant_id(planter_id,red)
if not mac then ngx.exit(400) end

-- add mac address to md5 check sum
value_for_md5_check = value_for_md5_check..'mac'..','..mac

-- start md5 check
if not is_md5_check_vaild(value_for_md5_check, sign) then ngx.exit(400) end

-- 
-- process 2
-- store the status in memory if md5 check is vaild
--

-- add systime to status_table
status_json_table['time'] = os.time()
-- create status  json 
local cjson = require "cjson"
jsonString = cjson.encode(status_json_table)
-- write status json formate to memory
local ok,err = red:set('status_'..planter_id, jsonString)

--
--
-- process 3
-- parse the command from backend
--

-- get command from memory
local command_in_memory,err = red:get('command_'..planter_id)

if command_in_memory == ngx.null then
    -- default command if command not exists in memory
    --ngx.say('not in memory')
    local out_str = string.format("PID=%0.10d&"..cmd_not_def, tonumber(planter_id))
    ngx.say(out_str)
    return 
end

command_in_memory  =  cmd_defalut
ngx.say('in memory')

local command_parase_result = parse_command(command_in_memory)
local manual_option         = tonumber(string.sub(command_parase_result['MD'],0,1))

local light_threshhold      = tonumber(command_parase_result['ADC4'])
local light_current         = tonumber(status_args['ADC4'])
local light_total,err       = red:get("light_total_"..planter_id)
local increase_time,err     = red:get("time_interval")

if increase_time == ngx.null then increase_time = 2 end
if light_total   == ngx.null then light_total   = 0 end


-- increase light time
if light_threshhold < light_current then
    res:incrby("light_time_"..planter_id, tonumber(increase_time))
end

-- manual mode, just send the command in memory
if manual_option == 1 then 
    local out_str = string.format("PID=%0.10d&"..command_in_memory, tonumber(planter_id))
    --local out_str = create_command_string(planter_id, command_in_memory, increase_time)
    ngx.say(out_str)
    return
end

-- auto mode 
local current_hour = tonumber(os.date("%H"))
local light_time,err   = red:get("light_time_"..planter_id)
if light_time == ngx.null then light_time = 0 end


if (current_hour > 18) and (light_time < light_total) then
    local out_str = string.format("PID=%0.10d&"..command_in_memory, tonumber(planter_id))
    ngx.say(out_str)
end

-- ngx.log(ngx.ERR, "no user-agent found")


--[[
-- light hour module begin
-- increase light time
if not light_time then light_time = 0 end

if (current_hour > 18) and (current_hour < reach_hour) then
    command = '111100'
do

]]--

