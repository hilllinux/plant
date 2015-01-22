--
--  tool functions
--

function trim (s)
    return (string.gsub(s, "^%s*(.-)%s*$", "%1"))
end

function mysql_query(sql_statement)
        local mysql = require "resty.mysql"
        local db, err = mysql:new()
        if not db then return nil end
        db:set_timeout(1000)

        -- connect pool
        ngx.log(ngx.DEBUG, "mysql query"..sql_statement)

        local ok, err, errno, sqlstate = db:connect {
            host = "127.0.0.1",
            port = 3306,
            database = "plant",
            user = "root",
            password = "1moodadmin",
            max_packet_size = 1024 * 1024 
        }

        if not ok then
            ngx.log(ngx.ERR, "mysql connect error!")
            return nil 
        end

        local res, err, errno, sqlstate = db:query(sql_statement)
        if not res then
            ngx.log(ngx.WARN, "mysql query no result !")
            return nil 
        end

        return res
end

function get_mac_with_plant_id(pid,redis)
    local mac_address,err = redis:get('mac_'..pid)

    if mac_address == ngx.null then

        ngx.log(ngx.DEBUG, "mac_"..pid.." not find in memory so get it from mysql !")

        local sql_statement = "select planter_code from tp_planter where planter_id = "..pid
        local res = mysql_query(sql_statement)

        if (not res) or (res[1] == nil) then
            ngx.log(ngx.ERR, "mac not find in mysql with pid"..pid.." !")
            return nil 
        end

        mac_address =  res[1]["planter_code"]
        redis:set('mac_'..pid, mac_address)
    end


    return mac_address
end


function get_pid_with_mac_address(mac_address)

    local sql_statement = "select planter_id from tp_planter where planter_code = \'"..mac_address.."\'"
    local res = mysql_query(sql_statement)

    if (not res) or (res[1] == nil) then
        ngx.log(ngx.WARN, "mac: "..mac_address.."not find in mysql,you need create it !")
        return nil
    end

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

function create_command_string(cmd_table)
--local out_str = string.format("PID=%0.10d&"..command_in_memory, tonumber(planter_id))
--    local cmd_defalut = "GPIO=111111&T1=0005&T2=0010&T3=2000&ADC1=100&ADC2=200&ADC3=600&ADC4=00600&ADC5=0&MD=0END"
      if cmd_table['GPIO'] == nil then cmd_table['GPIO'] = "010000" end
      if cmd_table['T1']   == nil then cmd_table['T1'] = "0005"     end
      if cmd_table['T2']   == nil then cmd_table['T2'] = "0010"     end
      if cmd_table['ADC1'] == nil then cmd_table['ADC1'] = 100      end
      if cmd_table['ADC2'] == nil then cmd_table['ADC2'] = 200      end
      if cmd_table['ADC3'] == nil then cmd_table['ADC3'] = 600      end
      if cmd_table['ADC4'] == nil then cmd_table['ADC4'] = "00600"  end
      if cmd_table['ADC5'] == nil then cmd_table['ADC5'] = 0        end

      local out_string = string.format("PID=%0.10d", tonumber(cmd_table["PID"]))
      out_string = out_string.."&GPIO="..cmd_table["GPIO"]
      out_string = out_string.."&T1="..cmd_table["T1"]
      out_string = out_string.."&T2="..cmd_table["T2"]
      out_string = out_string.."&T3="..cmd_table["T3"]
      out_string = out_string.."&ADC1="..cmd_table["ADC1"]
      out_string = out_string.."&ADC2="..cmd_table["ADC2"]
      out_string = out_string.."&ADC3="..cmd_table["ADC3"]
      out_string = out_string.."&ADC4="..cmd_table["ADC4"]
      out_string = out_string.."&ADC5="..cmd_table["ADC5"]
      out_string = out_string.."&MD="..cmd_table["MD"]
      out_string = out_string.."END"

      ngx.log(ngx.DEBUG, "out_string:"..out_string)
      return out_string
end

function is_md5_check_vaild(value,sign_to_compare)
    -- create md5 hash result
    local resty_md5 = require "resty.md5"
    local md5 = resty_md5:new()
    local ok = md5:update(value)

    if not ok then
        ngx.log(ngx.ERR, "md5 module failed!")
        return nil
    end

    local digest = md5:final()
    local str = require "resty.string"
    local md5_result = tostring(str.to_hex(digest))

    local sign_lower = string.lower(sign_to_compare)

    if not (md5_result == sign_lower) then
        ngx.log(ngx.WARN,"value: "..value..",md5:"..md5_result.."; check sum failed!")
        return false
    end

    return true
end

local planter_id  = ngx.var.arg_pid
local sign        = ngx.var.arg_sign
local mac_addr    = ngx.var.arg_mac
local cmd_defalut = "GPIO=010000&T1=0005&T2=0010&T3=2000&ADC1=100&ADC2=200&ADC3=600&ADC4=00600&ADC5=0&MD=0END"
local params_limit= 8
--local cmd_not_def = "GPIO=011111&T1=0005&T2=0010&T3=2000&ADC1=100&ADC2=200&ADC3=600&ADC4=00600&ADC5=0&MD=0END"

