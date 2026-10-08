-- RSE Stats Inspector 1.0.0. Read-only summary presentation.
-- Engine reference: bryanthaboi/gen1recomp 64af27e075d776a9646298132f7c14bfe138507a.
local mod = ...
local Version = require("src.core.GameVersion")
local game = Version.get()
if game ~= "ruby" and game ~= "sapphire" and game ~= "emerald" then return end

local Font = require("src.ui.game3.frlg_font")
local Kit = require("src.ui.game3.rse.scene_kit")
local Pokemon = require("src.core.game3.pokemon")
local SummaryData = require("src.core.game3.summary_data")
local Audio = require("src.core.game3.audio")
local modes = { "STATS", "IVs", "EVs" }
local values = { "hp", "atk", "def", "spa", "spd", "spe" }
-- SummaryData uses 'spd' for SPEED, unlike the stored IV/EV key 'spe'.
local natureKeys = { "hp", "atk", "def", "spAtk", "spDef", "spd" }
local UP = { 0.08, 0.48, 0.78, 1 }
local DOWN = { 0.85, 0.08, 0.12, 1 }
local states = setmetatable({}, { __mode = "k" })

local function state(menu)
  if not states[menu] then states[menu] = { mode = 1 } end
  return states[menu]
end
local function monOf(menu)
  return menu._loaded or (menu._party and menu._party[menu._cursor])
end
local function copy(t)
  local out = {}
  for k, v in pairs(t or {}) do out[k] = v end
  return out
end
local function number(mon, mode, index)
  local source = mode == 2 and mon.ivs or mon.evs
  local value = type(source) == "table" and tonumber(source[values[index]])
  -- Do not invent zero IVs/EVs for an incomplete imported Pokémon.
  return value and tostring(math.floor(value)) or "--"
end
local function colored(opts, mon, mode, index)
  local result = copy(opts)
  result.colors = copy(opts and opts.colors)
  if mode == 1 and index ~= 1 then
    local nature = (tonumber(mon.personality) or 0) % 25
    local effect = SummaryData.natureStatModifier(nature, natureKeys[index])
    if effect > 1 then result.colors.fg = UP
    elseif effect < 1 then result.colors.fg = DOWN end
  end
  return result
end

-- STATS is baked into the ROM-derived background, not a live text string.
-- Reuse its adjacent blank gold tile, then draw a compact 7-pixel label.
-- The original background is drawn anew every frame (no texture mutation).
local letters = {
  I = { "11111", "00100", "00100", "00100", "00100", "00100", "11111" },
  V = { "10001", "10001", "10001", "10001", "10001", "01010", "00100" },
  E = { "11111", "10000", "10000", "11110", "10000", "10000", "11111" },
  s = { "00000", "00000", "01111", "10000", "01110", "00001", "11110" },
}
local labelQuad, labelImage
local function title(man, mode)
  if mode == 1 then return end
  local entry = man.layers and man.layers.skills
  local img = entry and Kit.image(entry.png)
  if not img then return end
  local g = love.graphics
  g.push("all")
  if labelImage ~= img then
    labelImage = img
    labelQuad = g.newQuad(136, 48, 8, 8, img:getDimensions())
  end
  g.setColor(1, 1, 1, 1)
  for x = 96, 128, 8 do g.draw(img, labelQuad, x, 48) end
  for pass = 1, 2 do
    local offset = pass == 1 and 1 or 0
    if pass == 1 then g.setColor(0.38, 0.36, 0.28, 1) else g.setColor(1, 1, 1, 1) end
    for i = 1, #modes[mode] do
      local glyph = letters[modes[mode]:sub(i, i)]
      for y, row in ipairs(glyph) do
        for x = 1, #row do
          if row:sub(x, x) == "1" then
            g.rectangle("fill", 98 + (i - 1) * 6 + x - 1 + offset, 48 + y - 1 + offset, 1, 1)
          end
        end
      end
    end
  end
  g.pop()
end

local function otherInput(input)
  for _, key in ipairs({ "up", "down", "left", "right", "l", "r", "b", "start" }) do
    if input:wasPressed(key) then return true end
  end
  return false
end
local function cycle(menu, input, ready)
  local mon = monOf(menu)
  if ready and input and menu.open and menu._page == 1 and mon
      and not Pokemon.isEgg(mon) and input:wasPressed("a") and not otherInput(input) then
    local st = state(menu)
    st.mode = st.mode % 3 + 1
    pcall(Audio.playSe, "SE_SELECT")
    return true
  end
  return false
end
local function resetOnOpen(menu)
  local original = menu.openMenu
  menu.openMenu = function(...)
    states[menu] = { mode = 1 }
    return original(...)
  end
end

