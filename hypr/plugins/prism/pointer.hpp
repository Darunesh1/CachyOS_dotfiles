#pragma once

#include "core.hpp"
#include "hit.hpp"

#include <cmath>
#include <cstdint>
#include <functional>
#include <optional>

namespace prism {

// A window to move to another workspace: the compositor's address and the workspace to move it to.
struct Drop {
    std::uint64_t window;
    WorkspaceId workspace;
};

// Mouse and touchpad clicks, scrolling and window dragging while the cube is open (the same
// split as swipe.hpp: pure logic, no compositor types, tested in tests/pointer_test.cpp).
//
//   click a side face      turn it to the front
//   click the front face   go to that workspace
//   click the backdrop     close without changing workspace
//   scroll                 turn one face per step
//   drag a window          the cube unfolds into a flat row; drop on another workspace to move
//                          the window there; drop anywhere else to cancel
//
// A click is acted on at RELEASE, so a drag can start from the same press. Every event of an
// owned click is swallowed (press and release), so the application underneath never sees half
// a click.
class PointerRouter {
public:
    // Looks up the window under a point of a workspace's picture (u and v, 0 to 1), topmost first.
    using WindowFinder = std::function<std::optional<WindowRect>(WorkspaceId, double u, double v)>;

    // Further than this between press and release (a fraction of the output width) is not a
    // click. Dragging a window starts a little sooner than that.
    static constexpr double clickSlop = 0.02;
    static constexpr double dragSlop = 0.012;
    // Scroll needed for one face: a wheel notch is about 15 units; a touchpad sends many
    // small ones. Faster than 120 ms per face feels like it runs away.
    static constexpr double wheelStep = 10;
    static constexpr double touchpadStep = 40;
    static constexpr std::uint32_t minRotateMs = 120;

    void setWindowFinder(WindowFinder finder) { finder_ = std::move(finder); }

    // Returns true when the click is ours (the caller cancels the event).
    bool press(const Core& core, double x, double y) {
        const auto snapshot = core.snapshot();
        pressed_ = snapshot.phase == Phase::Open;
        pressX_ = x;
        pressY_ = y;
        dragging_ = false;
        candidate_.reset();
        drop_.reset();
        if (pressed_ && finder_) {
            const auto hit = hitTest(core.workspaces(), snapshot.facePosition, snapshot.openness, x, y, snapshot.flatness);
            if (hit)
                if (const auto window = finder_(hit->workspace, hit->uv.u, hit->uv.v))
                    candidate_ = Candidate{hit->workspace, *window};
        }
        return pressed_;
    }

    // The cursor moved. True when a frame should be drawn (a drag is in progress).
    bool move(Core& core, double x, double y) {
        if (!pressed_)
            return false;
        cursorX_ = x;
        cursorY_ = y;
        if (core.snapshot().phase != Phase::Open) {
            cancelDrag(core);
            return false;
        }
        if (candidate_ && !dragging_ && std::hypot(x - pressX_, y - pressY_) > dragSlop) {
            dragging_ = true;
            core.setFlat(true);
        }
        if (!dragging_)
            return false;
        const auto snapshot = core.snapshot();
        const auto hit = hitTest(core.workspaces(), snapshot.facePosition, snapshot.openness, x, y, snapshot.flatness);
        hover_ = hit && hit->workspace != candidate_->workspace ? std::optional{hit->workspace} : std::nullopt;
        return true;
    }

    bool release(Core& core, double x, double y) {
        if (!pressed_)
            return false;
        pressed_ = false;
        const auto snapshot = core.snapshot();
        if (dragging_) {
            // Where the faces are NOW decides the target: the row may still be unfolding.
            const auto hit = snapshot.phase == Phase::Open
                ? hitTest(core.workspaces(), snapshot.facePosition, snapshot.openness, x, y, snapshot.flatness)
                : std::nullopt;
            if (hit && candidate_ && hit->workspace != candidate_->workspace)
                drop_ = Drop{candidate_->window.id, hit->workspace};
            endDrag(core);
            return true;
        }
        candidate_.reset();
        if (std::hypot(x - pressX_, y - pressY_) > clickSlop)
            return true;
        if (snapshot.phase != Phase::Open)
            return true;
        const auto hit = hitTest(core.workspaces(), snapshot.facePosition, snapshot.openness, x, y, snapshot.flatness);
        if (!hit) {
            core.close(false);
        } else if (hit->workspace == core.targetFront()) {
            core.close(true);
        } else {
            core.rotateTo(hit->workspace);
        }
        return true;
    }

    // Escape (or the cube closing) while dragging: put the window back, fold the cube.
    bool cancelDrag(Core& core) {
        if (!dragging_)
            return false;
        endDrag(core);
        return true;
    }

    [[nodiscard]] std::optional<Drop> takeDrop() {
        auto out = drop_;
        drop_.reset();
        return out;
    }

    // `wheel` is true for a notched wheel, false for a touchpad's continuous scrolling.
    bool scroll(Core& core, double delta, bool wheel, std::uint32_t timeMs) {
        if (core.snapshot().phase != Phase::Open)
            return false; // not ours: the application underneath scrolls
        if (!std::isfinite(delta))
            return true;
        if (dragging_)
            return true; // the row is for dropping; do not turn it under the cursor
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
        dragging_ = false;
        candidate_.reset();
        hover_.reset();
        drop_.reset();
        accumulated_ = 0;
    }

    [[nodiscard]] bool pressedNow() const { return pressed_; }
    [[nodiscard]] bool dragging() const { return dragging_; }
    [[nodiscard]] std::optional<DragView> dragView() const {
        if (!dragging_ || !candidate_)
            return std::nullopt;
        return DragView{candidate_->workspace, candidate_->window, cursorX_, cursorY_, hover_};
    }

private:
    struct Candidate {
        WorkspaceId workspace;
        WindowRect window;
    };

    void endDrag(Core& core) {
        dragging_ = false;
        candidate_.reset();
        hover_.reset();
        core.setFlat(false);
    }

    WindowFinder finder_;
    bool pressed_ = false;
    bool dragging_ = false;
    double pressX_ = 0, pressY_ = 0, cursorX_ = 0, cursorY_ = 0;
    std::optional<Candidate> candidate_;
    std::optional<WorkspaceId> hover_;
    std::optional<Drop> drop_;
    double accumulated_ = 0;
    std::uint32_t lastRotateMs_ = 0;
};

} // namespace prism
