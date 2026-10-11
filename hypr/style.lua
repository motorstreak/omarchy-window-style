-- Omarchy Window Style
--
-- How every window looks: its border (on or off, colour from the theme, width,
-- how solid focused and unfocused), its rounding, its shadow, and how
-- see-through it is. Set once for all windows, and for each kind of window
-- (tiled, floating) only where it should differ: each kind takes the values
-- of `all` it doesn't set itself.
--
--   tiled      Hyprland's own settings (every window starts from these)
--   floating   a window rule for floating windows, and the rounding set on
--              each one as it floats (rules can't round past 20)
--
-- Sidebars (the Sidebar plugin) and pinned windows (the Dock plugin) style
-- their own windows for now.
--
-- Loaded into the running Hyprland by Service.qml with WINDOW_STYLE_DIR set to
-- the plugin folder. Options are set in ~/.config/omarchy/window-style.lua (a
-- Lua file returning a table like `defaults`); anything not there keeps
-- Omarchy's look.

if WINDOW_STYLE_LOADED then
  return
end
if WINDOW_STYLE_DIR == nil then
  error("set WINDOW_STYLE_DIR to the plugin folder before loading style.lua")
end
WINDOW_STYLE_LOADED = true

local home = os.getenv("HOME")
local state_home = os.getenv("XDG_STATE_HOME")
if state_home == nil or state_home == "" then
  state_home = home .. "/.local/state"
end
local quote = o.shell_quote

local function notify(message)
  hl.exec_cmd("notify-send -a 'Window Style' -- 'Window Style' " .. quote(message))
end

local reported = {}
local function guard(context, fn)
  return function(...)
    local ok, err = pcall(fn, ...)
    if not ok then
      local message = context .. ": " .. tostring(err)
      if not reported[message] then
        reported[message] = true
        notify(message)
      end
    end
  end
end

-- Config -----------------------------------------------------------------------

-- What a kind of window can set. Left out (nil), a value comes from `all`, and
-- left out there, it stays Omarchy's (its theme's colours, its 2 px border,
-- square corners, its slight see-through).
local OPTIONS = {
  border = "boolean", -- false: no border
  border_size = "number", -- in pixels
  -- A colour from the theme's colors.toml: "accent", "foreground", a palette
  -- slot ("color1" ... "color15"), a colour name ("green", "cyan", ...), or
  -- "theme" for the theme's own border colour (focused, or unfocused).
  border_colour = "string",
  border_colour_unfocused = "string",
  border_opacity = "number", -- 0 (clear) to 1 (solid)
  border_opacity_unfocused = "number",
  rounding = "number", -- corner radius in pixels; 0 for square
  shadow = "boolean",
  opacity = "number", -- the window itself, 0.1 to 1
  opacity_unfocused = "number",
}
local KINDS = { "all", "tiled", "floating" }

local defaults = {
  all = {},
  tiled = {},
  floating = {},
  -- One shadow look for every window (Hyprland has one): "glow", in the
  -- theme's accent colour, or "shadow", large, faint and dark.
  shadow_look = "glow",
  shadow_size = 6, -- its reach in pixels
  shadow_opacity = 0.2, -- 0 (clear) to 1 (solid)
}

local config = { all = {}, tiled = {}, floating = {} }
for k, v in pairs(defaults) do
  if type(v) ~= "table" then
    config[k] = v
  end
end

