// Workspace overview: swipe up with three fingers and your workspaces rise from
// the bottom of the screen as a glass cube you can turn. Scroll to rotate it,
// click to go, drag a window onto another face to move it. Esc, a click on the
// background, or a swipe down closes it.
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
// window pictures (ScreencopyView). Layout comes from `hyprctl ... -j`.
//
// Commands go out through `hyprctl dispatch 'hl.dsp...'`, never through
// Hyprland.dispatch(): this repo runs the Lua config, where the legacy string
// form is rejected, and the docs do not say what dispatch() sends.
//
// MOTION is three numbers and nothing else: `position` (which face is in front,
// sprung), `intro` (rise from below, 0..1) and `curve` (1 = cube, 0 = flat row).
// Every face is a binding on them; see WorkspaceCard.qml. No animation runs when
// nothing is moving, so an idle overview draws no frames.
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

    // ── data ────────────────────────────────────────────────────────────────
    property var cards: []                       // [{ id, label, current, isNew, windows: [...] }]
    property var mon: ({ name: "", x: 0, y: 0, w: 1920, h: 1080 })
    property bool dataReady: false
    property bool wallDone: false
    readonly property bool ready: dataReady && wallDone
    property bool closing: false

    // ── motion ──────────────────────────────────────────────────────────────
    property real position: 0        // which face is in front, in face units
    property bool tracking: false    // true while fingers drive `position` directly
    property real intro: 0           // 0 hidden below the screen, 1 settled
    property real curve: 1           // 1 = cube, 0 = flat row (while dragging)

    property bool dragging: false
    property string dragAddress: ""
    property alias dragLayer: dragLayerItem

    readonly property int faceCount: cards.length
    // With four or more faces the cube is a closed loop, so `position` is allowed
    // to run past either end and the faces wrap round it.
    readonly property bool loops: faceCount >= 4
    readonly property int frontIndex: modIdx(Math.round(position))
    readonly property real step: 360 / Math.max(faceCount, 4)
    readonly property real uiScale: win.height / 1080
    readonly property color accent: "#8ab4f8"
    readonly property string fontFamily: "JetBrainsMono Nerd Font"
    readonly property bool trace: Quickshell.env("OVERVIEW_TRACE") === "1"
    // True once the cube has come to rest on a face with nothing driving it. The
    // face in front takes a fresh snapshot when this becomes true.
    readonly property bool settled: !tracking && !closing && Math.abs(position - Math.round(position)) < 0.02

    Behavior on position {
        enabled: !root.tracking && root.ready
        // Tuned by measuring settle time and overshoot with OVERVIEW_TRACE=1.
        SpringAnimation { spring: 3.2; damping: 0.32; epsilon: 0.002 }
    }
    Behavior on curve { NumberAnimation { duration: 240; easing.type: Easing.InOutCubic } }

    onPositionChanged: if (trace) console.log("TRACE pos " + Date.now() + " " + position.toFixed(4))

    // ── helpers ─────────────────────────────────────────────────────────────

    // Which face an unbounded position means: wrapped round when the cube loops,
    // clamped to the ends when it is too small to loop.
    function modIdx(i) {
        const n = root.faceCount
        if (n <= 0) return 0
        return root.loops ? ((i % n) + n) % n : Math.max(0, Math.min(n - 1, i))
    }
    // Nearest whole face, without wrapping, so a spring can carry on round the loop.
    function snap(p) {
        const r = Math.round(p)
        return root.loops ? r : root.modIdx(r)
    }
    // The short way round: face 5 is one step left of face 0, not five steps right.
    function wrapDelta(d) {
        const n = root.faceCount
        return root.loops ? d - n * Math.round(d / n) : d
    }

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

    // Every way out goes through here, so the overview always plays its exit.
    function close() {
        if (root.closing) return
        root.closing = true
        root.tracking = false
        closeAnim.start()
        failsafe.start()
    }

    function focusWorkspace(id) {
        lua("hl.dsp.focus({ workspace = " + id + " })")
        root.close()
    }

    function activate(i) {
        const c = root.cards[i]
        if (c) root.focusWorkspace(c.id)
    }

    // A side face rotates to the front first; only the front face opens.
    function faceClicked(i) {
        if (i !== root.frontIndex) {
            root.tracking = false
            root.position = Math.round(root.position) + root.wrapDelta(i - root.frontIndex)
        } else {
            root.activate(i)
        }
    }

    function stepFace(dir) {
        root.tracking = false
        root.position = root.snap(Math.round(root.position) + dir)
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

    // ── a drag unfolds the cube so every workspace is a drop target ─────────
    // Hit-testing a perspective-transformed item is unreliable in Qt Quick, so no
    // drop ever has to land on a rotated face: the cube becomes a flat row first.
    function dragStart(address) {
        root.dragAddress = address
        root.dragging = true
        root.tracking = true
        root.curve = 0
    }
    function dragMove(p) {
        ghost.x = p.x - ghost.width / 2
        ghost.y = p.y - ghost.height / 2
    }
    function dragEnd() {
        ghost.Drag.drop()
        root.dragging = false
        root.dragAddress = ""
        root.curve = 1
        root.tracking = false
        root.position = root.snap(root.position)
    }

    function parse(text) {
        let d
        try { d = JSON.parse(text) } catch (e) { console.log("overview: bad json: " + e); return }

        const m = d.monitors.find(x => x.focused) || d.monitors[0]
        if (!m) return
        root.mon = { name: m.name, x: m.x, y: m.y, w: m.width, h: m.height }
        const currentId = m.activeWorkspace ? m.activeWorkspace.id : -1

        // Only real, numbered workspaces on this monitor. Special workspaces
        // (the scratchpad) have id <= 0 and are not faces.
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
        if (!root.dataReady) {
            // First read only: start with your own workspace in front, with no
            // spring, because nothing is on screen yet.
            root.position = Math.max(0, list.findIndex(c => c.current))
            root.dataReady = true
        } else if (!root.loops && root.position > list.length - 1) {
            root.position = list.length - 1
        }
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

    // ── open and close ──────────────────────────────────────────────────────
    // It rises from the bottom edge, matching a finger swiping up, and sinks
    // back down on close.
    onReadyChanged: {
        if (trace) console.log("TRACE ready " + Date.now())
        if (ready && !closing) openAnim.start()
    }
    onIntroChanged: if (trace) console.log("TRACE intro " + Date.now() + " " + intro.toFixed(3))
    Component.onCompleted: if (trace) console.log("TRACE start " + Date.now())

    NumberAnimation {
        id: openAnim
        target: root; property: "intro"
        from: 0; to: 1; duration: 340
        easing.type: Easing.OutCubic
    }
    NumberAnimation {
        id: closeAnim
        target: root; property: "intro"
        to: 0; duration: 190
        easing.type: Easing.InCubic
        onFinished: Qt.quit()
    }
    // If the exit animation never finishes, the overview must still go away.
    Timer { id: failsafe; interval: 700; onTriggered: Qt.quit() }

    // The wallpaper decodes asynchronously. Do not start rising until it is in,
    // or the desktop flashes behind a half-drawn overview; but never wait long.
    Timer { interval: 400; running: true; onTriggered: root.wallDone = true }

    // ── test and control hooks (qs ipc -c overview call overview <fn>) ──────
    IpcHandler {
        target: "overview"
        function close(): void { root.close() }
        function goto(i: int): void {
            root.tracking = false
            root.position = Math.round(root.position) + root.wrapDelta(i - root.frontIndex)
        }
        function flat(on: bool): void { root.curve = on ? 0 : 1 }
        function state(): string {
            return JSON.stringify({
                position: root.position, curve: root.curve, intro: root.intro,
                front: root.frontIndex, faces: root.faceCount,
                cardW: win.cardW, cardH: win.cardH, ready: root.ready
            })
        }
        // Which face is under this screen point? Exists to check hit-testing on
        // the perspective-transformed faces without a mouse.
        function faceAt(x: real, y: real): int {
            const p = stage.mapFromItem(dragLayerItem, x, y)
            const it = stage.childAt(p.x, p.y)
            return it ? it.index : -1
        }
        // Each face's projected on-screen rectangle, for checking the geometry
        // against what is actually painted.
        function dump(): string {
            const out = []
            for (let i = 0; i < faces.count; i++) {
                const f = faces.itemAt(i)
                if (!f) continue
                const a = f.mapToItem(dragLayerItem, 0, 0)
                const b = f.mapToItem(dragLayerItem, f.width, f.height)
                out.push({ i: i, vis: f.visible, off: Math.round(f.offset * 100) / 100,
                           x0: Math.round(a.x), x1: Math.round(b.x), y0: Math.round(a.y), y1: Math.round(b.y) })
            }
            return JSON.stringify(out)
        }
        // A scripted 0 -> last -> 0 scroll, for measuring frame times without a touchpad.
        function demo(): void { demoAnim.restart() }
    }
    SequentialAnimation {
        id: demoAnim
        ScriptAction { script: root.tracking = true }
        NumberAnimation { target: root; property: "position"; to: Math.max(1, root.faceCount - 1); duration: 1800; easing.type: Easing.InOutCubic }
        NumberAnimation { target: root; property: "position"; to: 0; duration: 1800; easing.type: Easing.InOutCubic }
        ScriptAction { script: root.tracking = false }
    }

    // ── the window ──────────────────────────────────────────────────────────
    PanelWindow {
        id: win
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        // OPAQUE FROM CREATION, and that is load-bearing. A window created
        // transparent has an alpha buffer, and Hyprland then blended the desktop
        // through it at about 10-12%: a bright-text window underneath (a terminal)
        // showed as a faint, oversized ghost of its text across the whole overlay
        // and over the faces. It hid whenever a dark window (Firefox) was
        // underneath or the wallpaper was busy, which is why it was missed at
        // first. Ruled out, each by test: constraintSize, partial alpha in my own
        // content (a solid black underlay did not help), and flipping `color` after
        // creation (Qt fixes the alpha buffer at creation, so that does nothing).
        // Only a window created opaque removed it, checked with a probe terminal
        // printing a recognisable line.
        //
        // The cost of opaque is that the overlay cannot crossfade itself over the
        // desktop. It does not need to: Hyprland already fades layer surfaces in
        // and out (layersIn / layersOut in config/animations.lua), so it is mapped
        // only once everything is ready (`visible`) and the compositor does the
        // fade. Mapping it early would show a black frame.
        color: "black"
        visible: root.ready
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        WlrLayershell.namespace: "qs-overview"

        // Sized from the screen itself, so it fits whatever monitor this runs on:
        // half the width, but never taller than 60 percent of the height.
        readonly property real cardW: Math.round(Math.min(width * 0.50, height * 0.60 * root.mon.w / root.mon.h))
        readonly property real cardH: Math.round(cardW * root.mon.h / root.mon.w)
        // Camera distance from the full-circle radius, so the perspective stays
        // the same while the cube unfolds instead of zooming.
        readonly property real camD: (cardW + 8) / (2 * Math.tan(root.step * Math.PI / 360)) * 3.2

        FocusScope {
            id: dragLayerItem
            anchors.fill: parent
            focus: true

            Keys.onEscapePressed: root.close()
            Keys.onLeftPressed: root.stepFace(-1)
            Keys.onRightPressed: root.stepFace(1)
            Keys.onReturnPressed: root.activate(root.frontIndex)
            Keys.onEnterPressed: root.activate(root.frontIndex)

            // ── backdrop: the real wallpaper, as glass ─────────────────────
            // Painted by the overlay itself instead of blurring the desktop: no
            // compositor blur pass, and no window text bleeding through. The path
            // is the one wallpaper scripts keep pointing at what awww shows.
            Image {
                id: wall
                anchors.fill: parent
                source: "file://" + Quickshell.env("HOME") + "/Pictures/Wallpaper/current_wallpaper"
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                sourceSize: Qt.size(win.screen ? win.screen.width : 1920, win.screen ? win.screen.height : 1080)
                onStatusChanged: if (status === Image.Ready || status === Image.Error) root.wallDone = true
            }
            // Soft dark gradient so the glass reads on any wallpaper; heavier if
            // the wallpaper failed to load.
            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    GradientStop { position: 0; color: wall.status === Image.Ready ? Qt.rgba(0.02, 0.03, 0.06, 0.28) : Qt.rgba(0.03, 0.04, 0.07, 0.92) }
                    GradientStop { position: 1; color: wall.status === Image.Ready ? Qt.rgba(0.02, 0.03, 0.06, 0.55) : Qt.rgba(0.03, 0.04, 0.07, 0.97) }
                }
                MouseArea { anchors.fill: parent; onClicked: root.close() }
            }

            // Scroll: a touchpad follows your fingers, a wheel notch steps one face.
            property real lastT: 0
            property real vel: 0
            WheelHandler {
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onWheel: event => {
                    if (root.dragging || root.closing) return
                    const ax = event.angleDelta.x, ay = event.angleDelta.y
                    const px = event.pixelDelta.x, py = event.pixelDelta.y
                    const raw = Math.abs(ax) >= Math.abs(ay) ? ax : ay
                    const pxv = Math.abs(px) >= Math.abs(py) ? px : py
                    // A wheel notch is a large multiple of 120 with no pixel delta.
                    // Anything smaller is a touchpad.
                    if (pxv === 0 && Math.abs(raw) >= 100) {
                        root.stepFace(raw > 0 ? -1 : 1)     // same direction the old row scrolled
                        return
                    }
                    const px_ = pxv !== 0 ? pxv : raw * 0.6
                    const now = Date.now()
                    const dt = Math.max(8, now - dragLayerItem.lastT) / 1000
                    const dPos = -px_ / (win.cardW * 0.85)
                    dragLayerItem.vel = 0.7 * dragLayerItem.vel + 0.3 * (dPos / dt)
                    dragLayerItem.lastT = now
                    root.tracking = true
                    // A loop turns freely; a short row has a soft stop past each end.
                    root.position = root.loops
                        ? root.position + dPos
                        : Math.max(-0.35, Math.min(root.faceCount - 1 + 0.35, root.position + dPos))
                    settle.restart()
                }
            }
            // Fingers lifted: carry a little momentum, then spring to the nearest face.
            Timer {
                id: settle
                interval: 90
                onTriggered: {
                    root.tracking = false
                    root.position = root.snap(root.position + dragLayerItem.vel * 0.12)
                    dragLayerItem.vel = 0
                }
            }

            // ── the cube ──────────────────────────────────────────────────
            Item {
                id: stage
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                // Rises from below as `intro` goes 0 -> 1.
                anchors.verticalCenterOffset: -24 * root.uiScale + (1 - root.intro) * win.height * 0.46
                width: 1; height: 1
                // A touch of growth on arrival, and a smaller footprint while
                // unfolded so more workspaces fit on screen to drop onto.
                scale: (0.9 + 0.1 * root.intro) * (1 - 0.5 * (1 - Math.max(0, root.curve)))
                opacity: Math.min(1, root.intro * 1.7)

                Repeater {
                    id: faces
                    model: root.cards
                    delegate: WorkspaceCard {
                        shell: root
                        cardW: win.cardW
                        cardH: win.cardH
                        pos: root.position
                        curve: root.curve
                        step: root.step
                        camD: win.camD
                    }
                }
            }

            // While dragging near either side, keep turning so a workspace that is
            // off screen can still be reached.
            Timer {
                interval: 16
                repeat: true
                running: root.dragging
                onTriggered: {
                    const x = ghost.x + ghost.width / 2
                    const edge = win.width * 0.14
                    let v = 0
                    if (x < edge) v = -(1 - x / edge)
                    else if (x > win.width - edge) v = (x - (win.width - edge)) / edge
                    if (v !== 0) {
                        const next = root.position + v * 0.07
                        root.position = root.loops ? next : Math.max(0, Math.min(root.faceCount - 1, next))
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
                width: Math.round(win.cardW * 0.45)
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
