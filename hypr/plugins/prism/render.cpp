#include "render.hpp"

#include <hyprland/src/render/Renderer.hpp>
#include <hyprgraphics/image/Image.hpp>

#include <pango/pangocairo.h>
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

struct DrawLabel {
    SP<Render::ITexture> texture;
    CBox box;
    float alpha;
};

// The window being dragged: its picture (a crop of the source workspace's), outline, shadow.
struct DrawGhost {
    SP<Render::ITexture> texture;
    std::vector<SMeshRenderVertex> vertices;
    std::vector<SMeshRenderVertex> edge;
    std::vector<SMeshRenderVertex> shadow;
};

struct DrawFace {
    SP<Render::ITexture> texture;
    std::vector<SMeshRenderVertex> vertices;
    std::vector<SMeshRenderVertex> wallVertices; // the wallpaper behind the picture; empty in lite
    std::vector<SMeshRenderVertex> shadow[3];    // three growing, faint rings: a soft shadow
    std::vector<SMeshRenderVertex> edge;         // a thin outline
    bool current = false;                        // the workspace you are on: accent outline
    bool hover = false;                          // a dragged window is over it: thick accent outline
    std::optional<DrawLabel> label;
};

// A line segment of `thickness` pixels as two triangles, in the output's normalised coordinates.
void ribbon(std::vector<SMeshRenderVertex>& out, ProjectedPoint a, ProjectedPoint b, double thickness,
            double width, double height) {
    const double ax = a.x * width, ay = a.y * height, bx = b.x * width, by = b.y * height;
    const double length = std::hypot(bx - ax, by - ay);
    if (length < 1e-6)
        return;
    const double nx = -(by - ay) / length * thickness / 2, ny = (bx - ax) / length * thickness / 2;
    const auto put = [&](double x, double y) {
        return SMeshRenderVertex{static_cast<float>(x / width), static_cast<float>(y / height), 0.5F, 0.5F};
    };
    out.insert(out.end(), {put(ax - nx, ay - ny), put(ax + nx, ay + ny), put(bx - nx, by - ny),
                           put(bx - nx, by - ny), put(ax + nx, ay + ny), put(bx + nx, by + ny)});
}

// The face's outline, `grow` pixels outside the quad (negative: inside).
std::vector<SMeshRenderVertex> outline(const ProjectedFace& face, double thickness, double grow, double width,
                                       double height) {
    ProjectedPoint corner[4] = {face.point(0, 0), face.point(1, 0), face.point(1, 1), face.point(0, 1)};
    // Push each corner away from the centre of the quad: approximate, and enough for a border.
    ProjectedPoint centre{(corner[0].x + corner[2].x) / 2, (corner[0].y + corner[2].y) / 2};
    for (auto& c : corner) {
        const double dx = (c.x - centre.x) * width, dy = (c.y - centre.y) * height;
        const double length = std::hypot(dx, dy);
        if (length > 1e-6) {
            c.x += dx / length * grow / width;
            c.y += dy / length * grow / height;
        }
    }
    std::vector<SMeshRenderVertex> out;
    for (int i = 0; i < 4; ++i)
        ribbon(out, corner[i], corner[(i + 1) % 4], thickness, width, height);
    return out;
}

