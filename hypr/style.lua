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
--   popped     windows popped out with Omarchy's SUPER + O (tagged "pop"): as
--              floating ones unless set here (it takes floating's values,
--              not all's), by rules on the tag
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
  -- An Omarchy theme (its folder name) to take this kind's colours from, or
  -- "current" for the one in use.
  theme = "string",
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
  -- Menus only: how solid their background is, 0 to 1.
  background_opacity = "number",
}
local KINDS = { "all", "tiled", "floating", "popped", "sidebars", "pinned", "menus" }

local defaults = {
  all = {},
  tiled = {},
  floating = {},
  popped = {},
  sidebars = {},
  pinned = {},
  menus = {},
  -- One shadow look for every window (Hyprland has one): "glow", in the
  -- theme's accent colour, or "shadow", large, faint and dark.
  shadow_look = "glow",
  shadow_size = 6, -- its reach in pixels
  shadow_opacity = 0.2, -- 0 (clear) to 1 (solid)
  shadow_unfocused = true, -- false: only the focused window has one
}

local config = { all = {}, tiled = {}, floating = {}, popped = {}, sidebars = {}, pinned = {}, menus = {} }
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
  if v == nil and kind == "popped" then
    return value("floating", option)
  end
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
-- And the other way round, for themes that only name them ("color2" is
-- "green").
local SLOT_NAME = {}
for name, slot in pairs(PALETTE) do
  SLOT_NAME[slot] = name
end
local function colour_in(colors, name)
  local pattern = '%s*=%s*"#?(%x%x%x%x%x%x)"'
  return colors:match("\n%s*" .. name .. pattern)
    or (PALETTE[name] and colors:match("\n%s*" .. PALETTE[name] .. pattern))
    or (SLOT_NAME[name] and colors:match("\n%s*" .. SLOT_NAME[name] .. pattern))
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

-- Another theme's colors.toml, as text (yours before Omarchy's).
local omarchy_path = os.getenv("OMARCHY_PATH") or "/usr/share/omarchy"
local function theme_colors_of(name)
  for _, root in ipairs({ home .. "/.config/omarchy/themes/", omarchy_path .. "/themes/" }) do
    local f = io.open(root .. name .. "/colors.toml", "r")
    if f then
      local text = "\n" .. f:read("a")
      f:close()
      return text
    end
  end
end

-- Another theme's hyprland.conf, as text, where it has one: many set their
-- border colours there rather than in colors.toml.
local function theme_conf_of(name)
  for _, root in ipairs({ home .. "/.config/omarchy/themes/", omarchy_path .. "/themes/" }) do
    if io.open(root .. name .. "/colors.toml", "r") then
      local f = io.open(root .. name .. "/hyprland.conf", "r")
      if f == nil then
        return nil
      end
      local text = "\n" .. f:read("a")
      f:close()
      return text
    end
  end
end

-- The first colour of a border option in a theme's hyprland.conf, through a
-- $variable if it names one: "rrggbb" and alpha (0-255).
local function conf_border(conf, option)
  local spec = conf and conf:match("\n[ \t]*col%." .. option .. "[ \t]*=[ \t]*([^\n#]+)")
  local var = spec and spec:match("^%$([%w_]+)")
  if var then
    spec = conf:match("\n[ \t]*%$" .. var .. "[ \t]*=[ \t]*([^\n#]+)")
  end
  if spec == nil then
    return nil
  end
  local rgb, alpha = spec:match("rgba%((%x%x%x%x%x%x)(%x%x)%)")
  if rgb == nil then
    rgb = spec:match("rgb%((%x%x%x%x%x%x)%)")
    alpha = "ff"
  end
  if rgb == nil then
    alpha, rgb = spec:match("0[xX](%x%x)(%x%x%x%x%x%x)")
  end
  if rgb then
    return rgb, tonumber(alpha, 16)
  end
end

-- A theme's own border colours: those its hyprland.conf sets, else (as
-- Omarchy makes them from its colors.toml) its hyprland_active_border (the
-- first colour of it), else its accent; and its hyprland_inactive_border,
-- else Omarchy's grey.
local function own_border(colors, conf)
  local function first(key)
    local spec = colors:match("\n%s*" .. key .. '%s*=%s*"([^"]*)"')
    if spec == nil then
      return nil
    end
    local rgb, alpha = spec:match("rgba?%((%x%x%x%x%x%x)(%x?%x?)%)")
    if rgb then
      return rgb, alpha ~= "" and tonumber(alpha, 16) or 255
    end
  end
  local a = { conf_border(conf, "active_border") }
  if a[1] == nil then
    a = { first("hyprland_active_border") }
  end
  if a[1] == nil then
    a = { colors:match('\n%s*accent%s*=%s*"#?(%x%x%x%x%x%x)"'), 255 }
  end
  local i = { conf_border(conf, "inactive_border") }
  if i[1] == nil then
    i = { first("hyprland_inactive_border") }
  end
  if i[1] == nil then
    i = { "595959", 170 }
  end
  return a, i
