#pragma once

#include <cstdint>
#include <optional>
#include <vector>

namespace prism {

using WorkspaceId = std::int64_t;

enum class Direction { Up, Down, Horizontal };
enum class Phase { Closed, Opening, Open, Closing };

struct Snapshot {
    Phase phase;
    double openness;
    double facePosition;
    std::optional<WorkspaceId> frontWorkspace;
    std::optional<WorkspaceId> originWorkspace;
    bool animating;
};

class Core {
public:
    void setWorkspaces(std::vector<WorkspaceId> workspaces);
    [[nodiscard]] const std::vector<WorkspaceId>& workspaces() const;

    // Deltas are in gesture units, with right and down positive. Release velocity
    // uses the same sign, in units per second along the gesture's axis.
    bool begin(Direction direction, WorkspaceId current);
    void update(double dx, double dy, double dtSeconds);
    void finish(bool cancelled, std::optional<double> releaseVelocity = std::nullopt);

    bool open(WorkspaceId current);
    bool close(bool selectFront);
    bool rotate(int faceDelta);
    void reset();

    void tick(double dtSeconds);
    [[nodiscard]] Snapshot snapshot() const;
    // A committed close delivers its workspace once, after the animation ends.
    [[nodiscard]] std::optional<WorkspaceId> takeSelection();

private:
    struct Gesture {
        Direction direction;
        bool returnOpen;
        double startFacePosition;
        double returnFacePosition;
        std::optional<WorkspaceId> returnSelection;
        double distance = 0;
        double velocity = 0;
    };

    [[nodiscard]] Phase phase() const;
    bool startFromWorkspace(WorkspaceId current);
    void settle(bool open, std::optional<WorkspaceId> selection, double velocity);
    void completeClose();

    std::vector<WorkspaceId> workspaces_;
    std::optional<Gesture> gesture_;
    std::optional<WorkspaceId> originWorkspace_;
    std::optional<WorkspaceId> pendingSelection_;
    std::optional<WorkspaceId> selection_;
    bool targetOpen_ = false;
    double openness_ = 0;
    double opennessVelocity_ = 0;
    double facePosition_ = 0;
    double targetFacePosition_ = 0;
    double faceVelocity_ = 0;
};

} // namespace prism