// A filled quad grown by `grow` pixels, for the shadow rings.
std::vector<SMeshRenderVertex> grown(const ProjectedFace& face, double grow, double width, double height) {
    ProjectedPoint c[4] = {face.point(0, 0), face.point(1, 0), face.point(1, 1), face.point(0, 1)};
    const ProjectedPoint centre{(c[0].x + c[2].x) / 2, (c[0].y + c[2].y) / 2};
    for (auto& p : c) {
        const double dx = (p.x - centre.x) * width, dy = (p.y - centre.y) * height;
        const double length = std::hypot(dx, dy);
        if (length > 1e-6) {
            p.x += dx / length * grow / width;
            p.y += dy / length * grow / height;
        }
    }
    const auto put = [](ProjectedPoint p) {
        return SMeshRenderVertex{static_cast<float>(p.x), static_cast<float>(p.y), 0.5F, 0.5F};
    };
    return {put(c[0]), put(c[3]), put(c[1]), put(c[1]), put(c[3]), put(c[2])};
}

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
    FacePass(std::vector<DrawFace> faces, double openness, SP<Render::ITexture> wallpaper, Cover cover,
             SP<Render::ITexture> accent, SP<Render::ITexture> soft, SP<Render::ITexture> shade,
             std::optional<DrawGhost> ghost)
        : faces_(std::move(faces)), openness_(openness), wallpaper_(std::move(wallpaper)), cover_(cover),
          accent_(std::move(accent)), soft_(std::move(soft)), shade_(std::move(shade)), ghost_(std::move(ghost)) {}

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
        const auto a = static_cast<float>(openness_);
        for (const auto& face : faces_) {
            if (shade_ && shade_->ok())
                for (const auto& ring : face.shadow)
                    if (!ring.empty())
                        gl->renderTextureMesh(ctx, shade_, output, ring,
                                              {.damage = &ctx.m_data.damage, .a = a, .allowDim = false});
            if (!face.wallVertices.empty() && wallpaper_ && wallpaper_->ok())
                gl->renderTextureMesh(ctx, wallpaper_, output, face.wallVertices,
                                      {.damage = &ctx.m_data.damage, .allowDim = false});
            gl->renderTextureMesh(ctx, face.texture, output, face.vertices,
                                  {.damage = &ctx.m_data.damage, .allowDim = false});
            const auto& line = face.current || face.hover ? accent_ : soft_;
            if (line && line->ok() && !face.edge.empty())
                gl->renderTextureMesh(ctx, line, output, face.edge,
                                      {.damage = &ctx.m_data.damage, .a = a, .allowDim = false});
            if (face.label && face.label->texture && face.label->texture->ok())
                gl->renderTexture(ctx, face.label->texture, face.label->box,
                                  {.damage = &ctx.m_data.damage, .a = face.label->alpha * a, .allowDim = false});
        }
        if (ghost_ && ghost_->texture && ghost_->texture->ok()) {
            if (shade_ && shade_->ok() && !ghost_->shadow.empty())
                gl->renderTextureMesh(ctx, shade_, output, ghost_->shadow,
                                      {.damage = &ctx.m_data.damage, .a = a, .allowDim = false});
            gl->renderTextureMesh(ctx, ghost_->texture, output, ghost_->vertices,
                                  {.damage = &ctx.m_data.damage, .a = 0.92F * a, .allowDim = false});
            if (accent_ && accent_->ok() && !ghost_->edge.empty())
                gl->renderTextureMesh(ctx, accent_, output, ghost_->edge,
                                      {.damage = &ctx.m_data.damage, .a = a, .allowDim = false});
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
    SP<Render::ITexture> accent_, soft_, shade_;
    std::optional<DrawGhost> ghost_;
};

} // namespace

void noteRenderStage() noexcept { ++stages; }

RenderDiagnostics renderDiagnostics() noexcept {
    return {stages.load(), attempts.load(), candidates.load(), ready.load(), enqueues.load(), draws.load(), 0};
}