if game == "emerald" then
  local Skin = require("src.ui.game3.rse.summary_menu")
  local Menu = require("src.ui.game3.summary_menu")
  local PalText = require("src.ui.game3.rse.pal_text")
  if Skin._rseSkillsInspector then return end
  Skin._rseSkillsInspector = true
  resetOnOpen(Menu)
  local oldInput, oldDraw, oldText = Skin.handleInput, Skin.draw, PalText.draw
  local active
  Skin.handleInput = function(input, menu)
    menu = menu or Menu
    if cycle(menu, input, menu._mode ~= "select_move" and not (menu._slide and menu._slide.active)) then return end
    return oldInput(input, menu)
  end
  -- Intercept only the two Skills value windows while this renderer is active.
  -- Labels, items, ribbons, experience and every other screen use native drawing.
  PalText.draw = function(text, x, y, ctx)
    local a = active
    if not a then return oldText(text, x, y, ctx) end
    local left, right = a.man.pageWindows.skills[3], a.man.pageWindows.skills[4]
    local isLeft = x == left.left * 8 + 4 and y == left.top * 8 + 1
    local isRight = x == right.left * 8 + 2 and y == right.top * 8 + 1
    if not isLeft and not isRight then return oldText(text, x, y, ctx) end
    if isLeft then title(a.man, a.mode) end
    local opts = { font = ctx and ctx.font, colors = PalText.colors(ctx.pal, ctx.colors) }
    local mon, st = a.mon, a.mon.stats or {}
    local function stat(short, long)
      return tonumber(mon[long] or mon[short] or st[long] or st[short]) or 0
    end
    local stats = {
      tostring(tonumber(mon.hp) or 0) .. "/" .. tostring(tonumber(mon.maxHp or st.hp) or 0),
      tostring(stat("atk", "attack")), tostring(stat("def", "defense")),
      tostring(stat("spa", "spAtk")), tostring(stat("spd", "spDef")), tostring(stat("spe", "speed")),
    }
    local pitch = ctx.pitch or Font.linePitch()
    local rightEdge = x + Font.measure("0", opts) * (isLeft and 7 or 3)
    for row = 1, 3 do
      local index = row + (isLeft and 0 or 3)
      local value = a.mode == 1 and stats[index] or number(mon, a.mode, index)
      Font.draw(value, rightEdge - Font.measure(value, opts), y + (row - 1) * pitch,
        colored(opts, mon, a.mode, index))
    end
    return rightEdge - x, pitch * 2
  end
  Skin.draw = function(menu)
    menu = menu or Menu
    local previous = active
    local mon, man = monOf(menu), Kit.manifest("rse/summary")
    if menu.open and menu._page == 1 and mon and not Pokemon.isEgg(mon)
        and man and man.pageWindows and man.pageWindows.skills then
      active = { mon = mon, man = man, mode = state(menu).mode }
    else active = nil end
    local ok, err = pcall(oldDraw, menu)
    active = previous
    if not ok then error(err, 0) end
  end
else
  local Menu = require("src.ui.game3.rs.summary_menu")
  if Menu._rseSkillsInspector then return end
  Menu._rseSkillsInspector = true
  resetOnOpen(Menu)
  local oldInput, oldDraw, oldText = Menu.handleInput, Menu.draw, Font.draw
  local active
  Menu.handleInput = function(input)
    local ready = not Menu._fade and not Menu._pageTask and not Menu._reload
      and Menu._selectSetup == nil and Menu._state == "normal"
      and not (Menu._opts and type(Menu._opts.linkBusy) == "function" and Menu._opts.linkBusy())
    if cycle(Menu, input, ready) then return end
    return oldInput(input)
  end
  Font.draw = function(text, x, y, opts)
    local a = active
    if not a or not (tonumber(text) or text == "/") then return oldText(text, x, y, opts) end
    local index
    if y == 56 and x >= 128 and x <= 174 then index = 1
    elseif y == 72 and x >= 128 and x < 176 then index = 2
    elseif y == 88 and x >= 128 and x < 176 then index = 3
    elseif y == 56 and x >= 216 then index = 4
    elseif y == 72 and x >= 216 then index = 5
    elseif y == 88 and x >= 216 then index = 6 end
    if not index then return oldText(text, x, y, opts) end
    if not a.titleDrawn then title(a.man, a.mode); a.titleDrawn = true end
    if a.mode == 1 then return oldText(text, x, y, colored(opts, a.mon, a.mode, index)) end
    -- Native HP is three print calls (current, slash, max); replace only once.
    if a.seen[index] then return 0, x, y end
    a.seen[index] = true
    local value = number(a.mon, a.mode, index)
    local center = index <= 3 and 153 or 225
    return oldText(value, center - math.floor(Font.measure(value, opts) / 2), y, opts)
  end
  Menu.draw = function(...)
    local previous = active
    local mon = monOf(Menu)
    if Menu.open and Menu._page == 1 and Menu._bodyReady and mon and not Pokemon.isEgg(mon) then
      active = { mon = mon, man = Menu._man, mode = state(Menu).mode, seen = {} }
    else active = nil end
    -- Additions occur inside native drawing, BEFORE its fade pass.
    local ok, err = pcall(oldDraw, ...)
    active = previous
    if not ok then error(err, 0) end
  end
end

if mod and mod.log then mod.log:info("RSE Skills Inspector 1.0.0 loaded: " .. game) end
