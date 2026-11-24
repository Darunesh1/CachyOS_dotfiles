#include "render.hpp"

#include <hyprland/src/render/Renderer.hpp>
#include <hyprgraphics/image/Image.hpp>

#include <sys/stat.h>

#include <atomic>
#include <cstdlib>
#include <string>

namespace prism {
namespace {

constexpr char passName[] = "MyArchPrismFaces";
std::atomic<std::uint64_t> stages = 0;
std::atomic<std::uint64_t> attempts = 0;
std::atomic<std::uint64_t> candidates = 0;
std::atomic<std::uint64_t> ready = 0;
std::atomic<std::uint64_t> enqueues = 0;
std::atomic<std::uint64_t> draws = 0;

struct DrawFace {
    SP<Render::ITexture> texture;
    std::vector<SMeshRenderVertex> vertices;
    std::vector<SMeshRenderVertex> wallVertices; // the wallpaper behind the picture; empty in lite
};

// The part of the wallpaper that covers the output without stretching (cover fit).
struct Cover {
    float u0 = 0, v0 = 0, uw = 1, vh = 1;
};

Cover coverFit(double textureAspect, double outputAspect) {
    Cover c;
    if (textureAspect <= 0 || outputAspect <= 0)
        return c;
    if (textureAspect > outputAspect) {
        c.uw = static_cast<float>(outputAspect / textureAspect);
        c.u0 = (1 - c.uw) / 2;
    } else {
        c.vh = static_cast<float>(textureAspect / outputAspect);
        c.v0 = (1 - c.vh) / 2;
    }
    return c;
}

std::vector<SMeshRenderVertex> mesh(const ProjectedFace& face, const Cover& cover = {}) {
    // The compositor mesh carries x/y/u/v only. Subdivide along the axis of
    // depth change to approximate perspective-correct UVs on angled faces.
    const int strips = std::abs(face.sine) < 1e-6 ? 1 : 24;
    std::vector<SMeshRenderVertex> vertices;
    vertices.reserve(strips * 6);
    const auto vertex = [&face, &cover](float u, float v) {
        const auto p = face.point(u, v);
        return SMeshRenderVertex{static_cast<float>(p.x), static_cast<float>(p.y), cover.u0 + u * cover.uw,
                                 cover.v0 + v * cover.vh};
    };
    for (int i = 0; i < strips; ++i) {
        const float left = static_cast<float>(i) / strips;
        const float right = static_cast<float>(i + 1) / strips;
        vertices.insert(vertices.end(), {vertex(left, 0), vertex(left, 1), vertex(right, 0),
                                         vertex(right, 0), vertex(left, 1), vertex(right, 1)});
    }
    return vertices;
}

class FacePass final : public IPassElement {
public:
    FacePass(std::vector<DrawFace> faces, double openness, SP<Render::ITexture> wallpaper, Cover cover)
        : faces_(std::move(faces)), openness_(openness), wallpaper_(std::move(wallpaper)), cover_(cover) {}

    const char* passName() override { return prism::passName; }
    ePassElementType type() override { return EK_CUSTOM; }
    bool needsLiveBlur(Render::CRenderContext&) override { return false; }
    bool needsPrecomputeBlur(Render::CRenderContext&) override { return false; }

