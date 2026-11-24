#include "../pointer.hpp"

#include <cstdlib>
#include <iostream>

using prism::Core;
using prism::Phase;
using prism::PointerRouter;

namespace {

void check(bool condition, const char* message) {
    if (!condition) {
        std::cerr << message << '\n';
        std::exit(EXIT_FAILURE);
    }
}

void settle(Core& core) {
    for (int frame = 0; core.snapshot().animating && frame < 240; ++frame)
        core.tick(1.0 / 120);
    check(!core.snapshot().animating, "spring did not settle");
}

Core openCube(std::vector<prism::WorkspaceId> ids, prism::WorkspaceId current) {
    Core core;
    core.setWorkspaces(std::move(ids));
    check(core.open(current), "open rejected");
    settle(core);
    check(core.snapshot().phase == Phase::Open, "cube did not open");
    return core;
}

// A click at a point: press then release in the same place.
bool click(PointerRouter& router, Core& core, double x, double y) {
    const bool pressOwned = router.press(core, x, y);
    const bool releaseOwned = router.release(core, x, y);
    check(pressOwned == releaseOwned, "a click was owned for one of its two events only");
    return pressOwned;
}

void testClicks() {
    PointerRouter router;
    // Five workspaces show a front face and two neighbours (three or four show only the front).
    auto core = openCube({1, 2, 3, 4, 5}, 3);
    check(core.targetFront() == 3, "setup: front face");

    // A neighbour: turn to it, do not close.
    const auto faces = prism::projectFaces(core.workspaces(), core.snapshot().facePosition, 1);
    check(faces.size() == 3, "setup: expected three visible faces");
    const auto& next = *std::ranges::find_if(faces, [](const auto& f) { return f.workspace == 4; });
    const auto p = next.point(0.5, 0.5);
    check(click(router, core, p.x, p.y), "a click on a side face was not owned");
    check(core.targetFront() == 4 && core.snapshot().phase == Phase::Open, "clicking a side face did not turn to it");
    settle(core);
    check(core.snapshot().frontWorkspace == 4, "the side face did not become the front");

    // The front face: choose it and close.
    check(click(router, core, 0.5, 0.5), "a click on the front face was not owned");
    settle(core);
    check(core.snapshot().phase == Phase::Closed && core.takeSelection() == 4, "clicking the front face did not go to it");
}

void testBackdropAndSlop() {
    PointerRouter router;
    auto core = openCube({1, 2, 3, 4, 5}, 3);
    check(click(router, core, 0.02, 0.02), "a click on the backdrop was not owned");
    settle(core);
    check(core.snapshot().phase == Phase::Closed && !core.takeSelection(), "the backdrop click must close without choosing");

    core = openCube({1, 2, 3, 4, 5}, 3);
    check(router.press(core, 0.5, 0.5), "press not owned");
    check(router.release(core, 0.7, 0.5), "the release of an owned press must be owned");
    check(core.snapshot().phase == Phase::Open && core.targetFront() == 3, "a drag counted as a click");
}

void testNotOwnedWhenNotOpen() {
    PointerRouter router;
    Core closed;
    closed.setWorkspaces({1, 2, 3});
    check(!router.press(closed, 0.5, 0.5) && !router.release(closed, 0.5, 0.5), "a closed cube took a click");
    check(!router.scroll(closed, 30, true, 1000), "a closed cube took a scroll");

    auto core = openCube({1, 2, 3}, 1);
    check(router.press(core, 0.5, 0.5), "press while open");
    core.reset(); // e.g. a monitor was lost between press and release
    check(router.release(core, 0.5, 0.5), "the release of an owned press must still be swallowed");
    check(!router.release(core, 0.5, 0.5), "a release with no press was owned");
    router.reset();
    check(!router.pressedNow(), "reset left a press pending");
}

void testScroll() {
    PointerRouter router;
    auto core = openCube({1, 2, 3}, 1);
    check(router.scroll(core, 15, true, 1000), "scroll not owned while open");
    check(core.targetFront() == 2, "a wheel notch did not turn one face");
    check(router.scroll(core, 15, true, 1010), "scroll not owned");
    check(core.targetFront() == 2, "two notches 10 ms apart turned twice");
    check(router.scroll(core, 15, true, 1200), "scroll not owned");
    check(core.targetFront() == 3, "the next notch after the pause did not turn");
    check(router.scroll(core, -15, true, 1400), "scroll not owned");
    check(core.targetFront() == 2, "scrolling back did not turn back");

    // Touchpad: many small deltas add up to one face.
    for (int i = 0; i < 5; ++i)
        router.scroll(core, 5, false, 2000 + 10U * static_cast<unsigned>(i));
    check(core.targetFront() == 2, "5 x 5 units must not yet turn on a touchpad (step 40)");
    for (int i = 0; i < 5; ++i)
        router.scroll(core, 5, false, 2300 + 10U * static_cast<unsigned>(i));
    check(core.targetFront() == 3, "a touchpad scroll of 50 units did not turn one face");
    check(!std::isnan(0.0) && router.scroll(core, std::nan(""), true, 3000), "a non-finite scroll must be swallowed");
}

// Each workspace holds one window that covers the middle 80 % of its picture; its id is 100 + the workspace.
std::optional<prism::WindowRect> oneWindow(prism::WorkspaceId workspace, double u, double v) {
    if (u < 0.1 || u > 0.9 || v < 0.1 || v > 0.9)
        return std::nullopt;
    return prism::WindowRect{static_cast<std::uint64_t>(100 + workspace), 0.1, 0.1, 0.8, 0.8};
}

// The centre of workspace `id` in the unfolded row, as output fractions.
prism::ProjectedPoint rowCentre(const Core& core, prism::WorkspaceId id) {
    const auto s = core.snapshot();
    for (const auto& f : prism::projectFaces(core.workspaces(), s.facePosition, s.openness, s.flatness))
        if (f.workspace == id)
            return f.point(0.5, 0.5);
    check(false, "workspace missing from the flat row");
    return {};
}

void testDragMovesAWindow() {
    PointerRouter router;
    router.setWindowFinder(oneWindow);
    auto core = openCube({1, 2, 3}, 1);

    check(router.press(core, 0.5, 0.5), "press on the window");
    check(!router.move(core, 0.505, 0.5), "a tiny wobble must not start a drag");
    check(!router.dragging(), "dragging started inside the slop");
    check(router.move(core, 0.55, 0.5) && router.dragging(), "moving past the slop did not start a drag");
    settle(core);
    check(core.snapshot().flatness == 1, "the cube did not unfold for the drag");
    check(core.targetFront() == 1, "unfolding changed the front face");

    const auto target = rowCentre(core, 3);
    check(router.move(core, target.x, target.y), "moving while dragging did not ask for a frame");
    const auto view = router.dragView();
    check(view && view->source == 1 && view->window.id == 101 && view->hover == 3, "the drag view does not name the source window and hovered workspace");
    check(router.release(core, target.x, target.y), "the release of a drag was not owned");
    const auto drop = router.takeDrop();
    check(drop && drop->window == 101 && drop->workspace == 3, "dropping on workspace 3 did not produce a move of window 101");
    check(!router.takeDrop(), "a drop was delivered twice");
    check(!router.dragging() && !router.dragView(), "the drag did not end");
    settle(core);
    check(core.snapshot().flatness == 0 && core.snapshot().phase == Phase::Open, "the cube did not fold back and stay open");
    check(core.targetFront() == 1, "a drop changed the workspace you are on");
}

void testDragCancels() {
    PointerRouter router;
    router.setWindowFinder(oneWindow);
    auto core = openCube({1, 2, 3}, 1);

    // Dropped on its own workspace: nothing to move.
    router.press(core, 0.5, 0.5);
    router.move(core, 0.55, 0.5);
    settle(core);
    const auto home = rowCentre(core, 1);
    router.move(core, home.x, home.y);
    check(router.release(core, home.x, home.y) && !router.takeDrop(), "dropping on the source workspace moved a window");

    // Dropped on the backdrop: nothing to move.
    router.press(core, 0.5, 0.5);
    router.move(core, 0.55, 0.5);
    settle(core);
    check(router.release(core, 0.01, 0.01) && !router.takeDrop(), "dropping on the backdrop moved a window");

    // Escape while dragging.
    settle(core);
    router.press(core, 0.5, 0.5);
    router.move(core, 0.55, 0.5);
    check(router.dragging(), "setup: dragging");
    check(router.cancelDrag(core) && !router.dragging(), "cancelDrag did not stop the drag");
    check(!router.cancelDrag(core), "cancelDrag with nothing to cancel claimed to cancel");
    settle(core);
    check(core.snapshot().flatness == 0, "cancel did not fold the cube");
    check(router.release(core, 0.55, 0.5) && !router.takeDrop(), "the release after a cancel produced a move");

    // The cube closes mid-drag (a key): the drag is dropped, nothing moves.
    router.press(core, 0.5, 0.5);
    router.move(core, 0.55, 0.5);
    core.close(false);
    router.move(core, 0.6, 0.5);
    check(!router.dragging(), "a drag survived the cube closing");
    check(router.release(core, 0.6, 0.5) && !router.takeDrop(), "closing mid-drag still moved a window");
    settle(core);

    // A press on empty space never becomes a drag, and a drag turns nothing by scrolling.
    core = openCube({1, 2, 3}, 1);
    router.press(core, 0.5, 0.05);
    check(!router.move(core, 0.6, 0.05) && !router.dragging(), "a press on empty space started a drag");
    router.release(core, 0.6, 0.05);
    router.press(core, 0.5, 0.5);
    router.move(core, 0.56, 0.5);
    check(router.scroll(core, 30, true, 5000) && core.targetFront() == 1, "scrolling while dragging turned the row");
    router.cancelDrag(core);
    router.release(core, 0.56, 0.5);
}

} // namespace

int main() {
    testDragMovesAWindow();
    testDragCancels();
    testClicks();
    testBackdropAndSlop();
    testNotOwnedWhenNotOpen();
    testScroll();
    std::cout << "pointer: side face, front face, backdrop, drag is not a click, not open, scroll, window drag and cancel passed\n";
}