void FaceRenderer::enqueue(Render::CRenderContext& ctx, const Snapshot& state,
                           std::span<const WorkspaceId> workspaces, std::span<const FaceTexture> textures,
                           const DragView* drag) {
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
    const auto solid = [](std::uint8_t r, std::uint8_t g, std::uint8_t b, std::uint8_t alpha) {
        std::uint8_t pixel[] = {r, g, b, alpha};
        return g_pHyprRenderer->createTexture(DRM_FORMAT_ABGR8888, pixel, 4, {1, 1});
    };
    if (!accentEdge_)
        accentEdge_ = solid(138, 180, 248, 255);        // #8ab4f8, the Quickshell accent
    if (!softEdge_)
        softEdge_ = solid(115, 115, 115, 115);          // white at 45 %, premultiplied
    if (!shade_)
        shade_ = solid(0, 0, 0, 22);                    // black at 9 %: three rings add up to a soft shadow
    const double outW = size.x, outH = size.y;
    const double frontPixels = 0.62 * outW;

    std::vector<DrawFace> faces;
    const auto projected = projectFaces(workspaces, state.facePosition, state.openness, state.flatness);
    for (const auto& face : projected) {
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
            DrawFace draw{std::move(tex), mesh(face), glass ? mesh(face, cover) : std::vector<SMeshRenderVertex>{}};
            const auto lite = quality_ == Quality::Lite;
            if (!lite) {
                draw.shadow[0] = grown(face, 26, outW, outH);
                draw.shadow[1] = grown(face, 16, outW, outH);
                draw.shadow[2] = grown(face, 7, outW, outH);
            }
            draw.hover = drag && drag->hover && *drag->hover == face.workspace;
            draw.edge = outline(face, draw.hover ? 5.0 : 2.0, 1.0, outW, outH);
            draw.current = state.originWorkspace && *state.originWorkspace == face.workspace;
            if (const auto label = labels_.find(face.workspace); label != labels_.end() && label->second.texture) {
                const auto left = face.point(0, 1), right = face.point(1, 1);
                const double facePixels = std::abs(right.x - left.x) * outW;
                const double scale = std::clamp(facePixels / frontPixels, 0.5, 1.0);
                const double w = label->second.width * scale, h = label->second.height * scale;
                const double cx = (left.x + right.x) / 2 * outW;
                const double by = std::max(left.y, right.y) * outH;
                draw.label = DrawLabel{label->second.texture, CBox{cx - w / 2, by + 12 * scale, w, h},
                                       static_cast<float>(0.55 + 0.45 * scale)};
            }
            faces.push_back(std::move(draw));
        }
    }
    // The dragged window follows the cursor, drawn at the size it has in the row.
    std::optional<DrawGhost> ghost;
    if (drag && !projected.empty()) {
        const auto source = std::ranges::find(textures, drag->source, &FaceTexture::workspace);
        const auto shown = std::ranges::find(projected, drag->source, &ProjectedFace::workspace);
        const auto& reference = shown != projected.end() ? *shown : projected.back();
        const double faceW = reference.point(1, 0).x - reference.point(0, 0).x;
        const double faceH = reference.point(0, 1).y - reference.point(0, 0).y;
        if (source != textures.end() && source->texture && source->texture->ok() && faceW > 0 && faceH > 0) {
            const double w = drag->window.w * faceW * 0.85, h = drag->window.h * faceH * 0.85;
            const double x0 = drag->x - w / 2, y0 = drag->y - h / 2;
            const float u0 = static_cast<float>(drag->window.x), v0 = static_cast<float>(drag->window.y);
            const float u1 = static_cast<float>(drag->window.x + drag->window.w);
            const float v1 = static_cast<float>(drag->window.y + drag->window.h);
            const auto put = [](double x, double y, float u, float v) {
                return SMeshRenderVertex{static_cast<float>(x), static_cast<float>(y), u, v};
            };
            DrawGhost g;
            g.texture = source->texture;
            g.vertices = {put(x0, y0, u0, v0),     put(x0, y0 + h, u0, v1), put(x0 + w, y0, u1, v0),
                          put(x0 + w, y0, u1, v0), put(x0, y0 + h, u0, v1), put(x0 + w, y0 + h, u1, v1)};
            const ProjectedPoint corner[4] = {{x0, y0}, {x0 + w, y0}, {x0 + w, y0 + h}, {x0, y0 + h}};
            for (int i = 0; i < 4; ++i)
                ribbon(g.edge, corner[i], corner[(i + 1) % 4], 3.0, outW, outH);
            const double grow = 14.0;
            const double gx = grow / outW, gy = grow / outH;
            g.shadow = {put(x0 - gx, y0 - gy, 0.5F, 0.5F),     put(x0 - gx, y0 + h + gy, 0.5F, 0.5F),
                        put(x0 + w + gx, y0 - gy, 0.5F, 0.5F), put(x0 + w + gx, y0 - gy, 0.5F, 0.5F),
                        put(x0 - gx, y0 + h + gy, 0.5F, 0.5F), put(x0 + w + gx, y0 + h + gy, 0.5F, 0.5F)};
            ghost = std::move(g);
        }
    }
    if (!faces.empty())
        ++enqueues;
    if (!faces.empty())
        Render::IHyprRenderer::addPassElement(
            ctx, makeUnique<FacePass>(std::move(faces), state.openness, wallpaper_, cover, accentEdge_, softEdge_,
                                      shade_, std::move(ghost)));
}

