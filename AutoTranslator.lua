_addon.name     = 'AutoTranslator'
_addon.author   = 'hikaruoshino'
_addon.version  = '0.9.2'
_addon.commands = {'at', 'autotranslate'}

local http   = require('socket.http')
local ltn12  = require('ltn12')
local json   = require('json')
local config = require('config')

http.TIMEOUT = 3

-- FFXI チャットモードIDマップ（構文修復済み）
local mode_ids = {
    say   = { [1]=true, [9]=true },
    shout = { [3]=true },
    tell  = { [12]=true, [26]=true, [27]=true },
    party = { [4]=true, [212]=true, [213]=true },
    ls    = { [5]=true, [6]=true, [214]=true, [215]=true, [216]=true },
    yell  = { [211]=true }
}

-- filler.xml (data/filler.xml) の初期設定
local defaults = {
    api_provider = 'openai', -- openai, claude, deepl
    target_lang  = 'ja',     -- 'ja': 日本語へ翻訳 / 'en': 英語へ翻訳
    api_keys = {
        openai = 'YOUR_OPENAI_API_KEY',
        claude = 'YOUR_CLAUDE_API_KEY',
        deepl  = 'YOUR_DEEPL_API_KEY'
    },
    enabled = true,
    chat_color = 207,
    modes = {
        party = true,
        ls    = true,
        tell  = true,
        shout = true,
        yell  = true,
        say   = true
    },
    blocklist = {},
    blocked_words = {
        "rmt", "gil", "http", "www", "%.com", "%.net", "%.org", "%.store", "%.shop"
    },
    dictionary = {
        lfg   = "パーティ参加希望(Looking for group)",
        lfp   = "パーティ参加希望(Looking for party)",
        inc   = "敵釣り/接近中(Incoming)",
        d3    = "死にデジョン(Blood warp)",
        d4    = "リトレース(Retrace)",
        sata  = "不意打ち&だまし討ち(Sneak Attack & Trick Attack)",
        dd    = "アタッカー(Damage Dealer)",
        voke  = "挑発(Provoke)",
        pst   = "Tellください(Please send tell)",
        tod   = "NMの没時間(Time of death)",
        ph    = "抽選対象モンスター(Place holder)",
        roe   = "エミネンス・レコード(Records of Eminence)",
        dot   = "スリップダメージ(Damage over time)",
        aoe   = "範囲攻撃(Area of effect)",
        brb   = "すぐ戻る(Be right back)",
        bbl   = "のちほど戻る(Be back later)",
        gtg   = "もう行かなくちゃ(Got to go)",
        dc    = "回線切断(Disconnected)",
        rep   = "補充要員(Replacement)",
        wipe  = "全滅(Wipeout)",
        yoyd  = "オーブ使用者総取り(Your orb your drop)",
        cs    = "イベントシーン(Cutscene)",
        ding  = "レベルアップ(Gaining a level)"
    }
}

local settings = config.load('filler.xml', defaults)
local cached_system_prompt = nil

-- システムプロンプトの動的生成
local function build_system_prompt()
    if cached_system_prompt then
        return cached_system_prompt
    end

    local lang_target = (settings.target_lang == 'en') and "natural English" or "natural Japanese"
    local prompt = string.format("You are an expert translator for FFXI game chat. Translate incoming chat into %s.\nGlossary:\n", lang_target)
    
    for key, val in pairs(settings.dictionary) do
        prompt = prompt .. string.format("- %s:%s\n", key, val)
    end
    prompt = prompt .. "Rules:\n1. Infer typos/slang from context.\n2. No extra commentary or parentheses.\n3. Output ONLY the translated text."

    cached_system_prompt = prompt
    return cached_system_prompt
end

local function invalidate_prompt_cache()
    cached_system_prompt = nil
end

local function is_mode_enabled(mode)
    for mode_name, is_active in pairs(settings.modes) do
        if is_active and mode_ids[mode_name] and mode_ids[mode_name][mode] then
            return true
        end
    end
    return false
end

local function is_blocked(speaker_name, text)
    if speaker_name and speaker_name ~= "" then
        if settings.blocklist[speaker_name:lower()] then
            return true
        end
    end

    local lower_text = text:lower()
    local normalized_text = lower_text:gsub('[%s%._%-%*%/]', '')

    for _, word in ipairs(settings.blocked_words) do
        local lower_word = word:lower()
        local clean_word = lower_word:gsub('[%s%._%-%*%/]', '')
        if lower_text:find(lower_word, 1, true) or (clean_word ~= '' and normalized_text:find(clean_word, 1, true)) then
            return true
        end
    end
    return false
