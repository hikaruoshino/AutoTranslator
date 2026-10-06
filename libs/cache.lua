local encoding = require('libs/encoding')
local json     = require('libs/json')

local cache = {}
local memory_cache = {}
local dictionary = {}

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
    memory_cache = {}

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

    if memory_cache[clean_lower] then return memory_cache[clean_lower] end
    if dictionary[clean_lower] then
        local res = dictionary[clean_lower]
        memory_cache[clean_lower] = res
        return res
    end

    return nil
end

function cache.set(text, translation)
    if not text or not translation or text == '' or translation == '' then return end
    memory_cache[encoding.trim_ascii(text):lower()] = translation
end

function cache.add_dict_item(key, value)
    if not key or not value or key == '' or value == '' then return end
    local k_lower = encoding.trim_ascii(key):lower()
    dictionary[k_lower] = value
    memory_cache[k_lower] = value
    save_json_dictionary()
end

function cache.del_dict_item(key)
    if not key or key == '' then return false end
    local k_lower = encoding.trim_ascii(key):lower()
    if dictionary[k_lower] ~= nil then
        dictionary[k_lower] = nil
        memory_cache[k_lower] = nil
        save_json_dictionary()
        return true
    end
    return false
end

function cache.get_dictionary()
    return dictionary
end

function cache.invalidate()
    memory_cache = {}
end

return cache
