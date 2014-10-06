function init_args()
local args = {}
local file_body = {}
local receive_headers = ngx.req.get_headers()
local request_method = ngx.var.request_method
--ngx.log(ngx.DEBUG,"XXXXXXXXXXXXXXXXX method:"..request_method)
if "GET" == request_method then
    args = ngx.req.get_uri_args()
elseif "POST" == request_method then
    ngx.req.read_body()
if string.sub(receive_headers["content-type"],1,20) == "multipart/form-data;" then-- if is multipart/form-data form
    content_type = receive_headers["content-type"]
    body_data = ngx.req.get_body_data()--body_data request body not string
    -- request body size > nginx config is client_body_buffer_size， buffer content to disk，client_body_buffer_size default is 8k or 16k
    if not body_data then
        local datafile = ngx.req.get_body_file()
        if not datafile then
            error_code = 1
            error_msg = "no request body found"
        else
            local fh, err = io.open(datafile, "r")
            if not fh then
                error_code = 2
                error_msg = "failed to open " .. tostring(datafile) .. "for reading: " .. tostring(err)
            else
                fh:seek("set")
                body_data = fh:read("*a")
                fh:close()
                if body_data == "" then
                        error_code = 3
                        error_msg = "request body is empty"
                end
             end
        end
    end
-- get body content
if not error_code then
local boundary = "--" .. string.sub(receive_headers["content-type"],31)
local body_data_table = explode(tostring(body_data),boundary)
local first_string = table.remove(body_data_table,1)
local last_string = table.remove(body_data_table)
for i,v in ipairs(body_data_table) do
local start_pos,end_pos,capture,capture2 = string.find(v,'Content%-Disposition: form%-data; name="(.+)"; filename="(.*)"')
if not start_pos then  --common param
local t = explode(v,"\r\n\r\n")

local temp_param_name = string.match(t[1],'(".-")')
temp_param_name = string.gsub(temp_param_name,'"','')

local temp_param_value = string.sub(t[2],1,-3)
args[temp_param_name] = temp_param_value
else
local bd = explode(v,"\r\n\r\n")
table.insert(file_body,capture.."\r\n\r\n"..string.sub(bd[2],0,-3))
end
end
end
else
args = ngx.req.get_post_args()
end
elseif "HEAD" == request_method then
ngx.log(ngx.DEBUG,"*****get head method start**********")
ngx.log(ngx.DEBUG,table_print(ngx.var))
ngx.log(ngx.DEBUG,ngx.var.CONTENT_LENGTH) --content_length
ngx.log(ngx.DEBUG,"*****get head method**********")
end
-- TODO　remove other keys , example : app_key,app_secret
-- print request code 
local uri         = ngx.var.REQUEST_URI
ngx.log(ngx.DEBUG,"\n************** "..request_method.." "..uri.."   ***********")
ngx.log(ngx.DEBUG,table_print(args))
ngx.log(ngx.DEBUG,table_print(receive_headers))
ngx.log(ngx.DEBUG,table_print(file_body))
return args,receive_headers,file_body
end
