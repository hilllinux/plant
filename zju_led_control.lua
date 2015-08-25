-- 设置 http 输出头
ngx.header.content_type = "text/plain";

local _const = {
    status_prefix = 'zju_led_status_',
    cmd_prefix    = 'zju_led_cmd_',
    cmd_defalut   = "pid=01&IO=000000&ADC1=11&ADC2=11&ADC3=11&ADC4=11END",
    periodicity   = 'zju_led_p_'   
}

-- 参数解析函数
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

-- 命令行格式化函数
function create_command_string(cmd_table)
    -- 初始化
    if cmd_table['GPIO'] == nil then cmd_table['GPIO'] = "000000" end
    if cmd_table['ADC1'] == nil then cmd_table['ADC1'] = 01  end
    if cmd_table['ADC2'] == nil then cmd_table['ADC2'] = 01  end
    if cmd_table['ADC3'] == nil then cmd_table['ADC3'] = 01  end
    if cmd_table['ADC4'] == nil then cmd_table['ADC4'] = 01  end

    local out_string = string.format("PID=%0.10d", tonumber(cmd_table["PID"]))
    out_string = out_string.."&GPIO="..cmd_table["GPIO"]
    out_string = out_string.."&ADC1="..cmd_table["ADC1"]
    out_string = out_string.."&ADC2="..cmd_table["ADC2"]
    out_string = out_string.."&ADC3="..cmd_table["ADC3"]
    out_string = out_string.."&ADC4="..cmd_table["ADC4"]
    out_string = out_string.."END"

    return out_string
end

local cjson = require "cjson"
local redis = require "resty.redis"
local red   = redis:new()

red:set_timeout(1000) -- 1 sec 
local ok, err = red:connect("127.0.0.1", 6379)
if not ok then
    ngx.log(ngx.ERR, "redis connect failed!")
    ngx.exit(400)
end

-- 获取输入参数
local request_method = ngx.var.request_method
local args = nil

if "GET" == request_method then
    args = ngx.req.get_uri_args()
elseif "POST" == request_method then
    ngx.req.read_body()
    args = ngx.req.get_post_args()
end

-- 获取不到参数，退出之
if not args then ngx.exit(404) end

-- 设备号不存在退出
local device_id = args.pid
if not device_id then ngx.exit(404) end

--[[
local command_in_memory,err = red:get(_const.cmd_prefix..device_id)

if command_in_memory == ngx.null then
    -- default command if command not exists in memory
    ngx.log(ngx.WARN, "command not in memory")
    command_in_memory = _const.cmd_defalut
end
]]

-- 获取所有周期性列表
local command_periodicity = red:lrange(_const.periodicity..device_id, 0, -1)

local now_time  = os.time()
local time_info = os.date('*t')
local command   = nil

for k, v in pairs(command_periodicity) do

    local result = cjson.decode(v)

    time_info.hour    = result.start_hour
    time_info.minutes = result.start_minutes
    local start_time  = os.time(time_info) 

    time_info.hour    = result.end_hour
    time_info.minutes = result.end_minutes
    local end_time    = os.time(time_info) 

    if start_time <= now_time and end_time >= now_time then
        command = result.cmd
    else
        command = _const.cmd_defalut
    end

end

if not command then command = _const.cmd_defalut end

-- 优先响应命令，提高接口响应速度，后续做状态存储功能
ngx.say(command);
ngx.eof();

-- 缓存状态
local jsonString = cjson.encode(args)
local ok,err = red:set(_const.status_prefix..device_id, jsonString)

-- 将redis对象放入连接池
local ok,err = red:set_keepalive(10000, 100)