    std::vector<UP<IPassElement>> draw(Render::CRenderContext& ctx) override {
        ++draws;
        // A weak pointer over Hyprland's unique pointer: lock() asserts and aborts the
        // compositor. Use valid() and operator-> only.
        const auto gl = g_pHyprRenderer->glBackend();
        if (!gl.valid() || !ctx.m_data.pMonitor || ctx.m_data.damage.empty())
            return {};

        const auto size = ctx.m_data.pMonitor->m_transformedSize;
        const CBox output{0, 0, size.x, size.y};
        const bool previousBlend = gl->blendEnabled();
        gl->blend(true);
        // Backdrop: your wallpaper (full) under a dark gradient, or just the gradient (lite).
        // The gradient is bands because a rectangle takes one colour.
        if (wallpaper_ && wallpaper_->ok()) {
            const auto wall = std::vector<SMeshRenderVertex>{
                {0, 0, cover_.u0, cover_.v0},
                {0, 1, cover_.u0, cover_.v0 + cover_.vh},
                {1, 0, cover_.u0 + cover_.uw, cover_.v0},
                {1, 0, cover_.u0 + cover_.uw, cover_.v0},
                {0, 1, cover_.u0, cover_.v0 + cover_.vh},
                {1, 1, cover_.u0 + cover_.uw, cover_.v0 + cover_.vh}};
            gl->renderTextureMesh(ctx, wallpaper_, output, wall,
                                  {.damage = &ctx.m_data.damage, .a = static_cast<float>(openness_), .allowDim = false});
        }
        constexpr int bands = 16;
        const bool glass = wallpaper_ && wallpaper_->ok();
        for (int i = 0; i < bands; ++i) {
            const double t = (i + 0.5) / bands;
            // Whole pixels that meet exactly: overlapping bands blend twice and show as lines.
            const double top = std::floor(size.y * i / bands);
            const double bottom = std::floor(size.y * (i + 1) / bands);
            const CBox band{0, top, size.x, bottom - top};
            const auto colour = glass
                ? CHyprColor(0.02, 0.03, 0.06, (0.28 + 0.27 * t) * openness_)
                : CHyprColor(0.075 - 0.05 * t, 0.095 - 0.062 * t, 0.15 - 0.09 * t, openness_);
            gl->renderRect(ctx, band, colour, {.damage = &ctx.m_data.damage});
        }
        for (const auto& face : faces_) {
            if (!face.wallVertices.empty() && wallpaper_ && wallpaper_->ok())
                gl->renderTextureMesh(ctx, wallpaper_, output, face.wallVertices,
                                      {.damage = &ctx.m_data.damage, .allowDim = false});
            gl->renderTextureMesh(ctx, face.texture, output, face.vertices,
                                  {.damage = &ctx.m_data.damage, .allowDim = false});
        }
        gl->disableScissor();
        gl->blend(previousBlend);
        return {};
    }

private:
    std::vector<DrawFace> faces_;
    double openness_;
    SP<Render::ITexture> wallpaper_;
    Cover cover_;
};

} // namespace

void noteRenderStage() noexcept { ++stages; }

RenderDiagnostics renderDiagnostics() noexcept {
    return {stages.load(), attempts.load(), candidates.load(), ready.load(), enqueues.load(), draws.load(), 0};
}

void FaceRenderer::enqueue(Render::CRenderContext& ctx, const Snapshot& state,
                           std::span<const WorkspaceId> workspaces, std::span<const FaceTexture> textures) {
    ++attempts;
    if (state.phase == Phase::Closed || state.openness <= 0 || !ctx.m_data.pMonitor ||
        ctx.m_renderingCapture || ctx.m_renderingSnapshot || ctx.m_mode != Render::RENDER_MODE_NORMAL ||
        &Render::IHyprRenderer::currentPass(ctx) != &ctx.m_pass || !g_pHyprRenderer->glBackend())
        return;

    const bool glass = wallpaper_ && wallpaper_->ok();
    const auto size = ctx.m_data.pMonitor->m_transformedSize;
    const auto cover = glass ? coverFit(wallpaper_->m_size.x / std::max(1.0, wallpaper_->m_size.y),
                                        size.x / std::max(1.0, size.y))
                             : Cover{};
    std::vector<DrawFace> faces;
    for (const auto& face : projectFaces(workspaces, state.facePosition, state.openness)) {
        ++candidates;
        const auto it = std::ranges::find(textures, face.workspace, &FaceTexture::workspace);
        auto tex = it != textures.end() ? it->texture : nullptr;
        if (!tex || !tex->ok() || tex->m_transform != HYPRUTILS_TRANSFORM_NORMAL) {
            if (!pane_) {
                // RGBA fallback for an empty workspace or a preview pending capture.
                std::uint8_t pixels[] = {66, 79, 101, 255, 53, 65, 86, 255,
                                         41, 51, 65, 255, 35, 42, 56, 255};
                pane_ = g_pHyprRenderer->createTexture(DRM_FORMAT_ABGR8888, pixels, 8, {2, 2});
            }
            tex = pane_;
        }
        if (tex && tex->ok()) {
            ++ready;
            faces.push_back({std::move(tex), mesh(face), glass ? mesh(face, cover) : std::vector<SMeshRenderVertex>{}});
        }
    }
    if (!faces.empty())
        ++enqueues;
    if (!faces.empty())
        Render::IHyprRenderer::addPassElement(
            ctx, makeUnique<FacePass>(std::move(faces), state.openness, wallpaper_, cover));
}

void FaceRenderer::reset() {
    if (g_pHyprRenderer)
        g_pHyprRenderer->context().m_pass.removeAllOfType(passName);
    pane_.reset();
    wallpaper_.reset();
    wallpaperStamp_ = 0;
}

void FaceRenderer::setQuality(Quality quality) {
    quality_ = quality;
    if (quality == Quality::Lite) {
        wallpaper_.reset();
        wallpaperStamp_ = 0;
    }
}

void FaceRenderer::prepareBackdrop() {
    if (quality_ != Quality::Full || !g_pHyprRenderer) {
        wallpaper_.reset();
        wallpaperStamp_ = 0;
        return;
    }
    std::string path;
    if (const char* override = std::getenv("PRISM_WALLPAPER"); override && *override)
        path = override;
    else if (const char* home = std::getenv("HOME"))
        path = std::string{home} + "/Pictures/Wallpaper/current_wallpaper";
    struct stat info{};
    if (path.empty() || stat(path.c_str(), &info) != 0) {
        wallpaper_.reset();
        wallpaperStamp_ = 0;
        return;
    }
    // A failed decode is remembered too, so a broken file is not decoded at every open.
    const long long stamp = static_cast<long long>(info.st_mtim.tv_sec) * 1000003LL + info.st_size;
    if (stamp == wallpaperStamp_)
        return;
    wallpaperStamp_ = stamp;
    wallpaper_.reset();

    Hyprgraphics::CImage image(path);
    if (!image.success())
        return;
    const auto surface = image.cairoSurface();
    if (!surface || !surface->cairo() || surface->status() != CAIRO_STATUS_SUCCESS)
        return;
    const auto sourceSize = surface->size();
    if (sourceSize.x < 1 || sourceSize.y < 1)
        return;

    // At most 1920 wide: a 4K wallpaper would be a 33 MB texture behind a dimmed backdrop.
    const double shrink = std::min(1.0, 1920.0 / sourceSize.x);
    const int width = std::max(1, static_cast<int>(sourceSize.x * shrink));
    const int height = std::max(1, static_cast<int>(sourceSize.y * shrink));
    cairo_surface_t* scaled = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, width, height);
    if (cairo_surface_status(scaled) != CAIRO_STATUS_SUCCESS) {
        cairo_surface_destroy(scaled);
        return;
    }
    if (const auto cr = cairo_create(scaled)) {
        cairo_scale(cr, shrink, shrink);
        cairo_set_source_surface(cr, surface->cairo(), 0, 0);
        cairo_pattern_set_filter(cairo_get_source(cr), CAIRO_FILTER_GOOD);
        cairo_paint(cr);
        cairo_destroy(cr);
    }
    cairo_surface_flush(scaled);
    const auto gl = g_pHyprRenderer->glBackend();
    if (gl.valid())
        gl->makeEGLCurrent();
    wallpaper_ = g_pHyprRenderer->createTexture(scaled);
    cairo_surface_destroy(scaled);
}

} // namespace prism
