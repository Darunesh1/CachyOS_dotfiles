#include "content.hpp"

#include <hyprland/src/state/WorkspaceState.hpp>
#include <hyprland/src/desktop/state/WindowState.hpp>
#include <hyprland/src/desktop/view/window/Window.hpp>
#include <hyprland/src/desktop/view/window/WindowPresentation.hpp>
#include <hyprland/src/managers/SessionLockManager.hpp>
#include <hyprland/src/protocols/core/Compositor.hpp>
#include <hyprland/src/render/Renderer.hpp>
#include <hyprland/src/render/SceneResources.hpp>
#include <hyprland/src/render/scene/SceneSelection.hpp>

namespace prism {
namespace {

void drawWindow(Render::CRenderContext& ctx, const PHLWINDOW& window, const PHLMONITOR& monitor) {
    const auto view = window->wlSurface();
    const auto root = view ? view->resource() : nullptr;
    if (!root)
        return;

    const auto presentation = window->presentation().renderPresentation(Render::eSceneMode::WORKSPACE_WINDOWS);
    if (!presentation.alphaVisible)
        return;

    const auto geom = window->geometricBox(Desktop::View::IGeometric::GEOMETRIC_CURRENT);
    CSurfacePassElement::SRenderData data;
    data.pMonitor = monitor;
    data.pos = geom.pos() + presentation.workspaceOffset + presentation.floatingOffset;
    data.w = geom.width;
    data.h = geom.height;
    data.alpha = presentation.alpha;
    data.fadeAlpha = presentation.fadeAlpha;
    data.pWindow = window;
    data.workspacePresentation = presentation;
    root->breadthfirst([&](SP<CWLSurfaceResource> surface, const Vector2D& offset, void*) {
        const auto& state = surface->m_current;
        if (!state.texture || !state.texture->ok() || state.size.x < 1 || state.size.y < 1)
            return;
        data.localPos = offset;
        data.mainSurface = surface == root;
        data.surface = surface;
        data.texture = state.texture;
        // The surface pass registers asynchronous buffer use with this render
        // context. The renderer retains it through submission and fence release.
        g_pHyprRenderer->draw(ctx, data, ctx.m_data.damage);
        ++data.surfaceCounter;
    }, nullptr);
}

} // namespace

PHLWORKSPACE findWorkspace(WorkspaceId id) {
    if (!State::workspaceState())
        return nullptr;
    for (const auto& ref : State::workspaceState()->workspaceRefs()) {
        const auto workspace = ref.lock();
        const auto numbered = workspace ? workspace->numberedID() : std::nullopt;
        if (numbered && static_cast<WorkspaceId>(*numbered) == id)
            return workspace;
    }
    return nullptr;
}

std::optional<FaceTexture> captureWorkspace(PHLWORKSPACE workspace) {
    if (!workspace || !workspace->numberedID() || !g_pHyprRenderer || g_pHyprRenderer->context().active() ||
        !g_pSessionLockManager || g_pSessionLockManager->isSessionLocked())
        return std::nullopt;
    const auto monitor = workspace->m_monitor.lock();
    // Weak over a unique pointer: never lock() it (asserts and aborts the compositor).
    const auto gl = g_pHyprRenderer->glBackend();
    if (!monitor || !monitor->m_output || !gl.valid())
        return std::nullopt;

    const auto size = monitor->m_transformedSize;
    if (size.x < 1 || size.y < 1)
        return std::nullopt;

    const auto belongs = [&](const PHLWINDOW& window) {
        return window && window->mapped() && !window->isHidden() &&
               window->m_monitor == monitor && window->m_workspace == workspace;
    };
    const auto& windows = Desktop::windowState()->windows();
    for (const auto& window : windows) {
        if (belongs(window) && window->m_ruleApplicator && window->m_ruleApplicator->noScreenShare().valueOrDefault())
            return std::nullopt;
    }

    const double scale = std::min(0.5, 768.0 / std::max(size.x, size.y));
    const int width = std::max(1, static_cast<int>(std::round(size.x * scale)));
    const int height = std::max(1, static_cast<int>(std::round(size.y * scale)));
    gl->makeEGLCurrent();
    Render::GL::CFramebufferBindingGuard bindings{gl};
    auto framebuffer = g_pHyprRenderer->createFB("Prism workspace preview");
    if (!framebuffer || !framebuffer->alloc(width, height, DRM_FORMAT_ABGR8888))
        return std::nullopt;
    framebuffer->setImageDescription(NColorManagement::DEFAULT_SRGB_IMAGE_DESCRIPTION);
    CRegion damage{0, 0, static_cast<double>(width), static_cast<double>(height)};
    if (!g_pHyprRenderer->beginFullFakeRender(monitor, damage, framebuffer))
        return std::nullopt;

    auto& ctx = g_pHyprRenderer->context();
    // FULL_FAKE shares the monitor's scene resources. endRender updates the
    // queued-blur flag even for an empty pass after our immediate draws.
    const auto resources = ctx.sceneResources();
    const bool queuedBlur = resources && resources->blurQueued();
    bool finished = false;
    const Render::CScopeGuard cleanup([&] {
        if (!finished)
            g_pHyprRenderer->abortRender();
        if (resources)
            resources->setBlurQueued(queuedBlur);
    });
    ctx.m_blockSurfaceFeedback = true;
    ctx.m_renderingCapture = true;
    ctx.m_renderingSnapshot = true;
    ctx.m_data.blockScreenShader = true;
    // Use the same unoccluded surface draw path as transformed-window sources.
    // Project monitor geometry into the already bound thumbnail viewport.
    ctx.m_data.renderingTransformedSource = true;
    ctx.m_data.fbSize = size;
    g_pHyprRenderer->setProjectionType(ctx, Render::RPT_EXPORT);
    g_pHyprRenderer->draw(ctx, CClearPassElement::SClearData{CHyprColor(0.12, 0.15, 0.20, 1.0)}, damage);
    for (const bool floating : {false, true}) {
        for (const auto& window : windows) {
            if (belongs(window) && window->isFloating() == floating)
                drawWindow(ctx, window, monitor);
        }
    }
    finished = true;
    g_pHyprRenderer->endRender();
    auto texture = framebuffer->getTexture();
    if (!texture || !texture->ok())
        return std::nullopt;
    return FaceTexture{static_cast<WorkspaceId>(*workspace->numberedID()), std::move(texture)};
}

void ContentCache::invalidateAll() noexcept {
    for (auto& [id, meta] : meta_)
        meta.dirty = true;
}

void ContentCache::drop(WorkspaceId id) noexcept {
    std::erase_if(faces_, [id](const FaceTexture& face) { return face.workspace == id; });
    meta_.erase(id);
}

void ContentCache::clear() noexcept {
    faces_.clear();
    meta_.clear();
}

void ContentCache::retain(std::span<const WorkspaceId> workspaces) {
    std::vector<WorkspaceId> stale;
    for (const auto& face : faces_)
        if (std::ranges::find(workspaces, face.workspace) == workspaces.end())
            stale.push_back(face.workspace);
    for (const auto id : stale)
        drop(id);
}

void ContentCache::refresh(std::span<const WorkspaceId> workspaces, std::optional<WorkspaceId> forced) {
    retain(workspaces);

    const auto now = std::chrono::steady_clock::now();
    for (const auto id : workspaces) {
        auto& meta = meta_[id];
        const bool have = std::ranges::any_of(faces_, [id](const FaceTexture& f) { return f.workspace == id; });
        if (have && !meta.dirty && forced != id && now - meta.captured < maxAge) {
            ++stats_.reused;
            continue;
        }
        auto captured = captureWorkspace(findWorkspace(id));
        // A failed capture must not leave an old picture of a changed workspace.
        std::erase_if(faces_, [id](const FaceTexture& face) { return face.workspace == id; });
        if (!captured) {
            ++stats_.failed;
            meta.dirty = true;
            continue;
        }
        faces_.push_back(std::move(*captured));
        meta.captured = now;
        meta.dirty = false;
        ++stats_.captured;
    }
}

} // namespace prism
