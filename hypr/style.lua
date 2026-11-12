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
--   scratchpad windows on Omarchy's scratchpad (SUPER + S): as tiled ones
--              unless set here (it takes tiled's values), by rules on the
--              workspace, and the space between them (Omarchy's has none)
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
  -- Menus and the bar only: how solid their background is, 0 to 1.
  background_opacity = "number",
  -- The scratchpad only: the space between its windows, and between them and
  -- the screen's edges (its top and sides), in pixels.
  gaps = "number",
  gaps_out = "number",
  -- The scratchpad only: how much of the usable screen it covers, from the
  -- top, 0.3 to 1 (Omarchy's is 0.5).
  height = "number",
}
-- `bar` is Omarchy's bar (its background) and the Island Bar plugin's islands
-- (their border and rounding); unlike the others it takes nothing from `all`
-- but the theme.
local KINDS = { "all", "tiled", "floating", "popped", "scratchpad", "sidebars", "pinned", "menus", "bar" }
-- The options for every window at once.
local GLOBALS = { "shadow_look", "shadow_size", "shadow_opacity", "shadow_unfocused", "open_as",
  "mode_keys", "key_mode", "key_pop", "key_dock", "key_drawer",
  "terminal_trail", "terminal_bloom", "terminal_bloom_strength", "terminal_bloom_size" }
local TERMINAL = { "terminal_trail", "terminal_bloom", "terminal_bloom_strength", "terminal_bloom_size" }
local is_global = {}
for _, k in ipairs(GLOBALS) do
  is_global[k] = true
end

local defaults = {
  all = {},
  tiled = {},
  floating = {},
  popped = {},
  scratchpad = {},
  sidebars = {},
  pinned = {},
  menus = {},
  bar = {},
  -- One shadow look for every window (Hyprland has one): "glow", in the
  -- theme's accent colour, or "shadow", large, faint and dark.
  shadow_look = "glow",
  shadow_size = 6, -- its reach in pixels
  shadow_opacity = 0.2, -- 0 (clear) to 1 (solid)
  shadow_unfocused = true, -- false: only the focused window has one
  -- How new windows open: "tiled", "floating" (centred, at their own size;
  -- SUPER + T tiles one), "popped" (as SUPER + O pops one out) or "docked"
  -- (the Dock plugin), or "workspace": as the workspace's own layout says
  -- (Omarchy's SUPER + L: floating on a floating workspace, tiled on the
  -- rest). Dialogs float either way; the Agent Sidebar plugin's
  -- windows open as its own open_as says.
  open_as = "tiled",
  -- One set of keys for a window's mode. key_mode switches the workspace
  -- between tiled and floating, or brings a popped, docked or drawer window
  -- back to it; key_pop / key_dock / key_drawer put the window in that mode
  -- (from any other), and do nothing when it's in it already. Off: Omarchy's,
  -- the Dock's and the Sidebar's own keys, each a toggle.
  mode_keys = false,
  key_mode = "SUPER + T",
  key_pop = "SUPER + O",
  key_dock = "SUPER + ALT + P", -- the Dock plugin's
  key_drawer = "SUPER + ALT + B", -- the Sidebar plugin's (its convert)
  -- Ghostty's effects (custom shaders): a cursor trail like Kitty's, and a
  -- soft bloom around text (its strength 0 to 1, its reach in pixels).
  terminal_trail = false,
  terminal_bloom = false,
  terminal_bloom_strength = 0.35,
  terminal_bloom_size = 6,
}
local OPEN_AS = { tiled = true, floating = true, popped = true, docked = true, workspace = true }

local config = { all = {}, tiled = {}, floating = {}, popped = {}, scratchpad = {}, sidebars = {}, pinned = {}, menus = {}, bar = {} }
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
  -- Before 0.14.0: open_floating = true (or false), now open_as.
  if overrides.open_floating ~= nil then
    if overrides.open_as == nil and type(overrides.open_floating) == "boolean" then
      overrides.open_as = overrides.open_floating and "floating" or "tiled"
    end
    overrides.open_floating = nil
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
  if not OPEN_AS[config.open_as] then
    problems[#problems + 1] = 'open_as must be "tiled", "floating", "popped", "docked" or "workspace"'
    config.open_as = "tiled"
  end
  if #problems > 0 then
    notify("Problems in ~/.config/omarchy/window-style.lua: " .. table.concat(problems, "; "))
  end
  -- The bar not styled here yet: what shell.toml's [bar] already says is taken
  -- as its look (so it isn't written away), and kept from the next save.
  if overrides.bar == nil then
    local f = io.open(home .. "/.config/omarchy/shell.toml", "r")
    local text = f and f:read("a") or ""
    if f then
      f:close()
    end
    local bar = ("\n" .. text):match("\n%s*%[bar%]%s*\n(.-)\n%s*%[") or ("\n" .. text):match("\n%s*%[bar%]%s*\n(.*)$") or ""
    local function number(key)
      return tonumber(("\n" .. bar):match("\n%s*" .. key:gsub("%-", "%%-") .. "%s*=%s*([%d.]+)"))
    end
    config.bar.background_opacity = number("background-alpha")
    config.bar.border_opacity = number("border-alpha")
    config.bar.border_size = number("border-width")
    config.bar.rounding = number("island-radius")
  end
end

-- A kind's value for an option: its own, else all windows'.
local function value(kind, option)
  local v = config[kind][option]
  if v == nil and kind == "popped" then
    return value("floating", option)
  end
  if v == nil and kind == "scratchpad" then
    return value("tiled", option)
  end
  if v == nil and (kind ~= "bar" or option == "theme") then
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
local function gap_of(option, fallback)
  local g = hl.get_config(option)
  if type(g) == "table" then
    return tonumber(g.top) or fallback
  end
  return tonumber(g) or fallback
end
local omarchy_gaps = gap_of("general:gaps_in", 5)
local omarchy_gaps_out = gap_of("general:gaps_out", 10)

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

-- Older Omarchy made windows slightly see-through with a rule on the windows
-- tagged "default-opacity" (apps that should stay solid drop the tag): there
-- this does the same, for the same windows. Omarchy 4.5 dropped that tag (only
-- a few apps opt in to see-through, tagged "transparent-window"), so there it
-- reaches every window, as the panel's "All windows" says.
local OMARCHY_OPACITY_TAG = (function()
  local f = io.open("/usr/share/omarchy/default/hypr/windows.lua")
  local source = f and f:read("a") or ""
  if f then
    f:close()
  end
  return source:find("default-opacity", 1, true) and "default-opacity" or nil
end)()
local SOLID_VIDEO = "(^.+-youtube\\.com__.*$|^.+-app\\.zoom\\.us__wc_home.*$)"
local function opacity_match(match)
  match.tag = OMARCHY_OPACITY_TAG
  return match
end

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
-- getting its kind's (floating or tiled) once back in, as they change; so do
-- the windows those plugins let go of (`adopt`). Sidebars and docked windows
-- are their plugins'. The colours outlast a reload (a theme change reloads),
-- so the windows are remembered in a file, and so are the ones the plugins
-- listed before this took them over.
local framed = {} -- address -> true: colours set here
local framed_file = state_home .. "/omarchy-window-style/framed"
local function save_framed()
  os.execute("mkdir -p " .. quote(state_home .. "/omarchy-window-style"))
  local f = io.open(framed_file, "w")
  if f then
    for address in pairs(framed) do
      f:write(address, "\n")
    end
    f:close()
  end
end
do
  local pruned = false
  for _, file in ipairs({ framed_file, state_home .. "/omarchy-dock/restored-borders",
      state_home .. "/omarchy-sidebar/restored-borders" }) do
    local f = io.open(file, "r")
    if f then
      for address in f:lines() do
        if hl.get_window("address:" .. address) then
          framed[address] = true
        else
          pruned = true
        end
      end
      f:close()
    end
  end
  if pruned then
    save_framed()
  end
end
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
  if not framed[window.address] then
    framed[window.address] = true
    save_framed()
  end
end

-- A window the Sidebar or Dock plugin lets go of: its kind's colours from now on.
local function adopt(window)
  window = window and window.address and hl.get_window("address:" .. window.address)
  if window == nil then
    return
  end
  framed[window.address] = true
  frame(window)
  save_framed()
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
    if framed[window.address] then
      framed[window.address] = nil
      save_framed()
    end
  end
end)

local write_menus -- defined with the menus, below
local shell_rounding -- the rounding the shell was last told of

-- The shadow switch and look (Hyprland's one for every window). On its own,
-- for the global shadow settings: their arrows change it many times a second.
-- New windows floating: a rule every window matches (floating is taken as a
-- window opens, so the ones open already stay as they are).
local function apply_open_as()
  if config.open_as == "floating" then
    rule("window-style-open-floating", { match = { class = ".*" }, float = true })
  else
    no_rule("window-style-open-floating", { class = ".*" })
  end
end

-- The Agent Sidebar plugin's windows: they open as its own open_as says.
local function agent_mode(window)
  if type(agent_sidebar) ~= "table" or type(agent_sidebar.open_as) ~= "function" then
    return nil
  end
  local mine
  if type(agent_sidebar.is_agent) == "function" then
    mine = agent_sidebar.is_agent(window)
  else
    local class = window.class or ""
    mine = class == "org.omarchy.agent" or class:sub(1, 18) == "org.omarchy.agent."
      or class:match("^sidebar%.agent%.s") ~= nil
  end
  return mine and agent_sidebar.open_as() or nil
end

-- On a floating workspace Omarchy gives floating windows a titlebar (its
-- hyprbars plugin, not on pinned ones here), drawn above the window. A window
-- placed just under the bar while it had none (popped out, docked) gets it back
-- once unpinned, over the bar: so it's moved down until the titlebar clears it.
local function titlebar_height(w)
  if w.pinned or not w.floating then
    return 0
  end
  local on = false
  for _, tag in ipairs(w.tags or {}) do
    if tag:gsub("%*$", "") == "omarchy-floating-workspace" then
      on = true
    end
  end
  if not on then
    return 0
  end
  local ok, h = pcall(hl.get_config, "plugin:hyprbars:bar_height")
  return (ok and tonumber(h)) or 0
end

local function clear_bar(w)
  local bar = titlebar_height(w)
  local m = w.monitor
  if bar <= 0 or m == nil or w.at == nil or (w.fullscreen or 0) ~= 0 then
    return
  end
  local r = m.reserved or {}
  local border = border_width("floating") or omarchy_border_size
  local top = m.y + (r.top or 0) + omarchy_gaps_out + border + bar
  if w.at.y < top then
    hl.dispatch(hl.dsp.window.move({ x = w.at.x, y = top, window = "address:" .. w.address }))
  end
end

-- A floating window bigger than its screen's visible area (the screen less the
-- bar and other reserved edges, Omarchy's outer gap and the border) is shrunk
-- to fit and centred. Apps that remember their size from a bigger or unscaled
-- screen (Chrome) otherwise open running off the edge. Sidebars, docked and
-- pinned windows and fullscreen ones are their own business.
local function fit_to_screen(address)
  local w = hl.get_window(address)
  if w == nil or not w.floating or w.pinned or is_sidebar(w) or w.size == nil then
    return
  end
  -- (fullscreen is a mode number: 0, not false, when it isn't.)
  if w.fullscreen ~= nil and w.fullscreen ~= false and w.fullscreen ~= 0 then
    return
  end
  local m = w.monitor
  if m == nil or (m.width or 0) <= 0 or (m.height or 0) <= 0 or not m.scale or m.scale <= 0 then
    return
  end
  local r = m.reserved or {}
  local edge = omarchy_gaps_out
  local border = border_width("floating") or omarchy_border_size
  local bar = titlebar_height(w)
  local max_w = math.floor(m.width / m.scale - (r.left or 0) - (r.right or 0) - 2 * (edge + border))
  local max_h = math.floor(m.height / m.scale - (r.top or 0) - (r.bottom or 0) - 2 * (edge + border) - bar)
  if max_w <= 0 or max_h <= 0 or (w.size.x <= max_w and w.size.y <= max_h) then
    clear_bar(w)
    return
  end
  hl.dispatch(hl.dsp.window.resize({ x = math.min(w.size.x, max_w), y = math.min(w.size.y, max_h), window = address }))
  hl.dispatch(hl.dsp.window.center({ window = address }))
  hl.timer(guard("keeping a titlebar under the bar", function()
    local again = hl.get_window(address)
    if again then
      clear_bar(again)
    end
  end), { timeout = 50, type = "oneshot" })
end

-- Checked as it opens and again a moment later: some apps (Chrome) only set
-- their remembered size after the window is shown.
local function fit_soon(address)
  fit_to_screen(address)
  hl.timer(guard("fitting a new window to the screen", function()
    fit_to_screen(address)
  end), { timeout = 300, type = "oneshot" })
end

-- Unpinned (popped back in, undocked): fitted again, titlebar and all, once
-- the pop-out or the Dock has finished with it.
hl.on("window.pin", guard("fitting an unpinned window", function(window)
  if window == nil or window.address == nil then
    return
  end
  local address = "address:" .. window.address
  hl.timer(guard("fitting an unpinned window", function()
    local w = hl.get_window(address)
    if w and not w.pinned and w.floating then
      fit_to_screen(address)
    end
  end), { timeout = 150, type = "oneshot" })
end))

-- A new window, once open. An agent's the floating rule caught but its plugin
-- wants tiled: tiled again. Otherwise, opened tiled on a regular workspace
-- (not a sidebar's or the scratchpad's): floated (when a rule tiled it),
-- popped out or docked, as open_as says. Focused first: both act on the focused window.
hl.on("window.open", guard("opening a new window", function(window)
  if window == nil or window.address == nil then
    return
  end
  local address = "address:" .. window.address
  local agent = agent_mode(window)
  if agent ~= nil then
    if config.open_as == "floating" and window.floating and agent ~= "sidebar" and agent ~= "floating" then
      hl.dispatch(hl.dsp.window.float({ action = "disable", window = address }))
    end
    return
  end
  local mode = config.open_as
  local ws = window.workspace and window.workspace.name or ""
  if window.floating then
    fit_soon(address)
  end
  -- "workspace": Omarchy's workspace modes float or tile it (SUPER + L).
  if mode == "tiled" or mode == "workspace" or window.floating or window.pinned or ws == "" or ws:sub(1, 8) == "special:" then
    return
  end
  -- Floating, but another rule tiled it (Omarchy's browser rule tiles Chrome
  -- and other Chromium browsers): floated here instead, centred.
  if mode == "floating" then
    hl.dispatch(hl.dsp.window.float({ action = "enable", window = address }))
    hl.dispatch(hl.dsp.window.center({ window = address }))
    fit_soon(address)
    return
  end
  hl.timer(guard("opening a new window", function()
    local w = hl.get_window(address)
    if w == nil or w.floating then
      return
    end
    hl.dispatch(hl.dsp.focus({ window = address }))
    hl.timer(guard("opening a new window", function()
      local active = hl.get_active_window()
      if active == nil or active.address ~= window.address or active.floating then
        return
      end
      if mode == "popped" then
        hl.exec_cmd("omarchy-hyprland-window-pop")
      elseif type(dock) == "table" and dock.toggle then
        dock.toggle()
      else
        notify('open_as = "docked" needs the Dock plugin: https://github.com/motorstreak/omarchy-dock')
      end
    end), { timeout = 50, type = "oneshot" })
  end), { timeout = 150, type = "oneshot" })
end))

local function apply_shadow()
  local any = value("tiled", "shadow") == true or value("floating", "shadow") == true
    or value("popped", "shadow") == true or value("scratchpad", "shadow") == true
    or value("sidebars", "shadow") == true
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

-- The scratchpad: Omarchy makes it a drop-down console (default/hypr/
-- qconsole.lua), with a workspace rule taking its windows' borders and the
-- space between them away. Here they're as tiled windows', or the
-- scratchpad's own: the workspace rule given them back (it keeps the rest,
-- the console's size and its first window), and window rules on the
-- workspace for what differs from tiled. Omarchy's rule is made again when
-- the screens change, so this is too, after it.
--
-- Omarchy sizes the console with its bottom gap (the screen below it) and
-- puts it flush against the other edges. Its gaps can only be set all four
-- at once, so the bottom one is worked out as Omarchy does, from the
-- scratchpad's height (the share of the usable screen it covers, from the
-- top), but never closer to the edge than the others, which take the
-- scratchpad's edge gap.
local OMARCHY_HEIGHT = 0.5 -- `share` in Omarchy's default/hypr/qconsole.lua
local SCRATCHPAD = { workspace = "name:special:scratchpad" }
local function scratchpad_workspace()
  local spec = {
    workspace = "special:scratchpad",
    gaps_in = math.floor(value("scratchpad", "gaps") or omarchy_gaps),
    no_border = border_width("scratchpad") == 0,
  }
  -- A screen going away answers nil to everything: Omarchy's edges stay.
  local monitor = hl.get_active_monitor()
  if monitor and monitor.scale and monitor.scale > 0 then
    local reserved = monitor.reserved
    local usable = monitor.height / monitor.scale - reserved.top - reserved.bottom
    local edge = math.floor(value("scratchpad", "gaps_out") or omarchy_gaps_out)
    local height = math.max(0.3, math.min(1, value("scratchpad", "height") or OMARCHY_HEIGHT))
    spec.gaps_out = { top = edge, right = edge, left = edge,
      bottom = math.max(edge, math.floor(usable * (1 - height))) }
  end
  hl.workspace_rule(spec)
end
hl.on("monitor.layout_changed", guard("styling the scratchpad", scratchpad_workspace))
hl.on("monitor.focused", guard("styling the scratchpad", scratchpad_workspace))

-- `active` and `inactive`: tiled windows' colours, which it otherwise has.
local function apply_scratchpad(active, inactive)
  scratchpad_workspace()
  local function differs_scratchpad(option)
    return value("scratchpad", option) ~= value("tiled", option)
  end
  local spec = {}
  if differs_scratchpad("border") or differs_scratchpad("border_size") then
    spec.border_size = math.floor(border_width("scratchpad") or omarchy_border_size)
  end
  if differs_scratchpad("theme") or differs_scratchpad("border_colour") or differs_scratchpad("border_colour_unfocused")
      or differs_scratchpad("border_opacity") or differs_scratchpad("border_opacity_unfocused") then
    local a, i = border_colours("scratchpad")
    a = a or active
    i = i or inactive
    if a then
      spec.border_color = a .. " " .. (i or a)
    end
  end
  if next(spec) then
    spec.match = SCRATCHPAD
    rule("window-style-scratchpad", spec)
  else
    no_rule("window-style-scratchpad", SCRATCHPAD)
  end
  local opacity = opacity_of("scratchpad")
  local scratch_match = opacity_match({ workspace = SCRATCHPAD.workspace })
  if opacity and (differs_scratchpad("opacity") or differs_scratchpad("opacity_unfocused")) then
    rule("window-style-scratchpad-opacity", { match = scratch_match, opacity = opacity })
  else
    no_rule("window-style-scratchpad-opacity", scratch_match)
  end
end

-- Pinned windows (docked, popped out with SUPER + O) have no titlebar. On a
-- floating workspace Omarchy gives every window one (its hyprbars plugin), drawn
-- above the window, so a window placed just under the bar had its titlebar
-- over the bar. Their plugins place them and their own looks set them apart.
-- Without hyprbars loaded (as on a machine without it) Hyprland rejects the
-- field and fails the whole load, even inside pcall: so only when it's there.
local function apply_titlebars()
  local ok, h = pcall(hl.get_config, "plugin:hyprbars:bar_height")
  if not ok or h == nil then
    return
  end
  pcall(rule, "window-style-pinned-no-titlebar", { match = { pin = true }, ["hyprbars:no_bar"] = true })
end

local function apply()
  apply_open_as()
  apply_titlebars()
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
    rule("window-style-tiled-opacity", { match = opacity_match({ float = false }), opacity = o_tiled })
  else
    no_rule("window-style-tiled-opacity", opacity_match({ float = false }))
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
  -- Always, not only when it differs from tiled: the tiled rule leaves floating
  -- windows (sidebars too) to Omarchy's own opacity rule.
  local o_floating = opacity_of("floating")
  if o_floating then
    rule("window-style-floating-opacity", { match = opacity_match({ float = true }), opacity = o_floating })
  else
    no_rule("window-style-floating-opacity", opacity_match({ float = true }))
  end
  -- Older Omarchy kept video windows (YouTube and Zoom web apps) solid by
  -- dropping their tag; without the tag, a later rule does the same.
  -- Browsers likewise were solid while focused; unfocused they follow the
  -- setting for their kind. Made before the video rule, which wins.
  if OMARCHY_OPACITY_TAG == nil then
    for _, browser in ipairs({ "chromium-based-browser", "firefox-based-browser" }) do
      for kind, float in pairs({ tiled = false, floating = true }) do
        local name = "window-style-solid-" .. browser .. "-" .. kind
        local match = { tag = browser, float = float }
        local o = opacity_of(kind)
        if o then
          rule(name, { match = match, opacity = "1 " .. o:match("%S+$") })
        else
          no_rule(name, match)
        end
      end
    end
    rule("window-style-solid-video", { match = { class = SOLID_VIDEO }, opacity = "1 1" })
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
  guard("styling the scratchpad", apply_scratchpad)(active or theme_rgba(theme_active),
    inactive or theme_rgba(theme_inactive))

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
  rule("window-style-scratchpad-no-shadow", { match = SCRATCHPAD, no_shadow = value("scratchpad", "shadow") ~= true })

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

-- The shell.toml keys for a kind: the menus', or the bar's (with its islands'
-- rounding, which only the Island Bar plugin reads).
local function shell_values(kind)
  local colors, own = kind_colors(kind)
  local keys = {}
  local name = value(kind, "border_colour")
  if name ~= nil then
    local theme = value(kind, "theme")
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
  local opacity = value(kind, "border_opacity")
  if opacity ~= nil then
    keys["border-alpha"] = opacity
  end
  local width = border_width(kind)
  if width == nil and kind == "bar" and value(kind, "border") == true then
    width = 1 -- turned on without a width (the bar takes none from all windows)
  end
  if width ~= nil then
    keys["border-width"] = math.floor(width)
  end
  local background = value(kind, "background_opacity")
  if background ~= nil then
    keys["background-alpha"] = background
  end
  if kind == "bar" and value(kind, "rounding") ~= nil then
    keys["island-radius"] = math.floor(value(kind, "rounding"))
  end
  return keys
end

local MENU_KEYS = { "border", "border-alpha", "border-width", "background-alpha" }
local BAR_KEYS = { "border", "border-alpha", "border-width", "background-alpha", "island-radius" }

function write_menus()
  local menus, bar = shell_values("menus"), shell_values("bar")
  -- Each section's keys: the ones this plugin owns there, and what it wants.
  local owned, wants = {}, {}
  for _, sec in ipairs(MENU_SECTIONS) do
    owned[sec], wants[sec] = MENU_KEYS, menus
  end
  owned.bar, wants.bar = BAR_KEYS, bar
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
  local out, section, done = {}, nil, {}
  local last -- the section's header or last setting, in `out`
  local function finish(sec)
    -- Keys still wanted in this section, added after its last setting (not
    -- after comments or blank lines, which may be about the next section).
    if sec and owned[sec] then
      for _, k in ipairs(owned[sec]) do
        if wants[sec][k] ~= nil and not (done[sec] and done[sec][k]) then
          last = last + 1
          table.insert(out, last, k .. " = " .. toml(wants[sec][k]))
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
      last = #out
    else
      local key = section and owned[section] and line:match("^%s*([%w-]+)%s*=")
      local ours = false
      for _, k in ipairs(key and owned[section] or {}) do
        if key == k then
          ours = true
        end
      end
      if ours then
        if wants[section][key] ~= nil and not done[section][key] then
          out[#out + 1] = key .. " = " .. toml(wants[section][key])
          done[section][key] = true
          last = #out
        end
        -- (Not wanted: taken out.)
      else
        out[#out + 1] = line
        if line:match("^%s*[%w-]+%s*=") then
          last = #out
        end
      end
    end
  end
  finish(section)
  -- Sections not there yet, when something is wanted.
  local order = { "bar" }
  for _, sec in ipairs(MENU_SECTIONS) do
    order[#order + 1] = sec
  end
  for _, sec in ipairs(order) do
    if not seen[sec] and next(wants[sec]) then
      if #out > 0 and out[#out] ~= "" then
        out[#out + 1] = ""
      end
      out[#out + 1] = "[" .. sec .. "]"
      for _, k in ipairs(owned[sec]) do
        if wants[sec][k] ~= nil then
          out[#out + 1] = k .. " = " .. toml(wants[sec][k])
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
  "border_opacity_unfocused", "rounding", "shadow", "opacity", "opacity_unfocused", "background_opacity", "height", "gaps", "gaps_out" }
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
  for _, k in ipairs(GLOBALS) do
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

-- Terminal effects ------------------------------------------------------------------

-- Ghostty's custom shaders: the cursor trail and the bloom. Ghostty can't hand
-- values to a shader, so each is written out from the plugin's own (ghostty/)
-- with the values filled in, to ~/.local/state/omarchy-window-style/ghostty/,
-- and listed in ~/.config/ghostty/window-style. Ghostty's config includes that
-- file (`config-file = ?window-style`, added the first time an effect is
-- turned on). Ghostty reloads its config on SIGUSR2; only when something
-- changed, as this runs on every Hyprland reload too.
local xdg_config = os.getenv("XDG_CONFIG_HOME")
if xdg_config == nil or xdg_config == "" then
  xdg_config = home .. "/.config"
end
local ghostty_dir = xdg_config .. "/ghostty"
local shader_dir = state_home .. "/omarchy-window-style/ghostty"

local function read_file(path)
  local f = io.open(path, "r")
  if not f then
    return nil
  end
  local text = f:read("a")
  f:close()
  return text
end

local function write_if_changed(path, text)
  if read_file(path) == text then
    return false
  end
  local f = io.open(path, "w")
  if not f then
    error("can't write " .. path)
  end
  f:write(text)
  f:close()
  return true
end

local function apply_terminal()
  local main = read_file(ghostty_dir .. "/config")
  if main == nil then
    return -- no Ghostty
  end
  local include = ghostty_dir .. "/window-style"
  local included = ("\n" .. main .. "\n"):find("\n%s*config%-file%s*=%s*%??window%-style%s*\n") ~= nil
  local any = config.terminal_trail or config.terminal_bloom
  -- Never turned on: Ghostty's folder is left alone.
  if not any and not included and read_file(include) == nil then
    return
  end
  local changed = false
  local lines = { "# Ghostty effects from the Window Style plugin (SUPER + CTRL + ALT + S, Terminal tab).",
    "# Written whole on every change there." }
  local function shader(name, values)
    local text = read_file(WINDOW_STYLE_DIR .. "/ghostty/" .. name .. ".glsl")
    if text == nil then
      error("the plugin's ghostty/" .. name .. ".glsl is missing")
    end
    text = text:gsub("@(%u+)@", function(k)
      return values[k] and string.format("%.3f", values[k]) or nil
    end)
    local p = io.popen("mkdir -p " .. quote(shader_dir))
    if p then
      p:close()
    end
    local path = shader_dir .. "/" .. name .. ".glsl"
    if write_if_changed(path, text) then
      changed = true
    end
    lines[#lines + 1] = "custom-shader = " .. path
  end
  -- The trail first, so the bloom glows it too.
  if config.terminal_trail then
    shader("cursor-trail", {})
  end
  if config.terminal_bloom then
    shader("bloom", {
      STRENGTH = math.max(0, math.min(1, config.terminal_bloom_strength)),
      SIZE = math.max(1, math.min(30, config.terminal_bloom_size)),
    })
  end
  -- The trail moves on its own: Ghostty draws it only while animating.
  if config.terminal_trail then
    lines[#lines + 1] = "custom-shader-animation = true"
  end
  if write_if_changed(include, table.concat(lines, "\n") .. "\n") then
    changed = true
  end
  if any and not included then
    -- Appended: written through, so a link (dotfiles) stays a link.
    local f = io.open(ghostty_dir .. "/config", "a")
    if f then
      f:write((main:sub(-1) == "\n" and "" or "\n")
        .. "\n# Effects (cursor trail, bloom) from the Window Style plugin: SUPER + CTRL + ALT + S, Terminal tab.\n"
        .. "config-file = ?window-style\n")
      f:close()
      changed = true
    end
  end
  if changed then
    hl.exec_cmd("pkill -USR2 -x ghostty")
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
  elseif option == nil and is_global[kind] then
    if type(v) ~= type(defaults[kind]) or (kind == "open_as" and not OPEN_AS[v]) then
      return
    end
    config[kind] = v
    -- Only that changes: the rest stays as it is.
    if kind == "open_as" then
      apply_open_as()
    elseif kind:sub(1, 9) == "terminal_" then
      guard("the terminal effects", apply_terminal)()
    else
      apply_shadow()
    end
    save()
    return
  else
    return
  end
  apply()
  save()
end

-- A kind (or everything, for "everything"; "terminal" for the terminal
-- effects) back to as if nothing were set.
local function reset(kind)
  if kind == "terminal" then
    for _, k in ipairs(TERMINAL) do
      config[k] = defaults[k]
    end
    guard("the terminal effects", apply_terminal)()
    save()
    return
  end
  if kind == "everything" then
    for _, k in ipairs(KINDS) do
      config[k] = {}
    end
    for _, k in ipairs(GLOBALS) do
      config[k] = defaults[k]
    end
  elseif config[kind] ~= nil then
    config[kind] = {}
  else
    return
  end
  apply()
  if kind == "everything" then
    guard("the terminal effects", apply_terminal)()
  end
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
      .. '"themes":[%s],"current_theme":%s,"sidebar":%s,"agent":%s,'
      .. '"omarchy":{"border_size":%d,"rounding":%d,"gaps":%d,"gaps_out":%d,"height":%s},"shadow":{"look":%s,"size":%s,"opacity":%s,"unfocused":%s,'
      .. '"open_as":%s,"terminal_trail":%s,"terminal_bloom":%s,"terminal_bloom_strength":%s,"terminal_bloom_size":%s}}',
    json_string(m and m.name or ""), json_string(tab or "all"), tonumber(index) or 0, table.concat(kinds, ","),
    table.concat(present, ","), table.concat(palettes, ","), table.concat(unfocused, ","),
    table.concat(themes, ","), json_string(current_name),
    -- The Sidebar plugin's own look options (dim behind, margin), on the
    -- Sidebars tab.
    (type(sidebar) == "table" and sidebar.style_options) and sidebar.style_options() or "null",
    -- The Agent Sidebar plugin's open_as, on All windows.
    (type(agent_sidebar) == "table" and agent_sidebar.open_as) and ('{"open_as":' .. json(agent_sidebar.open_as()) .. "}") or "null",
    omarchy_border_size, omarchy_rounding, omarchy_gaps, omarchy_gaps_out, json(OMARCHY_HEIGHT),
    json(config.shadow_look), json(config.shadow_size), json(config.shadow_opacity),
    json(config.shadow_unfocused), json(config.open_as), json(config.terminal_trail), json(config.terminal_bloom),
    json(config.terminal_bloom_strength), json(config.terminal_bloom_size))
  hl.exec_cmd("omarchy-shell -q window-style-panel open " .. quote(payload))
end

-- Mode keys -------------------------------------------------------------------------

-- A window's mode: "drawer" (in a sidebar), "popped" (SUPER + O), "docked"
-- (pinned otherwise: the Dock plugin's), or "workspace" (as its workspace is).
local function mode_of(w)
  if is_sidebar(w) then
    return "drawer"
  elseif w.pinned and is_popped(w) then
    return "popped"
  elseif w.pinned then
    return "docked"
  end
  return "workspace"
end

-- The user's own pop-out (dotfiles) when there is one, else Omarchy's (which
-- toggles floating: a floating window would be tiled). Hyprland's own PATH may
-- lack ~/.local/bin, so that's looked in too.
local function pop()
  hl.exec_cmd([[p=$(command -v pop-window || ls "$HOME/.local/bin/pop-window" 2>/dev/null) ]]
    .. [[&& exec "$p" || exec omarchy-hyprland-window-pop]])
end

local function dock_toggle()
  if type(dock) == "table" and dock.toggle then
    dock.toggle()
  else
    notify("Docking needs the Dock plugin: https://github.com/motorstreak/omarchy-dock")
  end
end

local function drawer_toggle()
  if type(sidebar) == "table" and sidebar.convert then
    sidebar.convert()
  else
    notify("The drawer needs the Sidebar plugin: https://github.com/motorstreak/omarchy-sidebar")
  end
end

-- Out of a drawer: to the workspace on its screen (the Sidebar plugin lets go
-- of it as it leaves; its own convert key may only make drawers).
local function leave_drawer()
  local w = hl.get_active_window()
  local regular = w and w.monitor and w.monitor.active_workspace
  if regular == nil then
    return
  end
  local target = tonumber(regular.name) and regular.name or ("name:" .. regular.name)
  hl.dispatch(hl.dsp.window.move({ workspace = target, window = "address:" .. w.address }))
end

-- Each acts on the focused window: into its mode, and out of it.
local TOGGLE = { popped = pop, docked = dock_toggle, drawer = drawer_toggle }
local LEAVE = { popped = pop, docked = dock_toggle, drawer = leave_drawer }

-- Whether a regular workspace floats: Omarchy's saved mode for it (SUPER + L),
-- or its default one.
local function read_mode(path)
  local f = io.open(path, "r")
  if f == nil then
    return nil
  end
  local text = f:read("*a")
  f:close()
  return text:match('mode%s*=%s*"(%a+)"') or text:match('default%s*=%s*"(%a+)"')
end
local function workspace_floats(name)
  local dir = state_home .. "/omarchy/workspace-layouts/"
  local mode = read_mode(dir .. tostring(name) .. ".lua") or read_mode(dir .. "default.lua")
  return mode == "floating"
end

-- Back in its workspace (once out of its mode has settled): floating or tiled
-- as the workspace is. Popping back in returns a window to what it was before,
-- and undocking leaves it floating, either of which may not be the workspace's.
local function settle(address)
  hl.timer(guard("putting the window back", function()
    local w = hl.get_window(address)
    if w == nil or mode_of(w) ~= "workspace" then
      return
    end
    local ws = w.workspace and w.workspace.name or ""
    if not tonumber(ws) or (w.fullscreen or 0) ~= 0 then
      return
    end
    local floats = workspace_floats(ws)
    if floats ~= w.floating then
      hl.dispatch(hl.dsp.window.float({ action = floats and "enable" or "disable", window = address }))
    end
    if floats then
      fit_soon(address)
    end
  end), { timeout = 400, type = "oneshot" })
end

-- The window into `mode`: out of the one it's in first, then (once that has
-- settled, focused again) in.
local function enter(mode)
  local w = hl.get_active_window()
  if w == nil then
    return
  end
  local now = mode_of(w)
  if now == mode then
    return
  end
  if now == "workspace" then
    TOGGLE[mode]()
    return
  end
  local address = "address:" .. w.address
  LEAVE[now]()
  hl.timer(guard("changing the window's mode", function()
    local again = hl.get_window(address)
    if again == nil or mode_of(again) == mode then
      return
    end
    hl.dispatch(hl.dsp.focus({ window = address }))
    hl.timer(guard("changing the window's mode", function()
      local active = hl.get_active_window()
      if active and active.address == again.address and mode_of(active) ~= mode then
        TOGGLE[mode]()
      end
    end), { timeout = 50, type = "oneshot" })
  end), { timeout = 400, type = "oneshot" })
end

-- key_mode: a popped, docked or drawer window back to its workspace's mode;
-- otherwise the workspace between tiled and floating (Omarchy's layouts, as
-- SUPER + L cycles them: scrolling counts as tiled). On a special workspace
-- (the scratchpad), just this window, as Omarchy's SUPER + T.
local function mode_key()
  local w = hl.get_active_window()
  local now = w and mode_of(w) or "workspace"
  if now ~= "workspace" then
    LEAVE[now]()
    settle("address:" .. w.address)
    return
  end
  local ws = w and w.workspace and w.workspace.name or (hl.get_active_workspace() or {}).name or ""
  if ws:sub(1, 8) == "special:" or not tonumber(ws) then
    if w then
      hl.dispatch(hl.dsp.window.float({ action = "toggle" }))
    end
    return
  end
  hl.exec_cmd([[case "$(omarchy-hyprland-workspace-layout-current)" in
    dwindle) omarchy-hyprland-workspace-layout-toggle back ;;
    *) omarchy-hyprland-workspace-layout-toggle ;;
  esac]])
end

local bound_keys = {}
local function bind_mode_keys()
  for _, k in ipairs(bound_keys) do
    hl.unbind(k)
  end
  bound_keys = {}
  if not config.mode_keys then
    return
  end
  local keys = {
    { config.key_mode, "Workspace tiled / floating, or the window back to it", mode_key },
    { config.key_pop, "Pop the window out", function() enter("popped") end },
    { config.key_dock, "Dock the window to the screen edge", function() enter("docked") end },
    { config.key_drawer, "Make the window a drawer", function() enter("drawer") end },
  }
  for _, k in ipairs(keys) do
    if type(k[1]) == "string" and k[1] ~= "" then
      hl.unbind(k[1])
      o.bind(k[1], k[2], guard(k[2]:lower(), k[3]))
      bound_keys[#bound_keys + 1] = k[1]
    end
  end
end

local PANEL_KEY = "SUPER + CTRL + ALT + S"
hl.unbind(PANEL_KEY)
o.bind(PANEL_KEY, "Window style", guard("opening the window style", function()
  open("all")
end))

-- For the plugins, the settings panel and tests.
window_style = {
  look = look,
  adopt = adopt,
  value = value,
  border_colours = border_colours,
  config = config,
  set = set,
  reset = reset,
  open = open,
  apply = apply,
  write_menus = write_menus,
  -- The Sidebar plugin leaves SUPER + T alone while this is on.
  mode_keys = function()
    return config.mode_keys == true
  end,
  -- The mode keys' actions: enter("popped" | "docked" | "drawer"), mode_key().
  enter = enter,
  mode_key = mode_key,
}

-- The mode keys, now and once everything else has loaded (the Dock, the
-- Sidebar and the user's own bindings bind some of the same keys).
guard("binding the mode keys", bind_mode_keys)()
hl.timer(guard("binding the mode keys", bind_mode_keys), { timeout = 100, type = "oneshot" })

-- Sidebars and pinned windows already styled before this loaded get these
-- looks once the others have loaded too.
guard("applying the window style", apply)()
guard("the terminal effects", apply_terminal)()
hl.timer(guard("restyling sidebars and pinned windows", function()
  if type(sidebar) == "table" and sidebar.retheme then
    sidebar.retheme()
  end
  if type(dock) == "table" and dock.restyle then
    dock.restyle()
  end
end), { timeout = 50, type = "oneshot" })
