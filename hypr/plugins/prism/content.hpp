#pragma once

#include "render.hpp"

#include <hyprland/src/desktop/DesktopTypes.hpp>

namespace prism {

// Draws windows and their subsurfaces into a bounded compositor-owned GPU
// texture. Call once per invalid preview on the compositor thread, outside an
// active render context. The caller controls the cache lifetime.
[[nodiscard]] std::optional<FaceTexture> captureWorkspace(PHLWORKSPACE workspace);

} // namespace prism
