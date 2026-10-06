local lang_detect = {}

function lang_detect.has_japanese(str)
    if not str or str == '' then return false end

    -- Strip Auto-Translate placeholders and brackets
    local clean = str:gsub('【Auto%-Translate】', ''):gsub('【', ''):gsub('】', '')
    clean = clean:gsub('^%s+', ''):gsub('%s+$', '')
    if clean == '' then return false end

    local len = #clean
    for i = 1, len do
        local b1 = string.byte(clean, i)
        local b2 = (i + 1 <= len) and string.byte(clean, i + 1) or 0
        local b3 = (i + 2 <= len) and string.byte(clean, i + 2) or 0

        -- 1. UTF-8 Hiragana / Katakana (E3 81..83 80..BF)
        if b1 == 0xE3 and (b2 >= 0x81 and b2 <= 0x83) and (b3 >= 0x80 and b3 <= 0xBF) then
            return true
        end

        -- 2. UTF-8 CJK Kanji (E4..E9 80..BF 80..BF)
        if (b1 >= 0xE4 and b1 <= 0xE9) and (b2 >= 0x80 and b2 <= 0xBF) and (b3 >= 0x80 and b3 <= 0xBF) then
            return true
        end

        -- 3. Shift-JIS Hiragana (82 9F..F1)
        if b1 == 0x82 and (b2 >= 0x9F and b2 <= 0xF1) then
            return true
        end

        -- 4. Shift-JIS Katakana (83 45..96)
        if b1 == 0x83 and (b2 >= 0x45 and b2 <= 0x96) then
            return true
        end

        -- 5. Shift-JIS Kanji (88..9F / E0..EA)
        if ((b1 >= 0x88 and b1 <= 0x9F) or (b1 >= 0xE0 and b1 <= 0xEA)) and (b2 >= 0x40 and b2 <= 0xFC and b2 ~= 0x7F) then
            return true
        end

        -- 6. Halfwidth Katakana (A1..DF)
        if b1 >= 0xA1 and b1 <= 0xDF then
            return true
        end
    end

    return false
end

return lang_detect
