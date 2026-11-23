#include "../core.hpp"

#include <cmath>
#include <cstdlib>
#include <iostream>
#include <limits>

using prism::Core;
using prism::Direction;
using prism::Phase;

namespace {

void check(bool condition, const char* message) {
    if (!condition) {
        std::cerr << message << '\n';
        std::exit(EXIT_FAILURE);
    }
}

bool near(double actual, double expected) {
    return std::abs(actual - expected) < 0.000001;
}

void settle(Core& core) {
    for (int frame = 0; core.snapshot().animating && frame < 120; ++frame)
        core.tick(1.0 / 120);
    check(!core.snapshot().animating, "spring did not settle within one second");
}

Core openOverview() {
    Core core;
    core.setWorkspaces({2, 11, 7});
    check(core.open(2), "dispatcher open rejected the current workspace");
    settle(core);
    check(core.snapshot().phase == Phase::Open, "dispatcher did not open the overview");
    return core;
}

void testVerticalTrackingAndCommit() {
    Core core;
    core.setWorkspaces({2, 11, 7});
    check(!core.begin(Direction::Down, 11), "closed overview intercepted a down swipe");
    check(!core.begin(Direction::Horizontal, 11), "closed overview intercepted a horizontal swipe");
    check(!core.begin(Direction::Up, 50), "opened for a workspace absent from the face list");
    check(core.begin(Direction::Up, 11), "closed overview rejected an up swipe");
    check(core.snapshot().frontWorkspace == 11, "gesture did not start on current workspace identity");

    core.update(900, -120, 0.10);
    check(near(core.snapshot().openness, 0.4), "opening did not follow the vertical delta on the first frame");
    check(near(core.snapshot().facePosition, 1), "opening gesture drifted sideways");
    core.tick(0.1);
    check(near(core.snapshot().openness, 0.4), "opening animated independently of held fingers");
    core.update(0, 30, 0.10);
    check(near(core.snapshot().openness, 0.3), "opening did not reverse with the fingers");
    core.finish(false, 0);
    settle(core);
    check(core.snapshot().phase == Phase::Closed && !core.takeSelection(), "short opening did not return to the desktop");

    core.begin(Direction::Up, 11);
    core.update(0, -40, 0.03);
    core.finish(false);
    settle(core);
    check(core.snapshot().openness == 1, "quick opening flick did not commit using observed velocity");

    core.begin(Direction::Down, 11);
    core.update(0, 90, 0.10);
    check(near(core.snapshot().openness, 0.7), "closing did not follow the vertical delta");
    core.finish(false, 0);
    settle(core);
    check(core.snapshot().phase == Phase::Open && !core.takeSelection(), "short close selected a workspace");
}

void testRotationAndSelection() {
    auto core = openOverview();
    check(core.begin(Direction::Horizontal, 2), "open overview rejected horizontal rotation");
    core.update(180, 800, 0.10);
    check(near(core.snapshot().facePosition, -0.6), "rotation did not follow horizontal delta continuously across the seam");
    check(core.snapshot().openness == 1 && core.snapshot().frontWorkspace == 7, "horizontal swipe changed openness or wrapped to the wrong workspace");
    core.finish(false, 0);
    settle(core);
    check(core.snapshot().facePosition == -1, "rotation did not settle on the adjacent face");

    core.begin(Direction::Horizontal, 2);
    core.update(0, 0, 0.20);
    core.update(30, 0, 0.15);
    core.finish(false, 0);
    settle(core);
    check(core.snapshot().frontWorkspace == 11, "deliberate short swipe did not turn one face");

    core.begin(Direction::Horizontal, 2);
    core.update(480, 0, 0.10);
    core.finish(true);
    settle(core);
    check(core.snapshot().frontWorkspace == 11 && core.snapshot().facePosition == -2, "cancelled rotation did not return to its starting face");

    core.begin(Direction::Down, 2);
    core.update(0, 140, 0.12);
    core.finish(false, 0);
    check(!core.takeSelection(), "committed selection arrived before close finished");
    settle(core);
    check(core.snapshot().phase == Phase::Closed && core.takeSelection() == 11, "committed close did not select the front workspace by identity");
    check(!core.takeSelection(), "selection was delivered twice");
}

void testInterruptionAndCancel() {
    Core core;
    core.setWorkspaces({2, 11, 7});
    core.begin(Direction::Up, 2);
    core.update(0, -160, 0.12);
    core.finish(false, 0);
    core.tick(0.04);
    const auto opening = core.snapshot().openness;
    check(core.begin(Direction::Down, 2), "could not interrupt an opening spring");
    check(core.snapshot().openness == opening, "starting a reverse swipe jumped the visible position");
    core.update(0, 90, 0.1);
    check(near(core.snapshot().openness, opening - 0.3), "reverse swipe did not start from the visible position");
    core.finish(true);
    settle(core);
    check(core.snapshot().phase == Phase::Open && !core.takeSelection(), "cancelled reversal did not resume opening");

    core.rotate(1);
    settle(core);
    core.close(true);
    core.tick(0.03);
    const auto closing = core.snapshot().openness;
    check(core.begin(Direction::Up, 2), "could not interrupt a closing spring");
    check(core.snapshot().openness == closing, "interrupted close jumped the visible position");
    core.update(0, -35, 0.10);
    core.finish(true);
    settle(core);
    check(core.takeSelection() == 11, "cancelled reversal lost the previous close selection");

    core.open(2);
    settle(core);
    core.rotate(1);
    settle(core);
    core.close(true);
    core.tick(0.03);
    core.begin(Direction::Up, 2);
    core.update(0, -60, 0.10);
    core.finish(false, 0);
    settle(core);
    check(core.snapshot().phase == Phase::Open && !core.takeSelection(), "completed reversal did not cancel the pending workspace switch");
    core.close(false);
    settle(core);
    check(core.snapshot().frontWorkspace == 2 && !core.takeSelection(), "dispatcher cancellation did not return to original workspace without switching");
}

void testCloseChoosesWhereTheTurnIsGoing() {
    auto core = openOverview();
    check(core.snapshot().frontWorkspace == 2, "fixture does not start on workspace 2");
    core.rotate(1);
    // No tick: the cube has not moved yet, but the user already pressed Enter.
    check(core.snapshot().frontWorkspace == 2, "the turn moved before any frame");
    core.close(true);
    settle(core);
    check(core.takeSelection() == 11, "Right then Enter chose the old face instead of the one turned to");
}

void testWorkspaceChangesAndFlatTiming() {
    auto core = openOverview();
    core.rotate(1);
    settle(core);
    core.setWorkspaces({7, 2, 11, 2, 5});
    check(core.workspaces().size() == 4 && core.snapshot().frontWorkspace == 11, "workspace reorder did not preserve front identity and deduplicate faces");
    core.close(true);
    core.setWorkspaces({7, 2, 5});
    settle(core);
    check(!core.takeSelection(), "removed workspace was delivered as a close selection");

    core.open(2);
    core.setWorkspaces({});
    check(core.snapshot().phase == Phase::Closed && !core.snapshot().frontWorkspace, "empty workspace list did not reset the overview");
    core.setWorkspaces({2});
    core.open(2);
    settle(core);
    check(!core.rotate(1) && !core.begin(Direction::Horizontal, 2), "one workspace accepted a meaningless turn");
    core.begin(Direction::Down, 2);
    core.update(0, std::numeric_limits<double>::infinity(), 0.10);
    check(core.snapshot().openness == 1, "nonfinite gesture delta changed openness");
    core.update(0, 300, 0.10);
    core.finish(false, 0);
    check(core.snapshot().phase == Phase::Closed && core.takeSelection() == 2, "full-distance close required another frame to select the workspace");

    Core oneTick;
    oneTick.setWorkspaces({2});
    oneTick.open(2);
    auto manyTicks = oneTick;
    oneTick.tick(0.1);
    for (int frame = 0; frame < 12; ++frame)
        manyTicks.tick(0.1 / 12);
    check(near(oneTick.snapshot().openness, manyTicks.snapshot().openness), "spring changed trajectory with different frame intervals");
}

} // namespace

int main() {
    testVerticalTrackingAndCommit();
    testRotationAndSelection();
    testInterruptionAndCancel();
    testCloseChoosesWhereTheTurnIsGoing();
    testWorkspaceChangesAndFlatTiming();
    std::cout << "Prism core tests passed\n";
}
