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
--   sidebars   (the Sidebar plugin) and
--   pinned     (the Dock plugin) style their windows when they take them in,
--              asking `window_style.look(kind)` for how
--
-- Shadows are this plugin's alone: Hyprland has one switch and look for every
-- window, which the Sidebar and Dock plugins leave to it when it's installed.
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
local KINDS = { "all", "tiled", "floating", "sidebars", "pinned" }

local defaults = {
  all = {},
  tiled = {},
  floating = {},
  sidebars = {},
  pinned = {},
  -- One shadow look for every window (Hyprland has one): "glow", in the
  -- theme's accent colour, or "shadow", large, faint and dark.
  shadow_look = "glow",
  shadow_size = 6, -- its reach in pixels
  shadow_opacity = 0.2, -- 0 (clear) to 1 (solid)
}

local config = { all = {}, tiled = {}, floating = {}, sidebars = {}, pinned = {} }
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
-- Omarchy's own width and rounding, likewise, for an option set and then
-- taken out again.
local omarchy_border_size = tonumber(hl.get_config("general:border_size")) or 2
local omarchy_rounding = tonumber(hl.get_config("decoration:rounding")) or 0

-- A kind's border colours as Hyprland takes them: "rgba(rrggbbaa)", focused and
-- unfocused; nil for one left as it is.
local function border_colours(kind, colors)
  colors = colors or theme_colors
  local function one(name, opacity, theme)
    if name == nil and opacity == nil then
      return nil
    end
    local rgb, alpha = theme[1], theme[2]
    if name ~= nil and name ~= "theme" then
      rgb = colour_in(colors, name)
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

-- Applying ----------------------------------------------------------------------
--
-- Everything is applied by `apply`, again after every change from the settings
-- panel: Hyprland's settings for tiled windows, named rules (made again under
-- the same name, which replaces them at once, or turned off), the rounding of
-- each floating window, the shadow switch, and sidebars and pinned windows
-- through their plugins.

local function rule(name, spec)
  spec.name = name
  hl.window_rule(spec)
end
local function no_rule(name)
  hl.window_rule({ name = name, enabled = false, match = { class = "^$" } })
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

-- What floating windows change from tiled ones.
local function differs(option)
  return value("floating", option) ~= value("tiled", option)
end

-- Rounding: a rule can't go past 20, and Omarchy's popped-out windows (SUPER +
-- O) have a rule of their own. So each floating window gets it set, and loses
-- it again once tiled. Sidebars are the Sidebar plugin's.
local rounded = {} -- address -> true: set here
local function is_sidebar(window)
  local ws = window.workspace and window.workspace.name or ""
  return ws:match("^special:sidebar%d*$") ~= nil
end
local function round(window)
  if window == nil or is_sidebar(window) then
    return
  end
  local r = value("floating", "rounding")
  local selector = "address:" .. window.address
  if window.floating and r then
    hl.dispatch(hl.dsp.window.set_prop({ prop = "rounding", value = tostring(math.floor(r)), window = selector }))
    rounded[window.address] = true
  elseif rounded[window.address] then
    hl.dispatch(hl.dsp.window.set_prop({ prop = "rounding", value = "unset", window = selector }))
    rounded[window.address] = nil
  end
end
hl.on("window.update_rules", guard("rounding a floating window", round))
hl.on("window.close", function(window)
  if window and window.address then
    rounded[window.address] = nil
  end
end)

