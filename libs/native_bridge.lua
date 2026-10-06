local ffi = _G.ffi
if not ffi then
    local status, lib = pcall(require, 'ffi')
    if status then
        ffi = lib
    end
end

local encoding = require('libs/encoding')

local native_bridge = {}
local native_dll = nil
local is_loaded = false

if not ffi then
    function native_bridge.init() return false end
    function native_bridge.is_available() return false end
    function native_bridge.translate_async() return false end
    function native_bridge.poll_result() return nil end
    function native_bridge.shutdown() end
    return native_bridge
end

-- FFI C Definition with pcall protection
local cdef_ok = pcall(function()
    ffi.cdef[[
        typedef struct {
            char request_id[64];
            char translated_text[2048];
            char provider_used[32];
            int success;
            char error_msg[256];
        } AT_Result;

        void AT_Init();
        void AT_Shutdown();
        int AT_TranslateAsync(
            const char* req_id,
            const char* text,
            const char* target_lang,
            const char* primary_provider,
            const char* deepl_key,
            const char* openai_key,
            const char* claude_key,
            const char* glossary_json
        );
        int AT_PollResult(AT_Result* out_result);
    ]]
end)

if not cdef_ok then
    function native_bridge.init() return false end
    function native_bridge.is_available() return false end
    function native_bridge.translate_async() return false end
    function native_bridge.poll_result() return nil end
    function native_bridge.shutdown() end
    return native_bridge
end

function native_bridge.init()
    if is_loaded then return true end

    local dll_paths = {
        windower.addon_path .. 'libs/AutoTranslatorNative.dll',
        windower.addon_path .. 'AutoTranslatorNative.dll',
        'AutoTranslatorNative.dll'
    }

    for _, path in ipairs(dll_paths) do
        local ok, dll = pcall(ffi.load, path)
        if ok and dll then
            native_dll = dll
            is_loaded = true
            pcall(native_dll.AT_Init)
            return true
        end
    end

    return false
end

function native_bridge.is_available()
    return is_loaded and native_dll ~= nil
end

function native_bridge.translate_async(req_id, text, settings)
    if not is_loaded or not native_dll then return false end

    local deepl_key = settings.api_keys and settings.api_keys.deepl or ""
    local openai_key = settings.api_keys and settings.api_keys.openai or ""
    local claude_key = settings.api_keys and settings.api_keys.claude or ""
    local primary = (settings.api_provider or 'deepl'):lower()
    local target = (settings.target_lang or 'ja'):lower()

    local ok, res = pcall(function()
        return native_dll.AT_TranslateAsync(
            tostring(req_id or "0"),
            encoding.to_utf8(text),
            target,
            primary,
            deepl_key,
            openai_key,
            claude_key,
            "{}"
        )
    end)

    return ok and (res == 1)
end

local result_buffer = nil
pcall(function() result_buffer = ffi.new("AT_Result") end)

function native_bridge.poll_result()
    if not is_loaded or not native_dll or not result_buffer then return nil end

    local ok, has_res = pcall(function()
        return native_dll.AT_PollResult(result_buffer)
    end)

    if ok and has_res == 1 then
        local req_id = ffi.string(result_buffer.request_id)
        local trans_text = ffi.string(result_buffer.translated_text)
        local prov = ffi.string(result_buffer.provider_used)
        local success = (result_buffer.success == 1)
        local err_msg = ffi.string(result_buffer.error_msg)

        return {
            id = req_id,
            text = encoding.sjis(trans_text),
            provider = prov,
            success = success,
            error = err_msg
        }
    end

    return nil
end

function native_bridge.shutdown()
    if is_loaded and native_dll then
        pcall(native_dll.AT_Shutdown)
    end
end

return native_bridge
