#include "core.hpp"

#include <algorithm>
#include <cmath>
#include <utility>

namespace prism {
namespace {

constexpr double swipeDistance = 300;
constexpr double faceDistance = 300;
constexpr double commitDistance = 1.0 / 3;
constexpr double velocityTime = 0.045;
constexpr double maxGestureVelocity = 4000;

double faceCenter(double position) {
    return std::floor(position + 0.5);
}

std::optional<WorkspaceId> workspaceAt(const std::vector<WorkspaceId>& workspaces, double position) {
    if (workspaces.empty())
        return std::nullopt;

    const auto count = static_cast<double>(workspaces.size());
    const auto wrapped = std::fmod(faceCenter(position), count);
    return workspaces[static_cast<std::size_t>(wrapped < 0 ? wrapped + count : wrapped)];
}

std::optional<double> positionOf(const std::vector<WorkspaceId>& workspaces, std::optional<WorkspaceId> workspace) {
    if (!workspace)
        return std::nullopt;

    const auto it = std::ranges::find(workspaces, *workspace);
    if (it == workspaces.end())
        return std::nullopt;

    return static_cast<double>(it - workspaces.begin());
}

double nearestPosition(double position, double reference, std::size_t count) {
    const auto period = static_cast<double>(count);
    return position + period * std::round((reference - position) / period);
}

void spring(double& position, double& velocity, double target, double rate, double dt) {
    if (position == target && velocity == 0)
        return;

    // Analytic critically damped spring. Splitting a frame interval gives the
    // same trajectory, and a paused frame does not need catch-up iterations.
    const auto elapsed = std::min(dt, 1.0);
    const auto offset = position - target;
    const auto slope = velocity + rate * offset;
    const auto decay = std::exp(-rate * elapsed);
    const auto nextOffset = (offset + slope * elapsed) * decay;
    velocity = (velocity - rate * slope * elapsed) * decay;
    position = target + nextOffset;

    if (std::abs(nextOffset) < 0.0005 && std::abs(velocity) < 0.01) {
        position = target;
        velocity = 0;
    }
}

} // namespace

void Core::setWorkspaces(std::vector<WorkspaceId> workspaces) {
    if (workspaces == workspaces_)
        return;

    // Keep the caller's face order and use each workspace identity once.
    for (auto it = workspaces.begin(); it != workspaces.end(); ++it)
        workspaces.erase(std::remove(it + 1, workspaces.end(), *it), workspaces.end());

    if (workspaces == workspaces_)
        return;

    if (workspaces.empty()) {
        workspaces_.clear();
        reset();
        return;
    }

    const auto front = workspaceAt(workspaces_, facePosition_);
    const auto frontPosition = positionOf(workspaces, front).value_or(
        positionOf(workspaces, originWorkspace_).value_or(0));
    const auto mapPosition = [&](double previous) {
        const auto workspace = workspaceAt(workspaces_, previous);
        const auto position = positionOf(workspaces, workspace).value_or(frontPosition);
        return nearestPosition(position, previous, workspaces.size());
    };

    const auto faceOffset = facePosition_ - faceCenter(facePosition_);
    facePosition_ = mapPosition(facePosition_) + faceOffset;
    targetFacePosition_ = mapPosition(targetFacePosition_);
    if (originWorkspace_ && !positionOf(workspaces, originWorkspace_))
        originWorkspace_ = workspaces[static_cast<std::size_t>(frontPosition)];
    if (!positionOf(workspaces, pendingSelection_))
        pendingSelection_.reset();
    if (!positionOf(workspaces, selection_))
        selection_.reset();
    if (gesture_) {
        gesture_->startFacePosition = mapPosition(gesture_->startFacePosition);
        gesture_->returnFacePosition = mapPosition(gesture_->returnFacePosition);
        if (!positionOf(workspaces, gesture_->returnSelection))
            gesture_->returnSelection.reset();
    }
    workspaces_ = std::move(workspaces);

    if (workspaces_.size() == 1) {
        facePosition_ = targetFacePosition_;
        faceVelocity_ = 0;
    }
}

const std::vector<WorkspaceId>& Core::workspaces() const {
    return workspaces_;
}

bool Core::startFromWorkspace(WorkspaceId current) {
    const auto position = positionOf(workspaces_, current);
    if (!position)
        return false;

    originWorkspace_ = current;
    facePosition_ = targetFacePosition_ = *position;
    faceVelocity_ = 0;
    selection_.reset();
    return true;
}

bool Core::begin(Direction direction, WorkspaceId current) {
    const auto currentPhase = phase();
    if (direction == Direction::Horizontal) {
        if (currentPhase != Phase::Open || workspaces_.size() < 2)
            return false;
    } else if (currentPhase == Phase::Closed) {
        if (direction != Direction::Up || !startFromWorkspace(current))
            return false;
    } else if (currentPhase == Phase::Open && direction == Direction::Up) {
        return false;
    }

    const auto returnOpen = gesture_ ? gesture_->returnOpen : targetOpen_;
    const auto returnFace = gesture_ ? gesture_->returnFacePosition : targetFacePosition_;
    const auto returnSelection = gesture_ ? gesture_->returnSelection : pendingSelection_;
    gesture_ = Gesture{direction, returnOpen, facePosition_, returnFace, returnSelection};
    pendingSelection_.reset();
    opennessVelocity_ = 0;
    faceVelocity_ = 0;
    if (direction == Direction::Down)
        targetFacePosition_ = faceCenter(facePosition_);
    return true;
}

void Core::update(double dx, double dy, double dtSeconds) {
    if (!gesture_)
        return;

    const auto horizontal = gesture_->direction == Direction::Horizontal;
    const auto delta = horizontal ? -dx : -dy;
    if (!std::isfinite(delta))
        return;

    // A single user event cannot usefully go farther than a full turn of the
    // prism. Bound malformed events before accumulating position and velocity.
    const auto maxDelta = horizontal ? faceDistance * static_cast<double>(workspaces_.size()) : swipeDistance;
    const auto movement = std::clamp(delta, -maxDelta, maxDelta);
    gesture_->distance += movement;
    if (std::isfinite(dtSeconds) && dtSeconds > 0) {
        const auto sample = std::clamp(movement / dtSeconds, -maxGestureVelocity, maxGestureVelocity);
        const auto weight = -std::expm1(-dtSeconds / velocityTime);
        gesture_->velocity += weight * (sample - gesture_->velocity);
    }

    if (horizontal) {
        if (workspaces_.size() > 1)
            facePosition_ += movement / faceDistance;
    } else {
        openness_ = std::clamp(openness_ + movement / swipeDistance, 0.0, 1.0);
    }
}

void Core::finish(bool cancelled, std::optional<double> releaseVelocity) {
    if (!gesture_)
        return;

    const auto gesture = *gesture_;
    const auto velocity = releaseVelocity && std::isfinite(*releaseVelocity)
        ? std::clamp(-*releaseVelocity, -maxGestureVelocity, maxGestureVelocity)
        : gesture.velocity;

    if (cancelled || gesture.distance == 0) {
        targetFacePosition_ = gesture.returnFacePosition;
        settle(gesture.returnOpen, gesture.returnSelection, 0);
        return;
    }

    if (gesture.direction == Direction::Horizontal) {
        if (workspaces_.size() > 1) {
            const auto projected = std::clamp(0.14 * velocity / faceDistance, -1.5, 1.5);
            targetFacePosition_ = faceCenter(facePosition_ + projected);

            // A deliberate short swipe should advance at least one face when
            // projection leaves it on the same face as the starting position.
            const auto startFace = faceCenter(gesture.startFacePosition);
            if (targetFacePosition_ == startFace && std::abs(gesture.distance) >= 18)
                targetFacePosition_ += std::copysign(1.0, gesture.distance);
            faceVelocity_ = velocity / faceDistance;
        }
        settle(true, std::nullopt, 0);
        return;
    }

    const auto opennessSpeed = velocity / swipeDistance;
    const auto projected = openness_ + std::clamp(0.12 * opennessSpeed, -0.25, 0.25);
    if (gesture.direction == Direction::Up) {
        settle(projected >= commitDistance, gesture.returnSelection, opennessSpeed);
    } else if (projected > 1 - commitDistance) {
        targetFacePosition_ = gesture.returnFacePosition;
        settle(true, std::nullopt, opennessSpeed);
    } else {
        settle(false, workspaceAt(workspaces_, targetFacePosition_), opennessSpeed);
    }
}

bool Core::open(WorkspaceId current) {
    if (phase() == Phase::Open)
        return false;
    if (phase() == Phase::Closed && !startFromWorkspace(current))
        return false;

    settle(true, std::nullopt, 0);
    return true;
}

bool Core::close(bool selectFront) {
    if (phase() == Phase::Closed)
        return false;

    // A turn still settling (Right, then Enter at once) counts: choose where the cube is
    // GOING, not where it is this frame. A finger still holding it uses the live position.
    const auto front = workspaceAt(workspaces_, gesture_ ? facePosition_ : targetFacePosition_);
    const auto workspace = selectFront ? front : originWorkspace_;
    const auto position = positionOf(workspaces_, workspace).value_or(faceCenter(facePosition_));
    targetFacePosition_ = nearestPosition(position, facePosition_, workspaces_.size());
    settle(false, selectFront ? front : std::nullopt, 0);
    return true;
}

bool Core::rotate(int faceDelta) {
    if (phase() != Phase::Open || workspaces_.size() < 2 || faceDelta == 0)
        return false;

    if (gesture_) {
        targetFacePosition_ = faceCenter(facePosition_);
        gesture_.reset();
    }
    targetFacePosition_ += faceDelta;
    return true;
}

void Core::reset() {
    gesture_.reset();
    originWorkspace_.reset();
    pendingSelection_.reset();
    selection_.reset();
    targetOpen_ = false;
    openness_ = opennessVelocity_ = 0;
    facePosition_ = targetFacePosition_ = faceVelocity_ = 0;
}

void Core::tick(double dtSeconds) {
    if (!std::isfinite(dtSeconds) || dtSeconds <= 0)
        return;

    if (!gesture_) {
        spring(openness_, opennessVelocity_, targetOpen_ ? 1 : 0, 26, dtSeconds);
        if (openness_ < 0 || openness_ > 1) {
            openness_ = std::clamp(openness_, 0.0, 1.0);
            opennessVelocity_ = 0;
        }
    }
    if (!gesture_ || gesture_->direction != Direction::Horizontal)
        spring(facePosition_, faceVelocity_, targetFacePosition_, 24, dtSeconds);

    completeClose();
}

Snapshot Core::snapshot() const {
    const auto currentPhase = phase();
    const auto opennessAnimating = !gesture_ && (currentPhase == Phase::Opening || currentPhase == Phase::Closing);
    const auto faceAnimating = (!gesture_ || gesture_->direction != Direction::Horizontal) &&
        (facePosition_ != targetFacePosition_ || faceVelocity_ != 0);
    return {currentPhase, openness_, facePosition_, workspaceAt(workspaces_, facePosition_), originWorkspace_,
        opennessAnimating || faceAnimating};
}

std::optional<WorkspaceId> Core::takeSelection() {
    return std::exchange(selection_, std::nullopt);
}

Phase Core::phase() const {
    if (gesture_) {
        if (gesture_->direction == Direction::Up)
            return Phase::Opening;
        if (gesture_->direction == Direction::Down)
            return Phase::Closing;
    }
    if (targetOpen_)
        return openness_ == 1 ? Phase::Open : Phase::Opening;
    return openness_ == 0 && facePosition_ == targetFacePosition_ && faceVelocity_ == 0 ? Phase::Closed : Phase::Closing;
}

void Core::settle(bool open, std::optional<WorkspaceId> selection, double velocity) {
    gesture_.reset();
    targetOpen_ = open;
    opennessVelocity_ = openness_ == (open ? 1 : 0) ? 0 : velocity;
    pendingSelection_ = open ? std::nullopt : selection;
    completeClose();
}

void Core::completeClose() {
    if (phase() == Phase::Closed && pendingSelection_)
        selection_ = std::exchange(pendingSelection_, std::nullopt);
}

} // namespace prism