local function apply()
  -- Tiled: Hyprland's own settings, Omarchy's where nothing is set.
  local width = border_width("tiled")
  local active, inactive = border_colours("tiled")
  local function theme_rgba(t)
    return t[1] and string.format("rgba(%s%02x)", t[1], t[2] or 255) or nil
  end
  hl.config({ general = {
    border_size = math.floor(width or omarchy_border_size),
    col = { active_border = active or theme_rgba(theme_active), inactive_border = inactive or theme_rgba(theme_inactive) },
  } })
  local rounding = value("tiled", "rounding")
  hl.config({ decoration = { rounding = math.floor(rounding or omarchy_rounding) } })
  local o_tiled = opacity_of("tiled")
  if o_tiled then
    rule("window-style-tiled-opacity", { match = { tag = "default-opacity", float = false }, opacity = o_tiled })
  else
    no_rule("window-style-tiled-opacity")
  end

  -- Floating: a rule for what differs from tiled.
  local spec = {}
  if differs("border") or differs("border_size") then
    local w = border_width("floating")
    spec.border_size = math.floor(w or omarchy_border_size)
  end
  if differs("border_colour") or differs("border_colour_unfocused")
      or differs("border_opacity") or differs("border_opacity_unfocused") then
    local a, i = border_colours("floating")
    a = a or active or theme_rgba(theme_active)
    i = i or inactive or theme_rgba(theme_inactive)
    if a then
      spec.border_color = a .. " " .. (i or a)
    end
  end
  if next(spec) then
    spec.match = { float = true }
    rule("window-style-floating", spec)
  else
    no_rule("window-style-floating")
  end
  local o_floating = opacity_of("floating")
  if o_floating and (differs("opacity") or differs("opacity_unfocused")) then
    rule("window-style-floating-opacity", { match = { tag = "default-opacity", float = true }, opacity = o_floating })
  else
    no_rule("window-style-floating-opacity")
  end
  for _, w in ipairs(hl.get_windows()) do
    guard("rounding a floating window", round)(w)
  end

  -- Shadows. Hyprland has one switch and look for every window. When any kind
  -- wants one: on, in the chosen look, with a rule taking it off every window
  -- and others giving it back to tiled or floating ones; sidebars and pinned
  -- windows get theirs back from their plugins. Otherwise off (also when
  -- another plugin had turned it on).
  local shadow_tiled, shadow_floating = value("tiled", "shadow") == true, value("floating", "shadow") == true
  local any = shadow_tiled or shadow_floating or value("sidebars", "shadow") == true
    or value("pinned", "shadow") == true
  if any then
    local alpha = string.format("%02x", math.floor(math.max(0, math.min(1, config.shadow_opacity)) * 255 + 0.5))
    local look
    if config.shadow_look == "glow" then
      local rgb = colour_in(theme_colors, "accent") or theme_active[1] or "000000"
      look = { enabled = true, range = math.floor(config.shadow_size), render_power = 3, offset = { 0, 0 },
        color = "rgba(" .. rgb .. alpha .. ")", color_inactive = "rgba(" .. rgb .. "00)" }
    else
      look = { enabled = true, range = math.floor(config.shadow_size), render_power = 2, offset = { 0, 0 },
        color = "rgba(000000" .. alpha .. ")", color_inactive = "rgba(000000" .. alpha .. ")" }
    end
    hl.config({ decoration = { shadow = look } })
    rule("window-style-no-shadow", { match = { class = ".*" }, no_shadow = true })
  else
    hl.config({ decoration = { shadow = { enabled = false } } })
    no_rule("window-style-no-shadow")
  end
  if any and shadow_tiled then
    rule("window-style-tiled-shadow", { match = { float = false }, no_shadow = false })
  else
    no_rule("window-style-tiled-shadow")
  end
  if any and shadow_floating then
    rule("window-style-floating-shadow", { match = { float = true }, no_shadow = false })
  else
    no_rule("window-style-floating-shadow")
  end

  -- Sidebars and pinned windows: their plugins style them, asking `look`.
  if type(sidebar) == "table" and sidebar.retheme then
    sidebar.retheme()
  end
  if type(dock) == "table" and dock.restyle then
    dock.restyle()
  end
end

-- How a sidebar or pinned window looks, for the plugins that style them:
-- { border_size, active, inactive (colours, "rgba(...)"), rounding, shadow },
-- each nil to leave it to Hyprland. `colors` is another theme's colors.toml
-- (as text) to take the colour from, for a sidebar given a theme of its own.
local function look(kind, colors)
  if config[kind] == nil then
    return nil
  end
  local active, inactive = border_colours(kind, colors)
  local width = border_width(kind)
  local rounding = value(kind, "rounding")
  return {
    border_size = width and math.floor(width) or nil,
    active = active,
    inactive = inactive,
    rounding = rounding and math.floor(rounding) or nil,
    shadow = value(kind, "shadow") == true,
  }
end

-- Saving --------------------------------------------------------------------------

