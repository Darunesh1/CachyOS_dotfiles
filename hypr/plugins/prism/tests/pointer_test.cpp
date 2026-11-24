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

} // namespace

int main() {
    testClicks();
    testBackdropAndSlop();
    testNotOwnedWhenNotOpen();
    testScroll();
    std::cout << "pointer: side face, front face, backdrop, drag is not a click, not open, scroll passed\n";
}
