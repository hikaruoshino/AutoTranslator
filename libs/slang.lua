-- FF11 のスラング・略語と、よくある誤字を、翻訳サービスに送る前に置き換える (英語→日本語のときだけ使う)
-- 辞書は data/slang.xml / data/typo.xml (UTF-8)。無ければ既定の内容で作る。書式は 1 語 1 行:
--   <entry word="lf1m" en="looking for 1 more member"/>  英語に言い換えて、翻訳サービスに訳させる
--   <entry word="sc" ja="連携"/>                          日本語のまま訳文に入れる (DeepL には「訳さない」印を付けて送る)
--   near="fusion light ..."  同じ発言か直前の発言に、この語のどれかがあるときだけ置き換える
--   alone="true"             「add!」「inc,」のように、その語だけで区切られているときだけ置き換える
--   else_en / else_ja        条件に合わないときの置き換え (無ければそのまま残す)
-- 語は大文字・小文字を区別せず、単語単位で探す (「add」は「address」の中では見つけない)。
-- 文字列はすべて UTF-8 で扱う。Windower に頼らないので、素の Lua 5.1 でも動く
local slang = {}

local KINDS = { 'typo', 'slang' }

local DEFAULTS = {
    typo = {},
    slang = {
        -- 募集・あいさつ
        { word = 'lf1m',  en = 'looking for 1 more member' },
        { word = 'lf2m',  en = 'looking for 2 more members' },
        { word = 'lf3m',  en = 'looking for 3 more members' },
        { word = 'lfm',   en = 'looking for more members' },
        { word = 'lfg',   en = 'looking for a party to join' },
        { word = 'lfp',   en = 'looking for a party to join' },
        { word = 'bbl',   en = 'be back later' },
        { word = 'gz',    en = 'congratulations' },
        { word = 'grats', en = 'congratulations' },
        { word = 'kk',    en = 'okay' },
        { word = 'gj',    en = 'good job' },
        { word = 'lul',   en = 'lol' },
        { word = 'ez clap', en = 'that was too easy' },
        { word = 'ez',    en = 'easy' },
        { word = 'drop',  ja = 'ドロップ', near = 'gz grats congrats congratulations lucky finally' },
        -- 戦闘
        { word = 'ws',    en = 'WS' },
        { word = 'sc',    ja = '連携' },
        { word = 'mb',    ja = 'マジックバースト', else_en = 'my bad',
          near = 'sc skillchain burst nuke nukes fusion fragmentation gravitation distortion light darkness radiance umbra '
              .. 'liquefaction impaction detonation scission reverberation induration compression transfixion '
              .. 'fire ice wind earth thunder water stone aero blizzard' },
        { word = '2hr',   ja = 'SPアビリティ' },
        { word = '1hr',   ja = 'SPアビリティ' },
        { word = 'sp1',   en = 'SP1' },
        { word = 'sp2',   en = 'SP2' },
        { word = 'nm',    en = 'NM' },
        { word = 'pop',    en = 'spawn',   near = 'nm' },
        { word = 'popped', en = 'spawned', near = 'nm' },
        { word = 'mob',   en = 'enemy' },
        { word = 'mobs',  en = 'enemies' },
        { word = 'voke',  en = 'Provoke' },
        { word = 'inc',   en = 'enemy incoming', alone = true },
        { word = 'add',   en = 'another enemy has joined', alone = true },
        { word = 'pull',  en = 'lure the enemy', near = 'ready mob mobs nm next tank camp' },
        { word = 'nuke',  en = 'cast offensive magic' },
        { word = 'dd',    ja = 'アタッカー' },
        { word = 'th',    ja = 'トレジャーハンター' },
        { word = 'rr',    ja = 'リレイズ' },
        { word = 'cap',   en = 'capped', near = 'merit merits exp xp jp cp ep level lvl' },
        -- そのほか
        { word = 'ki',    ja = 'だいじなもの' },
        { word = 'ah',    ja = '競売', near = 'price prices sell selling sold buy buying bid list listed stock check' },
        { word = 'pl',    en = 'power level' },
        { word = 'ls',    en = 'LS' },
        { word = 'ambu',  ja = 'アンバスケード' },
        { word = 'vd',    ja = 'とてむず' },
        -- ジョブ (war / run は普通の英単語でもあるので、募集の話のときだけ)
        { word = 'war', ja = '戦士', near = 'need lf lfg lfm lfp lf1m lf2m lf3m job jobs tank dd main sub' },
        { word = 'mnk', ja = 'モンク' },
        { word = 'whm', ja = '白魔道士' },
        { word = 'blm', ja = '黒魔道士' },
        { word = 'rdm', ja = '赤魔道士' },
        { word = 'thf', ja = 'シーフ' },
        { word = 'pld', ja = 'ナイト' },
        { word = 'drk', ja = '暗黒騎士' },
        { word = 'bst', ja = '獣使い' },
        { word = 'brd', ja = '吟遊詩人' },
        { word = 'rng', ja = '狩人' },
        { word = 'sam', ja = '侍' },
        { word = 'nin', ja = '忍者' },
        { word = 'drg', ja = '竜騎士' },
        { word = 'smn', ja = '召喚士' },
        { word = 'blu', ja = '青魔道士' },
        { word = 'cor', ja = 'コルセア' },
        { word = 'pup', ja = 'からくり士' },
        { word = 'dnc', ja = '踊り子' },
        { word = 'sch', ja = '学者' },
        { word = 'geo', ja = '風水士' },
        { word = 'run', ja = '魔導剣士', near = 'need lf lfg lfm lfp lf1m lf2m lf3m job jobs tank dd main sub' },
    },
}

