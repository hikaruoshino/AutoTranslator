-- ヘルパーが使えないときの Lua HTTP の休止を確かめる。実行: lua5.1 tests/fallback_test.lua (ルートで)
package.path = './?.lua;' .. package.path
local fails = 0
local function check(c, m) if not c then fails = fails + 1; io.write("NG: " .. m .. "\n") end end
local clock = 100
os.clock = function() return clock end
windower = {addon_path = './', ffxi = {}, create_dir = function() end, dir_exists = function() return true end}
local calls = 0
local mode = 'fail'
package.loaded['ssl.https'] = {request = function(r)
    calls = calls + 1
    if mode == 'fail' then return nil, 'timeout' end
    r.sink('{"translations":[{"text":"ok"}]}'); return 1, 200
end}
package.loaded['ltn12'] = {source = {string = function(s) return s end}, sink = {table = function(t) return function(chunk) t[#t + 1] = chunk end end}}
package.loaded['resources'] = dofile('tests/mock_resources.lua')
coroutine.schedule = function(fn) fn() end   -- 模擬: その場で実行する

local hb = require('libs/helper_bridge')
hb.start = function() return false, 'test: no helper' end
hb.is_started = function() return false end
local translator = require('libs/translator')

local settings = {enabled = true, target_lang = 'ja', api_provider = 'deepl', api_keys = {deepl = 'KEY:fx', openai = 'sk-x', claude = 'sk-y'}, dictionary = {}}
local errs, results = {}, {}
local function cb(res, err) if err ~= nil then errs[#errs + 1] = err end; if res and not res:find('^ASYNC_') then results[#results + 1] = res end end

translator.translate('hello there friend', settings, '1', cb)
check(calls == 3, "最初は 3 社を試す (実際 " .. calls .. ")")
check(#errs == 1 and errs[1] ~= '', "全部失敗したときは、エラーを 1 回出す")

local before = calls
for i = 2, 6 do translator.translate('another message ' .. i, settings, tostring(i), cb) end
check(calls == before, "休止中は HTTP を呼ばない (ゲームを止めない)")
local silent = true
for i = 2, #errs do if errs[i] ~= '' then silent = false end end
check(silent and #errs == 6, "休止中のエラーは空文字 (表示側で黙って捨てる)")

clock = clock + 61
mode = 'ok'
translator.translate('after pause', settings, '9', cb)
check(calls > before, "60 秒たてば、また試す")

-- 鍵が無いだけ (通信していない) のときは休止しない
clock = clock + 1000
settings.api_keys = {deepl = 'YOUR_DEEPL_KEY'}
mode = 'fail'
local c0 = calls
translator.translate('no key at all one', settings, '20', cb)
translator.translate('no key at all two', settings, '21', cb)
check(calls == c0, "鍵が無いときは通信しない")

io.write(string.format("== 失敗 %d 件\n", fails))
os.exit(fails == 0 and 0 or 1)
