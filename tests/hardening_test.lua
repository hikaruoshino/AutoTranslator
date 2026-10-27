-- 実行: lua5.1 tests/hardening_test.lua   (リポジトリのルートで。Windower は模擬)
package.path = './?.lua;' .. package.path
local fails = 0
local function check(c, m) if not c then fails = fails + 1; io.write("NG: " .. m .. "\n") end end

local clock = 0
windower = {addon_path = './', ffxi = {}, create_dir = function() end, dir_exists = function() return true end}
local real_os_clock = os.clock
os.clock = function() return clock end

-- 1. trim_ascii は 1 値。table.insert の末尾引数に渡せる
local encoding = require('libs/encoding')
check(select('#', encoding.trim_ascii('  hi  ')) == 1, "trim_ascii は 1 値")
check(encoding.trim_ascii('  hi  ') == 'hi', "trim_ascii の中身")
check(select('#', encoding.trim_ascii(nil)) == 1 and encoding.trim_ascii(nil) == '', "nil は空文字 1 値")
local t = {}
check(pcall(function() table.insert(t, encoding.trim_ascii(' x ')) end) and t[1] == 'x', "table.insert の末尾引数に渡せる")

-- 2. chat_parser.parse は常に 2 値
local cp = require('libs/chat_parser')
for _, line in ipairs{'(Bob) hello world', '[Bob] hello world', 'Bob: hello world', 'plain text only'} do
    local n = select('#', cp.parse(line))
    check(n == 2, "parse は 2 値: " .. line .. " (実際 " .. n .. ")")
end

-- 3. clean_result: 制御文字・長さ・UTF-8 の途中切り
package.loaded['libs/helper_bridge'] = nil
local ok, hb = pcall(require, 'libs/helper_bridge')
check(ok and type(hb.clean_result) == 'function', "helper_bridge を読み込める: " .. tostring(hb))
if ok then
    local c = hb.clean_result
    check(c("a\30b\31c\253d\127e\0f") == "a b c\253d e f", "制御文字は空白に (0xFD 以外の高位は残す)")
    check(c("  a \n\t b  ") == "a b", "空白をまとめて前後を落とす")
    check(c(nil) == "" and c(123) == "123", "nil・数値でも落ちない")
    local long = string.rep("a", 1000)
    check(#c(long) == 400, "400 バイトに切る")
    -- 日本語 (3 バイト) の途中で 400 バイト目が来るようにする: 399 バイト + 'あ' (3 バイト) ...
    local s = string.rep("a", 399) .. string.rep("\227\129\130", 10)   -- 'あ' x10
    local r = c(s)
    check(#r <= 400, "上限内")
    check(r == string.rep("a", 399), "途中の文字は落とす (文字を壊さない)")
    local s2 = string.rep("\227\129\130", 200)   -- 600 バイト、境界ちょうど (399 = 133 文字 x 3)
    local r2 = c(s2)
    check(#r2 % 3 == 0 and #r2 <= 400, "日本語だけでも文字単位で切れる (" .. #r2 .. ")")
    -- UTF-8 として妥当か (先頭バイトの直後に続きバイトが揃っている)
    local valid = true
    local i = 1
    while i <= #r2 do
        local b = r2:byte(i)
        local len = (b < 0x80 and 1) or (b >= 0xE0 and b < 0xF0 and 3) or (b >= 0xC0 and b < 0xE0 and 2) or (b >= 0xF0 and 4) or 0
        if len == 0 then valid = false; break end
        for j = 1, len - 1 do local cb = r2:byte(i + j); if not cb or cb < 0x80 or cb >= 0xC0 then valid = false end end
        i = i + len
    end
    check(valid, "切った結果が妥当な UTF-8")
end

-- 4. cache: 上限があり、よく使うものは残る。辞書は残る
local cache = require('libs/cache')
cache.init({})
cache.set('hello', '你好')
for i = 1, 5000 do cache.set('key' .. i, 'v' .. i) end
local alive = 0
for i = 1, 5000 do if cache.get('key' .. i) then alive = alive + 1 end end
check(alive <= 4000 and alive >= 1000, "記憶は 2 世代分 (<= 4000) に収まる (" .. alive .. ")")
check(cache.get('key5000') == 'v5000', "直近のものは残る")
check(cache.get('key1') == nil, "古いものは捨てる")
cache.init({})
cache.set('keep', 'K')
for i = 1, 1999 do cache.set('f' .. i, 'x') end   -- 世代が切り替わる直前
check(cache.get('keep') == 'K', "世代が切り替わる前は残る")
for i = 1, 1000 do cache.set('g' .. i, 'x') end
check(cache.get('keep') == 'K', "1 世代前なら、まだ引ける (使われたら新しい世代へ)")
cache.invalidate()
check(cache.get('keep') == nil, "invalidate で空")

os.clock = real_os_clock
io.write(string.format("== 失敗 %d 件\n", fails))
os.exit(fails == 0 and 0 or 1)