end

local function translate_text(text)
    if not settings.enabled or text == '' then return end

    local provider = settings.api_provider:lower()
    local system_prompt = build_system_prompt()
    local target_lang_code = (settings.target_lang == 'en') and "EN" or "JA"
    local url, headers, req_body

    if provider == 'openai' then
        url = "https://api.openai.com/v1/chat/completions"
        headers = {
            ["Content-Type"] = "application/json",
            ["Authorization"] = "Bearer " .. (settings.api_keys.openai or "")
        }
        req_body = json.encode({
            model = "gpt-4o-mini",
            messages = {
                { role = "system", content = system_prompt },
                { role = "user", content = text }
            },
            max_tokens = 100,
            temperature = 0.0
        })

    elseif provider == 'claude' then
        url = "https://api.anthropic.com/v1/messages"
        headers = {
            ["Content-Type"] = "application/json",
            ["x-api-key"] = settings.api_keys.claude or "",
            ["anthropic-version"] = "2023-06-01"
        }
        req_body = json.encode({
            model = "claude-3-haiku-20240307",
            system = system_prompt,
            messages = { { role = "user", content = text } },
            max_tokens = 100,
            temperature = 0.0
        })

    elseif provider == 'deepl' then
        url = "https://api-free.deepl.com/v2/translate"
        headers = {
            ["Content-Type"] = "application/json",
            ["Authorization"] = "DeepL-Auth-Key " .. (settings.api_keys.deepl or "")
        }
        req_body = json.encode({
            text = { text },
            target_lang = target_lang_code
        })
    else
        return nil
    end

    headers["Content-Length"] = tostring(#req_body)

    local response_body = {}
    local res, code = http.request{
        url = url,
        method = "POST",
        headers = headers,
        source = ltn12.source.string(req_body),
        sink = ltn12.sink.table(response_body)
    }

    if code == 200 then
        local response_text = table.concat(response_body)
        local parsed = json.decode(response_text)
        if not parsed then return nil end

        if provider == 'openai' and parsed.choices and parsed.choices[1] and parsed.choices[1].message then
            return parsed.choices[1].message.content:gsub("^%s*(.-)%s*$", "%1")
        elseif provider == 'claude' and parsed.content and parsed.content[1] then
            return parsed.content[1].text:gsub("^%s*(.-)%s*$", "%1")
        elseif provider == 'deepl' and parsed.translations and parsed.translations[1] then
            return parsed.translations[1].text:gsub("^%s*(.-)%s*$", "%1")
        end
    end
    return nil
end

-- チャット受信ハンドラ
windower.register_event('incoming text', function(original, modified, mode, blocked)
    if blocked or not settings.enabled then return end
    if not is_mode_enabled(mode) then return end

    local should_translate = false
    if settings.target_lang == 'ja' then
        if original:match('[a-zA-Z]') and not original:match('[\228-\233]') then
            should_translate = true
        end
    else
        if original:match('[\228-\233]') then
            should_translate = true
        end
    end

    if should_translate then
        local speaker, msg = original:match('^%s*([^:>%(%)]+)%s*[:>](.+)$')
        local target_text = msg or original
        local sender_name = speaker and speaker:gsub('^%s*(.-)%s*$', '%1') or "Chat"

        if is_blocked(sender_name, target_text) then return end

        local translated = translate_text(target_text)
        if translated then
            local log_output = string.format('%s < %s', sender_name, translated)
            windower.add_to_chat(settings.chat_color, log_output)
        end
    end
end)

-- コマンド制御 (//at)
windower.register_event('addon command', function(cmd, ...)
    local args = {...}
    cmd = cmd and cmd:lower() or 'help'

    if cmd == 'lang' or cmd == 'language' then
        local l = args[1] and args[1]:lower()
        if l == 'ja' or l == 'japanese' then
            settings.target_lang = 'ja'
            invalidate_prompt_cache()
            config.save(settings, 'all')
            windower.add_to_chat(207, 'AutoTranslator: 翻訳先言語を [日本語 (JA)] に設定しました。')
        elseif l == 'en' or l == 'english' then
            settings.target_lang = 'en'
            invalidate_prompt_cache()
            config.save(settings, 'all')
            windower.add_to_chat(207, 'AutoTranslator: Target language set to [English (EN)].')
        else
            windower.add_to_chat(207, 'AutoTranslator: 現在の翻訳先: ' .. settings.target_lang:upper())
            windower.add_to_chat(123, '使用方法: //at lang ja (日本語へ) | //at lang en (英語へ)')
        end

    elseif cmd == 'provider' or cmd == 'ai' then
        local p = args[1] and args[1]:lower()
        if p and (p == 'openai' or p == 'claude' or p == 'deepl') then
            settings.api_provider = p
            config.save(settings, 'all')
            windower.add_to_chat(207, string.format('AutoTranslator: APIプロバイダーを [%s] に変更しました。', p:upper()))
        else
            windower.add_to_chat(207, string.format('AutoTranslator: 現在のプロバイダー: [%s]', settings.api_provider:upper()))
            windower.add_to_chat(123, '使用可能: //at provider <openai | claude | deepl>')
        end

    elseif cmd == 'block' then
        local sub = args[1] and args[1]:lower()
        local name = args[2]
        if sub == 'add' and name then
            settings.blocklist[name:lower()] = true
            config.save(settings, 'all')
            windower.add_to_chat(207, 'ブロック追加: ' .. name)
        elseif (sub == 'del' or sub == 'delete') and name then
            settings.blocklist[name:lower()] = nil
            config.save(settings, 'all')
            windower.add_to_chat(207, 'ブロック削除: ' .. name)
        else
            windower.add_to_chat(207, '--- ブロックリスト ---')
            for k in pairs(settings.blocklist) do windower.add_to_chat(207, '- ' .. k) end
        end

    elseif cmd == 'word' then
        local sub = args[1] and args[1]:lower()
        table.remove(args, 1)
        local pattern = table.concat(args, ' ')
        if sub == 'add' and pattern ~= '' then
            table.insert(settings.blocked_words, pattern)
            config.save(settings, 'all')
            windower.add_to_chat(207, 'NGワード追加: ' .. pattern)
        elseif sub == 'del' and pattern ~= '' then
            for i, w in ipairs(settings.blocked_words) do
                if w:lower() == pattern:lower() then table.remove(settings.blocked_words, i); break end
            end
            config.save(settings, 'all')
            windower.add_to_chat(207, 'NGワード削除: ' .. pattern)
        else
            windower.add_to_chat(207, '--- NGワード一覧 ---')
            for _, w in ipairs(settings.blocked_words) do windower.add_to_chat(207, '- ' .. w) end
        end

    elseif cmd == 'mode' then
        if #args == 0 or (args[1] and args[1]:lower() == 'status') then
            for m, active in pairs(settings.modes) do
                windower.add_to_chat(207, string.format('%s : %s', m:upper(), active and 'ON' or 'OFF'))
            end
            return
        end
        for m in pairs(settings.modes) do settings.modes[m] = false end
        for _, arg in ipairs(args) do
            if settings.modes[arg:lower()] ~= nil then settings.modes[arg:lower()] = true end
        end
        config.save(settings, 'all')
        windower.add_to_chat(207, '監視チャット更新完了')

    elseif cmd == 'add' then
        local key = args[1] and args[1]:lower()
        table.remove(args, 1)
        local val = table.concat(args, ' ')
        if key and val ~= '' then
            settings.dictionary[key] = val
            invalidate_prompt_cache()
            config.save(settings, 'all')
            windower.add_to_chat(207, string.format('略語追加 [%s -> %s]', key, val))
        end

    elseif cmd == 'del' then
        local key = args[1] and args[1]:lower()
        if key and settings.dictionary[key] then
            settings.dictionary[key] = nil
            invalidate_prompt_cache()
            config.save(settings, 'all')
            windower.add_to_chat(207, '略語削除 [' .. key .. ']')
        end

    elseif cmd == 'list' then
        windower.add_to_chat(207, '--- 略語一覧 ---')
        for k, v in pairs(settings.dictionary) do windower.add_to_chat(207, k .. ' : ' .. v) end

    elseif cmd == 'toggle' then
        settings.enabled = not settings.enabled
        windower.add_to_chat(207, 'AutoTranslator: ' .. (settings.enabled and 'ON' or 'OFF'))
    else
        windower.add_to_chat(207, '//at lang <ja/en> | //at provider <openai/claude/deepl> | //at block | //at word | //at mode')
    end
end)
