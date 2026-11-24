#pragma once

#include "core.hpp"

#include <hyprutils/memory/SharedPtr.hpp>

#include <algorithm>
#include <cstdint>
#include <cmath>
#include <numbers>
#include <optional>
#include <span>
#include <string>
#include <unordered_map>

namespace Render {
class CRenderContext;
class ITexture;
}

namespace prism {

// full: wallpaper backdrop, sharp pictures. lite: plain gradient and small pictures, for
// Power Saving and Game Mode (see hypr/config/prism_native.lua, setQuality).
enum class Quality { Full, Lite };

// How much of the output a captured workspace picture covers on each axis when drawn at
// its largest, and the capture scale each tier uses. Full is sharp enough to read text on
// the front face at 1920x1080 (the front face is about 70 % of the screen wide).
[[nodiscard]] constexpr double captureScale(Quality quality) {
    return quality == Quality::Full ? 0.75 : 0.4;
}

struct RenderDiagnostics {
    std::uint64_t stage = 0;
    std::uint64_t attempted = 0;
    std::uint64_t candidates = 0;
    std::uint64_t ready = 0;
    std::uint64_t enqueued = 0;
    std::uint64_t drawn = 0;
    std::uint64_t backdrop = 0; // 1 when the wallpaper texture is loaded
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
//
// `flatness` 0 is the cube; 1 is a flat row of every workspace, small enough to fit the
// screen, used while a window is dragged so each workspace is a drop target.
inline std::vector<ProjectedFace> projectFaces(std::span<const WorkspaceId> workspaces,
                                               double position, double openness, double flatness = 0) {
    std::vector<ProjectedFace> visible;
    if (workspaces.empty() || !std::isfinite(position) || !std::isfinite(openness) || !std::isfinite(flatness))
        return visible;

    openness = std::clamp(openness, 0.0, 1.0);
    flatness = std::clamp(flatness, 0.0, 1.0);
    const auto count = workspaces.size();
    const double openSize = openFaceFraction(count);
    // Every face on screen at once: n faces and their n - 1 gaps (0.028 each, see `pitch`)
    // fit in 92 % of the width.
    const double flatSize = std::clamp(
        (0.92 - 0.028 * static_cast<double>(count - 1)) / static_cast<double>(count), 0.05, openSize);
    const double faceSize = openSize + (flatSize - openSize) * flatness;
    const double size = 1 - (1 - faceSize) * openness;
    const double pitch = size + (0.008 + 0.02 * flatness) * openness;
    // Two opposite planes disappear edge-on halfway through a turn. Put each
    // workspace on a pair of opposite faces of a four-sided drum instead.
    const auto sides = count == 2 && flatness == 0 ? 4UL : count;
    const double fullStep = 2 * std::numbers::pi / std::max<std::size_t>(3, sides);
    const double step = fullStep * openness * (1 - flatness);
    const double camera = std::max(1.5 * pitch, 3.2 * pitch / (2 * std::tan(fullStep / 2)));

    for (std::size_t i = 0; i < sides; ++i) {
        // A flat row has no duplicate faces; the two-workspace drum has two of each.
        if (flatness > 0 && i >= count)
            continue;
        const double offset = std::remainder(static_cast<double>(i) - position, static_cast<double>(sides));
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

// A window's place in its workspace picture, as fractions of the picture (0 to 1 each way), and
// an id that is the compositor's window address.
struct WindowRect {
    std::uint64_t id = 0;
    double x = 0, y = 0, w = 0, h = 0;
};

// A window being dragged, for the renderer: where it came from, where the cursor is (output
// fractions), and which other workspace is under it.
struct DragView {
    WorkspaceId source = 0;
    WindowRect window;
    double x = 0, y = 0;
    std::optional<WorkspaceId> hover;
};

struct FaceTexture {
    WorkspaceId workspace;
    Hyprutils::Memory::CSharedPointer<Render::ITexture> texture;
    std::vector<WindowRect> windowRects; // bottom to top, for picking a window to drag
    std::string name;  // reserved for a workspace name (Hyprland keeps it private); the number is shown
    int windows = 0;   // how many windows it holds, for its label
};

class FaceRenderer {
public:
    // The caller lends upright, normal-transform compositor-owned preview
    // textures. The pass takes a strong ref to each visible texture. Client
    // surface buffers require compositor synchronization before becoming previews.
    void enqueue(Render::CRenderContext& ctx, const Snapshot& state,
                 std::span<const WorkspaceId> workspaces, std::span<const FaceTexture> textures = {},
                 const DragView* drag = nullptr);
    void reset();

    void setQuality(Quality quality);
    [[nodiscard]] Quality quality() const { return quality_; }
    [[nodiscard]] bool hasBackdrop() const { return wallpaper_ != nullptr; }
    // Loads or frees the wallpaper to match the quality. Decoding a JPEG takes tens of
    // milliseconds, so call it from a Lua callback (gesture start), never from the render
    // pass. Cheap when nothing changed (one stat of the file).
    void prepareBackdrop();
    // Builds or refreshes the text label under each face ("2 · 3 windows"). Outside the render
    // pass for the same reason as prepareBackdrop. `origin` is the workspace you are on, shown
    // in the accent colour; `pixels` is the text height (about 1.9 % of the screen height).
    void prepareLabels(std::span<const FaceTexture> faces, std::optional<WorkspaceId> origin, int pixels);

private:
    Hyprutils::Memory::CSharedPointer<Render::ITexture> pane_;
    Hyprutils::Memory::CSharedPointer<Render::ITexture> wallpaper_;
    Quality quality_ = Quality::Full;
    long long wallpaperStamp_ = 0;

    // 1x1 textures for edges and shadows (a mesh can only be textured, not tinted).
    Hyprutils::Memory::CSharedPointer<Render::ITexture> accentEdge_, softEdge_, shade_;

    struct Label {
        std::string text;
        bool current = false;
        int pixels = 0;
        int width = 0, height = 0;
        Hyprutils::Memory::CSharedPointer<Render::ITexture> texture;
    };
    std::unordered_map<WorkspaceId, Label> labels_;
};

} // namespace prism
