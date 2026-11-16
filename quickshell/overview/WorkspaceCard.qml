// One face of the drum: a pane of glass holding the pictures of that
// workspace's windows.
//
// EVERYTHING here is a binding on two numbers owned by shell.qml, `pos` (which
// face is in front) and `curve` (1 = drum, 0 = flat row). Nothing in this file
// animates anything, so scrolling costs one matrix per face per frame and no
// layout work. Faces are moved with a transform, never by animating width or
// height, because a size change re-lays-out and re-samples the texture while a
// transform only updates a matrix.
//
// The geometry is a regular prism seen from outside. Face i sits at angle
// phi = (i - pos) * stepEff on a circle of radius rEff, chosen so neighbouring
// faces meet edge to edge. Unfolding is the same formula with stepEff -> 0, which
// sends rEff -> infinity and lays the faces out in a straight line, so the drum
// and the flat row are one continuous family, not two code paths.
//
// The 4x4 matrix is a real perspective projection (last row carries 1/camD).
// Measured in a spike against a plain Rotation and a rotation-plus-scale hack:
// only the matrix makes neighbouring faces meet at a cube corner; the others leave
// gaps and edge-on slivers. It cost about 2 points of CPU more than a plain
// rotation.

import QtQuick
import Quickshell.Wayland

