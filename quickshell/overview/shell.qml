// Workspace overview: swipe up with three fingers, see every workspace as a card
// with its windows on it, scroll sideways, click to go, drag a window onto
// another card to move it.
//
// WHY THIS IS A SEPARATE PROCESS and not a Hyprland plugin: a plugin runs inside
// the compositor, so a crash there kills every open app and loses unsaved work.
// This is an ordinary client; if it dies, only the overview closes. See
// decisions/0007-workspace-overview-in-quickshell.md.
//
// WHY THE DATA COMES FROM `hyprctl`, not from Quickshell's Hyprland module:
// measured on Hyprland 0.57.2 + Quickshell 0.3.2, `HyprlandWorkspace.id` is -1
// for EVERY workspace (names are right, ids are not) and so is every window's
// workspace id. Quickshell is used only for what it does well here, the live
// window pictures (ScreencopyView). Window and workspace layout come from
// `hyprctl ... -j`, whose ids are correct.
//
// Commands go out through `hyprctl dispatch 'hl.dsp...'`, never through
// Hyprland.dispatch(): this repo runs the Lua config, where the legacy string
// form is rejected, and the docs do not say what dispatch() sends.
//
// Started on demand by hypr/scripts/overview/toggle.sh and exits when closed, so
// it costs nothing while you are not looking at it.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

