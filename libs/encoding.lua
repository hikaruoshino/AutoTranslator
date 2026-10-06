local encoding = {}

function encoding.sjis(str)
    if not str then return '' end
    return windower.to_shift_jis and windower.to_shift_jis(str) or (windower.from_utf8 and windower.from_utf8(str) or str)
end

function encoding.to_utf8(str)
    if not str then return '' end
    return windower.to_utf8 and windower.to_utf8(str) or (windower.from_shift_jis and windower.from_shift_jis(str) or str)
end

function encoding.trim_ascii(s)
    if not s or type(s) ~= 'string' then return '' end
    return s:gsub('^[ \t\r\n]+', ''):gsub('[ \t\r\n]+$', '')
end

function encoding.sanitize_autotranslate_tokens(s)
    if not s or type(s) ~= 'string' then return '' end
    -- FFXI の定型文 (FD 種類 言語 番号上位 番号下位 FD の 6 バイト) を "[atid:種類:番号]" という文字にする。
    -- 後の処理で制御文字を消しても中身が残るようにし、autotrans.lua が日本語名に直す
    -- ※ Lua 5.1 は '\xFD' 形式を解釈しない ('xFD' という文字列になる) ため、バイトは '\253' のような 10 進表記で書く
    local clean = s:gsub('\253(.).(.)(.)\253', function(kind, hi, lo)
        return string.format('[atid:%d:%d]', kind:byte(), hi:byte() * 256 + lo:byte())
    end)
    -- 形の違う定型文は中身が分からないので、印だけ残す
    clean = clean:gsub('\253[\001-\252\254\255]+\253', '[atid:0:0]')
    return clean
end

function encoding.normalize_chat_line(s)
    if not s or type(s) ~= 'string' then return '' end

    -- Sanitize Auto-Translate tokens first
    local clean = encoding.sanitize_autotranslate_tokens(s)

    -- Remove Windower control bytes (0x1E, 0x1F, 0x12, 0x13, and 0x01-0x1F/0x7F)
    clean = clean:gsub('\030.', ''):gsub('\031.', ''):gsub('\018.', ''):gsub('\019.', '')
    clean = clean:gsub('\127.', '')  -- 行末記号 0x7F 0x31 などは 2 バイトまとめて消す
    clean = clean:gsub('[\001-\031\127]', '')
    clean = encoding.trim_ascii(clean)
    if clean == '' then return '' end

    -- UTF-8 Fullwidth Symbol Normalization (0xEF 0xBC ...)
    clean = clean:gsub('\239\188\154', ':'):gsub('\239\188\158', '>')
    clean = clean:gsub('\239\188\136', '('):gsub('\239\188\137', ')')
    clean = clean:gsub('\239\188\187', '['):gsub('\239\188\189', ']')

    -- Shift-JIS Fullwidth Symbol Normalization (0x81 ...)
    clean = clean:gsub('\129\070', ':'):gsub('\129\168', '>')
    clean = clean:gsub('\129\105', '('):gsub('\129\106', ')')
    clean = clean:gsub('\129\111', '['):gsub('\129\112', ']')

    return clean
end

return encoding