local HEADERS = {
    slang = 'FF11 のスラング・略語の辞書。en = 英語に言い換えて訳させる / ja = 日本語のまま訳文に入れる\n'
         .. '  near = 同じ発言か直前の発言にこの語のどれかがあるときだけ / alone = その語だけで区切られているときだけ\n'
         .. '  else_en / else_ja = 条件に合わないときの置き換え\n'
         .. '  ゲーム中に書き換えたら //at slang reload で読み込み直す',
    typo  = 'よくある誤字の補正表。en = 正しい綴り (例: <entry word="recieve" en="receive"/>)\n'
         .. '  ゲーム中に書き換えたら //at slang reload で読み込み直す',
}

local data_dir = nil
local lists = { typo = {}, slang = {} }   -- [種類] = entry の配列 (ファイルの順)
local index = nil                          -- [種類] = { [先頭の文字] = 長い語から順の entry 配列 }

--------------------------------------------------------------------------------
-- 読み書き
--------------------------------------------------------------------------------
local function xml_escape(s)
    return (tostring(s):gsub('&', '&amp;'):gsub('"', '&quot;'):gsub('<', '&lt;'):gsub('>', '&gt;'))
end

local function xml_unescape(s)
    return (s:gsub('&quot;', '"'):gsub('&apos;', "'"):gsub('&lt;', '<'):gsub('&gt;', '>'):gsub('&amp;', '&'))
end

local function trim(s)
    return (s:gsub('^%s+', ''):gsub('%s+$', ''))
end

-- 語と条件をそろえた entry を作る。使えなければ nil
local function normalize(e)
    if type(e) ~= 'table' or type(e.word) ~= 'string' then return nil end
    local word = trim(e.word):lower()
    if word == '' then return nil end
    local n = { word = word }
    for _, k in ipairs({ 'en', 'ja', 'else_en', 'else_ja', 'near' }) do
        if type(e[k]) == 'string' and trim(e[k]) ~= '' then n[k] = trim(e[k]) end
    end
    if not n.en and not n.ja then return nil end
    n.alone = (e.alone == true or e.alone == 'true')
    if n.near then
        n.near_set = {}
        for w in n.near:lower():gmatch("[%w']+") do n.near_set[w] = true end
    end
    return n
end

local function file_path(kind)
    return data_dir .. kind .. '.xml'
end

