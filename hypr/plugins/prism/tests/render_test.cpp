#include "../render.hpp"

#include <cstdlib>
#include <iostream>
#include <limits>

namespace {

void check(bool condition, const char* what) {
    if (!condition) {
        std::cerr << what << '\n';
        std::exit(EXIT_FAILURE);
    }
}

bool near(double a, double b) {
    return std::abs(a - b) < 1e-8;
}

void checkSameFrame(std::span<const prism::ProjectedFace> a, std::span<const prism::ProjectedFace> b) {
    check(a.size() == b.size(), "rotation changed the number of visible faces");
    for (const auto& face : a) {
        const auto i = std::ranges::find(b, face.workspace, &prism::ProjectedFace::workspace);
        check(i != b.end(), "wrapped rotation lost a workspace");
        const auto left = face.point(0, 0);
        const auto right = face.point(1, 1);
        check(near(i->point(0, 0).x, left.x) && near(i->point(0, 0).y, left.y) &&
              near(i->point(1, 1).x, right.x) && near(i->point(1, 1).y, right.y),
              "wrapped rotation moved a corner");
    }
}

} // namespace

int main() {
    using prism::projectFaces;
    const std::vector<prism::WorkspaceId> ids{9, 2, 16, 8, 4, 7};
    check(projectFaces({}, 0, 1).empty(), "empty workspace collection drew a face");
    check(projectFaces(ids, std::numeric_limits<double>::infinity(), 1).empty(), "invalid angle was rendered");

    auto flat = projectFaces(ids, 1, 0);
    check(flat.size() == 1 && flat[0].workspace == 2, "closed frame lost active workspace identity");
    check(near(flat[0].point(0, 0).x, 0) && near(flat[0].point(1, 1).y, 1),
          "closed workspace did not fill the output");
    auto open = projectFaces(ids, 1, 1);
    check(open.size() == 3 && open.back().workspace == 2, "back faces or draw order are incorrect");
    check(near(open.back().point(0, 0).x, 0.25) && near(open.back().point(1, 1).y, 0.75),
          "open front face does not have the requested aspect and scale");
    const auto& next = *std::ranges::find(open, 16, &prism::ProjectedFace::workspace);
    check(next.point(0, 0).y < next.point(1, 0).y, "both edges of an angled face have the same perspective");
    check(next.point(0, 0).x > open.back().point(1, 0).x, "neighbor crossed the front hinge");
    checkSameFrame(projectFaces(ids, 0.3, 1), projectFaces(ids, -5.7, 1));
    checkSameFrame(projectFaces(ids, 0.3, 1), projectFaces(ids, 12.3, 1));

    for (std::size_t n = 1; n <= ids.size(); ++n) {
        const auto subset = std::span(ids).first(n);
        for (int tick = -100; tick <= 100; ++tick) {
            const double position = n == 1 ? 0 : tick / 13.0;
            const auto frame = projectFaces(subset, position, 1);
            check(!frame.empty(), "overview turned edge-on and disappeared");
            for (const auto& f : frame) {
                const auto l = f.point(0, 0);
                const auto r = f.point(1, 1);
                check(l.x < r.x && l.y < r.y && std::isfinite(l.y) && std::isfinite(r.y),
                      "degenerate projected face");
            }
        }
    }
    std::cout << "projection: identity, size, backface culling, painter order, perspective, wrapping, 1–6 faces passed\n";
}
