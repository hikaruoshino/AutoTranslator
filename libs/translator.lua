local http = nil
local status, https_lib = pcall(require, 'ssl.https')
if status and https_lib then
    http = https_lib
else
    local status_soc, soc_http = pcall(require, 'socket.http')
    if status_soc then http = soc_http end
end

local ltn12         = require('ltn12')
local json          = require('libs/json')
local encoding      = require('libs/encoding')
local cache         = require('libs/cache')
local native_bridge = require('libs/native_bridge')
local helper_bridge = require('libs/helper_bridge')
local glossary      = require('libs/glossary')
local autotrans     = require('libs/autotrans')

if http then http.TIMEOUT = 2.5 end

local translator = {}
local cached_system_prompt = nil
local helper_texts = {}   -- [req_id] = 翻訳元の文 (ヘルパーの結果をキャッシュに入れるため)

native_bridge.init()

-- FFXI 固有名詞の対応表を書き出す。ヘルパーがこれを DeepL の用語集として登録する
-- (英語→日本語だけ。DeepL の用語集は 1 つまでなので、日本語→英語は glossary.replace_ja で地名を置き換える)
do
    pcall(function()
        local f = io.open(windower.addon_path .. 'data/glossary_en_ja.tsv', 'wb')
        if f then
            f:write(glossary.to_tsv())
            f:close()
        end
    end)
end

-- 翻訳ヘルパー (別プロセスの PowerShell) を起動する。起動できなければ従来の Lua HTTP で翻訳する
local helper_ok, helper_err = helper_bridge.start()

function translator.helper_status()
    return helper_ok, helper_err
end

local function build_system_prompt(settings)
    if cached_system_prompt then return cached_system_prompt end
    local lang_target = (settings.target_lang == 'en') and "natural English" or "natural Japanese"
    local prompt = string.format("You are an expert translator for FFXI game chat. Translate incoming chat into %s.\nGlossary:\n", lang_target)
    local dict = cache.get_dictionary()
    for key, val in pairs(dict) do
        prompt = prompt .. string.format("- %s:%s\n", key, val)
    end
    prompt = prompt .. "Rules:\n1. Infer typos/slang from context.\n2. No extra commentary or parentheses.\n3. Output ONLY the translated text."
    cached_system_prompt = prompt
    return cached_system_prompt
end

function translator.invalidate_prompt()
    cached_system_prompt = nil
    cache.invalidate()
end

function translator.has_native()
    return native_bridge.is_available()
end

function translator.poll_native()
    if native_bridge.is_available() then
        return native_bridge.poll_result()
    end
    return nil
end

-- DLL かヘルパーから届いた結果を 1 件返す (無ければ nil)。text / error は Shift-JIS
function translator.poll_result()
    local res = translator.poll_native()
    if res then return res end

    local h = helper_bridge.poll()
    if not h then return nil end

    local src = helper_texts[h.id]
    helper_texts[h.id] = nil
    if h.success and h.text ~= '' then
        if src then cache.set(src, h.text) end
        return { id = h.id, success = true, text = encoding.sjis(h.text), provider = h.provider }
    end
    return { id = h.id, success = false, error = encoding.sjis(h.error or 'translation failed') }
end

-- 日本語の発言に定型文が入っているとき用: 翻訳はせず、定型文だけ日本語の表記にした文を返す (Shift-JIS)。
-- 定型文が無ければ nil
function translator.render_autotranslate(text)
    local marked, toks = autotrans.extract(encoding.to_utf8(text))
    if not marked then return nil end
    return encoding.sjis(autotrans.render(marked, toks, 'ja'))
end

function translator.shutdown()
    helper_bridge.stop()
    native_bridge.shutdown()
end