-- check if planter_id or sign is exists?
if (not sign) or (not planter_id) then
    ngx.log(ngx.DEBUG,"query without sign and pid!")
    ngx.exit(400) 
end


local redis = require "resty.redis"
local red = redis:new()
red:set_timeout(1000) -- 1 sec 
local ok, err = red:connect("127.0.0.1", 6379)
if not ok then
    ngx.log(ngx.ERR, "redis connect failed!")
    ngx.exit(400)
end

--
-- process 0:
-- first binding, return planter_id to planter
--

-- if get mac_addr from plant_machine and pid equls to 0
-- it means the first connect from the machine
planter_id = tonumber(planter_id)
if planter_id == 0 then
    if type(mac_addr) ~= "string" then ngx.exit(400) end -- mac_address not exists!!

    ngx.log(ngx.DEBUG, "process 0 "..type(mac_address))

    planter_id = get_pid_with_mac_address(mac_addr)

    if not planter_id then 
        ngx.log(ngx.WARN, "pid not find when first time connect")
        ngx.exit(400) 
    end

    local out_str = string.format("PID=%0.10d&"..cmd_defalut, tonumber(planter_id))
    red:set("command_"..tonumber(planter_id)) -- init command
    ngx.say(out_str)

    ngx.log(ngx.DEBUG, "process 0 done with pid "..planter_id.." inited to client")
    return
end

--
-- process 1:
-- check if sign is vaild or not
--

ngx.log(ngx.DEBUG, "process 1")
local status_args    = ngx.req.get_uri_args() -- get GET params in table
local key_table = {}  
local status_json_table = {}
-- sort the GET Params
local params_counter = 0
for key,_ in pairs(status_args) do  
    table.insert(key_table,key)  
    if type(_) == "boolean" then
        ngx.log(ngx.DEBUG,"planter_id :"..planter_id.." machine get param error!")
        ngx.exit(400)
    end
    params_counter = params_counter + 1
end  
table.sort(key_table)
ngx.log(ngx.DEBUG,"planter_id : "..planter_id.." params counter: "..params_counter)

if params_counter ~= params_limit then
    ngx.log(ngx.DEBUG,"planter_id :"..planter_id.." param num wrong!")
    ngx.exit(400)
end
--pid=0000002004&IO=011111&ADC1=100&ADC2=0&ADC3=74&ADC4=0&ADC5=0&sign=ae4cf8c7b188ec77a2ec251200d23962
--pid=1&IO=101000&ADC1=100&ADC2=144&ADC3=152&ADC4=381&ADC5=0&sign=8bb3a85197b264d094ada49af1632127

-- create value for md5 check and create status_table for json encode
--[[
local cjson = require "cjson"
local jsonString = cjson.encode(status_args)
ngx.log(ngx.DEBUG,"planter_id :"..planter_id..";size: "..params_counter.."; content = "..jsonString)
]]--



-- get mac_address of planter_id
-- salt for md5 check sum
local mac = get_mac_with_plant_id(tonumber(planter_id),red)
if not mac then ngx.exit(400) end
mac = string.lower(mac)

-- md5 check process
-- format : ADC1,100,ADC2,1734,ADC3,74,ADC4,0,ADC5,0,IO,011111,pid,0000002004,mac,001fa880740b
local value_for_md5_check = ''
for _,key in pairs(key_table) do
    -- sign is for compare
    -- not in format list
    if not (key == 'sign') then
        value_for_md5_check = value_for_md5_check..key..','..status_args[key]..','
    end
    -- remove sign and pid from status table for saving memory
    if not ( (key == 'sign') or (key == 'pid') ) then
        status_json_table[key] = status_args[key]
    end
end

-- add mac address to md5 check sum
value_for_md5_check = value_for_md5_check..'mac'..','..mac

-- start md5 check
ngx.log(ngx.DEBUG, "...md5 check sum process")
if not is_md5_check_vaild(value_for_md5_check, sign) then ngx.exit(400) end

-- 
-- process 2
-- store the status in memory if md5 check is vaild
--

-- add systime to status_table
status_json_table['time'] = os.time()
-- create status  json 
local cjson = require "cjson"
local jsonString = cjson.encode(status_json_table)
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
    ngx.log(ngx.WARN, "command not in memory")
    command_in_memory = cmd_defalut
    red:set("command_"..planter_id,command_in_memory)
end

local command_parse_result  = parse_command(command_in_memory)
local manual_option         = tonumber(string.sub(command_parse_result['MD'],0,1))
local increase_time,err     = red:get("time_interval")

if increase_time == ngx.null then
    ngx.log(ngx.WARN, "time_interval is not set")
    red:set("time_interval",2000)
    increase_time = 2000 
end


-- change command table
command_parse_result["PID"]= planter_id
command_parse_result["T3"] = string.format("%0.4d",increase_time)
command_parse_result["MD"] = manual_option

local ok, err = red:set_keepalive(10000, 100)

local out_str = create_command_string(command_parse_result)
ngx.say(out_str)