end

-- The colours a kind takes: its theme's (a sidebar's own theme, from the
-- Sidebar plugin, comes as `colors`), and that theme's own border colours.
local function kind_colors(kind, colors)
  local name = value(kind, "theme")
  if colors == nil and name and name ~= "current" then
    colors = theme_colors_of(name)
  end
  if colors == nil then
    return theme_colors, theme_active, theme_inactive
  end
  local a, i = own_border(colors, name and name ~= "current" and theme_conf_of(name) or nil)
  return colors, a, i
end

-- A kind's border colours as Hyprland takes them: "rgba(rrggbbaa)", focused and
-- unfocused; nil for one left as it is.
local missing = {} -- colour names already reported
local function border_colours(kind, given)
  local colors, own_active, own_inactive = kind_colors(kind, given)
  local function one(name, opacity, theme)
    if name == nil and opacity == nil then
      return nil
    end
    local rgb, alpha = theme[1], theme[2]
    if name ~= nil and name ~= "theme" then
      rgb = colour_in(colors, name)
      alpha = 255
      if rgb == nil then
        if not missing[name] then
          missing[name] = true
          notify("No colour \"" .. name .. "\" in the theme; that border keeps the theme's")
        end
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
  return one(value(kind, "border_colour"), value(kind, "border_opacity"), own_active),
    one(value(kind, "border_colour_unfocused"), value(kind, "border_opacity_unfocused"), own_inactive)
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

-- A named rule made again replaces the one before, but keeps any match field
-- the new one doesn't give: so a rule is turned off with its own match (one
-- turned off by matching nothing could never match again), and on explicitly.
local function rule(name, spec)
  spec.name = name
  spec.enabled = true
  hl.window_rule(spec)
end
local function no_rule(name, match)
  hl.window_rule({ name = name, enabled = false, match = match })
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
local function is_popped(window)
  for _, tag in ipairs(window.tags or {}) do
    if tag:gsub("%*$", "") == "pop" then
      return true
    end
  end
  return false
end
-- Border colours: a window the Sidebar or Dock plugin let go of keeps the
-- colours they set on it, which beat any rule (and "unset" leaves it with
-- none). So a popped-out window gets its colours set on it here, and keeps
-- getting its kind's (floating or tiled) once back in, as they change. Sidebars
-- and docked windows are their plugins'.
local framed = {} -- address -> true: colours set here
local function rgba_of(t)
  return t[1] and string.format("rgba(%s%02x)", t[1], t[2] or 255) or nil
end
local function frame(window)
  local popped = is_popped(window)
  if not popped and (not framed[window.address] or window.pinned) then
    return
  end
  local kind = popped and "popped" or (window.floating and "floating" or "tiled")
  local a, i = border_colours(kind)
  local ta, ti = border_colours("tiled")
  a = a or ta or rgba_of(theme_active)
  i = i or ti or rgba_of(theme_inactive)
  local selector = "address:" .. window.address
  if a then
    hl.dispatch(hl.dsp.window.set_prop({ prop = "active_border_color", value = a, window = selector }))
  end
  if i then
    hl.dispatch(hl.dsp.window.set_prop({ prop = "inactive_border_color", value = i, window = selector }))
  end
  framed[window.address] = true
end

local function round(window)
  if window == nil or is_sidebar(window) then
    return
  end
  frame(window)
  local r = value(is_popped(window) and "popped" or "floating", "rounding")
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
    framed[window.address] = nil
  end
end)

local write_menus -- defined with the menus, below
local shell_rounding -- the rounding the shell was last told of

