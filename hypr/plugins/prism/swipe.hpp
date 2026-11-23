#pragma once

#include "core.hpp"

#include <algorithm>
#include <cmath>
#include <cstdint>

namespace prism {

// Decides, for each three-finger trackpad swipe, whether Prism owns it, and feeds the
// core when it does. It knows nothing about the compositor, so it can be replayed in a
// unit test (tests/swipe_test.cpp).
//
// WHY it exists: while the cube is open Hyprland's own three-finger horizontal swipe
// would change the real workspace behind it, and nothing turned the cube. The plugin
// listens to Hyprland's swipe events, which can be cancelled; a cancelled event never
// reaches Hyprland's gesture handling.
//
// RULES
//   * A swipe is owned or not from its first event and stays that way to its last. Owning
//     half of one would leave Hyprland with a gesture that never ends.
//   * Owned only when the cube is fully open (Phase::Open) and exactly three fingers.
//     While it is opening or closing, the existing Lua path keeps handling the swipe.
//   * After a few units of travel the direction is chosen: sideways turns the cube, down
//     closes it (as the Lua path did), up does nothing (the cube is already open).
class SwipeRouter {
public:
    static constexpr std::uint32_t fingers = 3;
    // Travel before the axis is chosen. Small, so the cube follows the fingers at once;
    // large enough that a wobble at the start does not pick the wrong axis.
    static constexpr double decideDistance = 8;

    // Returns true when Prism owns this swipe (the caller cancels the event).
    bool begin(const Core& core, std::uint32_t fingerCount) {
        state_ = State::Idle;
        if (fingerCount != fingers || core.snapshot().phase != Phase::Open)
            return false;
        state_ = State::Deciding;
        sumX_ = sumY_ = 0;
        seconds_ = 0;
        return true;
    }

    // `dtSeconds` is the time since the previous event of this swipe (0 when unknown).
    bool update(Core& core, double dx, double dy, double dtSeconds) {
        if (state_ == State::Idle)
            return false;
        if (!std::isfinite(dx) || !std::isfinite(dy))
            return true; // owned: swallow malformed events rather than leak them
        const double dt = std::isfinite(dtSeconds) && dtSeconds > 0 ? dtSeconds : 0.016;

        if (state_ == State::Deciding) {
            sumX_ += dx;
            sumY_ += dy;
            seconds_ += dt;
            if (std::hypot(sumX_, sumY_) < decideDistance)
                return true;
            const bool sideways = std::abs(sumX_) >= std::abs(sumY_);
            state_ = State::Ignored;
            if (sideways) {
                if (core.begin(Direction::Horizontal, 0))
                    state_ = State::Turning;
            } else if (sumY_ > 0) {
                if (core.begin(Direction::Down, 0))
                    state_ = State::Closing;
            }
            if (state_ != State::Ignored)
                core.update(sumX_, sumY_, seconds_);
            return true;
        }
        if (state_ == State::Turning || state_ == State::Closing)
            core.update(dx, dy, dt);
        return true;
    }

    // Returns true when the swipe was owned. Always leaves the router idle.
    bool end(Core& core, bool cancelled) {
        const auto owned = state_ != State::Idle;
        if (state_ == State::Turning || state_ == State::Closing)
            core.finish(cancelled);
        state_ = State::Idle;
        return owned;
    }

    // The cube was reset or the plugin unloads: forget any swipe in progress.
    void reset() { state_ = State::Idle; }

    [[nodiscard]] bool owning() const { return state_ != State::Idle; }

private:
    enum class State { Idle, Deciding, Turning, Closing, Ignored };
    State state_ = State::Idle;
    double sumX_ = 0, sumY_ = 0, seconds_ = 0;
};

} // namespace prism
