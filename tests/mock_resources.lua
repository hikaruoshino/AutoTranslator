-- Windower の resources を、Windower/Resources の resources_data/*.lua から読み込む簡易版 (テスト用)
-- 場所は環境変数 AT_RES (例: /path/to/Resources/resources_data)。
local dir = os.getenv('AT_RES') or '../../res'   -- 既定は Windower の res (AutoTranslator のフォルダーから実行したとき)
return setmetatable({}, {__index = function(t, name)
    local f = assert(loadfile(dir .. '/' .. name .. '.lua'))
    local v = f()
    rawset(t, name, v)
    return v
end})
