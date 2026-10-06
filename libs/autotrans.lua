-- FFXI の定型文辞書 (Tab 変換) を、ゲームと同じ日本語の表記にする
-- チャットには 2 種類の形で届く:
--   1. バイト列   : FD 種類 言語 番号(上位) 番号(下位) FD   (自分や近くの人の発言)
--                   encoding.lua が "[atid:種類:番号]" という文字に置き換えてから、ここで読む
--   2. 文字       : [at]100 Byne Bill[/at]               (yell など。英語名で届く)
-- どちらも Windower の一覧 (res) から日本語名を引き、[100バイン紙幣] のように表す。
-- 文字列はすべて UTF-8 で扱う
local res      = require('resources')
local glossary = require('libs/glossary')

local autotrans = {}

local by_en = nil   -- [英語名 (小文字)] = {en = 英語名, ja = 日本語名}

local function add(e)
    if type(e) ~= 'table' or type(e.en) ~= 'string' or type(e.ja) ~= 'string' or e.en == '' or e.ja == '' then return end
    local key = e.en:lower()
    if not by_en[key] then by_en[key] = { en = e.en, ja = e.ja } end
end

local function build()
    by_en = {}
    -- 先に入れたものが優先 (定型文辞書 → アイテム → 大事なもの → エリア)
    for _, e in pairs(res.auto_translates) do add(e) end
    for _, e in pairs(res.items) do add(e) end
    for _, e in pairs(res.key_items) do add(e) end
    for _, e in pairs(res.zones) do add(e) end
end

-- バイト列の種類ごとの一覧 (0x02: 定型文辞書, 0x07: アイテム, 0x13: 大事なもの)
local function from_id(kind, id)
    local list = (kind == 2 and res.auto_translates) or (kind == 7 and res.items) or (kind == 19 and res.key_items) or nil
    local e = list and list[id]
    if type(e) == 'table' and type(e.en) == 'string' and type(e.ja) == 'string' then
        return { en = e.en, ja = e.ja }
    end
    return nil
end

local function trim(s)
    return (s:gsub('^%s+', ''):gsub('%s+$', ''))
end

-- 定型文を印 (\3番号\4) に置き換える。無ければ nil
-- 戻り値: 印入りの文, 定型文の表 ({en, ja} の配列。印の番号に対応)
function autotrans.extract(text)
    if type(text) ~= 'string' then return nil end
    local lower = text:lower()
    if not lower:find('[atid:', 1, true) and not lower:find('[at]', 1, true) then return nil end
    if not by_en then build() end

    local toks = {}
    local function mark(entry)
        toks[#toks + 1] = entry
        return '\3' .. #toks .. '\4'
    end

    local s = text:gsub('%[atid:(%d+):(%d+)%]', function(kind, id)
        return mark(from_id(tonumber(kind), tonumber(id)) or { en = '', ja = '定型文' })
    end)
    s = s:gsub('%[[aA][tT]%](.-)%[/[aA][tT]%]', function(name)
        name = trim(name)
        return mark(by_en[name:lower()] or { en = name, ja = name })
    end)

    if #toks == 0 then return nil end
    return s, toks
end

-- lang: 翻訳先の言語 ('ja' = 英語→日本語 / 'en' = 日本語→英語)。定型文はその言語の表記で出す
local function name_of(t, lang)
    if lang == 'en' then return (t.en ~= '' and t.en) or t.ja end
    return t.ja
end

-- 定型文以外に訳すべき文字が残っているか (残っていなければ翻訳は要らない)
--   英語→日本語: 英字が残っているか / 日本語→英語: 英字か日本語 (0x80 以上のバイト) が残っているか
function autotrans.has_other_text(marked, lang)
    local rest = marked:gsub('\3%d+\4', '')
    if lang == 'en' then return rest:find('[%a\128-\255]') ~= nil end
    return rest:find('[A-Za-z]') ~= nil
end

-- 画面に出す形: 定型文を [日本語名] (日本語→英語のときは [英語名]) にする
function autotrans.render(marked, toks, lang)
    return (marked:gsub('\3(%d+)\4', function(n) return '[' .. name_of(toks[tonumber(n)], lang) .. ']' end))
end

-- DeepL に送る形。
--   英語→日本語: 地名は英語名のまま (用語集で正しく訳される)、それ以外は <x>[日本語名]</x> で囲んで「訳さない」
--   日本語→英語: 印は使わない (英語の訳文では印で囲むと文が崩れる)。地名は英語名、それ以外は [英語名] をそのまま入れる
-- 戻り値: 送る文, <x> を使ったか, OpenAI/Claude 用の対応 ("100 Byne Bill = 100バイン紙幣; ...")
function autotrans.to_request(marked, toks, lang)
    local function is_place(t) return t.en ~= '' and glossary.is_place(t.en) end

    if lang == 'en' then
        local pairs_desc = {}
        local s = marked:gsub('\3(%d+)\4', function(n)
            local t = toks[tonumber(n)]
            if t.en ~= '' then pairs_desc[#pairs_desc + 1] = t.ja .. ' = ' .. t.en end
            if is_place(t) then return t.en end
            return '[' .. name_of(t, 'en') .. ']'
        end)
        return s, false, table.concat(pairs_desc, '; ')
    end

    -- 印 (<x>) を使うのは、地名以外の定型文があるときだけ。そのときだけ記号を XML 用にする
    local used_x = false
    local pairs_desc = {}
    for _, t in ipairs(toks) do
        if not is_place(t) then used_x = true end
        if t.en ~= '' then
            pairs_desc[#pairs_desc + 1] = t.en .. ' = ' .. t.ja
        end
    end

    local s = marked
    if used_x then
        s = s:gsub('&', '&amp;'):gsub('<', '&lt;'):gsub('>', '&gt;')
    end
    s = s:gsub('\3(%d+)\4', function(n)
        local t = toks[tonumber(n)]
        if is_place(t) then return t.en end
        return '<x>[' .. name_of(t, lang) .. ']</x>'
    end)
    return s, used_x, table.concat(pairs_desc, '; ')
end

return autotrans
