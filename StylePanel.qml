import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// The window style panel (SUPER + CTRL + ALT + S): a tab for all windows and
// one for each kind (tiled, floating, and sidebars and pinned windows when
// their plugins are installed). A kind's tab shows its own values, and the
// ones it takes from all windows dimmed; changing one sets it for that kind,
// Backspace hands it back. Each change is applied at once and saved by
// hypr/style.lua (window_style.set).
Scope {
  id: root

  property bool open: false
  property string monitor: ""
  property var kinds: ({}) // kind -> option -> value or null
  property var present: ({})
  property var palettes: ({}) // kind -> [{ name, label, hex }], from its theme
  property var unfocusedHex: ({}) // kind -> its theme's own unfocused border colour
  property var themes: [] // [{ slug, label }]
  property string currentTheme: ""
  readonly property var colours: palettes[tab] || []
  property var omarchy: ({})
  property var shadow: ({}) // { look, size, opacity }
  property var sidebarOptions: null // the Sidebar plugin's { dim, margin }
  property var sidebarPending: ({}) // changed, to be saved
  property string tab: "all"
  property int index: 0
  property bool confirming: false

  readonly property var tabs: {
    var list = [{ kind: "all", label: "All windows" }, { kind: "tiled", label: "Tiled" }, { kind: "floating", label: "Floating" }]
    if (present.sidebars) list.push({ kind: "sidebars", label: "Sidebars" })
    if (present.pinned) list.push({ kind: "pinned", label: "Pinned" })
    list.push({ kind: "menus", label: "Menus" })
    return list
  }

  readonly property var options: [
    { key: "theme", label: "Theme", hint: "The Omarchy theme its colours come from", type: "theme" },
    { key: "border", label: "Border", hint: "Off: no border, whatever the rows below say", type: "bool" },
    { key: "border_colour", label: "Border colour", hint: "Focused, from the theme's colours", type: "colour", needs: "border" },
    { key: "border_colour_unfocused", label: "Unfocused border colour", hint: "From the theme's colours", type: "colour", needs: "border", unfocused: true },
    { key: "border_size", label: "Border width", hint: "Omarchy's windows have 2", type: "number", min: 0, max: 20, step: 1, unit: "px", needs: "border" },
    { key: "border_opacity", label: "Border opacity", hint: "Focused; 0 is clear, 100 solid", type: "number", min: 0, max: 1, step: 0.05, unit: "%", needs: "border" },
    { key: "border_opacity_unfocused", label: "Unfocused border opacity", hint: "0 is clear, 100 solid", type: "number", min: 0, max: 1, step: 0.05, unit: "%", needs: "border" },
    { key: "rounding", label: "Rounding", hint: "Corner radius", type: "number", min: 0, max: 50, step: 2, unit: "px" },
    { key: "shadow", label: "Shadow", hint: "In the look set on All windows", type: "bool" },
    { key: "opacity", label: "Window opacity", hint: "Focused; Omarchy's is 98.5%", type: "number", min: 0.5, max: 1, step: 0.01, unit: "%" },
    { key: "opacity_unfocused", label: "Unfocused window opacity", hint: "Omarchy's is 96%", type: "number", min: 0.5, max: 1, step: 0.01, unit: "%" }
  ]
  // On All windows only: the one shadow look every window shares.
  readonly property var shadowRows: [
    { key: "shadow_look", label: "Shadow look", hint: "One for every window: a glow in the accent colour, or a dark shadow", type: "enum", options: ["glow", "shadow"], global: true },
    { key: "shadow_size", label: "Shadow size", hint: "How far it reaches", type: "number", min: 1, max: 60, step: 1, unit: "px", global: true },
    { key: "shadow_opacity", label: "Shadow strength", hint: "0 is clear, 100 solid", type: "number", min: 0, max: 1, step: 0.05, unit: "%", global: true },
    { key: "shadow_unfocused", label: "Shadow on unfocused windows", hint: "Off: only the focused window has one", type: "bool", global: true }
  ]
  // Menus (Omarchy's shell draws them): the border, and how solid their
  // background is. Their rounding is shown, not set: the shell has one
  // rounding for all it draws, tiled windows' (Hyprland's own).
  readonly property var menuKeys: ["theme", "border", "border_colour", "border_size", "border_opacity"]
  readonly property var menuRows: options.filter(function(r) { return menuKeys.indexOf(r.key) >= 0 }).concat([
    { key: "background_opacity", label: "Background opacity", hint: "Menus, launcher, popups and notifications", type: "number", min: 0.3, max: 1, step: 0.02, unit: "%" },
    { key: "rounding", label: "Rounding", hint: "Always tiled windows': set it there (or on All windows)", type: "number", unit: "px", follows: "tiled" }
  ])
  // On Sidebars: the Sidebar plugin's own look options, shown and saved
  // through it (its settings leave them to this panel).
  readonly property var sidebarRows: [
    { key: "dim", label: "Dim behind", hint: "How much the rest of the screen dims while a sidebar shows", type: "number", min: 0, max: 1, step: 0.05, unit: "%", sidebar: true },
    { key: "margin", label: "Margin", hint: "Gap to the screen edges and the bar", type: "number", min: 0, max: 120, step: 4, unit: "px", sidebar: true }
  ]
  readonly property var rows: tab === "all" ? options.concat(shadowRows) : tab === "menus" ? menuRows
    : tab === "sidebars" && sidebarOptions !== null ? options.concat(sidebarRows) : options
  readonly property int count: rows.length + 1 // and the reset row
  // Whether the reset row has anything to do: an option set on this tab (on
  // All windows: on any tab, or the shadow look changed).
  readonly property bool resettable: {
    function set(kind) {
      var k = kinds[kind] || {}
      for (var o in k) if (k[o] !== null && k[o] !== undefined) return true
      return false
    }
    if (tab !== "all") return set(tab)
    for (var kind in kinds) if (set(kind)) return true
    return shadow.look !== undefined && (shadow.look !== "glow" || shadow.size !== 6 || shadow.opacity !== 0.2 || shadow.unfocused === false)
  }
  // The last row ↓ reaches: the reset row only when it can do something.
  readonly property int lastIndex: resettable ? rows.length : rows.length - 1

  function show(payload) {
    var p = JSON.parse(payload)
    monitor = String(p.monitor || "")
    kinds = p.kinds || {}
    present = p.present || {}
    palettes = p.palettes || {}
    unfocusedHex = p.unfocused || {}
    themes = Array.isArray(p.themes) ? p.themes : []
    currentTheme = String(p.current_theme || "")
    omarchy = p.omarchy || {}
    shadow = p.shadow || {}
    sidebarOptions = p.sidebar && typeof p.sidebar === "object" ? p.sidebar : null
    tab = tabs.some(function(t) { return t.kind === p.tab }) ? p.tab : "all"
    index = Math.max(0, Math.min(Number(p.index) || 0, lastIndex))
    confirming = false
    open = true
    keys.forceActiveFocus()
  }

  // Omarchy's value, where nothing is set.
  function omarchyValue(key) {
    switch (key) {
    case "border": return true
    case "border_size": return omarchy.border_size
    case "rounding": return omarchy.rounding
    case "shadow": return false
    case "border_colour": case "border_colour_unfocused": return "theme"
    case "theme": return "current"
    }
    return null
  }

  // A row's value on this tab, and where it comes from: "own", "all" or "omarchy".
  function lookup(row) {
    if (row.sidebar) return { value: sidebarOptions[row.key], from: "own" }
    if (row.global) {
      var g = { shadow_look: shadow.look, shadow_size: shadow.size, shadow_opacity: shadow.opacity, shadow_unfocused: shadow.unfocused }[row.key]
      return { value: g, from: "own" }
    }
    // A row another kind's value shows (a menus' rounding: tiled windows').
    var kind = row.follows || tab
    var own = (kinds[kind] || {})[row.key]
    if (own !== null && own !== undefined) return { value: own, from: row.follows ? row.follows : "own" }
    if (kind !== "all") {
      var all = (kinds.all || {})[row.key]
      if (all !== null && all !== undefined) return { value: all, from: "all" }
    }
    return { value: omarchyValue(row.key), from: "omarchy" }
  }

  function enabled(row) {
    return !row.needs || lookup({ key: row.needs }).value !== false
  }

  function themeLabel(slug) {
    for (var i = 0; i < themes.length; i++) {
      if (themes[i].slug === slug) return themes[i].label
    }
    return String(slug)
  }

  function colourOf(name) {
    for (var i = 0; i < colours.length; i++) {
      if (colours[i].name === name) return colours[i]
    }
    return null
  }

  function swatch(row) {
    var v = lookup(row).value
    if (row.unfocused && v === "theme") return unfocusedHex[tab] || ""
    var c = colourOf(v)
    return c ? c.hex : ""
  }

  function shown(row) {
    var l = lookup(row), v = l.value, text
    if (row.type === "bool") text = v === true ? "On" : "Off"
    else if (row.type === "enum") text = String(v)
    else if (row.type === "colour") { var c = colourOf(v); text = c ? c.label : String(v) }
    else if (row.type === "theme") text = v === "current" ? "Omarchy's (" + themeLabel(currentTheme) + ")" : themeLabel(v)
    else if (typeof v !== "number") text = row.key.indexOf("opacity") === 0 || row.key === "background_opacity" ? "Omarchy's" : "theme's"
    else text = row.unit === "%" ? Math.round(v * 100) + "%" : Math.round(v) + " px"
    if (row.follows && l.from === row.follows) text += "  · " + row.follows
    else if (l.from === "all") text += "  · all"
    else if (l.from === "omarchy" && tab !== "all" && !row.global) text += "  · Omarchy"
    return text
  }

  function luaValue(v) {
    if (v === null || v === undefined) return "nil"
    if (typeof v === "string") return "'" + v.replace(/[^A-Za-z0-9_.-]/g, "") + "'"
    return String(v)
  }

  function send(key, v, global) {
    var call = global ? "window_style.set('" + key + "', nil, " + luaValue(v) + ")"
                      : "window_style.set('" + tab + "', '" + key + "', " + luaValue(v) + ")"
    Quickshell.execDetached(["hyprctl", "eval", call])
  }

  function store(key, v, global) {
    if (global) {
      var s = Object.assign({}, shadow)
      s[{ shadow_look: "look", shadow_size: "size", shadow_opacity: "opacity", shadow_unfocused: "unfocused" }[key]] = v
      shadow = s
    } else {
      var k = Object.assign({}, kinds)
      k[tab] = Object.assign({}, k[tab] || {})
      k[tab][key] = v
      kinds = k
    }
    send(key, v, global)
    // Another theme: its colours to pick from (the panel opens again with them).
    if (key === "theme") refresh.restart()
  }

  // Saving reloads Hyprland, so only once the arrows rest.
  Timer {
    id: sidebarSave
    interval: 600
    onTriggered: {
      var args = []
      for (var k in root.sidebarPending) args.push("'" + k + "'", String(root.sidebarPending[k]))
      root.sidebarPending = {}
      if (args.length) Quickshell.execDetached(["hyprctl", "eval", "sidebar.save(" + args.join(", ") + ")"])
    }
  }

  Timer {
    id: refresh
    interval: 250
    onTriggered: Quickshell.execDetached(["hyprctl", "eval", "window_style.open('" + root.tab + "', " + root.index + ")"])
  }

  function change(row, step) {
    if (!enabled(row) || row.follows) return
    var v = lookup(row).value
    if (row.type === "bool") {
      v = !(v === true)
    } else if (row.type === "enum") {
      var i = row.options.indexOf(String(v))
      v = row.options[((i < 0 ? 0 : i + step) + row.options.length) % row.options.length]
    } else if (row.type === "theme") {
      var list = ["current"].concat(themes.map(function(t) { return t.slug }))
      var n = list.indexOf(String(v))
      v = list[((n < 0 ? 0 : n + step) + list.length) % list.length]
    } else if (row.type === "colour") {
      var at = -1
      for (var j = 0; j < colours.length; j++) {
        if (colours[j].name === String(v)) at = j
      }
      v = colours[((at < 0 ? 0 : at + step) + colours.length) % colours.length].name
    } else {
      if (typeof v !== "number") v = row.key.indexOf("opacity") === 0 || row.key === "background_opacity" ? 1 : row.min
      else v = Math.min(row.max, Math.max(row.min, Math.round((v + step * row.step) / row.step) * row.step))
      v = Math.round(v * 1000) / 1000
    }
    if (row.sidebar) {
      var o = Object.assign({}, sidebarOptions)
      o[row.key] = v
      sidebarOptions = o
      var pend = Object.assign({}, sidebarPending)
      pend[row.key] = v
      sidebarPending = pend
      Quickshell.execDetached(["hyprctl", "eval", "sidebar.set_live('" + row.key + "', " + v + ")"])
      sidebarSave.restart()
      return
    }
    store(row.key, v, row.global)
  }

  // Back to all windows' value (or Omarchy's, on All windows).
  function clear(row) {
    if (row.global || row.follows || row.sidebar || lookup(row).from !== "own") return
    store(row.key, null, false)
  }

  function reset() {
    var k = Object.assign({}, kinds)
    if (tab === "all") {
      for (var name in k) k[name] = {}
      shadow = { look: "glow", size: 6, opacity: 0.2, unfocused: true }
    } else {
      k[tab] = {}
    }
    kinds = k
    index = rows.length - 1
    Quickshell.execDetached(["hyprctl", "eval", "window_style.reset('" + (tab === "all" ? "everything" : tab) + "')"])
    confirming = false
  }

  function activate(step) {
    if (index >= rows.length) {
      if (!resettable) return
      if (confirming) reset()
      else confirming = true
    } else {
      change(rows[index], step)
    }
  }

  function switchTab(step) {
    var i = 0
    for (var j = 0; j < tabs.length; j++) {
      if (tabs[j].kind === tab) i = j
    }
    tab = tabs[(i + step + tabs.length) % tabs.length].kind
    index = Math.min(index, lastIndex)
    confirming = false
  }

  IpcHandler {
    target: "window-style-panel"
    function open(payload: string): string { root.show(payload); return "ok" }
    function close(): string { root.open = false; return "ok" }
    // Omarchy's shell takes its rounding from Hyprland's, but reads it only
    // on a theme change; hypr/style.lua asks after setting it.
    function restyle(): string { Style.scheduleRefresh(); return "ok" }
    function state(): string { return (root.open ? "open " : "closed ") + root.tab + " " + root.index + " " + JSON.stringify(root.kinds[root.tab] || {}) }
  }

  PanelWindow {
    id: panel

    screen: {
      var screens = Quickshell.screens
      for (var i = 0; i < screens.length; i++) {
        if (screens[i].name === root.monitor) return screens[i]
      }
      return screens.length > 0 ? screens[0] : null
    }
    visible: root.open
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "omarchy-window-style"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    readonly property int rowHeight: Math.max(Style.space(50), Style.font.body + Style.font.caption + Style.spacing.rowPaddingX * 2)

    Rectangle {
      anchors.fill: parent
      color: Commons.Color.menu.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.open = false
    }

    BorderSurface {
      id: card

      width: Math.min(Style.space(600), panel.width - Style.gapsOut * 2)
      height: Math.min(panel.height - Style.gapsOut * 2, column.implicitHeight + Style.spacing.panelPadding * 2)
      anchors.centerIn: parent
      radius: Style.cornerRadius
      // As Omarchy's menus: their background, border and its width from
      // shell.toml's [menu] (the Window Style plugin's Menus tab).
      color: Commons.Color.menu.background
      borderSpec: Border.surfaceSpec("menu", "border", Commons.Color.menu.border, Math.max(1, Style.space(2)))
      clip: true

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keys
        anchors.fill: parent
        focus: true

        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            if (root.confirming) root.confirming = false
            else root.open = false
          } else if (event.key === Qt.Key_Tab) {
            root.switchTab(1)
          } else if (event.key === Qt.Key_Backtab) {
            root.switchTab(-1)
          } else if (event.key === Qt.Key_Up) {
            root.index = Math.max(0, root.index - 1)
            root.confirming = false
          } else if (event.key === Qt.Key_Down) {
            root.index = Math.min(root.lastIndex, root.index + 1)
          } else if (event.key === Qt.Key_Left || event.key === Qt.Key_Right) {
            // Only changes a value: the reset row takes Enter, Space or a
            // click, so arrows held past the last row reset nothing.
            if (root.index < root.rows.length) root.activate(event.key === Qt.Key_Left ? -1 : 1)
          } else if (event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.activate(1)
          } else if (event.key === Qt.Key_Backspace || event.key === Qt.Key_Delete) {
            if (root.index < root.rows.length) root.clear(root.rows[root.index])
          } else {
            return
          }
          event.accepted = true
        }
      }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Style.spacing.panelPadding
        spacing: Style.space(2)

        Text {
          width: parent.width
          height: Math.max(Style.space(30), Style.font.title + Style.spacing.controlPaddingY)
          verticalAlignment: Text.AlignVCenter
          textFormat: Text.PlainText
          text: "Window style"
          color: Commons.Color.menu.text
          opacity: 0.58
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.heading
        }

        // The tabs: Tab / Shift + Tab, or a click.
        Row {
          width: parent.width
          spacing: Style.space(4)
          bottomPadding: Style.space(6)

          Repeater {
            model: root.tabs

            delegate: Rectangle {
              required property var modelData
              readonly property bool current: modelData.kind === root.tab
              width: label.implicitWidth + Style.space(24)
              height: label.implicitHeight + Style.space(12)
              radius: height / 2
              color: current ? Commons.Color.menu.selectedBackground : "transparent"
              border.color: Util.alpha(Commons.Color.menu.text, current ? 0 : 0.15)
              border.width: 1

              Text {
                id: label
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: modelData.label
                color: parent.current ? Commons.Color.menu.selectedText : Commons.Color.menu.text
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.bodySmall
                font.weight: parent.current ? Font.Medium : Font.Normal
              }

              MouseArea {
                anchors.fill: parent
                onClicked: {
                  root.tab = modelData.kind
                  root.index = Math.min(root.index, root.lastIndex)
                  root.confirming = false
                }
              }
            }
          }
        }

        Repeater {
          model: root.rows

          delegate: Rectangle {
            id: row
            required property var modelData
            required property int index
            readonly property bool current: index === root.index
            readonly property var source: { root.kinds; root.shadow; root.tab; return root.lookup(modelData) }

            width: column.width
            height: panel.rowHeight
            radius: Style.cornerRadius
            color: current ? Commons.Color.menu.selectedBackground : "transparent"
            opacity: root.enabled(modelData) ? 1 : 0.4

            Column {
              anchors.left: parent.left
              anchors.leftMargin: Style.space(14)
              anchors.right: value.left
              anchors.rightMargin: Style.space(40)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              Text {
                width: parent.width
                textFormat: Text.PlainText
                text: row.modelData.label
                color: row.current ? Commons.Color.menu.selectedText : Commons.Color.menu.text
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.body
                font.weight: Font.Medium
                elide: Text.ElideRight
              }

              Text {
                width: parent.width
                textFormat: Text.PlainText
                text: row.modelData.hint
                color: row.current ? Commons.Color.menu.selectedText : Commons.Color.menu.text
                opacity: 0.52
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight
              }
            }

            Rectangle {
              readonly property string hex: { root.kinds; root.tab; return row.modelData.type === "colour" ? root.swatch(row.modelData) : "" }
              visible: hex !== ""
              anchors.right: value.left
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(18)
              height: width
              radius: width / 4
              color: hex || "transparent"
              border.color: Util.alpha(Commons.Color.menu.text, 0.3)
              border.width: 1
            }

            Text {
              id: value
              anchors.right: parent.right
              anchors.rightMargin: Style.space(14)
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: { root.kinds; root.shadow; root.tab; var arrows = row.modelData.type !== "bool" && !row.modelData.follows; return (arrows ? "‹  " : "") + root.shown(row.modelData) + (arrows ? "  ›" : "") }
              color: row.current ? Commons.Color.menu.selectedText : Commons.Color.menu.text
              // Inherited: dimmed.
              opacity: row.source.from === "own" ? 1 : 0.5
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.body
            }

            MouseArea {
              anchors.fill: parent
              onClicked: function(mouse) {
                root.index = row.index
                root.confirming = false
                root.change(row.modelData, row.modelData.type !== "bool" && mouse.x < width / 2 ? -1 : 1)
              }
            }
          }
        }

        Rectangle {
          readonly property bool current: root.index === root.rows.length
          width: column.width
          height: Math.max(Style.space(40), Style.font.body + Style.spacing.rowPaddingX * 2)
          radius: Style.cornerRadius
          color: current ? Commons.Color.menu.selectedBackground : "transparent"
          // Nothing set here: nothing to reset.
          opacity: root.resettable ? 1 : 0.35

          Text {
            anchors.left: parent.left
            anchors.leftMargin: Style.space(14)
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: !root.resettable ? (root.tab === "all" ? "Nothing to reset: Omarchy's look" : "Nothing to reset: all windows' look")
                : root.confirming ? "Press again to reset " + (root.tab === "all" ? "every tab" : "this tab")
                                  : (root.tab === "all" ? "Reset everything to Omarchy's look" : "Reset this tab to all windows'")
            color: parent.current ? Commons.Color.menu.selectedText : Commons.Color.menu.text
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.body
            font.weight: Font.Medium
          }

          MouseArea {
            anchors.fill: parent
            onClicked: {
              if (!root.resettable) return
              root.index = root.rows.length
              root.activate(1)
            }
          }
        }

        Text {
          width: parent.width
          topPadding: Style.space(8)
          textFormat: Text.PlainText
          text: "Tab next tab · ↑↓ choose · ←→ change · ⌫ back to " + (root.tab === "all" ? "Omarchy's" : "all windows'") + " · Enter on reset · Esc close"
          color: Commons.Color.menu.text
          opacity: 0.45
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.bodySmall
          horizontalAlignment: Text.AlignHCenter
          elide: Text.ElideRight
        }
      }
    }
  }
}
