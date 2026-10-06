local texts  = require('texts')
local hud = {}

local hud_box = nil
local hud_lines = {}
local on_pos_change_cb = nil
local hud_settings = nil

function hud.init(settings, on_pos_change)
    on_pos_change_cb = on_pos_change
    hud_settings = settings
    local start_x = settings.hud and settings.hud.pos and settings.hud.pos.x or 20
    local start_y = settings.hud and settings.hud.pos and settings.hud.pos.y or 20

    hud_box = texts.new('${text}', {
        pos = { x = start_x, y = start_y },
        text = { size = 11, font = 'Arial', red = 255, green = 255, blue = 255 },
        bg = { alpha = 180, red = 10, green = 10, blue = 10, visible = true },
        flags = { draggable = true },
        padding = 6
    })

    if settings.hud_enabled then
        hud_box:show()
    else
        hud_box:hide()
    end

    windower.register_event('mouse', function(type, x, y, delta, blocked)
        if blocked or not settings.hud_enabled then return end
        if type == 2 then
            local pos_x = hud_box:pos_x()
            local pos_y = hud_box:pos_y()
            if on_pos_change_cb then
                on_pos_change_cb(pos_x, pos_y)
            end
        end
    end)
end

function hud.update(new_line)
    if not hud_box then return end
    table.insert(hud_lines, new_line)
    if #hud_lines > 5 then table.remove(hud_lines, 1) end
    -- チャット用の行は Shift-JIS なので、texts (UTF-8) 用に戻してから表示する
    local text = table.concat(hud_lines, '\n')
    if windower.from_shift_jis then text = windower.from_shift_jis(text) end
    hud_box:text(text)
    -- HUD を OFF にしている間は、翻訳が来ても勝手に表示しない
    if hud_settings == nil or hud_settings.hud_enabled then
        hud_box:show()
    end
end

function hud.toggle()
    if not hud_box then return false end
    if hud_box:visible() then
        hud_box:hide()
        return false
    else
        hud_box:show()
        if #hud_lines == 0 then hud.update('AutoTranslator Native HUD Active') end
        return true
    end
end

function hud.set_pos(x, y)
    if hud_box then
        hud_box:pos(x, y)
    end
end

return hud
