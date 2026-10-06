_addon.name     = 'AutoTranslator'
_addon.author   = 'Prototype'
_addon.version  = '3.1.2'
_addon.commands = {'at', 'autotranslate'}

local config      = require('config')
local encoding    = require('libs/encoding')
local lang_detect = require('libs/lang_detect')
local chat_parser = require('libs/chat_parser')
local cache       = require('libs/cache')
local translator  = require('libs/translator')
local hud         = require('libs/hud')

-- add_to_chat で出した行は、少し遅れて incoming text に戻ってくる。
-- 自分の出力を翻訳し直さないよう、出した行を数秒間覚えておき、同じ行が戻ってきたら無視する
local ECHO_HOLD_SEC = 5
local recent_emits = {}   -- [出した行] = 覚えておく期限 (os.clock)

local function emit(color, text)
    text = tostring(text)
    local now = os.clock()
    for line, expire in pairs(recent_emits) do   -- 戻ってこなかった行を掃除する
        if expire < now then recent_emits[line] = nil end
    end
    recent_emits[text] = now + ECHO_HOLD_SEC
    windower.add_to_chat(color, text)
end

local function is_own_echo(text)
    local expire = recent_emits[text]
    if not expire then return false end
    recent_emits[text] = nil
    return os.clock() <= expire
end

--------------------------------------------------------------------------------
-- チャットモードマップ動的生成
--------------------------------------------------------------------------------
local mode_id_to_name = {}
local function reg_modes(name, ids)
    for _, id in ipairs(ids) do
        mode_id_to_name[id] = name
    end
end
-- 番号は Windower の res/chat.lua (自分の発言 = outgoing / 他人の発言 = incoming) に合わせる
reg_modes('say',   {1, 9})
reg_modes('shout', {2, 10})
reg_modes('yell',  {3, 11})
reg_modes('tell',  {4, 12})
reg_modes('party', {5, 13})
reg_modes('ls',    {6, 14, 213, 214})   -- リンクシェル / リンクシェル2
reg_modes('unity', {211, 212})
reg_modes('echo',  {206})               -- /echo (会話ではないので既定は翻訳しない)

--------------------------------------------------------------------------------
-- 設定初期化 & 完全深層サニタイズ
--------------------------------------------------------------------------------
local defaults = {
    api_provider = 'deepl',
    target_lang  = 'ja',
    api_keys = {
        openai = 'YOUR_OPENAI_API_KEY',
        claude = 'YOUR_CLAUDE_API_KEY',
        deepl  = 'YOUR_DEEPL_API_KEY'
    },
    enabled = true,
    hud_enabled = false,
    chat_color = 207,
    modes = {
        party = true, ls = true, tell = true, shout = true, yell = true, say = true, unity = true, echo = false
    },
    blocklist = {},
    blocked_words = {
        'rmt', 'gil', 'http', 'www', '%.com', '%.net', '%.org'
    },
    dictionary = {
        hello = "こんにちは",
        lfg   = "Looking for group",
        lfp   = "Looking for party",
        inc   = "Incoming mob",
        voke  = "Provoke"
    },
    hud = {
        pos = { x = 20, y = 20 },
        text = { size = 10, font = 'Arial' },
        bg = { alpha = 180, red = 0, green = 0, blue = 0 }
    }
}

local settings = config.load('filler.xml', defaults)

local function sanitize_settings()
    if type(settings.blocked_words) == 'table' then
        local clean_bw = {}
        local seen = {}
        for k, v in pairs(settings.blocked_words) do
            local item = nil
            if type(v) == 'string' and v ~= '' then item = v:lower()
            elseif type(k) == 'string' and k ~= '' and (v == true or v == 'true') then item = k:lower() end
            if item and not seen[item] then seen[item] = true; table.insert(clean_bw, item) end
        end
        settings.blocked_words = clean_bw
    else
        settings.blocked_words = { 'rmt', 'gil', 'http', 'www', '%.com', '%.net', '%.org' }
    end

    if type(settings.blocklist) == 'table' then
        local clean_bl = {}
        local seen = {}
        for k, v in pairs(settings.blocklist) do
            local item = nil
            if type(v) == 'string' and v ~= '' then item = v:lower()
            elseif type(k) == 'string' and k ~= '' and (v == true or v == 'true') then item = k:lower() end
            if item and not seen[item] then seen[item] = true; table.insert(clean_bl, item) end
        end
        settings.blocklist = clean_bl
    else
        settings.blocklist = {}
    end

    local valid_modes = { party = true, ls = true, tell = true, shout = true, yell = true, say = true, unity = true, echo = false }
    local clean_modes = {}
    if type(settings.modes) == 'table' then
        for m in pairs(valid_modes) do clean_modes[m] = (settings.modes[m] == true) end
    else clean_modes = valid_modes end
    settings.modes = clean_modes

    local valid_providers = { openai = true, claude = true, deepl = true }
    local clean_keys = { openai = 'YOUR_OPENAI_API_KEY', claude = 'YOUR_CLAUDE_API_KEY', deepl = 'YOUR_DEEPL_API_KEY' }
    if type(settings.api_keys) == 'table' then
        for p in pairs(valid_providers) do
            if type(settings.api_keys[p]) == 'string' then clean_keys[p] = settings.api_keys[p] end
        end
    end
    settings.api_keys = clean_keys

    if type(settings.dictionary) == 'table' then
        local clean_dict = {}
        for k, v in pairs(settings.dictionary) do
            if type(k) == 'string' and type(v) == 'string' then clean_dict[k:lower()] = v end
        end
        settings.dictionary = clean_dict
    else
        settings.dictionary = { hello = "こんにちは", lfg = "Looking for group", lfp = "Looking for party", inc = "Incoming mob", voke = "Provoke" }
    end
