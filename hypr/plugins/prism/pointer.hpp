#pragma once

#include "core.hpp"
#include "hit.hpp"

#include <cmath>
#include <cstdint>

namespace prism {

// Mouse and touchpad clicks and scrolling while the cube is open (the same split as
// swipe.hpp: pure logic, no compositor types, tested in tests/pointer_test.cpp).
//
//   click a side face      turn it to the front
//   click the front face   go to that workspace
//   click the backdrop     close without changing workspace
//   scroll                 turn one face per step
//
// The click is acted on at RELEASE, so a later stage can start a drag from the press. Every
// event of an owned click is swallowed (press and release), so the application underneath
// never sees half a click.
class PointerRouter {
public:
    // Further than this between press and release (a fraction of the output width) is not a
    // click. Nothing happens then; dragging a window is a separate step.
    static constexpr double clickSlop = 0.02;
    // Scroll needed for one face: a wheel notch is about 15 units; a touchpad sends many
    // small ones. Faster than 120 ms per face feels like it runs away.
    static constexpr double wheelStep = 10;
    static constexpr double touchpadStep = 40;
    static constexpr std::uint32_t minRotateMs = 120;

    // Returns true when the click is ours (the caller cancels the event).
    bool press(const Core& core, double x, double y) {
        pressed_ = core.snapshot().phase == Phase::Open;
        pressX_ = x;
        pressY_ = y;
        return pressed_;
    }

    bool release(Core& core, double x, double y) {
        if (!pressed_)
            return false;
        pressed_ = false;
        if (std::hypot(x - pressX_, y - pressY_) > clickSlop)
            return true;
        const auto snapshot = core.snapshot();
        if (snapshot.phase != Phase::Open)
            return true;
        const auto hit = hitTest(core.workspaces(), snapshot.facePosition, snapshot.openness, x, y);
        if (!hit) {
            core.close(false);
        } else if (hit->workspace == core.targetFront()) {
            core.close(true);
        } else {
            core.rotateTo(hit->workspace);
        }
        return true;
    }

    // `wheel` is true for a notched wheel, false for a touchpad's continuous scrolling.
    bool scroll(Core& core, double delta, bool wheel, std::uint32_t timeMs) {
        if (core.snapshot().phase != Phase::Open)
            return false; // not ours: the application underneath scrolls
        if (!std::isfinite(delta))
            return true;
        accumulated_ += delta;
        const double step = wheel ? wheelStep : touchpadStep;
        if (std::abs(accumulated_) >= step && timeMs - lastRotateMs_ >= minRotateMs) {
            core.rotate(accumulated_ > 0 ? 1 : -1);
            accumulated_ = 0;
            lastRotateMs_ = timeMs;
        } else if (std::abs(accumulated_) >= 4 * step) {
            accumulated_ = 0; // a long burst must not queue up several turns for later
        }
        return true;
    }

    void reset() {
        pressed_ = false;
        accumulated_ = 0;
    }

    [[nodiscard]] bool pressedNow() const { return pressed_; }

private:
    bool pressed_ = false;
    double pressX_ = 0, pressY_ = 0;
    double accumulated_ = 0;
    std::uint32_t lastRotateMs_ = 0;
};

} // namespace prism
