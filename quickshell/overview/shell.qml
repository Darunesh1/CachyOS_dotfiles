// Prism: the workspace overview. Swipe up with three fingers and your current
// screen shrinks, at the speed of your fingers, into the middle of the display and
// becomes the front face of a glass cube of workspaces you can turn. Pick one and
// it grows from the middle back out to fill the screen. Esc, a click on the
// background, or a swipe down closes it.
//
// WHY THIS IS A SEPARATE PROCESS and not a Hyprland plugin: a plugin runs inside
// the compositor, so a crash there kills every open app and loses unsaved work.
// This is an ordinary client; if it dies, only the overview closes. See
// decisions/0007-workspace-overview-in-quickshell.md.
//
// TWO TIERS, because 8 GB is a hard constraint (ADR 0001):
//   full  RESIDENT: started at login and kept hidden, so the swipe can drive it
//         from the first millimetre. Costs memory all the time.
//   lite  started on demand and quits when closed (PRISM_LITE=1): used while
//         Game Mode is on or memory is low. Cannot follow the first ~200 ms of a
//         swipe, and it draws less (no sheen, smaller pictures, fewer faces).
// hypr/scripts/overview/toggle.sh chooses; see hypr/README.md.
//
// THE SWIPE: Hyprland's Lua gesture callbacks (config/input.lua) append lines to
// $XDG_RUNTIME_DIR/prism/gesture, and this file reads them with `tail -F`:
//   B up|down      a swipe began        M <p>        progress 0..1 (1 = fully open)
//   F <cancelled> <v>   fingers lifted; v is progress per millisecond
// Measured transport latency, write to QML: median 0.65 ms, p95 1.7 ms.
//
// WHY THE DATA COMES FROM `hyprctl`, not from Quickshell's Hyprland module:
// measured on Hyprland 0.57.2 + Quickshell 0.3.2, `HyprlandWorkspace.id` is -1
// for EVERY workspace (names are right, ids are not) and so is every window's
// workspace id. Layout comes from `hyprctl ... -j`; Quickshell is used for the
// pictures (ScreencopyView).
//
// Commands go out through `hyprctl dispatch 'hl.dsp...'`, never through
// Hyprland.dispatch(): this repo runs the Lua config, where the legacy string
// form is rejected.
//
// MOTION is a few numbers and nothing else: `intro` (0 = your screen at full
// size, 1 = the cube is open; driven by your fingers, then settled), `expand`
// (the chosen face growing to fill the screen), `position` (which face is in
// front, sprung) and `curve` (1 = cube, 0 = flat row, while dragging). Every face
// is a binding on them; see WorkspaceCard.qml. No animation runs when nothing is
// moving, so an idle overview draws no frames.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

