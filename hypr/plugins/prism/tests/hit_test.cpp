#include "../hit.hpp"

#include <cstdlib>
#include <iostream>
#include <vector>

namespace {

void check(bool condition, const char* what) {
    if (!condition) {
        std::cerr << what << '\n';
        std::exit(EXIT_FAILURE);
    }
}

} // namespace

int main() {
    using namespace prism;
    int roundTrips = 0;
    // Every face of 1 to 8 workspaces, at whole and fractional turns: a point projected from
    // (u, v) must map back to (u, v). This is the property clicking relies on.
    for (std::size_t n = 1; n <= 8; ++n) {
        std::vector<WorkspaceId> ids(n);
        for (std::size_t i = 0; i < n; ++i)
            ids[i] = static_cast<WorkspaceId>(i + 1);
        for (const double position : {0.0, 0.5, 1.0, 2.3, -1.7}) {
            for (const double openness : {1.0, 0.6}) {
              for (const double flatness : {0.0, 0.5, 1.0}) {
                for (const auto& face : projectFaces(ids, position, openness, flatness)) {
                    for (const double u : {0.05, 0.3, 0.5, 0.8, 0.95}) {
                        for (const double v : {0.05, 0.5, 0.95}) {
                            const auto p = face.point(u, v);
                            const auto back = faceUV(face, p.x, p.y);
                            check(back.has_value(), "a point on a face was not found on it");
                            check(std::abs(back->u - u) < 1e-6 && std::abs(back->v - v) < 1e-6,
                                  "projecting then hit-testing did not return the same point");
                            ++roundTrips;
                        }
                    }
                }
              }
            }
        }
    }

    const std::vector<WorkspaceId> ids{4, 9, 2, 7, 5};
    // Front face, centre: the workspace at the position, flagged as the front.
    auto hit = hitTest(ids, 1, 1, 0.5, 0.5);
    check(hit && hit->workspace == 9 && hit->front, "the centre of the screen is not the front face");
    check(std::abs(hit->uv.u - 0.5) < 1e-6 && std::abs(hit->uv.v - 0.5) < 1e-6, "front centre is not u = v = 0.5");

    // Outside every face: the backdrop. Corners and the gap above the front face.
    check(!hitTest(ids, 1, 1, 0.01, 0.01), "the top-left corner hit a face");
    check(!hitTest(ids, 1, 1, 0.99, 0.99), "the bottom-right corner hit a face");
    check(!hitTest(ids, 1, 1, 0.5, 0.02), "the strip above the cube hit a face");

    // A side face is found and is not the front one. Find a point on it from its own projection.
    const auto faces = projectFaces(ids, 1, 1);
    check(faces.size() == 3, "five workspaces should show a front face and two neighbours");
    for (const auto& face : faces) {
        const auto p = face.point(0.5, 0.5);
        const auto h = hitTest(ids, 1, 1, p.x, p.y);
        check(h && h->workspace == face.workspace, "the centre of a visible face hit another workspace");
        check(h->front == (face.workspace == 9), "only the middle face is the front one");
    }

    // The unfolded row (dragging a window): every workspace's centre hits that workspace.
    for (const auto id : ids) {
        const auto row = projectFaces(ids, 2, 1, 1);
        const auto face = std::ranges::find(row, id, &ProjectedFace::workspace);
        check(face != row.end(), "a workspace is missing from the flat row");
        const auto p = face->point(0.5, 0.5);
        const auto h = hitTest(ids, 2, 1, p.x, p.y, 1);
        check(h && h->workspace == id, "the centre of a flat-row face hit another workspace");
    }

    // Closed (openness 0): the one face fills the output, so every point is on it.
    hit = hitTest(ids, 1, 0, 0.2, 0.9);
    check(hit && hit->workspace == 9, "a closed overview should be one face filling the output");

    // Bad input must not produce a hit.
    check(!hitTest({}, 0, 1, 0.5, 0.5), "no workspaces produced a hit");
    check(!hitTest(ids, std::nan(""), 1, 0.5, 0.5), "a non-finite position produced a hit");

    std::cout << "hit: " << roundTrips << " projection round trips, front face, side faces, backdrop, closed, bad input passed\n";
}
