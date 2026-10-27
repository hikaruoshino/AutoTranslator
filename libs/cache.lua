local encoding = require('libs/encoding')
local json     = require('libs/json')

local cache = {}
local dictionary = {}

-- 翻訳の記憶は 2 世代。1 世代が LIMIT 件になったら古いほうを捨てる (長時間でも増え続けない)
local CACHE_LIMIT = 2000
local gen_a, gen_b, count_a = {}, {}, 0

local function mem_get(k)
    local v = gen_a[k]
    if v ~= nil then return v end
    v = gen_b[k]
    if v ~= nil then gen_a[k] = v; count_a = count_a + 1 end   -- 使われたものは新しい世代へ
    return v
end

local function mem_set(k, v)
    if gen_a[k] == nil then count_a = count_a + 1 end
    gen_a[k] = v
    if count_a >= CACHE_LIMIT then gen_b, gen_a, count_a = gen_a, {}, 0 end
end

local function mem_del(k)
    if gen_a[k] ~= nil then gen_a[k] = nil; count_a = count_a - 1 end
    gen_b[k] = nil
end

local function mem_clear() gen_a, gen_b, count_a = {}, {}, 0 end

local dict_file_path = windower.addon_path .. 'data/dictionary.json'

local function load_json_dictionary()
    local f = io.open(dict_file_path, 'r')
    if f then
        local content = f:read('*all')
        f:close()
        local parsed = json.decode(content)
        if type(parsed) == 'table' then
            for k, v in pairs(parsed) do
                if type(k) == 'string' and type(v) == 'string' then
                    dictionary[encoding.trim_ascii(k):lower()] = v
                end
            end
        end
    end
end

local function save_json_dictionary()
    local f = io.open(dict_file_path, 'w')
    if f then
        f:write(json.encode(dictionary))
        f:close()
    end
end

function cache.init(dict_settings)
    dictionary = {}
    mem_clear()

    if type(dict_settings) == 'table' then
        for k, v in pairs(dict_settings) do
            if type(k) == 'string' and type(v) == 'string' then
                dictionary[encoding.trim_ascii(k):lower()] = v
            end
        end
    end

    load_json_dictionary()
end

function cache.get(text)
    if not text or text == '' then return nil end
    local clean_lower = encoding.trim_ascii(text):lower()

    local hit = mem_get(clean_lower)
    if hit then return hit end
    if dictionary[clean_lower] then
        local res = dictionary[clean_lower]
        mem_set(clean_lower, res)
        return res
    end

    return nil
end

function cache.set(text, translation)
    if not text or not translation or text == '' or translation == '' then return end
    mem_set(encoding.trim_ascii(text):lower(), translation)
end

function cache.add_dict_item(key, value)
    if not key or not value or key == '' or value == '' then return end
    local k_lower = encoding.trim_ascii(key):lower()
    dictionary[k_lower] = value
    mem_set(k_lower, value)
    save_json_dictionary()
end

function cache.del_dict_item(key)
    if not key or key == '' then return false end
    local k_lower = encoding.trim_ascii(key):lower()
    if dictionary[k_lower] ~= nil then
        dictionary[k_lower] = nil
        mem_del(k_lower)
        save_json_dictionary()
        return true
    end
    return false
end

function cache.get_dictionary()
    return dictionary
end

function cache.invalidate()
    mem_clear()
end

return cache
