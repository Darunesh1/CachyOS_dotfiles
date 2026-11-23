#pragma once

#include "core.hpp"

#include <hyprutils/memory/SharedPtr.hpp>

#include <algorithm>
#include <cstdint>
#include <cmath>
#include <numbers>
#include <span>

namespace Render {
class CRenderContext;
class ITexture;
}

namespace prism {

struct RenderDiagnostics {
    std::uint64_t stage = 0;
    std::uint64_t attempted = 0;
    std::uint64_t candidates = 0;
    std::uint64_t ready = 0;
    std::uint64_t enqueued = 0;
    std::uint64_t drawn = 0;
};

void noteRenderStage() noexcept;
[[nodiscard]] RenderDiagnostics renderDiagnostics() noexcept;

struct ProjectedPoint {
    double x, y; // Monitor coordinates normalized to the interval [0, 1].
};

struct ProjectedFace {
    WorkspaceId workspace;
    double centerX, centerZ, cosine, sine, camera;
    double width, height; // Fractions of the output width and height.

    // World x and z are in output-width units. The camera looks straight down -z.
    [[nodiscard]] ProjectedPoint point(double u, double v) const {
        const double localX = (u - 0.5) * width;
        const double w = 1 - (centerZ - localX * sine) / camera;
        return {0.5 + (centerX + localX * cosine) / w, 0.5 + (v - 0.5) * height / w};
    }
};

// Fraction of the output (width and height alike, so the screen's shape is kept)
// the front face fills when fully open. Fewer workspaces get bigger faces. These
// numbers are a starting guess, to be tuned by looking at it on the real screen.
[[nodiscard]] inline double openFaceFraction(std::size_t workspaceCount) {
    const double extra = workspaceCount > 2 ? static_cast<double>(workspaceCount - 2) : 0.0;
    return std::clamp(0.72 - 0.035 * extra, 0.58, 0.72);
}

// Keep projection independent of compositor objects so geometry can be replayed
// without a GL context. Results are sorted back to front for painter's order.
inline std::vector<ProjectedFace> projectFaces(std::span<const WorkspaceId> workspaces,
                                               double position, double openness) {
    std::vector<ProjectedFace> visible;
    if (workspaces.empty() || !std::isfinite(position) || !std::isfinite(openness))
        return visible;

    openness = std::clamp(openness, 0.0, 1.0);
    const double size = 1 - (1 - openFaceFraction(workspaces.size())) * openness;
    const double pitch = size + 0.008 * openness;
    const auto count = workspaces.size();
    // Two opposite planes disappear edge-on halfway through a turn. Put each
    // workspace on a pair of opposite faces of a four-sided drum instead.
    const auto sides = count == 2 ? 4UL : count;
    const double fullStep = 2 * std::numbers::pi / std::max<std::size_t>(3, sides);
    const double step = fullStep * openness;
    const double camera = std::max(1.5 * pitch, 3.2 * pitch / (2 * std::tan(fullStep / 2)));

    for (std::size_t i = 0; i < sides; ++i) {
        const double offset = std::remainder(i - position, static_cast<double>(sides));
        const double angle = offset * step;
        const double cosine = std::cos(angle);
        const double sine = std::sin(angle);
        const double radius = step > 1e-8 ? pitch / (2 * std::tan(step / 2)) : 0.0;
        const double centerX = radius ? radius * sine : offset * pitch;
        // This form of cos(angle) - 1 remains accurate near the flat-row limit.
        const double halfSine = std::sin(angle / 2);
        const double centerZ = -2 * radius * halfSine * halfSine;

        ProjectedFace face{workspaces[i % count], centerX, centerZ, cosine, sine, camera, size, size};
        const auto left = face.point(0, 0);
        const auto right = face.point(1, 0);
        if (right.x <= left.x || right.x <= 0 || left.x >= 1)
            continue;
        visible.push_back(face);
    }

    std::ranges::sort(visible, {}, &ProjectedFace::centerZ);
    return visible;
}

struct FaceTexture {
    WorkspaceId workspace;
    Hyprutils::Memory::CSharedPointer<Render::ITexture> texture;
};

class FaceRenderer {
public:
    // The caller lends upright, normal-transform compositor-owned preview
    // textures. The pass takes a strong ref to each visible texture. Client
    // surface buffers require compositor synchronization before becoming previews.
    void enqueue(Render::CRenderContext& ctx, const Snapshot& state,
                 std::span<const WorkspaceId> workspaces, std::span<const FaceTexture> textures = {});
    void reset();

private:
    Hyprutils::Memory::CSharedPointer<Render::ITexture> pane_;
};

} // namespace prism
