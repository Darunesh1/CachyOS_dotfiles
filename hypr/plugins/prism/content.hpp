#pragma once

#include "render.hpp"

#include <hyprland/src/desktop/DesktopTypes.hpp>

#include <chrono>
#include <cstdint>
#include <optional>
#include <span>
#include <unordered_map>
#include <vector>

namespace prism {

// Draws windows and their subsurfaces into a bounded compositor-owned GPU
// texture. Call once per invalid preview on the compositor thread, outside an
// active render context. The caller controls the cache lifetime.
[[nodiscard]] std::optional<FaceTexture> captureWorkspace(PHLWORKSPACE workspace);

[[nodiscard]] PHLWORKSPACE findWorkspace(WorkspaceId id);

struct ContentStats {
    std::uint64_t captured = 0;
    std::uint64_t failed = 0;
    std::uint64_t reused = 0;
};

// One preview texture per workspace. refresh() renders, so it must run outside
// the render pass (a Lua callback, not the render-stage hook).
//
// A face is re-captured when it was invalidated, when it is `forced`, or when
// it is older than maxAge: a client repainting inside a hidden workspace sends
// no event, so age is the only way to notice. `forced` is the workspace the
// gesture starts on, which therefore never shows an old picture.
class ContentCache {
public:
    static constexpr std::chrono::milliseconds maxAge{2000};

    void invalidateAll() noexcept;
    void refresh(std::span<const WorkspaceId> workspaces, std::optional<WorkspaceId> forced);
    // Forget faces whose workspace is not listed: they hold GPU memory for nothing.
    void retain(std::span<const WorkspaceId> workspaces);
    void clear() noexcept;

    [[nodiscard]] std::span<const FaceTexture> textures() const noexcept { return faces_; }
    [[nodiscard]] ContentStats stats() const noexcept { return stats_; }

private:
    struct Meta {
        std::chrono::steady_clock::time_point captured;
        bool dirty = true;
    };

    void drop(WorkspaceId id) noexcept;

    std::vector<FaceTexture> faces_;
    std::unordered_map<WorkspaceId, Meta> meta_;
    ContentStats stats_;
};

} // namespace prism