end
sanitize_settings()

local function safe_save_settings()
    sanitize_settings()
    local ok, err = pcall(function() config.save(settings, 'all') end)
    if not ok then
        emit(123, encoding.sjis('[AutoTranslator] 設定保存通知: ') .. tostring(err))
    end
end

-- 各モジュールの初期化
cache.init(settings.dictionary)

hud.init(settings, function(pos_x, pos_y)
    if not settings.hud then settings.hud = {} end
    if not settings.hud.pos then settings.hud.pos = {} end
    if settings.hud.pos.x ~= pos_x or settings.hud.pos.y ~= pos_y then
        settings.hud.pos.x = pos_x
        settings.hud.pos.y = pos_y
        safe_save_settings()
    end
end)

--------------------------------------------------------------------------------
-- 内部状態追跡テーブル (ネイティブ非同期レスポンス受信用)
--------------------------------------------------------------------------------
local pending_requests = {}
local request_counter = 0

--------------------------------------------------------------------------------
-- フィルタリング判定
--------------------------------------------------------------------------------
-- 会話のチャットだけを翻訳する。一覧に無い番号 (システムメッセージ・NPC の会話・戦闘ログ・
-- ほかのアドオンの表示など) は翻訳しない
local function is_mode_enabled(mode)
    local name = mode_id_to_name[tonumber(mode) or -1]
    if not name then return false end
    return settings.modes[name] == true
end

local function is_blocked(speaker_name, text)
    if speaker_name and speaker_name ~= "" then
        local lower_speaker = speaker_name:lower()
        for _, name in ipairs(settings.blocklist) do
            if name == lower_speaker then return true end
        end
    end
    local lower_text = text:lower()
    for _, word in ipairs(settings.blocked_words) do
        if lower_text:find(word:lower(), 1, true) then return true end
    end
    return false
end

--------------------------------------------------------------------------------
-- 非同期の翻訳結果 (Native DLL / 翻訳ヘルパー) のポーリング (Prerender / Frame Event)
--------------------------------------------------------------------------------
windower.register_event('prerender', function()
    local res = translator.poll_result()
    while res do
        if res.id and pending_requests[res.id] then
            local spk = pending_requests[res.id].speaker or 'Chat'
            pending_requests[res.id] = nil

            if res.success and res.text and res.text ~= '' then
                local log_output = string.format('%s < %s', spk, res.text)
                emit(settings.chat_color, log_output)
                hud.update(log_output)
            elseif res.error and res.error ~= '' then
                emit(123, encoding.sjis('[AutoTranslator API Error] ') .. res.error)
            end
        end
        res = translator.poll_result()
    end
end)

-- 翻訳ヘルパーを起動できなかったときは知らせる (その場合は従来の Lua HTTP で翻訳し、返事待ちの間ゲームが止まる)
do
    local ok, err = translator.helper_status()
    if not ok then
        emit(123, encoding.sjis('[AutoTranslator] 翻訳ヘルパーを起動できませんでした: ') .. tostring(err))
    end
end