do
  local problems = {}
  local chunk, load_err = loadfile(home .. "/.config/omarchy/window-style.lua")
  local overrides = {}
  if chunk then
    local ok, result = pcall(chunk)
    if not ok then
      problems[#problems + 1] = tostring(result)
    elseif type(result) ~= "table" then
      problems[#problems + 1] = "the file must return a table"
    else
      overrides = result
    end
  elseif load_err and not load_err:find("No such file", 1, true) then
    problems[#problems + 1] = load_err
  end
  for k, v in pairs(overrides) do
    if config[k] ~= nil and type(config[k]) == "table" then
      if type(v) ~= "table" then
        problems[#problems + 1] = k .. " must be a table"
      else
        for option, value in pairs(v) do
          if OPTIONS[option] == nil then
            problems[#problems + 1] = "unknown option " .. k .. "." .. tostring(option)
          elseif type(value) ~= OPTIONS[option] then
            problems[#problems + 1] = k .. "." .. option .. " must be a " .. OPTIONS[option]
          else
            config[k][option] = value
          end
        end
      end
    elseif k == "sidebars" or k == "pinned" then
      -- (Read by the Sidebar and Dock plugins.)
    elseif config[k] == nil then
      problems[#problems + 1] = "unknown option " .. tostring(k)
    elseif type(v) ~= type(config[k]) then
      problems[#problems + 1] = k .. " must be a " .. type(config[k])
    else
      config[k] = v
    end
  end
  if config.shadow_look ~= "glow" and config.shadow_look ~= "shadow" then
    problems[#problems + 1] = 'shadow_look must be "glow" or "shadow"'
    config.shadow_look = "glow"
  end
  if #problems > 0 then
    notify("Problems in ~/.config/omarchy/window-style.lua: " .. table.concat(problems, "; "))
  end
end

-- A kind's value for an option: its own, else all windows'.
local function value(kind, option)
  local v = config[kind][option]
  if v == nil then
    v = config.all[option]
  end
  return v
end

-- Colours ----------------------------------------------------------------------

local theme_colors = ""
do
  local f = io.open(state_home .. "/omarchy/current/theme/colors.toml", "r")
  if f then
    theme_colors = "\n" .. f:read("a")
    f:close()
  end
end
-- The slots behind colour names, for themes that only give the palette.
local PALETTE = {
  red = "color1", green = "color2", yellow = "color3", blue = "color4", magenta = "color5", cyan = "color6",
  bright_red = "color9", bright_green = "color10", bright_yellow = "color11",
  bright_blue = "color12", bright_magenta = "color13", bright_cyan = "color14",
}
local function colour_in(colors, name)
  local pattern = '%s*=%s*"#?(%x%x%x%x%x%x)"'
  return colors:match("\n%s*" .. name .. pattern)
    or (PALETTE[name] and colors:match("\n%s*" .. PALETTE[name] .. pattern))
end

-- The theme's own border colours, as "rrggbb" and alpha (0-255), read before
-- this changes them (a reload sets them afresh first).
local function theme_border(option)
  local g = hl.get_config(option)
  local c = g and g.colors and g.colors[1]
  if type(c) == "number" then
    c = string.format("0x%08X", c)
  end
  local alpha, rgb = tostring(c):match("^0[xX](%x%x)(%x%x%x%x%x%x)$")
  if rgb then
    return rgb, tonumber(alpha, 16)
  end
end
local theme_active = { theme_border("general:col.active_border") }
local theme_inactive = { theme_border("general:col.inactive_border") }

-- A kind's border colours as Hyprland takes them: "rgba(rrggbbaa)", focused and
-- unfocused; nil for one left as it is.
local function border_colours(kind)
  local function one(name, opacity, theme)
    if name == nil and opacity == nil then
      return nil
    end
    local rgb, alpha = theme[1], theme[2]
    if name ~= nil and name ~= "theme" then
      rgb = colour_in(theme_colors, name)
      alpha = 255
      if rgb == nil then
        notify("No colour \"" .. name .. "\" in the theme; that border keeps the theme's")
        rgb, alpha = theme[1], theme[2]
      end
    end
    if rgb == nil then
      return nil
    end
    if opacity ~= nil then
      alpha = math.floor(math.max(0, math.min(1, opacity)) * 255 + 0.5)
    end
    return string.format("rgba(%s%02x)", rgb, alpha)
  end
  return one(value(kind, "border_colour"), value(kind, "border_opacity"), theme_active),
    one(value(kind, "border_colour_unfocused"), value(kind, "border_opacity_unfocused"), theme_inactive)
end

local function border_width(kind)
  if value(kind, "border") == false then
    return 0
  end
  return value(kind, "border_size")
end

-- Tiled: Hyprland's settings ------------------------------------------------------

do
  local general, decoration = {}, {}
  local width = border_width("tiled")
  if width then
    general.border_size = math.floor(width)
  end
  local active, inactive = border_colours("tiled")
  if active or inactive then
    general.col = { active_border = active, inactive_border = inactive }
  end
  local rounding = value("tiled", "rounding")
  if rounding then
    decoration.rounding = math.floor(rounding)
  end
  if next(general) then
    hl.config({ general = general })
  end
  if next(decoration) then
    hl.config({ decoration = decoration })
  end
end

-- Omarchy makes windows slightly see-through with a rule on the windows tagged
-- "default-opacity" (apps that should stay solid drop the tag): so this does
-- the same, for the same windows.
local function opacity_of(kind)
  local a, i = value(kind, "opacity"), value(kind, "opacity_unfocused")
  if a == nil and i == nil then
    return nil
  end
  a = a or 1
  i = i or a
  return string.format("%.3f %.3f", math.max(0.1, math.min(1, a)), math.max(0.1, math.min(1, i)))
end
do
  local o_tiled = opacity_of("tiled")
  if o_tiled then
    hl.window_rule({ name = "window-style-tiled-opacity", match = { tag = "default-opacity", float = false },
      opacity = o_tiled })
  end
end

-- Floating: a rule, and rounding per window ---------------------------------------

-- What floating windows change from tiled ones.
local function differs(option)
  return value("floating", option) ~= value("tiled", option)
end

do
  local rule = {}
  if differs("border") or differs("border_size") then
    local width = border_width("floating")
    if width then
      rule.border_size = math.floor(width)
    end
  end
  if differs("border_colour") or differs("border_colour_unfocused")
      or differs("border_opacity") or differs("border_opacity_unfocused") then
    local active, inactive = border_colours("floating")
    -- A rule sets both: one left as it is is the tiled one.
    local tiled_active, tiled_inactive = border_colours("tiled")
    active = active or tiled_active
    inactive = inactive or tiled_inactive
    if active then
      rule.border_color = active .. " " .. (inactive or active)
    end
  end
  if next(rule) then
    rule.name = "window-style-floating"
    rule.match = { float = true }
    hl.window_rule(rule)
  end
  local o_floating = opacity_of("floating")
  if o_floating and (differs("opacity") or differs("opacity_unfocused")) then
    hl.window_rule({ name = "window-style-floating-opacity", match = { tag = "default-opacity", float = true },
      opacity = o_floating })
  end
end

-- Rounding: a rule can't go past 20, and Omarchy's popped-out windows (SUPER +
-- O) have a rule of their own. So each floating window gets it set, and loses
-- it again once tiled. Sidebars are the Sidebar plugin's.
local rounded = {} -- address -> true: set here
local function floating_rounding()
  local r = value("floating", "rounding")
  return r and math.floor(r) or nil
end

local function is_sidebar(window)
  local ws = window.workspace and window.workspace.name or ""
  return ws:match("^special:sidebar%d*$") ~= nil
end

local function round(window)
  local r = floating_rounding()
  if window == nil or r == nil or is_sidebar(window) then
    return
  end
  local selector = "address:" .. window.address
  if window.floating then
    hl.dispatch(hl.dsp.window.set_prop({ prop = "rounding", value = tostring(r), window = selector }))
    rounded[window.address] = true
  elseif rounded[window.address] then
    hl.dispatch(hl.dsp.window.set_prop({ prop = "rounding", value = "unset", window = selector }))
    rounded[window.address] = nil
  end
end

if floating_rounding() then
  hl.on("window.update_rules", guard("rounding a floating window", round))
  hl.on("window.close", function(window)
    if window and window.address then
      rounded[window.address] = nil
    end
  end)
  for _, w in ipairs(hl.get_windows()) do
    guard("rounding a floating window", round)(w)
  end
end

-- Shadows -------------------------------------------------------------------------

-- Hyprland has one shadow switch and look for every window. When tiled or
-- floating windows want one: on, in the chosen look, with a rule taking it off
-- every window and others giving it back to those kinds. (The Sidebar and
-- Dock plugins give theirs their own way, for now.)
local shadow_tiled, shadow_floating = value("tiled", "shadow") == true, value("floating", "shadow") == true
if shadow_tiled or shadow_floating then
  local alpha = string.format("%02x", math.floor(math.max(0, math.min(1, config.shadow_opacity)) * 255 + 0.5))
  local look
  if config.shadow_look == "glow" then
    local rgb = colour_in(theme_colors, "accent") or theme_active[1] or "000000"
    look = { enabled = true, range = math.floor(config.shadow_size), render_power = 3, offset = { 0, 0 },
      color = "rgba(" .. rgb .. alpha .. ")", color_inactive = "rgba(" .. rgb .. "00)" }
  else
    look = { enabled = true, range = math.floor(config.shadow_size), render_power = 2, offset = { 0, 0 },
      color = "rgba(000000" .. alpha .. ")" }
  end
  hl.config({ decoration = { shadow = look } })
  hl.window_rule({ name = "window-style-no-shadow", match = { class = ".*" }, no_shadow = true })
  if shadow_tiled then
    hl.window_rule({ name = "window-style-tiled-shadow", match = { float = false }, no_shadow = false })
  end
  if shadow_floating then
    hl.window_rule({ name = "window-style-floating-shadow", match = { float = true }, no_shadow = false })
  end
end

-- For the settings panel (later) and tests: `hyprctl eval 'window_style.value("floating", "rounding")'`.
window_style = {
  value = value,
  border_colours = border_colours,
  config = config,
}