ShellRoot {
    id: root

    // ── tier and environment ────────────────────────────────────────────────
    readonly property bool lite: Quickshell.env("PRISM_LITE") === "1"
    readonly property bool resident: Quickshell.env("PRISM_RESIDENT") === "1"
    readonly property string run: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/prism"
    readonly property bool trace: Quickshell.env("OVERVIEW_TRACE") === "1"
    // Below this much MemAvailable a hidden resident instance quits itself, so it
    // is not holding ~150 MiB while the machine is short. The starting figure is
    // a guess to be replaced by measurement; toggle.sh owns the way back up.
    readonly property int lowMemKb: parseInt(Quickshell.env("PRISM_LOW_KB") || "1000000")

    // ── state ───────────────────────────────────────────────────────────────
    // hidden | drag (fingers opening) | settling (animating) | open | dragclose
    property string phase: "hidden"
    property bool selecting: false      // a face was chosen and is growing to fill the screen
    property bool pendingOpen: false    // opened by key: start animating once the screen picture is in

    // ── data ────────────────────────────────────────────────────────────────
    property var cards: []                       // [{ id, label, current, isNew, windows: [...] }]
    property var mon: ({ name: "", x: 0, y: 0, w: 1920, h: 1080 })
    property bool dataReady: false
    property bool sheetReady: false              // the picture of your screen has arrived

    // ── motion ──────────────────────────────────────────────────────────────
    property real position: 0        // which face is in front, in face units
    property bool tracking: false    // true while fingers drive `position` directly
    property real intro: 0           // 0 = your screen at full size, 1 = cube open
    property real expand: 0          // 0 = cube, 1 = the chosen face fills the screen
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
    // True once the cube has come to rest on a face with nothing driving it. The
    // face in front takes a fresh snapshot when this becomes true.
    readonly property bool settled: phase === "open" && !tracking && !selecting && Math.abs(position - Math.round(position)) < 0.02

    // The cube builds itself as you open: the faces swing out of a flat row into
    // the cube over the second half of the swipe, and fade in with it.
    readonly property real cubeIn: smooth(0.35, 1, intro)
    readonly property real cubeFade: smooth(0.5, 1, intro)
    readonly property real sheetFade: 1 - smooth(0.78, 1, intro)

    Behavior on position {
        enabled: !root.tracking && root.phase !== "hidden"
        // Tuned by measuring settle time and overshoot with OVERVIEW_TRACE=1. Lite
        // is critically damped, so it settles in fewer frames and never overshoots.
        SpringAnimation { spring: 3.2; damping: root.lite ? 0.6 : 0.32; epsilon: 0.002 }
    }
    Behavior on curve { NumberAnimation { duration: 240; easing.type: Easing.InOutCubic } }

    onPositionChanged: if (trace) console.log("TRACE pos " + Date.now() + " " + position.toFixed(4))
    onIntroChanged: if (trace) console.log("TRACE intro " + Date.now() + " " + intro.toFixed(3))

    // ── helpers ─────────────────────────────────────────────────────────────

    function smooth(a, b, x) {
        const t = Math.max(0, Math.min(1, (x - a) / (b - a)))
        return t * t * (3 - 2 * t)
    }

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

    // ── opening and closing ─────────────────────────────────────────────────

    // `fingers` true: a swipe is driving `intro`. False: a key or the lite path,
    // so play the open animation once the picture of the screen is in.
    function begin(fingers) {
        if (root.phase !== "hidden") return
        root.selecting = false
        root.expand = 0
        root.intro = 0
        root.dataReady = false
        root.sheetReady = false
        root.curve = 1
        root.tracking = false
        root.phase = fingers ? "drag" : "settling"
        root.pendingOpen = !fingers
        if (trace) console.log("TRACE begin " + Date.now() + " fingers=" + fingers)
        loader.running = true
        sheetTimer.tries = 0
        sheetTimer.start()
        guard.restart()
    }

    // Animate `intro` to 0 or 1. Shorter when there is less distance to cover, so
    // a swipe that was nearly there finishes quickly.
    function settleTo(target) {
        settleAnim.stop()
        settleAnim.from = root.intro
        settleAnim.to = target
        settleAnim.duration = Math.round(110 + 260 * Math.abs(target - root.intro))
        root.phase = "settling"
        settleAnim.start()
    }

    // Every way out goes through here, so the overview always plays its exit.
    function close() {
        if (root.phase === "hidden" || root.phase === "settling" && settleAnim.to === 0 || root.selecting) return
        root.tracking = false
        root.dragging = false
        root.settleTo(0)
        guard.restart()
    }

    // Back to idle. A resident instance stays alive but holds no pictures and no
    // window; an on-demand one just quits.
    function finishHide() {
        guard.stop()
        sheetTimer.stop()
        root.phase = "hidden"
        root.selecting = false
        root.pendingOpen = false
        root.expand = 0
        root.intro = 0
        root.cards = []
        root.dataReady = false
        root.sheetReady = false
        root.reloadWall()
        if (trace) console.log("TRACE hidden " + Date.now())
        if (!root.resident) Qt.quit()
    }

    // The chosen face grows from the middle to fill the screen, and the real
    // desktop of that workspace is underneath by the time it is done.
    function focusWorkspace(id) {
        if (root.selecting || root.phase === "hidden") return
        lua("hl.dsp.focus({ workspace = " + id + " })")
        root.selecting = true
        root.tracking = false
        expandAnim.restart()
        guard.restart()
    }

    function activate(i) {
        const c = root.cards[i]
        if (c) root.focusWorkspace(c.id)
    }

    // A side face rotates to the front first; only the front face opens.
    function faceClicked(i) {
        if (root.phase !== "open") return
        if (i !== root.frontIndex) {
            root.tracking = false
            root.position = Math.round(root.position) + root.wrapDelta(i - root.frontIndex)
        } else {
            root.activate(i)
        }
    }

    function stepFace(dir) {
        if (root.phase !== "open") return
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

    // The last 20 wheel events the overlay received, newest last.
    property var wheelEvents: []
    property int wheelCount: 0
    function noteWheel(s) {
        root.wheelCount++
        const a = root.wheelEvents.slice(-19)
        a.push(root.wheelCount + " " + s)
        root.wheelEvents = a
    }

    // Scroll goes to the surface under the POINTER, and a touchpad swipe never moves
    // the pointer after the overlay maps, so Hyprland may keep it on the window
    // underneath and the scroll never reaches us (the arrow keys do, because keyboard
    // focus is forced). Warping the cursor to where it already is makes Hyprland
    // re-pick the surface under it (Actions::moveCursor ends in
    // simulateMouseMovement()) without the pointer visibly moving.
    // Hypothesis from the symptom, not yet seen on a touchpad.
    Process {
        id: refocus
        command: ["sh", "-c", "p=$(hyprctl cursorpos) && hyprctl dispatch \"hl.dsp.cursor.move({ x = ${p%,*}, y = ${p#*, } })\""]
    }

    // ── the swipe ───────────────────────────────────────────────────────────
    function gestureLine(line) {
        const a = line.trim().split(" ")
        if (a[0] === "B") {
            if (a[1] === "up" && root.phase === "hidden") {
                root.begin(true)
            } else if (a[1] === "down" && root.phase === "open") {
                root.phase = "dragclose"
                root.tracking = false
                guard.restart()
            }
        } else if (a[0] === "M") {
            if (root.phase === "drag" || root.phase === "dragclose") {
                root.intro = Math.max(0, Math.min(1, parseFloat(a[1])))
                guard.restart()
            }
        } else if (a[0] === "F") {
            root.release(a[1] === "1", parseFloat(a[2]) || 0)
        }
    }

    // Fingers lifted. Commit by how far it got, or by how fast it was going.
    function release(cancelled, v) {
        const fast = 0.0015            // progress per ms; unverified, tune on the touchpad
        if (root.phase === "drag") {
            const open = !cancelled && v > -fast && (root.intro > 0.35 || v > fast)
            root.settleTo(open ? 1 : 0)
        } else if (root.phase === "dragclose") {
            const shut = !cancelled && v < fast && (root.intro < 0.65 || v < -fast)
            root.settleTo(shut ? 0 : 1)
        }
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
            root.tracking = true
            root.position = Math.max(0, list.findIndex(c => c.current))
            root.tracking = false
            root.dataReady = true
        } else if (!root.loops && root.position > list.length - 1) {
            root.position = list.length - 1
        }
    }

    // One process, one JSON document: three snapshots taken together so the
    // window list and the workspace list cannot disagree.
    Process {
        id: loader
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

    // The picture of your screen: asked for as soon as the window exists, retried
    // until the compositor has a capture session for it. Measured: it arrives in
    // about 30 ms and shows the desktop WITHOUT the overlay, bar included, because
    // the overlay has not been composited yet. A capture needs a mapped window;
    // a hidden one never gets a frame.
    Timer {
        id: sheetTimer
        property int tries: 0
        interval: 5
        repeat: true
        onTriggered: {
            if (sheet.hasContent) {
                running = false
                root.sheetReady = true
                if (root.trace) console.log("TRACE sheet " + Date.now() + " tries " + tries)
                if (!refocus.running) refocus.running = true
                // A key-opened (non-swipe) overview starts animating now.
                if (root.pendingOpen) { root.pendingOpen = false; root.settleTo(1) }
                return
            }
            tries++
            if (tries > 400) {
                // No picture of the screen after ~2 s: carry on without it.
                running = false
                root.sheetReady = true
                if (root.pendingOpen) { root.pendingOpen = false; root.settleTo(1) }
                return
            }
            sheet.captureFrame()
        }
    }

    // Nothing may hold the keyboard for ever. A swipe that stops sending lines
    // (Hyprland reloaded mid-gesture, say), or an animation that never ends,
    // must still let go.
    Timer {
        id: guard
        interval: 2500
        onTriggered: {
            if (root.phase === "drag" || root.phase === "dragclose") root.release(false, 0)
            else if (root.phase === "settling" || root.selecting) root.finishHide()
        }
    }

    NumberAnimation {
        id: settleAnim
        target: root; property: "intro"
        easing.type: Easing.OutCubic
        onFinished: {
            if (root.intro <= 0.001) root.finishHide()
            else { root.phase = "open"; guard.stop() }
        }
    }
    NumberAnimation {
        id: expandAnim
        target: root; property: "expand"
        from: 0; to: 1; duration: 230
        easing.type: Easing.OutCubic
        onFinished: root.finishHide()
    }

    // ── the swipe feed and the resident's bookkeeping ───────────────────────
    Process {
        running: root.resident
        command: ["sh", "-c", "mkdir -p '" + root.run + "' && : >> '" + root.run + "/gesture' && exec tail -n 0 -F '" + root.run + "/gesture'"]
        stdout: SplitParser { onRead: data => root.gestureLine(data) }
    }
    // Lets the gesture callback know a resident instance is there. A stale file
    // after a crash is harmless: the reader checks /proc/<pid> too.
    FileView { id: pidFile; path: root.run + "/pid" }
    Component.onCompleted: {
        if (trace) console.log("TRACE start " + Date.now() + " resident=" + resident + " lite=" + lite)
        if (resident) pidFile.setText(String(Quickshell.processId) + "\n")
        else root.begin(false)
        root.reloadWall()
    }

    // Memory guard. While hidden, a resident instance that finds the machine short
    // of memory quits, giving back ~150 MiB; toggle.sh brings it back when there
    // is room again. `MemAvailable` already counts reclaimable cache.
    Process {
        id: mem
        command: ["sh", "-c", "awk '/^MemAvailable:/ {print $2}' /proc/meminfo"]
        stdout: StdioCollector {
            onStreamFinished: {
                const kb = parseInt(this.text)
                if (root.trace) console.log("TRACE memavail_kb " + kb)
                if (kb > 0 && kb < root.lowMemKb && root.phase === "hidden") {
                    console.log("prism: MemAvailable " + kb + " kB below " + root.lowMemKb + ", quitting to free memory")
                    Qt.quit()
                }
            }
        }
    }
    Timer {
        interval: 15000
        repeat: true
        running: root.resident && root.phase === "hidden"
        onTriggered: { if (!mem.running) mem.running = true }
    }

    // The wallpaper file is rewritten every few minutes by the wallpaper cycle.
    // Reloading it each time the overview goes away keeps the next open current
    // without decoding on the critical path.
    property string wallSource: ""
    function reloadWall() {
        root.wallSource = ""
        Qt.callLater(() => { root.wallSource = "file://" + Quickshell.env("HOME") + "/Pictures/Wallpaper/current_wallpaper" })
    }

    // ── test and control hooks (qs ipc -c overview call overview <fn>) ──────
    IpcHandler {
        target: "overview"
        // Not named show/hide: `qs ipc call overview show` is read by qs itself as a
        // request to list the target (measured: it printed the function list and
        // returned 0 without calling anything), so these are reveal/conceal.
        function reveal(): void { root.begin(false) }
        function conceal(): void { root.close() }
        function toggleShow(): void { if (root.phase === "hidden") root.begin(false); else root.close() }
        // Same as `conceal`.
        function close(): void { root.close() }
        function quit(): void { Qt.quit() }
        // Chooses the face in front, as Enter does. For scripted checks.
        function select(): void { root.activate(root.frontIndex) }
        function goto(i: int): void {
            root.tracking = false
            root.position = Math.round(root.position) + root.wrapDelta(i - root.frontIndex)
        }
        function flat(on: bool): void { root.curve = on ? 0 : 1 }
        // Feeds a swipe line exactly as the gesture file would, so a swipe can be
        // scripted without a touchpad.
        function swipe(line: string): void { root.gestureLine(line) }
        // The last wheel events this overlay received, and how many in all.
        function wheellog(): string {
            return "received " + root.wheelCount + " wheel events; last " + root.wheelEvents.length + ":\n" + root.wheelEvents.join("\n")
        }
        function refocusPointer(): void { if (!refocus.running) refocus.running = true }
        function state(): string {
            return JSON.stringify({
                phase: root.phase, intro: root.intro, expand: root.expand,
                position: root.position, curve: root.curve,
                front: root.frontIndex, faces: root.faceCount,
                sheet: root.sheetReady, data: root.dataReady,
                resident: root.resident, lite: root.lite,
                cardW: win.cardW, cardH: win.cardH
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
        // desktop. It does not need to: your screen is the first thing it shows (the
        // `sheet`), and Hyprland fades layer surfaces in and out (layersIn /
        // layersOut in config/animations.lua).
        color: "black"
        visible: root.phase !== "hidden"
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
        // Where the middle of the cube sits, a little above centre so the labels fit.
        readonly property real cubeLift: 24 * root.uiScale

        FocusScope {
            id: dragLayerItem
            anchors.fill: parent
            focus: true

            // First frame presented after a swipe began, for measuring how long the
            // overlay takes to appear. Only listens when tracing.
            Connections {
                enabled: root.trace && root.phase !== "hidden"
                target: dragLayerItem.Window.window
                property bool first: true
                property double lastFrame: 0
                function onFrameSwapped() {
                    const now = Date.now()
                    if (first) { first = false; console.log("TRACE firstframe " + now) }
                    // A gap over 20 ms between frames while something is moving is a
                    // late frame; gaps over 400 ms are just idle.
                    else if (now - lastFrame > 20 && now - lastFrame < 400) console.log("TRACE late " + (now - lastFrame))
                    else console.log("TRACE frame")
                    lastFrame = now
                }
                function onVisibleChanged() { first = true }
            }

            Keys.onEscapePressed: root.close()
            Keys.onLeftPressed: root.stepFace(-1)
            Keys.onRightPressed: root.stepFace(1)
            Keys.onReturnPressed: root.activate(root.frontIndex)
            Keys.onEnterPressed: root.activate(root.frontIndex)

            // ── backdrop: the real wallpaper, as glass ─────────────────────
            // Painted by the overlay itself instead of blurring the desktop: no
            // compositor blur pass, and no window text bleeding through. The path
            // is the one wallpaper scripts keep pointing at what awww shows. It is
            // fully opaque from the start because it is what you see around your
            // screen as that shrinks away.
            Image {
                id: wall
                anchors.fill: parent
                source: root.wallSource
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: false
                // Lite decodes it at half size and lets the GPU scale it up.
                sourceSize: Qt.size((win.screen ? win.screen.width : 1920) / (root.lite ? 2 : 1),
                                    (win.screen ? win.screen.height : 1080) / (root.lite ? 2 : 1))
            }
            // Soft dark gradient so the glass reads on any wallpaper; heavier if
            // the wallpaper failed to load. It arrives with the swipe.
            Rectangle {
                anchors.fill: parent
                opacity: Math.min(1, root.intro * 1.25)
                gradient: Gradient {
                    GradientStop { position: 0; color: wall.status === Image.Ready ? Qt.rgba(0.02, 0.03, 0.06, 0.28) : Qt.rgba(0.03, 0.04, 0.07, 0.92) }
                    GradientStop { position: 1; color: wall.status === Image.Ready ? Qt.rgba(0.02, 0.03, 0.06, 0.55) : Qt.rgba(0.03, 0.04, 0.07, 0.97) }
                }
                MouseArea { anchors.fill: parent; onClicked: root.close() }
            }

            // ── your screen, shrinking into the middle ─────────────────────
            // A still of the real desktop taken the instant the swipe begins, so at
            // intro = 0 it is pixel-identical to what was there (bar included).
            // `intro` is your fingers, so it shrinks at their speed; at 1 it sits
            // exactly where the front face is, and fades out under it.
            ScreencopyView {
                id: sheet
                // null while hidden: frees the picture and makes the next open
                // capture a fresh one instead of showing the last.
                captureSource: root.phase === "hidden" ? null : win.screen
                live: false
                visible: root.sheetReady && !root.selecting
                opacity: root.sheetFade
                width: win.width
                height: win.height
                x: 0
                y: -win.cubeLift * root.intro
                transformOrigin: Item.Center
                scale: 1 - (1 - win.cardW / win.width) * root.intro
            }

            // Scroll: a touchpad follows your fingers, a wheel notch steps one face.
            property real lastT: 0
            property real vel: 0
            property real startPos: 0
            property bool scrolling: false
            WheelHandler {
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onWheel: event => {
                    const ax = event.angleDelta.x, ay = event.angleDelta.y
                    const px = event.pixelDelta.x, py = event.pixelDelta.y
                    // Kept, always, so `wheellog` can say whether a touchpad that does
                    // not scroll is sending events at all, without a restart.
                    root.noteWheel("angle=" + ax + "," + ay + " pixel=" + px + "," + py +
                        " phase=" + event.phase + " dev=" + event.device.type + " state=" + root.phase)
                    if (root.trace) console.log("TRACE wheel angle=" + ax + "," + ay + " pixel=" + px + "," + py +
                        " phase=" + event.phase + " inverted=" + event.inverted + " dev=" + event.device.type)
                    if (root.dragging || root.phase !== "open") return
                    const raw = Math.abs(ax) >= Math.abs(ay) ? ax : ay
                    const pxv = Math.abs(px) >= Math.abs(py) ? px : py
                    // A wheel notch is a large multiple of 120 with no pixel delta.
                    // Anything smaller is a touchpad.
                    if (pxv === 0 && Math.abs(raw) >= 100) {
                        root.stepFace(raw > 0 ? -1 : 1)     // same direction the old row scrolled
                        return
                    }
                    const px_ = pxv !== 0 ? pxv : raw * 0.6
                    if (!dragLayerItem.scrolling) {
                        dragLayerItem.scrolling = true
                        dragLayerItem.startPos = root.position
                        dragLayerItem.vel = 0
                    }
                    const now = Date.now()
                    const dt = Math.max(8, now - dragLayerItem.lastT) / 1000
                    // About 300 px of finger travel turns one face. The first version
                    // used 0.85 of the card width (~800 px), so an ordinary swipe moved
                    // the cube a fraction of a face and then snapped straight back.
                    const dPos = -px_ / (win.cardW * 0.3)
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
            // Fingers lifted: project where the motion was headed, and land on a face.
            // Any deliberate swipe moves at least one face in its direction, however
            // short, so a gentle flick is never thrown away.
            Timer {
                id: settle
                interval: 90
                onTriggered: {
                    const d = root.position - dragLayerItem.startPos
                    let n = Math.round(d + dragLayerItem.vel * 0.18)
                    if (n === 0 && Math.abs(d) > 0.1) n = d > 0 ? 1 : -1
                    root.tracking = false
                    root.position = root.snap(Math.round(dragLayerItem.startPos) + n)
                    dragLayerItem.vel = 0
                    dragLayerItem.scrolling = false
                }
            }

            // ── the cube ──────────────────────────────────────────────────
            Item {
                id: stage
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: -win.cubeLift * (1 - root.expand)
                width: 1; height: 1
                // A smaller footprint while unfolded so more workspaces fit on
                // screen to drop onto; and, once a face is chosen, the whole cube
                // grows until that face fills the screen.
                scale: (1 - 0.5 * (1 - Math.max(0, root.curve))) * (1 + root.expand * (win.width / win.cardW - 1))
                opacity: root.cubeFade
                visible: root.cubeFade > 0.01

                Repeater {
                    id: faces
                    model: root.cards
                    delegate: WorkspaceCard {
                        shell: root
                        cardW: win.cardW
                        cardH: win.cardH
                        pos: root.position
                        curve: root.curve * root.cubeIn
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