--------------------------------------------------------------------------------
-- イベントハンドラ
-- 引数は (original, modified, original_mode, modified_mode, blocked) の 5 つ。
-- 4 つしか受けないと 4 番目の modified_mode (数値) が blocked に入り、常に「ブロック済み」扱いで全行を素通りしてしまう
--------------------------------------------------------------------------------
windower.register_event('incoming text', function(original, modified, mode, modified_mode, blocked)
    if blocked or not settings.enabled or is_own_echo(original) or not is_mode_enabled(mode) then return end

    local speaker_name, target_text = chat_parser.parse(original)
    if not target_text or target_text == '' then return end

    local is_jp = lang_detect.has_japanese(target_text)
    local should_translate = false

    if settings.target_lang == 'ja' then
        if not is_jp and target_text:match('[a-zA-Z]') then should_translate = true end
    else
        if is_jp then should_translate = true end
    end

    -- 日本語の発言に定型文 ([at]Crawlers' Nest [S][/at] など) が入っているときは、翻訳はせずに
    -- 定型文だけ日本語の表記 ([クロウラーの巣〔Ｓ〕]) にした行を出す
    if not should_translate and settings.target_lang == 'ja' and is_jp and not is_blocked(speaker_name, target_text) then
        local converted = translator.render_autotranslate(target_text)
        if converted then
            local spk = (speaker_name ~= '') and speaker_name or 'Chat'
            local log_output = string.format('%s < %s', spk, converted)
            emit(settings.chat_color, log_output)
            hud.update(log_output)
        end
        return
    end

    if should_translate and not is_blocked(speaker_name, target_text) then
        request_counter = request_counter + 1
        local req_id = tostring(request_counter)

        local spk = (speaker_name ~= '') and speaker_name or 'Chat'
        pending_requests[req_id] = {
            speaker = spk,
            raw_text = target_text
        }

        translator.translate(target_text, settings, req_id, function(res, err)
            if res and res ~= '' and not res:find('^ASYNC_') then
                pending_requests[req_id] = nil
                local log_output = string.format('%s < %s', spk, res)
                emit(settings.chat_color, log_output)
                hud.update(log_output)
            elseif err then
                pending_requests[req_id] = nil
                emit(123, encoding.sjis('[AutoTranslator Error] ') .. tostring(err))
            end
        end)
    end
end)

--------------------------------------------------------------------------------
-- コマンド制御 (//at)
--------------------------------------------------------------------------------
windower.register_event('addon command', function(cmd, ...)
    local args = {...}
    cmd = cmd and cmd:lower() or 'help'
    local arg1 = rawget(args, 1)
    arg1 = arg1 and arg1:lower() or ''

    if cmd == 'test' then
        local test_input = table.concat(args, ' ')
        if test_input == '' then test_input = 'hello' end
        emit(207, 'AutoTranslator [Test Input]: ' .. test_input)

        request_counter = request_counter + 1
        local req_id = tostring(request_counter)
        pending_requests[req_id] = { speaker = 'Test', raw_text = test_input }

        translator.translate(test_input, settings, req_id, function(res, err)
            if res and res ~= '' and not res:find('^ASYNC_') then
                pending_requests[req_id] = nil
                local out = 'AutoTranslator [Test Result]: ' .. res
                emit(207, out)
                hud.update(out)
            elseif err then
                pending_requests[req_id] = nil
                emit(123, 'AutoTranslator [Test Result]: Translation failed. ' .. tostring(err))
            end
        end)

    elseif cmd == 'add' or (cmd == 'dict' and arg1 == 'add') then
        if cmd == 'dict' then table.remove(args, 1) end
        local key = rawget(args, 1)
        table.remove(args, 1)
        local val = table.concat(args, ' ')

        if key and val and key ~= '' and val ~= '' then
            cache.add_dict_item(key, val)
            settings.dictionary[key:lower()] = val
            safe_save_settings()
            translator.invalidate_prompt()
            emit(207, encoding.sjis(string.format('AutoTranslator 辞書追加: [%s] -> %s', key, val)))
        else
            emit(123, encoding.sjis('使用方法: //at add <単語> <訳語>'))
        end

    elseif cmd == 'del' or (cmd == 'dict' and arg1 == 'del') then
        if cmd == 'dict' then table.remove(args, 1) end
        local key = rawget(args, 1)

        if key and key ~= '' then
            if cache.del_dict_item(key) then
                settings.dictionary[key:lower()] = nil
                safe_save_settings()
                translator.invalidate_prompt()
                emit(207, encoding.sjis(string.format('AutoTranslator 辞書削除: [%s]', key)))
            else
                emit(123, encoding.sjis(string.format('単語 [%s] は辞書に存在しません。', key)))
            end
        else
            emit(123, encoding.sjis('使用方法: //at del <単語>'))
        end

    elseif cmd == 'dict' or cmd == 'list' then
        emit(207, encoding.sjis('AutoTranslator --- 登録辞書一覧 ---'))
        local current_dict = cache.get_dictionary()
        local count = 0
        for k, v in pairs(current_dict) do
            count = count + 1
            emit(207, encoding.sjis(string.format('- [%s] : %s', k, v)))
        end
        if count == 0 then
            emit(207, encoding.sjis('現在辞書に登録されている単語はありません。'))
        end

    elseif cmd == 'hud' or cmd == 'overlay' then
        if arg1 == 'reset' then
            if not settings.hud then settings.hud = {} end
            settings.hud.pos = { x = 20, y = 20 }
            hud.set_pos(20, 20)
            safe_save_settings()
            emit(207, 'AutoTranslator: HUD Position reset to (20, 20).')
        elseif tonumber(arg1) and tonumber(rawget(args, 2)) then
            local nx = tonumber(arg1)
            local ny = tonumber(rawget(args, 2))
            if not settings.hud then settings.hud = {} end
            settings.hud.pos = { x = nx, y = ny }
            hud.set_pos(nx, ny)
            safe_save_settings()
            emit(207, string.format('AutoTranslator: HUD Position set to (%d, %d).', nx, ny))
        else
            local now_active = hud.toggle()
            settings.hud_enabled = now_active
            safe_save_settings()
            if now_active then
                emit(207, 'AutoTranslator: HUD Overlay [ON] (マウスドラッグで移動可能)')
            else
                emit(207, 'AutoTranslator: HUD Overlay [OFF]')
            end
        end

    elseif cmd == 'lang' or cmd == 'language' then
        if arg1 == 'ja' or arg1 == 'japanese' then
            settings.target_lang = 'ja'; translator.invalidate_prompt(); safe_save_settings()
            emit(207, 'AutoTranslator: Target language set to [Japanese (ja)].')
        elseif arg1 == 'en' or arg1 == 'english' then
            settings.target_lang = 'en'; translator.invalidate_prompt(); safe_save_settings()
            emit(207, 'AutoTranslator: Target language set to [English (en)].')
        else
            emit(207, 'AutoTranslator: Current target language -> ' .. tostring(settings.target_lang):upper())
        end

    elseif cmd == 'provider' or cmd == 'ai' then
        if arg1 == 'openai' or arg1 == 'claude' or arg1 == 'deepl' then
            settings.api_provider = arg1
            safe_save_settings()
            emit(207, 'AutoTranslator: API Provider set to [' .. arg1:upper() .. '].')
        else
            emit(207, 'AutoTranslator: Current provider -> [' .. tostring(settings.api_provider):upper() .. ']')
        end

    elseif cmd == 'block' then
        local name = arg1
        if name ~= '' then
            table.insert(settings.blocklist, name:lower())
            safe_save_settings()
            emit(207, 'AutoTranslator: Added to blocklist -> ' .. name)
        else
            emit(207, 'AutoTranslator: --- Blocklist ---')
            for _, k in ipairs(settings.blocklist) do emit(207, '- ' .. k) end
        end

    elseif cmd == 'word' then
        if arg1 == 'add' then
            table.remove(args, 1)
            local pattern = table.concat(args, ' ')
            if pattern ~= '' then
                table.insert(settings.blocked_words, pattern:lower())
                safe_save_settings()
                emit(207, 'AutoTranslator: Added NG word -> ' .. pattern)
            end
        elseif arg1 == 'del' then
            table.remove(args, 1)
            local pattern = table.concat(args, ' ')
            if pattern ~= '' then
                for i, w in ipairs(settings.blocked_words) do
                    if w:lower() == pattern:lower() then
                        table.remove(settings.blocked_words, i)
                        break
                    end
                end
                safe_save_settings()
                emit(207, 'AutoTranslator: Removed NG word -> ' .. pattern)
            end
        else
            emit(207, 'AutoTranslator: --- NG Words ---')
            for _, w in ipairs(settings.blocked_words) do emit(207, '- ' .. w) end
        end

    elseif cmd == 'mode' then
        if #args == 0 or arg1 == 'status' then
            emit(207, 'AutoTranslator: --- Chat Modes ---')
            for m, active in pairs(settings.modes) do
                emit(207, string.format('%s : %s', m:upper(), active and 'ON' or 'OFF'))
            end
            return
        end
        for m in pairs(settings.modes) do settings.modes[m] = false end
        for _, arg in ipairs(args) do
            if settings.modes[arg:lower()] ~= nil then settings.modes[arg:lower()] = true end
        end
        safe_save_settings()
        emit(207, 'AutoTranslator: Chat modes updated.')

    elseif cmd == 'toggle' then
        settings.enabled = not settings.enabled
        emit(207, 'AutoTranslator: ' .. (settings.enabled and 'ON' or 'OFF'))
    else
        emit(207, 'AutoTranslator: //at test <text> | //at add <k> <v> | //at del <k> | //at dict | //at hud | //at lang <ja/en> | //at provider <deepl/openai/claude>')
    end
end)

windower.register_event('unload', function()
    -- 翻訳ヘルパーに終了を伝え、DLL を使っていれば止める
    translator.shutdown()
end)
