local cmd = tostring(ngx.var.arg_cmd)
local key = tostring(ngx.var.arg_key)
local val = tostring(ngx.var.arg_val)
local commands = {
        get="get",
        set="set"
}
cmd = commands[cmd]
if not cmd then
        ngx.say("command not found!")
        ngx.exit(400)
end


if cmd == "get" then
        if not key then ngx.exit(400) end
	local capture = ngx.location.capture('/get_command', {
                args= {
                    key= key
                    }
                })
	local parser = require 'redis.parser' --require redis.parser
	local res, err = parser.parse_reply(capture.body)
	
	if res == nil then
		ngx.say("error")
	else
		ngx.say(res)
	end
end

if cmd == "set" then
	ngx.say('OK')
end