-- The shadow switch and look (Hyprland's one for every window). On its own,
-- for the global shadow settings: their arrows change it many times a second.
local function apply_shadow()
  local any = value("tiled", "shadow") == true or value("floating", "shadow") == true
    or value("popped", "shadow") == true or value("sidebars", "shadow") == true
    or value("pinned", "shadow") == true
  if any then
    local alpha = string.format("%02x", math.floor(math.max(0, math.min(1, config.shadow_opacity)) * 255 + 0.5))
    local look
    if config.shadow_look == "glow" then
      local rgb = colour_in(theme_colors, "accent") or theme_active[1] or "000000"
      look = { enabled = true, range = math.floor(config.shadow_size), render_power = 3, offset = { 0, 0 },
        color = "rgba(" .. rgb .. alpha .. ")",
        color_inactive = "rgba(" .. rgb .. (config.shadow_unfocused and alpha or "00") .. ")" }
    else
      look = { enabled = true, range = math.floor(config.shadow_size), render_power = 2, offset = { 0, 0 },
        color = "rgba(000000" .. alpha .. ")",
        color_inactive = "rgba(000000" .. (config.shadow_unfocused and alpha or "00") .. ")" }
    end
    hl.config({ decoration = { shadow = look } })
  else
    hl.config({ decoration = { shadow = { enabled = false } } })
  end
end

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
  local rounding = math.floor(value("tiled", "rounding") or omarchy_rounding)
  hl.config({ decoration = { rounding = rounding } })
  -- The shell's menus and panels round as Hyprland does, but it reads that
  -- only on a theme change: tell it.
  if rounding ~= shell_rounding then
    shell_rounding = rounding
    hl.exec_cmd("omarchy-shell -q window-style-panel restyle")
  end
  local o_tiled = opacity_of("tiled")
  if o_tiled then
    rule("window-style-tiled-opacity", { match = { tag = "default-opacity", float = false }, opacity = o_tiled })
  else
    no_rule("window-style-tiled-opacity", { tag = "default-opacity", float = false })
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
    no_rule("window-style-floating", { float = true })
  end
  local o_floating = opacity_of("floating")
  if o_floating and (differs("opacity") or differs("opacity_unfocused")) then
    rule("window-style-floating-opacity", { match = { tag = "default-opacity", float = true }, opacity = o_floating })
  else
    no_rule("window-style-floating-opacity", { tag = "default-opacity", float = true })
  end

  -- Popped out: rules on Omarchy's "pop" tag for what differs from floating
  -- (made after the floating ones, so they win).
  local function differs_popped(option)
    return value("popped", option) ~= value("floating", option)
  end
  local pspec = {}
  if differs_popped("border") or differs_popped("border_size") then
    local w = border_width("popped")
    pspec.border_size = math.floor(w or omarchy_border_size)
  end
  if differs_popped("border_colour") or differs_popped("border_colour_unfocused")
      or differs_popped("border_opacity") or differs_popped("border_opacity_unfocused") then
    local a, i = border_colours("popped")
    a = a or active or theme_rgba(theme_active)
    i = i or inactive or theme_rgba(theme_inactive)
    if a then
      pspec.border_color = a .. " " .. (i or a)
    end
  end
  if next(pspec) then
    pspec.match = { tag = "pop" }
    rule("window-style-popped", pspec)
  else
    no_rule("window-style-popped", { tag = "pop" })
  end
  local o_popped = opacity_of("popped")
  if o_popped and (differs_popped("opacity") or differs_popped("opacity_unfocused")) then
    rule("window-style-popped-opacity", { match = { tag = "pop" }, opacity = o_popped })
  else
    no_rule("window-style-popped-opacity", { tag = "pop" })
  end
  -- A rule made new doesn't reach windows already open (a replaced one does):
  -- the windows popped out now take the tag again, which checks their rules.
  for _, w in ipairs(hl.get_windows()) do
    if is_popped(w) then
      local selector = "address:" .. w.address
      hl.dispatch(hl.dsp.window.tag({ tag = "-pop", window = selector }))
      hl.dispatch(hl.dsp.window.tag({ tag = "+pop", window = selector }))
    end
  end
  for _, w in ipairs(hl.get_windows()) do
    guard("rounding a floating window", round)(w)
  end

  -- Shadows. Hyprland has one switch and look for every window. When any kind
  -- wants one: on, in the chosen look, with a rule taking it off tiled or
  -- floating windows if they don't want it; sidebars and pinned windows get
  -- theirs from their plugins. Otherwise off (also when another plugin had
  -- turned it on). The two rules always exist, and only their value changes:
  -- open windows take a replaced rule at once, but not a new one.
  local shadow_tiled, shadow_floating = value("tiled", "shadow") == true, value("floating", "shadow") == true
  local shadow_popped = value("popped", "shadow") == true
  apply_shadow()
  rule("window-style-tiled-no-shadow", { match = { float = false }, no_shadow = not shadow_tiled })
  rule("window-style-floating-no-shadow", { match = { float = true }, no_shadow = not shadow_floating })
  rule("window-style-popped-no-shadow", { match = { tag = "pop" }, no_shadow = not shadow_popped })

  guard("styling the menus", write_menus)()

  -- Sidebars and pinned windows: their plugins style them, asking `look`.
  if type(sidebar) == "table" and sidebar.retheme then
    sidebar.retheme()
  end
  if type(dock) == "table" and dock.restyle then
    dock.restyle()
  end
end

-- Menus: Omarchy's shell draws its menus, launcher, popups and notifications
-- itself, styled from ~/.config/omarchy/shell.toml (which it reloads on a
-- change). So the menus kind is written there: in each of those sections, the
-- border's colour, opacity and width, and the background's opacity; a value
-- not set anywhere is taken out, back to the theme's. Everything else in the
-- file stays. (Their rounding follows Hyprland's, so tiled windows'.)
local shell_file = home .. "/.config/omarchy/shell.toml"
local MENU_SECTIONS = { "menu", "launcher", "popups", "notifications" }

local function menu_values()
  local colors, own = kind_colors("menus")
  local keys = {}
  local name = value("menus", "border_colour")
  if name ~= nil then
    local theme = value("menus", "theme")
    local current = theme == nil or theme == "current"
    if current and (name == "accent" or name == "foreground") then
      keys["border"] = name -- the shell follows theme changes itself
    else
      local rgb = name == "theme" and own[1] or colour_in(colors, name)
      if rgb then
        keys["border"] = "#" .. rgb
      end
    end
  end
  local opacity = value("menus", "border_opacity")
  if opacity ~= nil then
    keys["border-alpha"] = opacity
  end
  local width = border_width("menus")
  if width ~= nil then
    keys["border-width"] = math.floor(width)
  end
  local background = value("menus", "background_opacity")
  if background ~= nil then
    keys["background-alpha"] = background
  end
  return keys
end

local MENU_KEYS = { "border", "border-alpha", "border-width", "background-alpha" }

function write_menus()
  local wanted = menu_values()
  local f = io.open(shell_file, "r")
  local text = f and f:read("a") or ""
  if f then
    f:close()
  end
  local function toml(v)
    if type(v) == "string" then
      return '"' .. v .. '"'
    end
    return (string.format("%.3f", v):gsub("0+$", ""):gsub("%.$", ""))
  end
  local is_menu = {}
  for _, sec in ipairs(MENU_SECTIONS) do
    is_menu[sec] = true
  end
  local out, section, done = {}, nil, {}
  local function finish(sec)
    -- Keys still wanted in this section, added at its end.
    if sec and is_menu[sec] then
      for _, k in ipairs(MENU_KEYS) do
        if wanted[k] ~= nil and not (done[sec] and done[sec][k]) then
          -- Before trailing blank lines.
          local at = #out + 1
          while at > 1 and out[at - 1] == "" do
            at = at - 1
          end
          table.insert(out, at, k .. " = " .. toml(wanted[k]))
        end
      end
    end
  end
  local seen = {}
  for line in (text .. (text:sub(-1) == "\n" and "" or "\n")):gmatch("([^\n]*)\n") do
    local header = line:match("^%s*%[([%w._-]+)%]%s*$")
    if header then
      finish(section)
      section = header
      seen[header] = true
      done[header] = done[header] or {}
      out[#out + 1] = line
    else
      local key = section and is_menu[section] and line:match("^%s*([%w-]+)%s*=")
      local ours = false
      for _, k in ipairs(MENU_KEYS) do
        if key == k then
          ours = true
        end
      end
      if ours then
        if wanted[key] ~= nil and not done[section][key] then
          out[#out + 1] = key .. " = " .. toml(wanted[key])
          done[section][key] = true
        end
        -- (Not wanted: taken out.)
      else
        out[#out + 1] = line
      end
    end
  end
  finish(section)
  -- Sections not there yet, when something is wanted.
  if next(wanted) then
    for _, sec in ipairs(MENU_SECTIONS) do
      if not seen[sec] then
        if #out > 0 and out[#out] ~= "" then
          out[#out + 1] = ""
        end
        out[#out + 1] = "[" .. sec .. "]"
        for _, k in ipairs(MENU_KEYS) do
          if wanted[k] ~= nil then
            out[#out + 1] = k .. " = " .. toml(wanted[k])
          end
        end
      end
    end
  end
  local new = table.concat(out, "\n")
  while new:sub(-1) == "\n" do
    new = new:sub(1, -2)
  end
  new = new .. "\n"
  if new ~= text then
    -- Written through, so a link (dotfiles) stays a link.
    f = io.open(shell_file, "w")
    if f then
      f:write(new)
      f:close()
    end
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
local ORDER = { "theme", "border", "border_size", "border_colour", "border_opacity", "border_colour_unfocused",
  "border_opacity_unfocused", "rounding", "shadow", "opacity", "opacity_unfocused", "background_opacity" }
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
  for _, k in ipairs({ "shadow_look", "shadow_size", "shadow_opacity", "shadow_unfocused" }) do
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
  elseif option == nil and (kind == "shadow_look" or kind == "shadow_size" or kind == "shadow_opacity"
      or kind == "shadow_unfocused") then
    if type(v) ~= type(defaults[kind]) then
      return
    end
    config[kind] = v
    -- Only the shadow's look changes: the rest stays as it is.
    apply_shadow()
    save()
    return
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
    for _, k in ipairs({ "shadow_look", "shadow_size", "shadow_opacity", "shadow_unfocused" }) do
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
local function open(tab, index)
  local kinds = {}
  for _, kind in ipairs(KINDS) do
    local parts = {}
    for _, option in ipairs(ORDER) do
      parts[#parts + 1] = json_string(option) .. ":" .. json(config[kind][option])
    end
    kinds[#kinds + 1] = json_string(kind) .. ":{" .. table.concat(parts, ",") .. "}"
  end
  -- Each kind's colours to pick from, from its theme: that theme's own border
  -- colour, its accent, its text colour and its palette.
  local palettes, unfocused = {}, {}
  for _, kind in ipairs(KINDS) do
    local colors, a, i = kind_colors(kind)
    local colours = {}
    local function add(name, label, hex)
      if hex then
        colours[#colours + 1] = string.format('{"name":%s,"label":%s,"hex":%s}', json_string(name),
          json_string(label), json_string("#" .. hex))
      end
    end
    add("theme", "theme's border", a[1])
    add("accent", "accent", colour_in(colors, "accent"))
    add("foreground", "text colour", colour_in(colors, "foreground"))
    for n = 1, 6 do
      add("color" .. n, "palette " .. n, colour_in(colors, "color" .. n))
    end
    for n = 9, 14 do
      add("color" .. n, "bright " .. (n - 8), colour_in(colors, "color" .. n))
    end
    palettes[#palettes + 1] = json_string(kind) .. ":[" .. table.concat(colours, ",") .. "]"
    unfocused[#unfocused + 1] = json_string(kind) .. ":" .. json_string(i[1] and ("#" .. i[1]) or "")
  end
  -- The installed themes, by folder name.
  local themes, seen = {}, {}
  local p = io.popen("ls -1 " .. quote(home .. "/.config/omarchy/themes") .. " " .. quote(omarchy_path .. "/themes")
    .. " 2>/dev/null")
  if p then
    for name in p:lines() do
      if name:match("^[%w._-]+$") and not seen[name] and theme_colors_of(name) then
        seen[name] = true
        themes[#themes + 1] = name
      end
    end
    p:close()
  end
  table.sort(themes)
  for n, name in ipairs(themes) do
    local label = name:gsub("[-_]", " "):gsub("(%a)(%w*)", function(x, y) return x:upper() .. y end)
    themes[n] = string.format('{"slug":%s,"label":%s}', json_string(name), json_string(label))
  end
  local current_name = ""
  local cf = io.open(state_home .. "/omarchy/current/theme.name", "r")
  if cf then
    current_name = (cf:read("l") or "")
    cf:close()
  end
  local present = {
    '"sidebars":' .. tostring(type(sidebar) == "table"),
    '"pinned":' .. tostring(type(dock) == "table"),
  }
  local m = hl.get_active_monitor()
  local payload = string.format(
    '{"monitor":%s,"tab":%s,"index":%d,"kinds":{%s},"present":{%s},"palettes":{%s},"unfocused":{%s},'
      .. '"themes":[%s],"current_theme":%s,"sidebar":%s,'
      .. '"omarchy":{"border_size":%d,"rounding":%d},"shadow":{"look":%s,"size":%s,"opacity":%s,"unfocused":%s}}',
    json_string(m and m.name or ""), json_string(tab or "all"), tonumber(index) or 0, table.concat(kinds, ","),
    table.concat(present, ","), table.concat(palettes, ","), table.concat(unfocused, ","),
    table.concat(themes, ","), json_string(current_name),
    -- The Sidebar plugin's own look options (dim behind, margin), on the
    -- Sidebars tab.
    (type(sidebar) == "table" and sidebar.style_options) and sidebar.style_options() or "null",
    omarchy_border_size, omarchy_rounding,
    json(config.shadow_look), json(config.shadow_size), json(config.shadow_opacity),
    json(config.shadow_unfocused))
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
  write_menus = write_menus,
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
