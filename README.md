# Omarchy Window Style

How every window looks, in one place: its border (on or off, a colour from your
theme, width, how solid focused and unfocused), its rounding, its shadow, and
how see-through it is. Set it once for **all windows**, then for each kind of
window only where it should differ:

| Kind | Which windows |
|---|---|
| All windows | Every window: what the others start from |
| Tiled | Ordinary tiled windows |
| Floating | Floating windows |
| Popped out | Windows popped out with Omarchy's `Super + O` (floating, on every workspace): as Floating unless set here |
| Scratchpad | Windows on Omarchy's scratchpad (`Super + S`): as Tiled unless set here, so with borders and gaps between them, which Omarchy's drop-down console takes away |
| Sidebars | Windows of the [Sidebar plugin](https://github.com/motorstreak/omarchy-sidebar), when it's installed |
| Docked | Windows the [Dock plugin](https://github.com/motorstreak/omarchy-dock) docks, when it's installed (`pinned` in the config) |
| Menus | Omarchy's menus, launcher, popups and notifications |

Without this plugin, the Sidebar and Dock plugins keep their own looks.

## Install

```bash
omarchy plugin add https://github.com/motorstreak/omarchy-window-style.git --enable
```

Update with `omarchy plugin update window-style`; if an update changes a `.qml`
file, also run `omarchy restart shell`. Remove it with
`omarchy plugin remove window-style`: windows go back to Omarchy's look.

## The panel

`Super + Ctrl + Alt + S` opens it (and the Sidebar plugin's settings,
`Super + Alt + S` in a sidebar, have a "Window style…" row that opens it on the
Sidebars tab).

- `Tab` / `Shift + Tab` (or a click) switch tabs: All windows, Tiled, Floating,
  Popped out, Scratchpad, Sidebars, Docked, Menus.
- `↑` / `↓` choose a row; `←` / `→` (or a click) change it. A change shows at
  once and is saved.
- On a kind's tab, values it takes from All windows are dimmed and marked
  "· all" (or "· Omarchy" where nothing is set); on Popped out, values it takes
  from Floating are marked "· floating", and on Scratchpad, those from Tiled
  "· tiled". Changing one sets it for that
  kind; `Backspace` hands it back.
- **Theme**, at the top of each tab: the Omarchy theme that kind takes its
  colours from. The first choice, "Omarchy's", follows the theme Omarchy is
  using (and changes with it); it's what a tab has until you pick another. A sidebar given a theme of its
  own (the Sidebar plugin's `Super + Alt + T`) keeps that one.
- Border colours come from the tab's theme, with a swatch: first "theme's
  border", the border colours the theme itself sets (in its `hyprland.conf` or
  its `colors.toml`, focused and unfocused), then its accent, its text colour,
  and the palette's six colours, plain and bright. A palette colour follows the slot into other themes ("palette 2" is
  green in most), also in themes that only name their colours.
- The Sidebars tab also has **Dim behind** (how much the rest of the screen
  dims while a sidebar shows) and **Margin** (its gap to the screen edges and
  the bar). They're the Sidebar plugin's own options, which its settings
  (`Super + Alt + S`) then leave to this panel: shown at once and saved into
  `~/.config/omarchy/sidebar.lua`; the tab's reset leaves them.
- The Scratchpad tab also has **Height** (how much of the screen it drops
  down over, 30% to 100%; Omarchy's is 50%), **Gaps between windows** and
  **Gaps to screen edges** (unset: as on other workspaces). Its rounding is always Tiled's: Hyprland rounds tiled windows
  as one.
- The bottom row resets the tab (on All windows: everything, back to Omarchy's
  look): `Enter` (or a click) twice; the arrows never reset. It's greyed out,
  and skipped, when the tab has nothing set.

The **Menus** tab styles Omarchy's own menus, launcher, popups and
notifications: theme, border, its colour, width and opacity, and how solid
their background is. They aren't windows, so it writes these into
`~/.config/omarchy/shell.toml` (its `[menu]`, `[launcher]`, `[popups]` and
`[notifications]` sections; everything else there is left alone), which the
shell picks up at once. Their rounding is shown but not set there: the shell
has one rounding for everything it draws, tiled windows'.

Shadows have one look for every window, as Hyprland allows only one: set it on
All windows (a **glow** in the accent colour, or a faint dark **shadow**, its
size and strength, and whether unfocused windows have one too or only the
focused window); each kind only turns it on or off.

The **Terminal** tab has effects for [Ghostty](https://ghostty.org), made
with its custom shaders: a **Cursor trail** (a fading streak follows the
cursor when it jumps two or more cells, like Kitty's `cursor_trail`) and a
**Bloom** (text and the cursor glow softly), with its strength and size. The
glow takes the text's colour against the theme's background, so it brightens
on dark themes and stays soft on light ones. The plugin writes the shaders
(from its `ghostty/` folder, values filled in) to
`~/.local/state/omarchy-window-style/ghostty/` and lists them in
`~/.config/ghostty/window-style`; the first time an effect is turned on it
adds `config-file = ?window-style` to the end of `~/.config/ghostty/config`
(written through, so a dotfiles link stays a link). Open Ghostty windows
reload at once (SIGUSR2). Both cost GPU time: the trail keeps Ghostty
animating while it's focused, and the bloom samples around every pixel.

## The file

The panel saves to `~/.config/omarchy/window-style.lua`, which you can also
edit (then reload Hyprland). The panel writes it whole, so comments in it
aren't kept.

```lua
return {
  all = {
    border_size = 6,
    rounding = 32,
    border_colour = "accent",          -- "theme" (the theme's own), "accent", "foreground", "color1".."color15", "green"...
    border_opacity = 0.7,              -- 0 to 1
    border_colour_unfocused = "theme",
    border_opacity_unfocused = 0.35,
  },
  floating = { rounding = 20 },        -- only what differs from all windows
  sidebars = { border_colour = "color2", border_opacity = 1 },
  pinned = { border = false, shadow = true },
  scratchpad = { height = 0.75, gaps = 10 }, -- only what differs from tiled windows
  menus = { border_size = 3, background_opacity = 0.95 },
  shadow_look = "glow",                -- or "shadow"
  shadow_size = 6,
  shadow_opacity = 0.2,
  shadow_unfocused = false,            -- only the focused window has a shadow
  open_as = "workspace",               -- or "tiled", "floating", "popped" (Super + O's), "docked" (Dock plugin)
  terminal_trail = true,               -- Ghostty: cursor trail
  terminal_bloom = true,               -- Ghostty: bloom
  terminal_bloom_strength = 0.35,      -- 0 to 1
  terminal_bloom_size = 6,             -- pixels
}
```

`open_as` is how new windows open: as their workspace's layout says
("workspace": Omarchy's Super + L, so a floating workspace floats them and a
tiled or scrolling one tiles them), tiled (Omarchy's way), floating (centred,
at their own size; Super + T tiles one), popped out as Super + O does, or
docked to a screen edge (needs the [Dock plugin](https://github.com/motorstreak/omarchy-dock)).
Dialogs float either way, and only windows opening tiled on a regular
workspace pop out or dock (not a sidebar's or the scratchpad's). The Agent
Sidebar plugin's windows open as its own `open_as` says. The panel shows it on
All windows as "Open new windows as". The old `open_floating = true` still
reads as `open_as = "floating"`.

### Mode keys

With `mode_keys = true`, one set of keys sets a window's mode, and each key
only ever puts a window *into* its mode (pressing it again does nothing):

| Key | Does |
|---|---|
| `key_mode` (Super + T) | the workspace between tiled and floating (Omarchy's layouts; Super + L still cycles in scrolling); on a popped, docked or drawer window: back to its workspace's mode |
| `key_pop` (Super + O) | pops the window out (your `pop-window` if you have one, else Omarchy's) |
| `key_dock` (Super + Alt + P) | docks it to the screen edge (Dock plugin) |
| `key_drawer` (Super + Alt + B) | makes it a drawer (Sidebar plugin) |

From one of those modes to another, the window leaves the first and enters
the second. On the scratchpad, `key_mode` floats or tiles just that window.
The Sidebar plugin (0.41.0 and later) leaves Super + T alone while this is on.

```lua
mode_keys = true,
key_dock = "SUPER + P",
key_drawer = "SUPER + SHIFT + D",
```

A floating window that opens bigger than its screen's visible area (the screen
less the bar, Omarchy's outer gap and the border) is shrunk to fit and
centred, whatever `open_as` says. Apps that remember a size from a bigger
screen, like Chrome, would otherwise open running off the edge.

Each kind (`all`, `tiled`, `floating`, `popped`, `scratchpad`, `sidebars`, `pinned`, `menus`) takes: `theme`
(a theme's folder name, or "current": Omarchy's), `border`
(false: none), `border_size`, `border_colour`, `border_colour_unfocused`,
`border_opacity`, `border_opacity_unfocused`, `rounding`, `shadow`,
`opacity`, `opacity_unfocused` (the window, 0.5 to 1; only windows Omarchy
makes see-through, as apps that should stay solid opt out). `menus` also
takes `background_opacity` (0 to 1), and ignores the window-only options
(rounding, shadow, opacity). `scratchpad` also takes `height` (0.3 to 1, the
share of the screen it covers), `gaps` (pixels between its windows) and
`gaps_out` (to the screen's edges), and ignores `rounding`.

## How it works

Its service loads `hypr/style.lua` into the running Hyprland with `hyprctl
eval`, at start and after every config reload (the same loader as the Sidebar
plugin's). Tiled windows get Hyprland's own settings; floating ones a window
rule for what differs, and their rounding set on each as it floats (rules can't
round past 20); popped-out ones rules on Omarchy's `pop` tag, made after the
floating ones; the scratchpad Omarchy's workspace rule on it given back its
borders, gaps and edge gaps (the console's height set by its bottom gap, as Omarchy does) (again whenever Omarchy remakes it, as the screens change),
and rules on the workspace for what differs from tiled; sidebars and docked windows are styled by their plugins, which
ask `window_style.look(kind)`, and hand back the windows they let go of
(`window_style.adopt(window)`). A window's border colour, once set on it, can't
go back to the theme's, so popped-out and handed-back windows get their kind's
colours set on them here, as those change and across reloads (a theme change
reloads): they're listed in `~/.local/state/omarchy-window-style/framed`. It
alone switches Hyprland's shadows on or off.

## Requirements

Omarchy with Hyprland's Lua config (tested on Hyprland 0.56).
