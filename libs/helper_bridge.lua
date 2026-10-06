-- 翻訳ヘルパー (helper/at_helper.ps1) との受け渡し
-- 依頼はファイルに書いてすぐ戻り、結果は poll() で少しずつ確認する。ゲームは翻訳を待たない。
local json = require('libs/json')

local helper_bridge = {}

local function strip_slash(path)
    return (path:gsub('[\\/]+$', ''))
end

local addon_dir   = strip_slash(windower.addon_path)
local queue_dir   = addon_dir .. '/data/queue/'
local launcher_path = addon_dir .. '/helper/start_helper.vbs'

local HEARTBEAT_SEC      = 5     -- ヘルパーへ「ゲームは動いている」と伝える間隔
local POLL_SEC           = 0.1   -- 結果ファイルを確認する間隔
local RESULT_TIMEOUT_SEC = 20    -- これを過ぎても結果が無ければ失敗扱い

local started = false
-- 読み込みごとの「回」の番号。依頼ファイル名に付けて古い結果と混ざらないようにし、
-- heartbeat にも書いて、前の回のヘルパーに「新しい回が始まった (終了してよい)」と伝える
local session = string.format('%d%03d', os.time(), math.floor((os.clock() * 1000) % 1000))
local pending = {}                    -- [req_id] = 依頼した時刻 (os.clock)
local last_heartbeat = -HEARTBEAT_SEC
local last_poll = 0

local function write_file(path, content)
    local f = io.open(path, 'wb')
    if not f then return false end
    f:write(content)
    f:close()
    return true
end

local function file_name(req_id)
    return session .. '_' .. tostring(req_id):gsub('[^%w_%-]', '_')
end

local function heartbeat()
    write_file(queue_dir .. 'heartbeat', session)
    last_heartbeat = os.clock()
end

-- ヘルパーを起動する。二重起動はヘルパー側で防いでいるので、何度呼んでもよい
function helper_bridge.start()
    if not windower.execute then
        return false, 'windower.execute is not available'
    end
    os.remove(queue_dir .. 'stop')
    if not write_file(queue_dir .. 'heartbeat', session) then
        return false, 'cannot write ' .. queue_dir
    end
    last_heartbeat = os.clock()

    -- windower.execute は powershell.exe に引数を渡せなかった (引数なしの PowerShell が起動するだけだった)。
    -- そこで、引数の要らない起動用 VBS を開き、VBS から画面を出さずにヘルパーを起動する
    local launcher = (launcher_path:gsub('/', '\\'))
    local ok, err = pcall(windower.execute, launcher)
    if not ok then
        ok, err = pcall(windower.execute, launcher, {})
    end
    started = ok
    return ok, err
end

function helper_bridge.is_started()
    return started
end

-- 翻訳を依頼する。text は UTF-8。terms は文に含まれる固有名詞の対応 ("Norg = ノーグ; ...")
function helper_bridge.submit(req_id, text, settings, system_prompt, terms, xml)
    if not started then return false end
    local name = file_name(req_id)
    local body = json.encode({
        id = name,
        text = text,
        target_lang = settings.target_lang or 'ja',
        provider = (settings.api_provider or 'deepl'):lower(),
        system_prompt = system_prompt or '',
        terms = terms or '',
        xml = xml and true or false,  -- true: text に <x>[定型文]</x> の「訳さない」印が入っている
    })
    -- 書きかけをヘルパーに読まれないよう、.tmp に書いてから名前を変える
    local tmp = queue_dir .. name .. '.tmp'
    if not write_file(tmp, body) then return false end
    if not os.rename(tmp, queue_dir .. name .. '.req') then
        os.remove(tmp)
        return false
    end
    pending[req_id] = os.clock()
    return true
end

-- 結果を 1 件返す (無ければ nil)。{ id, success, text (UTF-8), provider, error }
function helper_bridge.poll()
    if not started then return nil end
    local now = os.clock()
    if now - last_heartbeat >= HEARTBEAT_SEC then heartbeat() end
    if now - last_poll < POLL_SEC then return nil end
    last_poll = now

    for req_id, sent in pairs(pending) do
        local path = queue_dir .. file_name(req_id) .. '.res'
        local f = io.open(path, 'rb')
        if f then
            local content = f:read('*a')
            f:close()
            os.remove(path)
            pending[req_id] = nil

            local status, provider, body = content:match('^(%u+)\r?\n([^\r\n]*)\r?\n(.*)$')
            body = (body or ''):gsub('[\r\n]+', ' ')
            if status == 'OK' then
                return { id = req_id, success = true, text = body, provider = provider }
            end
            return { id = req_id, success = false, error = (body ~= '' and body or 'translation failed') }
        elseif now - sent > RESULT_TIMEOUT_SEC then
            pending[req_id] = nil
            -- ヘルパーが止まっているかもしれないので起動し直しておく (動いていれば二重起動はされない)
            helper_bridge.start()
            return { id = req_id, success = false, error = 'no response from translator helper (timeout)' }
        end
    end
    return nil
end

-- ヘルパーに終了を伝える
function helper_bridge.stop()
    if started then write_file(queue_dir .. 'stop', '1') end
    started = false
end

return helper_bridge
