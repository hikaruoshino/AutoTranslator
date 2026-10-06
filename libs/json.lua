local json = {}

function json.encode(val)
    local t = type(val)
    if t == 'nil' then return 'null'
    elseif t == 'boolean' or t == 'number' then return tostring(val)
    elseif t == 'string' then
        local s = val:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n'):gsub('\r', '\\r')
        return '"' .. s .. '"'
    elseif t == 'table' then
        local is_arr = true
        local n = 0
        for k, v in pairs(val) do
            n = n + 1
            if type(k) ~= 'number' or k ~= n then is_arr = false end
        end
        local parts = {}
        if is_arr then
            for i = 1, n do table.insert(parts, json.encode(val[i])) end
            return '[' .. table.concat(parts, ',') .. ']'
        else
            for k, v in pairs(val) do table.insert(parts, json.encode(tostring(k)) .. ':' .. json.encode(v)) end
            return '{' .. table.concat(parts, ',') .. '}'
        end
    end
    return 'null'
end

function json.decode(str)
    if not str or str == '' or type(str) ~= 'string' then return nil end
    local pos = 1
    local function skip() pos = str:find('%S', pos) or (#str + 1) end
    local parse_val
    local function parse_str()
        local e = pos
        while true do
            e = str:find('"', e + 1)
            if not e then return '' end
            if str:sub(e - 1, e - 1) ~= '\\' then break end
        end
        local s = str:sub(pos + 1, e - 1)
        pos = e + 1
        return s:gsub('\\"', '"'):gsub('\\\\', '\\'):gsub('\\n', '\n'):gsub('\\r', '\r'):gsub('\\/', '/')
    end
    parse_val = function()
        skip()
        if pos > #str then return nil end
        local c = str:sub(pos, pos)
        if c == '"' then return parse_str()
        elseif c == '{' then
            pos = pos + 1; local obj = {}
            skip()
            if str:sub(pos, pos) == '}' then pos = pos + 1; return obj end
            while pos <= #str do
                skip(); local k = parse_str()
                skip(); if str:sub(pos, pos) == ':' then pos = pos + 1 end
                obj[k] = parse_val()
                skip(); local nc = str:sub(pos, pos)
                if nc == '}' then pos = pos + 1; return obj
                elseif nc == ',' then pos = pos + 1 end
            end
            return obj
        elseif c == '[' then
            pos = pos + 1; local arr = {}
            skip()
            if str:sub(pos, pos) == ']' then pos = pos + 1; return arr end
            while pos <= #str do
                table.insert(arr, parse_val())
                skip(); local nc = str:sub(pos, pos)
                if nc == ']' then pos = pos + 1; return arr
                elseif nc == ',' then pos = pos + 1 end
            end
            return arr
        elseif c == 't' and str:sub(pos, pos + 3) == 'true' then pos = pos + 4; return true
        elseif c == 'f' and str:sub(pos, pos + 4) == 'false' then pos = pos + 5; return false
        elseif c == 'n' and str:sub(pos, pos + 3) == 'null' then pos = pos + 4; return nil
        else
            -- ']' must be a terminator: otherwise '[1,2,3]' reads the last
            -- token as '3]' and tonumber returns nil.
            local e = str:find('[]%s,%}[{]', pos) or (#str + 1)
            local num = tonumber(str:sub(pos, e - 1))
            pos = e
            return num
        end
    end
    local ok, res = pcall(parse_val)
    if ok then return res else return nil end
end

return json