void FaceRenderer::reset() {
    if (g_pHyprRenderer)
        g_pHyprRenderer->context().m_pass.removeAllOfType(passName);
    pane_.reset();
    wallpaper_.reset();
    wallpaperStamp_ = 0;
    accentEdge_.reset();
    softEdge_.reset();
    shade_.reset();
    labels_.clear();
}

SP<Render::ITexture> makeLabelTexture(const std::string& text, bool current, int pixels, int& width, int& height) {
    cairo_surface_t* probe = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, 1, 1);
    cairo_t* measure = cairo_create(probe);
    PangoLayout* layout = pango_cairo_create_layout(measure);
    PangoFontDescription* font = pango_font_description_from_string("JetBrainsMono Nerd Font, Sans Bold");
    pango_font_description_set_absolute_size(font, pixels * PANGO_SCALE);
    pango_layout_set_font_description(layout, font);
    pango_layout_set_text(layout, text.c_str(), -1);
    int textWidth = 0, textHeight = 0;
    pango_layout_get_pixel_size(layout, &textWidth, &textHeight);

    const double padX = pixels * 0.9, padY = pixels * 0.32;
    width = static_cast<int>(std::ceil(textWidth + 2 * padX));
    height = static_cast<int>(std::ceil(textHeight + 2 * padY));
    SP<Render::ITexture> texture;
    if (width > 0 && height > 0 && width < 4096) {
        cairo_surface_t* surface = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, width, height);
        if (cairo_t* cr = cairo_create(surface)) {
            const double r = height / 2.0;
            cairo_new_sub_path(cr);
            cairo_arc(cr, width - r, r, r, -M_PI / 2, M_PI / 2);
            cairo_arc(cr, r, r, r, M_PI / 2, 3 * M_PI / 2);
            cairo_close_path(cr);
            if (current)
                cairo_set_source_rgba(cr, 0.54, 0.71, 0.97, 0.94);
            else
                cairo_set_source_rgba(cr, 0.02, 0.03, 0.06, 0.55);
            cairo_fill(cr);
            if (current)
                cairo_set_source_rgba(cr, 0.04, 0.06, 0.10, 1.0);
            else
                cairo_set_source_rgba(cr, 1.0, 1.0, 1.0, 0.92);
            cairo_move_to(cr, padX, padY);
            PangoLayout* draw = pango_cairo_create_layout(cr);
            pango_layout_set_font_description(draw, font);
            pango_layout_set_text(draw, text.c_str(), -1);
            pango_cairo_show_layout(cr, draw);
            g_object_unref(draw);
            cairo_destroy(cr);
        }
        cairo_surface_flush(surface);
        texture = g_pHyprRenderer->createTexture(surface);
        cairo_surface_destroy(surface);
    }
    g_object_unref(layout);
    pango_font_description_free(font);
    cairo_destroy(measure);
    cairo_surface_destroy(probe);
    return texture;
}

void FaceRenderer::prepareLabels(std::span<const FaceTexture> faces, std::optional<WorkspaceId> origin, int pixels) {
    if (!g_pHyprRenderer)
        return;
    pixels = std::clamp(pixels, 12, 40);
    std::erase_if(labels_, [&](const auto& entry) {
        return std::ranges::find(faces, entry.first, &FaceTexture::workspace) == faces.end();
    });
    bool madeTexture = false;
    for (const auto& face : faces) {
        std::string text = face.name.empty() ? std::to_string(face.workspace) : face.name;
        text += face.windows == 0 ? "  ·  empty" : face.windows == 1 ? "  ·  1 window"
                                                                     : "  ·  " + std::to_string(face.windows) + " windows";
        const bool current = origin && *origin == face.workspace;
        auto& label = labels_[face.workspace];
        if (label.texture && label.text == text && label.current == current && label.pixels == pixels)
            continue;
        if (!madeTexture) {
            if (const auto gl = g_pHyprRenderer->glBackend(); gl.valid())
                gl->makeEGLCurrent();
            madeTexture = true;
        }
        label.text = text;
        label.current = current;
        label.pixels = pixels;
        label.texture = makeLabelTexture(text, current, pixels, label.width, label.height);
    }
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
