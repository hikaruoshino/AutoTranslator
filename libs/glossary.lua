-- FFXI 固有名詞 (エリア名・地方名) を正しい日本語にするための対応表
-- 翻訳 API は "Norg" を「ノルウェー」「ノルグ」のように一般の言葉として訳してしまうため、
-- ゲームと同じ日本語名 (Windower の res/zones.lua, res/regions.lua) を使う。
--   DeepL         : この表を DeepL の「用語集」として登録し、翻訳時に指定する (ヘルパー側で処理)
--   OpenAI/Claude : 文に含まれる地名の対応を指示文に書き足す
--   名前だけの発言 : API を使わずにその場で日本語名を返す
-- 文字列はすべて UTF-8 で扱う (Shift-JIS だと 2 バイト目が英字と一致して誤検出するため)
local res = require('resources')

local glossary = {}

-- 一覧の名前を、チャットで普通に使われる言い方へ直すもの / 一覧に無いがよく使うもの
local OVERRIDES = {
    { en = "San d'Oria", ja = 'サンドリア' },
    { en = 'Bastok',     ja = 'バストゥーク' },
    { en = 'Windurst',   ja = 'ウィンダス' },
    { en = 'Jeuno',      ja = 'ジュノ' },
    { en = 'Adoulin',    ja = 'アドゥリン' },
}
-- 普通の英語として使われやすく、置き換えると誤訳になるもの
local EXCLUDES = {
    ['unknown']  = true,
    ['far east'] = true,
}

local terms = nil   -- { {key = 小文字の英語名, en = 英語名, ja = 日本語名}, ... } 長い名前から順

local function build()
    local map = {}
    local function add(en, ja, force)
        if type(en) ~= 'string' or type(ja) ~= 'string' or en == '' or ja == '' then return end
        local key = en:lower()
        if EXCLUDES[key] or key == ja:lower() then return end
        if map[key] and not force then return end
        map[key] = { key = key, en = en, ja = ja }
    end
    for _, z in pairs(res.zones) do add(z.en, z.ja) end
    for _, r in pairs(res.regions) do add(r.en, r.ja) end
    for _, o in ipairs(OVERRIDES) do add(o.en, o.ja, true) end

    terms = {}
    for _, t in pairs(map) do terms[#terms + 1] = t end
    -- "Port Jeuno" を "Jeuno" より先に見つけるため、長い名前から順に探す
    table.sort(terms, function(a, b)
        if #a.key ~= #b.key then return #a.key > #b.key end
        return a.key < b.key
    end)
end

-- 英字・数字・アポストロフィが前後に続いていたら、単語の一部なので一致とみなさない
local function is_word_char(c)
    return c ~= '' and c:match("[%w']") ~= nil
end

-- 固有名詞を印 (\1番号\2) に置き換える。見つからなければ nil
-- 戻り値: 印入りの文, 見つかった用語の表 ({en, ja} の配列。印の番号に対応)
function glossary.protect(text)
    if not text or text == '' then return nil end
    if not terms then build() end

    local found = {}
    local w = text
    local wl = w:lower()
    for _, t in ipairs(terms) do
        local init = 1
        while true do
            local s, e = wl:find(t.key, init, true)
            if not s then break end
            if is_word_char(wl:sub(s - 1, s - 1)) or is_word_char(wl:sub(e + 1, e + 1)) then
                init = e + 1
            else
                found[#found + 1] = t
                local mark = '\1' .. #found .. '\2'
                w = w:sub(1, s - 1) .. mark .. w:sub(e + 1)
                wl = w:lower()
                init = s + #mark
            end
        end
    end

    if #found == 0 then return nil end
    return w, found
end

-- 英語名が地名の一覧にあるか (定型文の地名を、用語集に任せるかどうかの判断に使う)
function glossary.is_place(en)
    if type(en) ~= 'string' then return false end
    if not terms then build() end
    if not glossary.index then
        glossary.index = {}
        for _, t in ipairs(terms) do glossary.index[t.key] = true end
    end
    return glossary.index[en:lower()] == true
end

-- 印をそのまま日本語名にする (名前だけの発言の訳として使う)
function glossary.to_plain(marked, found)
    return (marked:gsub('\1(%d+)\2', function(n) return found[tonumber(n)].ja end))
end

-- OpenAI / Claude の指示文に書き足す用: "Norg = ノーグ; Port Jeuno = ジュノ港"
function glossary.describe(found)
    local seen, parts = {}, {}
    for _, t in ipairs(found or {}) do
        if not seen[t.key] then
            seen[t.key] = true
            parts[#parts + 1] = t.en .. ' = ' .. t.ja
        end
    end
    return table.concat(parts, '; ')
end

-- 日本語 → 英語用: 日本語名から英語名を引く表。同じ日本語名が複数あるときは、短い英語名を優先する
-- (例: ジュノ → "Jeuno"。チャットで普通に使う言い方を残すため)
local by_ja = nil
local function build_ja()
    if not terms then build() end
    by_ja = {}
    for _, t in ipairs(terms) do
        local cur = by_ja[t.ja]
        if not cur or #t.en < #cur.en then by_ja[t.ja] = t end
    end
end

-- 日本語 → 英語用: 日本語の文の中の地名を、ゲームの英語名に置き換える。
-- DeepL の用語集は 1 つまでしか作れず (英語→日本語で使用中)、印で囲むと文が崩れるため、
-- 英語名を文中にそのまま入れて送る (例: ジュノ港で待ち合わせ → Port Jeunoで待ち合わせ)
-- 戻り値: 置き換えた文, OpenAI / Claude 用の対応 ("ジュノ港 = Port Jeuno; ...")
local ja_sorted = nil
function glossary.replace_ja(text)
    if type(text) ~= 'string' or text == '' then return text, '' end
    if not by_ja then build_ja() end
    if not ja_sorted then
        ja_sorted = {}
        for ja, t in pairs(by_ja) do ja_sorted[#ja_sorted + 1] = { ja = ja, en = t.en } end
        -- 「ジュノ港」を「ジュノ」より先に見つけるため、長い名前から順に探す
        table.sort(ja_sorted, function(a, b)
            if #a.ja ~= #b.ja then return #a.ja > #b.ja end
            return a.ja < b.ja
        end)
    end

    local found, parts = {}, {}
    local w = text
    for _, t in ipairs(ja_sorted) do
        local init = 1
        while true do
            local s, e = w:find(t.ja, init, true)
            if not s then break end
            found[#found + 1] = t.en
            local mark = '\1' .. #found .. '\2'
            w = w:sub(1, s - 1) .. mark .. w:sub(e + 1)
            init = s + #mark
            parts[#parts + 1] = t.ja .. ' = ' .. t.en
        end
    end
    if #found == 0 then return text, '' end
    w = w:gsub('\1(%d+)\2', function(n) return found[tonumber(n)] end)
    return w, table.concat(parts, '; ')
end

-- DeepL の用語集に登録する表 (TSV: 英語名<TAB>日本語名)。並び順を固定して、中身が同じなら同じ文字列にする
function glossary.to_tsv()
    if not terms then build() end
    local rows = {}
    for _, t in ipairs(terms) do
        if not t.en:find('[\t\r\n]') and not t.ja:find('[\t\r\n]') then
            rows[#rows + 1] = t.en .. '\t' .. t.ja
        end
    end
    table.sort(rows)
    return table.concat(rows, '\n')
end

return glossary