-- The file is this plugin's: written whole on every change from the panel
-- (a comment of yours in it isn't kept).
local config_file = home .. "/.config/omarchy/window-style.lua"
local ORDER = { "border", "border_size", "border_colour", "border_opacity", "border_colour_unfocused",
  "border_opacity_unfocused", "rounding", "shadow", "opacity", "opacity_unfocused" }
local function lua_value(v)
  if type(v) == "string" then
    return string.format("%q", v)
  elseif type(v) == "number" then
    return (string.format("%.3f", v):gsub("0+$", ""):gsub("%.$", ""))
  end
  return tostring(v)
end
local function save()
  local lines = {
    "-- Window Style plugin: how windows look. Written by its settings panel",
    "-- (SUPER + CTRL + ALT + S); edits here work too. `all` is every window; each",
    "-- kind sets only what differs from it.",
    "return {",
  }
  for _, kind in ipairs(KINDS) do
    local set = {}
    for _, option in ipairs(ORDER) do
      if config[kind][option] ~= nil then
        set[#set + 1] = "    " .. option .. " = " .. lua_value(config[kind][option]) .. ","
      end
    end
    if #set > 0 then
      lines[#lines + 1] = "  " .. kind .. " = {"
      for _, l in ipairs(set) do
        lines[#lines + 1] = l
      end
      lines[#lines + 1] = "  },"
    end
  end
  for _, k in ipairs({ "shadow_look", "shadow_size", "shadow_opacity" }) do
    if config[k] ~= defaults[k] then
      lines[#lines + 1] = "  " .. k .. " = " .. lua_value(config[k]) .. ","
    end
  end
  lines[#lines + 1] = "}"
  -- Written through, so a link (dotfiles) stays a link.
  local f = io.open(config_file, "w")
  if f then
    f:write(table.concat(lines, "\n"), "\n")
    f:close()
  end
end

-- One change from the panel: applied at once, then saved. `option` nil-valued
-- (`value` nil) takes it out, back to all windows' (or Omarchy's).
local function set(kind, option, v)
  if config[kind] ~= nil and OPTIONS[option] then
    if v ~= nil and type(v) ~= OPTIONS[option] then
      return
    end
    config[kind][option] = v
  elseif option == nil and (kind == "shadow_look" or kind == "shadow_size" or kind == "shadow_opacity") then
    if type(v) ~= type(defaults[kind]) then
      return
    end
    config[kind] = v
  else
    return
  end
  apply()
  save()
end

-- A kind (or everything, for "everything") back to as if nothing were set.
local function reset(kind)
  if kind == "everything" then
    for _, k in ipairs(KINDS) do
      config[k] = {}
    end
    for _, k in ipairs({ "shadow_look", "shadow_size", "shadow_opacity" }) do
      config[k] = defaults[k]
    end
  elseif config[kind] ~= nil then
    config[kind] = {}
  else
    return
  end
  apply()
  save()
end

-- The settings panel -----------------------------------------------------------------

local function json_string(v)
  return '"' .. tostring(v):gsub('[%c"\\]', function(c)
    return string.format("\\u%04x", c:byte())
  end) .. '"'
end
local function json(v)
  if type(v) == "string" then
    return json_string(v)
  elseif type(v) == "number" then
    return string.format("%.4g", v)
  elseif type(v) == "boolean" then
    return tostring(v)
  end
  return "null"
end

-- SUPER + CTRL + ALT + S (or the Sidebar plugin's settings): StylePanel.qml with
-- every kind's options as set (null: from all windows, or Omarchy's), and the
-- theme's colours to pick from. `tab` opens it on that kind.
local function open(tab)
  local kinds = {}
  for _, kind in ipairs(KINDS) do
    local parts = {}
    for _, option in ipairs(ORDER) do
      parts[#parts + 1] = json_string(option) .. ":" .. json(config[kind][option])
    end
    kinds[#kinds + 1] = json_string(kind) .. ":{" .. table.concat(parts, ",") .. "}"
  end
  local colours = {}
  local function add(name, label, hex)
    if hex then
      colours[#colours + 1] = string.format('{"name":%s,"label":%s,"hex":%s}', json_string(name),
        json_string(label), json_string("#" .. hex))
    end
  end
  add("theme", "theme's own", theme_active[1])
  add("accent", "accent", colour_in(theme_colors, "accent"))
  add("foreground", "text colour", colour_in(theme_colors, "foreground"))
  for i = 1, 6 do
    add("color" .. i, "palette " .. i, colour_in(theme_colors, "color" .. i))
  end
  for i = 9, 14 do
    add("color" .. i, "bright " .. (i - 8), colour_in(theme_colors, "color" .. i))
  end
  local present = {
    '"sidebars":' .. tostring(type(sidebar) == "table"),
    '"pinned":' .. tostring(type(dock) == "table"),
  }
  local m = hl.get_active_monitor()
  local payload = string.format(
    '{"monitor":%s,"tab":%s,"kinds":{%s},"present":{%s},"colours":[%s],"theme_unfocused":%s,'
      .. '"omarchy":{"border_size":%d,"rounding":%d},"shadow":{"look":%s,"size":%s,"opacity":%s}}',
    json_string(m and m.name or ""), json_string(tab or "all"), table.concat(kinds, ","),
    table.concat(present, ","), table.concat(colours, ","),
    json_string(theme_inactive[1] and ("#" .. theme_inactive[1]) or ""),
    omarchy_border_size, omarchy_rounding,
    json(config.shadow_look), json(config.shadow_size), json(config.shadow_opacity))
  hl.exec_cmd("omarchy-shell -q window-style-panel open " .. quote(payload))
end

local PANEL_KEY = "SUPER + CTRL + ALT + S"
hl.unbind(PANEL_KEY)
o.bind(PANEL_KEY, "Window style", guard("opening the window style", function()
  open("all")
end))

-- For the plugins, the settings panel and tests.
window_style = {
  look = look,
  value = value,
  border_colours = border_colours,
  config = config,
  set = set,
  reset = reset,
  open = open,
  apply = apply,
}

-- Sidebars and pinned windows already styled before this loaded get these
-- looks once the others have loaded too.
guard("applying the window style", apply)()
hl.timer(guard("restyling sidebars and pinned windows", function()
  if type(sidebar) == "table" and sidebar.retheme then
    sidebar.retheme()
  end
  if type(dock) == "table" and dock.restyle then
    dock.restyle()
  end
end), { timeout = 50, type = "oneshot" })