Item {
    id: card

    required property int index
    required property var modelData
    required property var shell          // the ShellRoot: state, actions, helpers
    required property real cardW
    required property real cardH
    required property real pos           // animated position, including the intro spin
    required property real curve         // 1 = drum, 0 = flat row
    required property real step          // degrees between faces when curve = 1
    required property real camD          // camera distance, constant so unfolding does not zoom

    readonly property real gap: 8
    readonly property real rd: Math.round(16 * shell.uiScale)   // corner radius, scales with the screen
    readonly property real c: Math.max(0.02, curve)   // 0 would divide by zero below
    readonly property real stepEff: step * c
    // A closed prism: the last face is the neighbour of the first, so the cube
    // turns round for ever instead of ending in empty space. With fewer than four
    // faces there is no closed prism, so there is nothing to wrap.
    readonly property real offset: {
        const n = shell.faceCount
        const d = index - pos
        return n >= 4 ? d - n * Math.round(d / n) : d
    }
    readonly property real rad: offset * stepEff * Math.PI / 180
    readonly property real cosP: Math.cos(rad)
    readonly property real sinP: Math.sin(rad)
    readonly property real rEff: (cardW + gap) / (2 * Math.tan(stepEff * Math.PI / 360))

    readonly property bool isFront: Math.abs(index - shell.position) < 0.5

    // How far this face has turned away: 0 facing us, 1 edge-on. Drives the
    // shading. While flat there is no turning, so distance from the front stands
    // in for it and the row still reads as depth.
    readonly property real dim: Math.max(0, Math.min(1,
        (1 - cosP) * 0.5 * c + Math.min(Math.abs(offset), 2) * 0.07 * (1 - c)))

    width: cardW
    height: cardH
    x: -cardW / 2
    y: -cardH / 2
    z: cosP * 100 - Math.abs(offset)

    // A face behind the drum is never drawn, and neither is one far off in the
    // flat row. About half the faces cost nothing at any moment.
    // Lite (Game Mode, or memory is short) draws the front face and one either side.
    visible: cosP > -0.1 && Math.abs(offset) < (shell.lite ? 1.6 : 4.6)

    transform: Matrix4x4 {
        matrix: {
            const cs = card.cosP, sn = card.sinP, R = card.rEff, d = card.camD
            const hw = card.cardW / 2, hh = card.cardH / 2
            // Scales ONLY the depth that reaches the GPU. Qt's scene graph renders
            // with a depth range of about +-1, and the true depth of a face is in
            // the hundreds of pixels (up to ~-835 for a 960 px cube), so the GPU
            // clipped everything outside the range: each side face survived as a
            // ~15 px sliver at the hinge where z is near 0. Measured in a spike:
            // unscaled, the neighbours were chopped slivers; with z * 0.001 they
            // were whole 60 degree panes meeting at a real cube corner. x, y and
            // the perspective divide (row 4) still use the true z, so the shape
            // is unchanged. A bigger cube made it worse, which is why a 440 px
            // test cube had looked fine.
            const zk = 0.001
            // face point (u, v) -> drum: x = R sin + u cos ; z = R cos - u sin - R
            // w = 1 - z / camD is the perspective divide.
            const q = Qt.matrix4x4(
                cs, 0, 0, R * sn,
                0, 1, 0, 0,
               -sn * zk, 0, zk, (R * cs - R) * zk,
                sn / d, 0, -1 / d, 1 - (R * cs - R) / d)
            const toOrigin = Qt.matrix4x4(1, 0, 0, -hw, 0, 1, 0, -hh, 0, 0, 1, 0, 0, 0, 0, 1)
            const back     = Qt.matrix4x4(1, 0, 0,  hw, 0, 1, 0,  hh, 0, 0, 1, 0, 0, 0, 0, 1)
            return back.times(q).times(toOrigin)
        }
    }

    // ── the glass ───────────────────────────────────────────────────────────
    Rectangle {
        id: pane
        anchors.fill: parent
        radius: card.rd
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.rgba(1, 1, 1, 0.20) }
            GradientStop { position: 1; color: Qt.rgba(1, 1, 1, 0.06) }
        }
        border.width: card.modelData.current ? 2 : 1
        border.color: card.modelData.current ? shell.accent : Qt.rgba(1, 1, 1, 0.38)
    }

    // Light catching the top rim.
    Rectangle {
        x: card.rd; y: 1
        width: card.cardW - 2 * card.rd; height: 1
        color: Qt.rgba(1, 1, 1, 0.55)
    }

    // Soft sheen from the left. Its strength follows how far the face is turned,
    // so the glass glints as the drum rotates: one binding on a number that
    // already exists, no shader. Not drawn in lite.
    Rectangle {
        visible: !shell.lite
        width: card.cardW * 0.55
        height: card.cardH
        radius: card.rd
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: Qt.rgba(1, 1, 1, 0.07 + 0.20 * Math.abs(card.sinP) * card.c) }
            GradientStop { position: 1; color: Qt.rgba(1, 1, 1, 0) }
        }
    }

    // ── the windows on this workspace ───────────────────────────────────────
    Item {
        id: inset
        x: 8; y: 8
        width: card.cardW - 16
        height: card.cardH - 16
        readonly property real k: width / shell.mon.w

        // The "+" face: a place to drop a window to start a new workspace.
        Text {
            visible: card.modelData.isNew
            anchors.centerIn: parent
            text: "+"
            color: Qt.rgba(1, 1, 1, 0.6)
            font.pixelSize: Math.round(72 * shell.uiScale)
            font.family: shell.fontFamily
        }

        Repeater {
            model: card.modelData.windows

            delegate: Item {
                id: thumb
                required property var modelData
                x: modelData.x * inset.k
                y: modelData.y * inset.k
                width: Math.max(8, modelData.w * inset.k)
                height: Math.max(8, modelData.h * inset.k)
                opacity: shell.dragging && shell.dragAddress === modelData.address ? 0.35 : 1

                // STILL frames only, never `live`. A live capture of one window
                // measured 15-18% of a core while nothing was moving, against 0%
                // for stills, because it streams a frame every refresh whether
                // or not the window changed. An overview does not need a video
                // of the window in front of you. Instead the face you stop on is
                // refreshed once (the Timer below), so it stays current where you
                // are looking for the cost of one capture per stop.
                ScreencopyView {
                    id: pic
                    anchors.fill: parent
                    captureSource: shell.toplevelFor(thumb.modelData.address)
                    // Caps the capture at 1.3x the size it is DRAWN at instead of the
                    // window's full size. Measured: about 33 MiB less RSS (171 vs
                    // 215 and 182 vs 204 across two alternating pairs). Text is
                    // equally sharp in a side-by-side crop, because the front face
                    // shows a window at about half size, so 1.3x still oversamples.
                    //
                    // It was once blamed for a "ghost" of oversized desktop text
                    // across the overlay, and dropped. That was wrong: the ghost was
                    // the window's alpha buffer (see `color` in shell.qml) and
                    // appeared with and without this line.
                    // Lite takes 0.8x, which is smaller than drawn, to hold less memory.
                    constraintSize: Qt.size(Math.round(thumb.width * (shell.lite ? 0.8 : 1.3)),
                                            Math.round(thumb.height * (shell.lite ? 0.8 : 1.3)))
                    live: false

                    // captureFrame() called at once fails with "Cannot capture
                    // frame, as no recording context is ready" -- the capture
                    // session does not exist yet. Ask again until a picture
                    // arrives, then stop. The cap keeps a window that never yields
                    // one from retrying for as long as the overview is open.
                    property int tries: 0
                    Timer {
                        // Fast while the cube is opening, because the pictures are
                        // what the faces are waiting for (was 120 ms).
                        interval: 40
                        repeat: true
                        running: !pic.hasContent && pic.tries < 75
                        onTriggered: { pic.tries++; pic.captureFrame() }
                    }

                    // One fresh frame when the cube settles on this face. Not
                    // repeating: it fires once per stop and costs nothing after.
                    Timer {
                        interval: 200
                        running: !shell.lite && card.isFront && shell.settled && pic.hasContent
                        onTriggered: pic.captureFrame()
                    }
                }

                // Until the picture arrives, or if the compositor has none.
                Rectangle {
                    anchors.fill: parent
                    visible: !pic.hasContent
                    color: Qt.rgba(1, 1, 1, 0.10)
                    Text {
                        anchors.centerIn: parent
                        text: thumb.modelData.cls
                        color: Qt.rgba(1, 1, 1, 0.7)
                        font.pixelSize: Math.round(14 * shell.uiScale)
                        font.family: shell.fontFamily
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
                            shell.dragStart(thumb.modelData.address)
                        }
                        if (moved) shell.dragMove(grab.mapToItem(shell.dragLayer, m.x, m.y))
                    }
                    onReleased: if (moved) shell.dragEnd()
                    onClicked: if (!moved) shell.faceClicked(card.index)
                }
            }
        }
    }

    // ── shading, the drop target, and the click target ─────────────────────
    Rectangle {
        anchors.fill: parent
        radius: card.rd
        color: "black"
        opacity: card.dim
    }

    // The face lights up when a dragged window is over it.
    Rectangle {
        anchors.fill: parent
        radius: card.rd
        color: Qt.rgba(1, 1, 1, 0.22)
        opacity: drop.containsDrag ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 90 } }
    }

    MouseArea {
        anchors.fill: parent
        z: -1                       // under the window pictures, so they get their own press first
        onClicked: shell.faceClicked(card.index)
    }

    DropArea {
        id: drop
        anchors.fill: parent
        onDropped: d => shell.moveWindow(d.source.address, card.modelData.id)
    }

    Text {
        y: card.cardH + Math.round(12 * shell.uiScale)
        width: card.cardW
        horizontalAlignment: Text.AlignHCenter
        text: card.modelData.label + (card.modelData.isNew ? "" : "  ·  " + card.modelData.windows.length)
        color: card.modelData.current ? shell.accent : Qt.rgba(1, 1, 1, 0.8)
        opacity: 1 - card.dim * 1.3
        font.pixelSize: Math.round(17 * shell.uiScale)
        font.family: shell.fontFamily
    }
}