ShellRoot {
    id: root

    // ── state ───────────────────────────────────────────────────────────────
    property var cards: []                       // [{ id, label, current, isNew, windows: [...] }]
    property var mon: ({ name: "", x: 0, y: 0, w: 1920, h: 1080 })
    property bool ready: false

    property bool dragging: false
    property string dragAddress: ""

    readonly property color accent: "#8ab4f8"
    readonly property string fontFamily: "JetBrainsMono Nerd Font"

    // ── helpers ─────────────────────────────────────────────────────────────

    // hyprctl reports "0x55ae1ba38e50"; Quickshell's HyprlandToplevel.address has
    // no 0x prefix (measured). Strip it before comparing.
    function toplevelFor(addr) {
        const want = String(addr).replace(/^0x/, "")
        const list = Hyprland.toplevels.values
        for (let i = 0; i < list.length; i++)
            if (list[i].address === want) return list[i].wayland
        return null
    }

    function lua(expr) {
        Quickshell.execDetached(["hyprctl", "dispatch", expr])
    }

    function focusWorkspace(id) {
        lua("hl.dsp.focus({ workspace = " + id + " })")
        Qt.quit()
    }

    // `follow = false` is the silent move. Without it the compositor switches to
    // the destination workspace (measured: dropping a test window on workspace 5
    // took the focus from 1 to 5), which would land you somewhere you did not
    // ask to go the moment the overview closed. Confirmed in Hyprland's
    // hlWindowMove: `silent = follow.has_value() && !*follow`.
    function moveWindow(address, workspaceId) {
        lua('hl.dsp.window.move({ workspace = ' + workspaceId + ', follow = false, window = "address:' + address + '" })')
        refresh.restart()
    }

    function parse(text) {
        let d
        try { d = JSON.parse(text) } catch (e) { console.log("overview: bad json: " + e); return }

        const m = d.monitors.find(x => x.focused) || d.monitors[0]
        if (!m) return
        root.mon = { name: m.name, x: m.x, y: m.y, w: m.width, h: m.height }
        const currentId = m.activeWorkspace ? m.activeWorkspace.id : -1

        // Only real, numbered workspaces on this monitor. Special workspaces
        // (the scratchpad) have id <= 0 and are not cards.
        const byId = {}
        d.workspaces.forEach(w => {
            if (w.id > 0 && w.monitor === m.name)
                byId[w.id] = { id: w.id, label: "Workspace " + w.name, current: w.id === currentId, isNew: false, windows: [] }
        })
        if (currentId > 0 && !byId[currentId])
            byId[currentId] = { id: currentId, label: "Workspace " + currentId, current: true, isNew: false, windows: [] }

        d.clients.forEach(c => {
            if (!c.mapped || c.hidden || !c.workspace) return
            const card = byId[c.workspace.id]
            if (!card) return
            card.windows.push({
                address: c.address, cls: c["class"], title: c.title,
                x: c.at[0] - m.x, y: c.at[1] - m.y, w: c.size[0], h: c.size[1]
            })
        })

        const list = Object.values(byId).sort((a, b) => a.id - b.id)
        const nextId = list.length ? list[list.length - 1].id + 1 : 1
        list.push({ id: nextId, label: "New workspace", current: false, isNew: true, windows: [] })

        root.cards = list
        root.ready = true
        const at = list.findIndex(c => c.current)
        Qt.callLater(() => { if (at >= 0) strip.positionViewAtIndex(at, ListView.Center) })
    }

    // One process, one JSON document: three snapshots taken together so the
    // window list and the workspace list cannot disagree.
    Process {
        id: loader
        running: true
        command: ["sh", "-c",
            "jq -n --argjson c \"$(hyprctl clients -j)\" --argjson w \"$(hyprctl workspaces -j)\" " +
            "--argjson m \"$(hyprctl monitors -j)\" '{clients:$c, workspaces:$w, monitors:$m}'"]
        stdout: StdioCollector { onStreamFinished: root.parse(this.text) }
    }

    // A move needs a moment to land before the layout is read back.
    Timer {
        id: refresh
        interval: 250
        onTriggered: { if (!loader.running) loader.running = true }
    }

    // ── the window ──────────────────────────────────────────────────────────
    PanelWindow {
        id: win
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        WlrLayershell.namespace: "qs-overview"

        readonly property real cardW: Math.round(width * 0.29)
        readonly property real cardH: Math.round(cardW * root.mon.h / root.mon.w)
        readonly property real scale: cardW / root.mon.w

        FocusScope {
            id: dragLayer
            anchors.fill: parent
            focus: true

            Keys.onEscapePressed: Qt.quit()
            Keys.onLeftPressed: strip.contentX = Math.max(strip.originX - strip.leftMargin, strip.contentX - win.cardW)
            Keys.onRightPressed: strip.contentX = Math.min(strip.originX + strip.contentWidth - strip.width + strip.rightMargin, strip.contentX + win.cardW)

            // Translucent scrim. Blur comes from the layer rule in rules.lua,
            // keyed on the namespace above.
            Rectangle {
                anchors.fill: parent
                color: Qt.rgba(0.03, 0.04, 0.07, 0.66)
                opacity: root.ready ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 140 } }

                MouseArea {
                    anchors.fill: parent
                    onClicked: Qt.quit()
                }
            }

            ListView {
                id: strip
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                height: win.cardH + 56
                orientation: ListView.Horizontal
                spacing: 28
                model: root.cards
                boundsBehavior: Flickable.StopAtBounds
                leftMargin: Math.max(40, (width - contentWidth) / 2)
                rightMargin: 40
                opacity: root.ready ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 140 } }

                // A touchpad or wheel scrolls sideways whichever axis it uses.
                WheelHandler {
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    onWheel: event => {
                        const d = event.angleDelta.x !== 0 ? event.angleDelta.x : event.angleDelta.y
                        const lo = strip.originX - strip.leftMargin
                        const hi = strip.originX + strip.contentWidth - strip.width + strip.rightMargin
                        strip.contentX = Math.max(lo, Math.min(hi, strip.contentX - d))
                    }
                }

                delegate: Item {
                    id: card
                    required property var modelData
                    width: win.cardW
                    height: win.cardH + 56

                    Rectangle {
                        id: frame
                        y: 0
                        width: win.cardW
                        height: win.cardH
                        radius: 14
                        color: Qt.rgba(1, 1, 1, drop.containsDrag ? 0.24 : (hover.hovered ? 0.13 : 0.07))
                        border.width: card.modelData.current ? 3 : 1
                        border.color: card.modelData.current ? root.accent : Qt.rgba(1, 1, 1, 0.20)
                        Behavior on color { ColorAnimation { duration: 90 } }

                        HoverHandler { id: hover }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: root.focusWorkspace(card.modelData.id)
                        }

                        DropArea {
                            id: drop
                            anchors.fill: parent
                            onDropped: d => root.moveWindow(d.source.address, card.modelData.id)
                        }

                        Text {
                            visible: card.modelData.isNew
                            anchors.centerIn: parent
                            text: "+"
                            color: Qt.rgba(1, 1, 1, 0.55)
                            font.pixelSize: 64
                            font.family: root.fontFamily
                        }

                        Repeater {
                            model: card.modelData.windows

                            delegate: Item {
                                id: thumb
                                required property var modelData
                                x: modelData.x * win.scale
                                y: modelData.y * win.scale
                                width: Math.max(8, modelData.w * win.scale)
                                height: Math.max(8, modelData.h * win.scale)
                                opacity: root.dragging && root.dragAddress === modelData.address ? 0.35 : 1

                                // Still frame for most cards (one capture, no
                                // ongoing cost); live only for the current
                                // workspace and the card under the pointer.
                                ScreencopyView {
                                    id: pic
                                    anchors.fill: parent
                                    captureSource: root.toplevelFor(thumb.modelData.address)
                                    live: card.modelData.current || hover.hovered

                                    // captureFrame() called straight away fails with
                                    // "Cannot capture frame, as no recording context is
                                    // ready" -- the capture session does not exist yet.
                                    // Ask again until a picture arrives, then stop. The
                                    // cap keeps a window that never yields one from
                                    // retrying for as long as the overview is open.
                                    property int tries: 0
                                    Timer {
                                        interval: 120
                                        repeat: true
                                        running: !pic.live && !pic.hasContent && pic.tries < 25
                                        onTriggered: { pic.tries++; pic.captureFrame() }
                                    }
                                }

                                // Shown until the picture arrives, or if the
                                // compositor has none for this window.
                                Rectangle {
                                    anchors.fill: parent
                                    visible: !pic.hasContent
                                    color: Qt.rgba(1, 1, 1, 0.10)
                                    Text {
                                        anchors.centerIn: parent
                                        text: thumb.modelData.cls
                                        color: Qt.rgba(1, 1, 1, 0.7)
                                        font.pixelSize: 14
                                        font.family: root.fontFamily
                                    }
                                }

                                Rectangle {
                                    anchors.fill: parent
                                    color: "transparent"
                                    border.width: 1
                                    border.color: Qt.rgba(1, 1, 1, 0.28)
                                }

                                MouseArea {
                                    id: grab
                                    anchors.fill: parent
                                    property real startX: 0
                                    property real startY: 0
                                    property bool moved: false

                                    onPressed: m => { startX = m.x; startY = m.y; moved = false }
                                    onPositionChanged: m => {
                                        if (!moved && Math.abs(m.x - startX) + Math.abs(m.y - startY) > 10) {
                                            moved = true
                                            root.dragAddress = thumb.modelData.address
                                            root.dragging = true
                                        }
                                        if (moved) {
                                            const p = grab.mapToItem(dragLayer, m.x, m.y)
                                            ghost.x = p.x - ghost.width / 2
                                            ghost.y = p.y - ghost.height / 2
                                        }
                                    }
                                    onReleased: {
                                        if (moved) {
                                            ghost.Drag.drop()
                                            root.dragging = false
                                            root.dragAddress = ""
                                        }
                                    }
                                    onClicked: if (!moved) root.focusWorkspace(card.modelData.id)
                                }
                            }
                        }
                    }

                    Text {
                        y: win.cardH + 12
                        width: win.cardW
                        horizontalAlignment: Text.AlignHCenter
                        text: card.modelData.label + (card.modelData.isNew ? "" : "  ·  " + card.modelData.windows.length)
                        color: card.modelData.current ? root.accent : Qt.rgba(1, 1, 1, 0.75)
                        font.pixelSize: 16
                        font.family: root.fontFamily
                    }
                }
            }

            // What follows the pointer while a window is being dragged. A single
            // stable item whose x/y are set by hand, so a drag never breaks a
            // binding on a real thumbnail.
            Item {
                id: ghost
                visible: root.dragging
                z: 1000
                width: Math.round(win.cardW * 0.7)
                height: Math.round(width * root.mon.h / root.mon.w)
                property string address: root.dragAddress

                Drag.active: root.dragging
                Drag.source: ghost
                Drag.hotSpot.x: width / 2
                Drag.hotSpot.y: height / 2

                ScreencopyView {
                    id: ghostPic
                    anchors.fill: parent
                    captureSource: root.toplevelFor(root.dragAddress)
                    opacity: 0.92
                    property int tries: 0
                    onCaptureSourceChanged: tries = 0
                    Timer {
                        interval: 120
                        repeat: true
                        running: root.dragging && !ghostPic.hasContent && ghostPic.tries < 25
                        onTriggered: { ghostPic.tries++; ghostPic.captureFrame() }
                    }
                }
                Rectangle {
                    anchors.fill: parent
                    color: "transparent"
                    border.width: 2
                    border.color: root.accent
                }
            }
        }
    }
}
