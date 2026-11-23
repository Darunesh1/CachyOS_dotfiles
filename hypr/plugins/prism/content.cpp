#include "content.hpp"

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
    return FaceTexture{*workspace->numberedID(), std::move(texture)};
}

} // namespace prism