local function save(kind)
    local f = io.open(file_path(kind), 'wb')
    if not f then return false end
    local out = { '<?xml version="1.0" encoding="UTF-8"?>', '<!--', HEADERS[kind], '-->', '<' .. kind .. '>' }
    for _, e in ipairs(lists[kind]) do
        local attrs = { 'word="' .. xml_escape(e.word) .. '"' }
        for _, k in ipairs({ 'en', 'ja', 'else_en', 'else_ja', 'near' }) do
            if e[k] then attrs[#attrs + 1] = k .. '="' .. xml_escape(e[k]) .. '"' end
        end
        if e.alone then attrs[#attrs + 1] = 'alone="true"' end
        out[#out + 1] = '    <entry ' .. table.concat(attrs, ' ') .. '/>'
    end
    out[#out + 1] = '</' .. kind .. '>'
    f:write(table.concat(out, '\n') .. '\n')
    f:close()
    return true
end

local function load(kind)
    local list = {}
    local f = io.open(file_path(kind), 'rb')
    if not f then
        -- 初めて使うとき: 既定の内容でファイルを作る
        for _, e in ipairs(DEFAULTS[kind]) do list[#list + 1] = normalize(e) end
        lists[kind] = list
        save(kind)
        return
    end
    local content = f:read('*a')
    f:close()
    content = content:gsub('^\239\187\191', ''):gsub('<!%-%-.-%-%->', '')   -- BOM とコメントを外す
    local seen = {}
    for body in content:gmatch('<entry%s+(.-)/>') do
        local e = {}
        for k, v in body:gmatch('([%w_]+)%s*=%s*"(.-)"') do e[k] = xml_unescape(v) end
        e = normalize(e)
        if e and not seen[e.word] then
            seen[e.word] = true
            list[#list + 1] = e
        end
    end
    lists[kind] = list
end

local function build_index()
    index = {}
    for _, kind in ipairs(KINDS) do
        local by_first = {}
        for _, e in ipairs(lists[kind]) do
            local c = e.word:sub(1, 1)
            by_first[c] = by_first[c] or {}
            table.insert(by_first[c], e)
        end
        -- 「lf1m」を「lf」より先に見つけるため、長い語から順に試す
        for _, arr in pairs(by_first) do
            table.sort(arr, function(a, b)
                if #a.word ~= #b.word then return #a.word > #b.word end
                return a.word < b.word
            end)
        end
        index[kind] = by_first
    end
end

-- dir: 辞書ファイルを置くフォルダ (末尾の / 付き)
function slang.init(dir)
    data_dir = dir
    slang.reload()
end

function slang.reload()
    for _, kind in ipairs(KINDS) do load(kind) end
    build_index()
end

-- 追加・上書きする。value に日本語 (0x80 以上のバイト) があれば ja、無ければ en として登録する
function slang.add(kind, word, value)
    if not lists[kind] then return nil end
    local e = normalize({ word = word, en = (not value:find('[\128-\255]')) and value or nil,
                          ja = value:find('[\128-\255]') and value or nil })
    if not e then return nil end
    if kind == 'typo' and e.ja then return nil end   -- 誤字の補正は英語だけ
    local replaced = false
    for i, old in ipairs(lists[kind]) do
        if old.word == e.word then lists[kind][i] = e; replaced = true; break end
    end
    if not replaced then table.insert(lists[kind], e) end
    save(kind)
    build_index()
    return e
end

function slang.del(kind, word)
    if not lists[kind] or type(word) ~= 'string' then return false end
    word = trim(word):lower()
    for i, e in ipairs(lists[kind]) do
        if e.word == word then
            table.remove(lists[kind], i)
            save(kind)
            build_index()
            return true
        end
    end
    return false
end

function slang.list(kind)
    return lists[kind] or {}
end

-- 一覧表示用: "lf1m -> looking for 1 more member [near: ...]"
function slang.describe(e)
    local s = e.word .. ' -> ' .. (e.ja or e.en)
    if e.alone then s = s .. ' [alone]' end
    if e.near then s = s .. ' [near: ' .. e.near .. ']' end
    if e.else_ja or e.else_en then s = s .. ' [else: ' .. (e.else_ja or e.else_en) .. ']' end
    return s
end

--------------------------------------------------------------------------------
-- 置き換え
--------------------------------------------------------------------------------
-- 英字・数字・アポストロフィが前後に続いていたら、単語の一部なので一致とみなさない (glossary.lua と同じ考え方)
local function is_word_char(c)
    return c ~= '' and c:match("[%w']") ~= nil
end

-- 語の前後が「区切り」(文の始め・終わり、または記号) だけか。空白は飛ばして見る
local function is_alone(text, s, e)
    local before = text:sub(1, s - 1):match('(%S)%s*$')
    local after = text:sub(e + 1):match('^%s*(%S)')
    local function ok(c) return c == nil or (c:match('%p') ~= nil and c ~= "'") end
    return ok(before) and ok(after)
end

-- 条件に合わせて、使う置き換えを返す ({text, ja}) 。置き換えないなら nil
local function choose(e, text, s, finish, words)
    local hit = true
    if e.alone and not is_alone(text, s, finish) then hit = false end
    if hit and e.near_set then
        hit = false
        for w in pairs(e.near_set) do
            if w ~= e.word and words[w] then hit = true; break end
        end
    end
    if hit then
        if e.ja then return { text = e.ja, ja = true } end
        return { text = e.en, ja = false }
    end
    if e.else_ja then return { text = e.else_ja, ja = true } end
    if e.else_en then return { text = e.else_en, ja = false } end
    return nil
end

-- text の中の語を探し、見つけたら on_hit(entry, 位置) の戻り値で置き換える (戻り値が nil ならそのまま)
local function scan(kind, text, words, on_hit)
    local by_first = index and index[kind]
    if not by_first or not next(by_first) then return text end
    local lower = text:lower()
    local out = {}
    local i, n = 1, #text
    local copied = 1
    while i <= n do
        local cands = (i == 1 or not is_word_char(lower:sub(i - 1, i - 1))) and by_first[lower:sub(i, i)]
        local advanced = false
        if cands then
            for _, e in ipairs(cands) do
                local finish = i + #e.word - 1
                if lower:sub(i, finish) == e.word and not is_word_char(lower:sub(finish + 1, finish + 1)) then
                    local rep = on_hit(e, text, i, finish, words)
                    if rep then
                        out[#out + 1] = text:sub(copied, i - 1)
                        out[#out + 1] = rep
                        i = finish + 1
                        copied = i
                        advanced = true
                    end
                    break
                end
            end
        end
        if not advanced then i = i + 1 end
    end
    out[#out + 1] = text:sub(copied)
    return table.concat(out)
end

-- 発言 text (UTF-8) の誤字を直し、スラングを印 (\5番号\6) に置き換える。
-- context: 直前の発言 (UTF-8 の文字列。near の判断に使う)
-- 戻り値: 印入りの文, 置き換えの表 ({text, ja, word} の配列。印の番号に対応) — 置き換えが無ければ text と空の表
function slang.apply(text, context)
    if type(text) ~= 'string' or text == '' or not index then return text, {} end

    -- 1. 誤字: そのまま正しい綴りにする (後のスラングの判断にも使えるように)
    text = scan('typo', text, nil, function(e) return e.en end)

    -- 2. スラング: 同じ発言と直前の発言に出てくる語を集めて、near の判断に使う
    local words = {}
    for w in (text .. ' ' .. (context or '')):lower():gmatch("[%w']+") do words[w] = true end
    local toks = {}
    text = scan('slang', text, words, function(e, t, s, finish, ws)
        local rep = choose(e, t, s, finish, ws)
        if not rep then return nil end
        rep.word = t:sub(s, finish)
        toks[#toks + 1] = rep
        return '\5' .. #toks .. '\6'
    end)
    return text, toks
end

-- 印を戻す。mode = 'xml': 日本語は <x>..</x> で囲む (DeepL の「訳さない」印。文の記号は呼び出し側で XML 用にしておく)
--            mode = 'plain': 日本語もそのまま入れる (OpenAI / Claude / Lua の HTTP 用)
function slang.render(marked, toks, mode)
    return (marked:gsub('\5(%d+)\6', function(n)
        local t = toks[tonumber(n)]
        if not t then return '' end
        if mode == 'xml' then
            if t.ja then return '<x>' .. t.text .. '</x>' end
            return (t.text:gsub('&', '&amp;'):gsub('<', '&lt;'):gsub('>', '&gt;'))
        end
        return t.text
    end))
end

-- OpenAI / Claude の指示文に書き足す用: "lf1m = looking for 1 more member; sc = 連携"
function slang.describe_terms(toks)
    local seen, parts = {}, {}
    for _, t in ipairs(toks or {}) do
        local key = t.word:lower()
        if not seen[key] then
            seen[key] = true
            parts[#parts + 1] = t.word .. ' = ' .. t.text
        end
    end
    return table.concat(parts, '; ')
end

return slang
