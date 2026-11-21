#include "render.hpp"

#include <hyprland/src/render/Renderer.hpp>

namespace prism {
namespace {

constexpr char passName[] = "MyArchPrismFaces";

struct DrawFace {
    SP<Render::ITexture> texture;
    std::vector<SMeshRenderVertex> vertices;
};

std::vector<SMeshRenderVertex> mesh(const ProjectedFace& face) {
    // The compositor mesh carries x/y/u/v only. Subdivide along the axis of
    // depth change to approximate perspective-correct UVs on angled faces.
    const int strips = std::abs(face.sine) < 1e-6 ? 1 : 24;
    std::vector<SMeshRenderVertex> vertices;
    vertices.reserve(strips * 6);
    const auto vertex = [&face](float u, float v) {
        const auto p = face.point(u, v);
        return SMeshRenderVertex{static_cast<float>(p.x), static_cast<float>(p.y), u, v};
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
    FacePass(std::vector<DrawFace> faces, double openness) : faces_(std::move(faces)), openness_(openness) {}

    const char* passName() override { return prism::passName; }
    ePassElementType type() override { return EK_CUSTOM; }
    bool needsLiveBlur(Render::CRenderContext&) override { return false; }
    bool needsPrecomputeBlur(Render::CRenderContext&) override { return false; }

    std::vector<UP<IPassElement>> draw(Render::CRenderContext& ctx) override {
        auto gl = g_pHyprRenderer->glBackend().lock();
        if (!gl || !ctx.m_data.pMonitor || ctx.m_data.damage.empty())
            return {};

        const auto size = ctx.m_data.pMonitor->m_transformedSize;
        const CBox output{0, 0, size.x, size.y};
        const bool previousBlend = gl->blendEnabled();
        gl->blend(true);
        gl->renderRect(ctx, output, CHyprColor(0.035, 0.045, 0.06, openness_), {.damage = &ctx.m_data.damage});
        for (const auto& face : faces_) {
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
};

} // namespace

void FaceRenderer::enqueue(Render::CRenderContext& ctx, const Snapshot& state,
                           std::span<const WorkspaceId> workspaces, std::span<const FaceTexture> textures) {
    if (state.phase == Phase::Closed || state.openness <= 0 || !ctx.m_data.pMonitor ||
        ctx.m_renderingCapture || ctx.m_renderingSnapshot || ctx.m_mode != Render::RENDER_MODE_NORMAL ||
        &Render::IHyprRenderer::currentPass(ctx) != &ctx.m_pass || !g_pHyprRenderer->glBackend())
        return;

    std::vector<DrawFace> faces;
    for (const auto& face : projectFaces(workspaces, state.facePosition, state.openness)) {
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
        if (tex && tex->ok())
            faces.push_back({std::move(tex), mesh(face)});
    }
    if (!faces.empty())
        Render::IHyprRenderer::addPassElement(ctx, makeUnique<FacePass>(std::move(faces), state.openness));
}

void FaceRenderer::reset() {
    if (g_pHyprRenderer)
        g_pHyprRenderer->context().m_pass.removeAllOfType(passName);
    pane_.reset();
}

} // namespace prism
