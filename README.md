# Omarchy Window Style

How every window looks, in one place: its border (on or off, a colour from your
theme, width, how solid focused and unfocused), its rounding, its shadow, and
how see-through it is. Set it once for **all windows**, then for each kind of
window only where it should differ:

| Kind | Which windows |
|---|---|
| All windows | Every window: what the others start from |
| Tiled | Ordinary tiled windows |
| Floating | Floating windows, popped-out ones (Super + O) included |
| Sidebars | Windows of the [Sidebar plugin](https://github.com/motorstreak/omarchy-sidebar), when it's installed |
| Pinned | Windows the [Dock plugin](https://github.com/motorstreak/omarchy-dock) pins, when it's installed |
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
  Sidebars, Pinned, Menus.
- `↑` / `↓` choose a row; `←` / `→` (or a click) change it. A change shows at
  once and is saved.
- On a kind's tab, values it takes from All windows are dimmed and marked
  "· all" (or "· Omarchy" where nothing is set). Changing one sets it for that
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
size and strength); each kind only turns it on or off.

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
  menus = { border_size = 3, background_opacity = 0.95 },
  shadow_look = "glow",                -- or "shadow"
  shadow_size = 6,
  shadow_opacity = 0.2,
}
```

Each kind (`all`, `tiled`, `floating`, `sidebars`, `pinned`, `menus`) takes: `theme`
(a theme's folder name, or "current": Omarchy's), `border`
(false: none), `border_size`, `border_colour`, `border_colour_unfocused`,
`border_opacity`, `border_opacity_unfocused`, `rounding`, `shadow`,
`opacity`, `opacity_unfocused` (the window, 0.5 to 1; only windows Omarchy
makes see-through, as apps that should stay solid opt out). `menus` also
takes `background_opacity` (0 to 1), and ignores the window-only options
(rounding, shadow, opacity).

## How it works

Its service loads `hypr/style.lua` into the running Hyprland with `hyprctl
eval`, at start and after every config reload (the same loader as the Sidebar
plugin's). Tiled windows get Hyprland's own settings; floating ones a window
rule for what differs, and their rounding set on each as it floats (rules can't
round past 20); sidebars and pinned windows are styled by their plugins, which
ask `window_style.look(kind)`. It alone switches Hyprland's shadows on or off.

## Requirements

Omarchy with Hyprland's Lua config (tested on Hyprland 0.56).
