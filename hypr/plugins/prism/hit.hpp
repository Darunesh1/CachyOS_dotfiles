#pragma once

#include "render.hpp"

#include <cmath>
#include <optional>
#include <span>

namespace prism {

// Where on a face a point of the output lies: u and v run 0 to 1 across the face's width and
// height, like the texture coordinates it is drawn with.
struct FaceUV {
    double u, v;
};

// The inverse of ProjectedFace::point. Pure geometry, so it can be tested without a
// compositor. `x` and `y` are the output coordinates normalised to [0, 1]. Returns nothing
// when the point is outside the face's quad or the face is turned away or edge-on.
[[nodiscard]] inline std::optional<FaceUV> faceUV(const ProjectedFace& face, double x, double y) {
    const double a = x - 0.5;
    const double k = 1 - face.centerZ / face.camera;
    // a * w = centerX + lx * cosine, with w = k + lx * sine / camera, solved for lx:
    const double denominator = a * face.sine / face.camera - face.cosine;
    if (std::abs(denominator) < 1e-9 || face.width <= 0 || face.height <= 0)
        return std::nullopt;
    const double lx = (face.centerX - a * k) / denominator;
    const double w = k + lx * face.sine / face.camera;
    if (!std::isfinite(lx) || !std::isfinite(w) || w <= 1e-9)
        return std::nullopt;
    const double u = lx / face.width + 0.5;
    const double v = 0.5 + (y - 0.5) * w / face.height;
    if (u < 0 || u > 1 || v < 0 || v > 1)
        return std::nullopt;
    return FaceUV{u, v};
}

struct Hit {
    WorkspaceId workspace;
    FaceUV uv;
    bool front; // the face that is turned to the viewer: the one a click opens
};

// The face under a point, nearest to the viewer first (the faces are drawn back to front, so
// the last one drawn is on top). Nothing means the backdrop.
[[nodiscard]] inline std::optional<Hit> hitTest(std::span<const WorkspaceId> workspaces, double position,
                                                 double openness, double x, double y, double flatness = 0) {
    const auto faces = projectFaces(workspaces, position, openness, flatness);
    for (auto it = faces.rbegin(); it != faces.rend(); ++it) {
        if (const auto uv = faceUV(*it, x, y))
            return Hit{it->workspace, *uv, it == faces.rbegin()};
    }
    return std::nullopt;
}

} // namespace prism
