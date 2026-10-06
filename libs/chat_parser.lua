local encoding = require('libs/encoding')
local chat_parser = {}

function chat_parser.parse(text)
    if not text or text == '' then return "Chat", "" end
    local clean = encoding.normalize_chat_line(text)
    if clean == '' then return "Chat", "" end

    local clean_sub = clean:gsub('^[><]+', ''):gsub('^%s+', '')

    local speaker, msg = clean_sub:match('^%(([^%)]+)%)%s*(.+)$')
    if speaker and msg then return encoding.trim_ascii(speaker), encoding.trim_ascii(msg) end

    speaker, msg = clean_sub:match('^%[([^%]]+)%]%s*(.+)$')
    if speaker and msg then return encoding.trim_ascii(speaker), encoding.trim_ascii(msg) end

    speaker, msg = clean_sub:match('^([^:>]+)%s*[:>]+%s*(.+)$')
    if speaker and msg then return encoding.trim_ascii(speaker), encoding.trim_ascii(msg) end

    return "Chat", clean_sub
end

return chat_parser