local function execute_single_provider(provider, text, settings)
    if not http then return nil, "HTTP library unavailable" end
    local raw_key = settings.api_keys and settings.api_keys[provider] or ""
    local api_key = encoding.trim_ascii(raw_key):gsub('^["\'](.-)["\']$', '%1')

    if api_key == "" or api_key:find("YOUR_") then
        return nil, string.format("[%s Key Missing]", provider:upper())
    end

    local system_prompt = build_system_prompt(settings)
    local target_lang_code = (settings.target_lang == 'en') and "EN" or "JA"
    local utf8_text = encoding.to_utf8(text)
    local url, headers, req_body

    local user_agent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AutoTranslator/3.1.2"

    if provider == 'openai' then
        url = "https://api.openai.com/v1/chat/completions"
        headers = {
            ["Content-Type"] = "application/json",
            ["Authorization"] = "Bearer " .. api_key,
            ["User-Agent"] = user_agent,
            ["Connection"] = "keep-alive"
        }
        req_body = json.encode({
            model = "gpt-4o-mini",
            messages = { { role = "system", content = system_prompt }, { role = "user", content = utf8_text } },
            max_tokens = 60, temperature = 0.0
        })
    elseif provider == 'claude' then
        url = "https://api.anthropic.com/v1/messages"
        headers = {
            ["Content-Type"] = "application/json",
            ["x-api-key"] = api_key,
            ["anthropic-version"] = "2023-06-01",
            ["User-Agent"] = user_agent,
            ["Connection"] = "keep-alive"
        }
        req_body = json.encode({
            model = "claude-3-haiku-20240307", system = system_prompt,
            messages = { { role = "user", content = utf8_text } },
            max_tokens = 60, temperature = 0.0
        })
    elseif provider == 'deepl' then
        if api_key:sub(-3) == ':fx' then
            url = "https://api-free.deepl.com/v2/translate"
        else
            url = "https://api.deepl.com/v2/translate"
        end
        headers = {
            ["Content-Type"] = "application/json",
            ["Authorization"] = "DeepL-Auth-Key " .. api_key,
            ["User-Agent"] = user_agent,
            ["Connection"] = "keep-alive"
        }
        req_body = json.encode({ text = { utf8_text }, target_lang = target_lang_code })
    else
        return nil, "Invalid provider"
    end

    headers["Content-Length"] = tostring(#req_body)
    local response_body = {}
    local res, code = http.request{
        url = url, method = "POST", headers = headers,
        source = ltn12.source.string(req_body), sink = ltn12.sink.table(response_body)
    }

    local num_code = tonumber(code) or 0

    if num_code == 200 then
        local response_text = table.concat(response_body)
        local parsed = json.decode(response_text)
        if not parsed then return nil, "JSON decode failed" end

        local result_str = nil
        if provider == 'openai' and parsed.choices then
            local first_choice = rawget(parsed.choices, 1)
            if first_choice and first_choice.message then
                result_str = first_choice.message.content
            end
        elseif provider == 'claude' and parsed.content then
            local first_content = rawget(parsed.content, 1)
            if first_content and first_content.text then
                result_str = first_content.text
            end
        elseif provider == 'deepl' and parsed.translations then
            local first_trans = rawget(parsed.translations, 1)
            if first_trans and first_trans.text then
                result_str = first_trans.text
            end
        end

        if result_str then
            -- UTF-8 のまま返す (キャッシュは辞書と同じ UTF-8 で持ち、表示直前に 1 回だけ Shift-JIS にする)
            return encoding.trim_ascii(result_str), nil
        end
    end

    return nil, string.format("HTTP %s", tostring(code))
end

local function schedule_async(fn)
    if coroutine and type(coroutine.schedule) == 'function' then
        coroutine.schedule(fn, 0)
    else
        fn()
    end
end

function translator.translate(text, settings, req_id, callback)
    if not settings.enabled or not text or text == '' then return nil end

    -- 1. Check local dictionary / memory cache (0ms instant return)
    local local_res = cache.get(text)
    if local_res then
        local sjis_text = encoding.sjis(local_res)
        if type(callback) == 'function' then callback(sjis_text, nil) end
        return sjis_text
    end

    -- 1.2 FFXI の定型文辞書 (Tab 変換) を、ゲームと同じ表記にする
    --     英語→日本語: [100バイン紙幣] / 日本語→英語: [100 Byne Bill]
    local lang = (settings.target_lang == 'en') and 'en' or 'ja'
    local at_send, at_xml, at_terms
    do
        local at_marked, at_toks = autotrans.extract(encoding.to_utf8(text))
        if at_marked then
            -- 定型文だけの発言は、API を使わずにその場で出す
            if not autotrans.has_other_text(at_marked, lang) then
                local plain = autotrans.render(at_marked, at_toks, lang)
                cache.set(text, plain)
                local sjis_text = encoding.sjis(plain)
                if type(callback) == 'function' then callback(sjis_text, nil) end
                return sjis_text
            end
            at_send, at_xml, at_terms = autotrans.to_request(at_marked, at_toks, lang)
        end
    end

    -- 1.5 FFXI 固有名詞 (エリア名など) を正しい日本語名にする。英語→日本語のときだけ
    local marked, found
    if settings.target_lang == 'ja' and not at_send then
        marked, found = glossary.protect(encoding.to_utf8(text))
        if marked then
            -- "Norg" のように名前だけの発言は、API を使わずにその場で訳す
            local plain = glossary.to_plain(marked, found)
            if not plain:find('[A-Za-z]') then
                cache.set(text, plain)
                local sjis_text = encoding.sjis(plain)
                if type(callback) == 'function' then callback(sjis_text, nil) end
                return sjis_text
            end
        end
    end

    -- 2. Native C++ DLL Multithreaded Async Engine (0ms main thread delay)
    if native_bridge.is_available() then
        local submitted = native_bridge.translate_async(req_id or "0", text, settings)
        if submitted then
            if type(callback) == 'function' then callback("ASYNC_NATIVE_SUBMITTED", nil) end
            return "ASYNC_NATIVE_SUBMITTED"
        end
    end

    -- 3. 翻訳ヘルパー (別プロセス) に依頼する。結果は poll_result() で受け取るので、ゲームは止まらない
    if helper_bridge.is_started() and req_id then
        -- 英語→日本語: 元の英文をそのまま送る。地名は DeepL では用語集で、OpenAI / Claude では指示文で正しく訳させる。
        --              定型文入りのときは、地名以外の定型文を <x>[日本語名]</x> で囲んだ文を送る (at_xml = true)
        -- 日本語→英語: 地名をゲームの英語名に置き換えた文を送る (ジュノ港 → Port Jeuno)
        local send_text = at_send or encoding.to_utf8(text)
        local terms
        if lang == 'en' then
            local place_terms
            send_text, place_terms = glossary.replace_ja(send_text)
            terms = table.concat({ at_terms or '', place_terms }, '; '):gsub('^; ', ''):gsub('; $', '')
        else
            terms = at_terms or (marked and glossary.describe(found)) or ''
        end
        if helper_bridge.submit(req_id, send_text, settings, build_system_prompt(settings), terms, at_xml) then
            helper_texts[req_id] = text
            if type(callback) == 'function' then callback("ASYNC_HELPER_SUBMITTED", nil) end
            return "ASYNC_HELPER_SUBMITTED"
        end
    end

    -- 4. Fallback Lua Http pipeline (ヘルパーが使えないときだけ。返事を待つ間ゲームが止まる)
    schedule_async(function()
        local provider_order = {}
        local primary = (settings.api_provider or 'deepl'):lower()

        if primary == 'deepl' then
            provider_order = {'deepl', 'openai', 'claude'}
        elseif primary == 'openai' then
            provider_order = {'openai', 'deepl', 'claude'}
        elseif primary == 'claude' then
            provider_order = {'claude', 'deepl', 'openai'}
        else
            provider_order = {'deepl', 'openai', 'claude'}
        end

        local last_err = nil
        for _, prov in ipairs(provider_order) do
            local res, err = execute_single_provider(prov, text, settings)
            if res and res ~= '' then
                cache.set(text, res)
                if type(callback) == 'function' then callback(encoding.sjis(res), nil) end
                return
            else
                if err and not err:find("Missing") then
                    last_err = string.format("%s (%s)", prov:upper(), err)
                end
            end
        end

        local final_err = last_err or "DeepL / OpenAI API Keys missing or failed"
        if type(callback) == 'function' then callback(nil, final_err) end
    end)

    if type(callback) == 'function' then callback("ASYNC_LUA_SCHEDULED", nil) end
    return "ASYNC_LUA_SCHEDULED"
end

return translator
