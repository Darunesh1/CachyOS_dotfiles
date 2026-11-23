#include "../swipe.hpp"

#include <cmath>
#include <cstdlib>
#include <iostream>

using prism::Core;
using prism::Phase;
using prism::SwipeRouter;

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

Core openCube() {
    Core core;
    core.setWorkspaces({2, 11, 7});
    check(core.open(2), "open rejected");
    settle(core);
    check(core.snapshot().phase == Phase::Open, "cube did not open");
    return core;
}

// A swipe as Hyprland delivers it: begin, several updates, end.
bool swipe(SwipeRouter& router, Core& core, double dx, double dy, bool cancelled = false, int steps = 12) {
    const bool owned = router.begin(core, 3);
    bool allOwned = owned;
    for (int i = 0; i < steps; ++i)
        allOwned = router.update(core, dx / steps, dy / steps, 0.05) == owned && allOwned;
    const bool endOwned = router.end(core, cancelled);
    check(endOwned == owned, "an owned swipe was not owned from begin to end");
    check(allOwned, "an owned swipe leaked an update");
    return owned;
}

void testNotOwnedUnlessOpenAndThreeFingers() {
    SwipeRouter router;
    Core closed;
    closed.setWorkspaces({2, 11, 7});
    check(!router.begin(closed, 3), "closed cube took a swipe");
    check(!router.update(closed, 5, 0, 0.016) && !router.end(closed, false), "a swipe that was not owned was owned later");

    auto core = openCube();
    check(!router.begin(core, 4), "4 fingers were taken");
    check(!router.update(core, 50, 0, 0.016) && !router.end(core, false), "4-finger swipe leaked into ownership");
    check(!router.begin(core, 2), "2 fingers were taken");
    router.end(core, false);

    check(core.begin(prism::Direction::Down, 2), "setup: closing swipe");
    check(core.snapshot().phase == Phase::Closing && !router.begin(core, 3), "a closing cube took a swipe");
    core.finish(true);
    settle(core);

    core.reset();
    check(!router.begin(core, 3), "a reset (closed) cube took a swipe");
}

void testSidewaysTurnsTheCube() {
    SwipeRouter router;
    auto core = openCube();
    check(core.snapshot().frontWorkspace == 2, "setup: front face");
    check(swipe(router, core, -300, 10), "open cube did not own a sideways swipe");
    settle(core);
    check(core.snapshot().phase == Phase::Open && core.snapshot().openness == 1, "turning changed openness");
    check(core.snapshot().frontWorkspace == 11, "swipe did not turn the cube to the next face");

    check(swipe(router, core, 300, -10), "second sideways swipe was not owned");
    settle(core);
    check(core.snapshot().frontWorkspace == 2, "opposite swipe did not turn back");

    check(swipe(router, core, -400, 0, true), "cancelled swipe was not owned");
    settle(core);
    check(core.snapshot().frontWorkspace == 2, "cancelled turn moved the cube");
    check(!core.takeSelection(), "turning selected a workspace");
}

void testDownClosesAndUpDoesNothing() {
    SwipeRouter router;
    auto core = openCube();
    check(swipe(router, core, 5, -300), "upward swipe was not swallowed");
    settle(core);
    check(core.snapshot().phase == Phase::Open && core.snapshot().frontWorkspace == 2, "upward swipe changed an open cube");

    check(swipe(router, core, 0, 300), "downward swipe was not owned");
    settle(core);
    check(core.snapshot().phase == Phase::Closed, "downward swipe did not close the cube");
    check(core.takeSelection() == 2, "closing did not select the front workspace");
}

void testTinySwipeAndStateHygiene() {
    SwipeRouter router;
    auto core = openCube();
    check(swipe(router, core, 3, 2), "tiny swipe was not owned");
    settle(core);
    check(core.snapshot().phase == Phase::Open && core.snapshot().frontWorkspace == 2, "tiny swipe moved the cube");

    check(router.begin(core, 3), "begin");
    router.update(core, 100, 0, 0.016);
    core.reset(); // the plugin resets the core (monitor lost, lock)
    router.reset();
    check(!router.owning(), "reset did not clear ownership");
    check(!router.update(core, 100, 0, 0.016) && !router.end(core, false), "stale ownership survived a reset");

    // Non-finite events are swallowed, never forwarded.
    auto open = openCube();
    check(router.begin(open, 3), "begin before nan");
    check(router.update(open, std::nan(""), 0, 0.016), "malformed event leaked");
    router.end(open, true);
    check(open.snapshot().phase == Phase::Open, "malformed event changed the cube");
}

} // namespace

int main() {
    testNotOwnedUnlessOpenAndThreeFingers();
    testSidewaysTurnsTheCube();
    testDownClosesAndUpDoesNothing();
    testTinySwipeAndStateHygiene();
    std::cout << "swipe: ownership, sideways turn, close, up ignored, cancel, reset, malformed events passed\n";
}
