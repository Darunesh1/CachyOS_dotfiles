#include "core.hpp"
#include "render.hpp"

#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/state/MonitorState.hpp>
#include <hyprland/src/render/Renderer.hpp>
#include <hyprland/src/managers/SessionLockManager.hpp>
#include <lua.hpp>

#include <array>
#include <chrono>
#include <cmath>
#include <limits>
#include <stdexcept>
#include <string_view>

namespace {

constexpr auto PRISM_NAMESPACE = "prism";

constexpr std::string_view versionWithoutPatch(std::string_view version) {
    return version.substr(0, version.rfind('.'));
}

constexpr auto makeBuildAbi() {
    constexpr std::string_view parts[]{
        GIT_COMMIT_HASH,
        "_aq_", versionWithoutPatch(AQUAMARINE_VERSION),
        "_hu_", versionWithoutPatch(HYPRUTILS_VERSION),
        "_hg_", versionWithoutPatch(HYPRGRAPHICS_VERSION),
        "_hc_", versionWithoutPatch(HYPRCURSOR_VERSION),
        "_hlg_", versionWithoutPatch(HYPRLANG_VERSION),
    };
    constexpr auto size = [](const auto& values) {
        std::size_t total = 1;
        for (const auto part : values)
            total += part.size();
        return total;
    }(parts);
    std::array<char, size> abi{};
    std::size_t position = 0;
    for (const auto part : parts)
        for (const auto character : part)
            abi[position++] = character;
    return abi;
}

// The pre-load check reads this string from the ELF file without loading it.
[[gnu::used, gnu::section(".prism_abi")]] constexpr auto BUILD_ABI = makeBuildAbi();

HANDLE pluginHandle = nullptr;
prism::Core core;
prism::FaceRenderer renderer;
CHyprSignalListener renderListener;
std::chrono::steady_clock::time_point lastFrame;

void requestFrame() noexcept {
    if (!State::monitorState() || !g_pHyprRenderer)
        return;
    for (const auto& monitor : State::monitorState()->monitors())
        if (monitor)
            g_pHyprRenderer->damageMonitor(monitor);
}

void onRenderStage(const Event::SRenderStageEvent& event) {
    if (event.stage != RENDER_POST_WINDOWS || !event.context ||
        !g_pSessionLockManager || g_pSessionLockManager->isSessionLocked())
        return;

    const auto before = core.snapshot();
    if (before.phase == prism::Phase::Closed)
        return;

    try {
        const auto now = std::chrono::steady_clock::now();
        if (lastFrame != std::chrono::steady_clock::time_point{} && before.animating) {
            const auto seconds = std::chrono::duration<double>(now - lastFrame).count();
            core.tick(std::clamp(seconds, 0.0, 0.1));
        }
        lastFrame = now;
        const auto state = core.snapshot();
        renderer.enqueue(event.context->get(), state, core.workspaces());
        if (state.animating && event.monitor && g_pHyprRenderer)
            g_pHyprRenderer->damageMonitor(event.monitor);
    } catch (...) {
        core.reset();
    }
}

int prismStatus(lua_State* state) noexcept {
    lua_pushliteral(state, "loaded");
    return 1;
}

int pushResult(lua_State* state, bool result) noexcept {
    lua_pushboolean(state, result);
    return 1;
}

void pushWorkspace(lua_State* state, std::optional<prism::WorkspaceId> workspace) noexcept {
    if (workspace)
        lua_pushinteger(state, *workspace);
    else
        lua_pushnil(state);
}

bool readFiniteNumber(lua_State* state, int index, double& value) noexcept {
    if (lua_type(state, index) != LUA_TNUMBER)
        return false;
    value = lua_tonumber(state, index);
    return std::isfinite(value);
}

int setWorkspaces(lua_State* state) noexcept {
    if (!lua_istable(state, 1) || !lua_checkstack(state, 1))
        return pushResult(state, false);

    const auto count = lua_rawlen(state, 1);
    if (count >= static_cast<std::size_t>(std::numeric_limits<lua_Integer>::max()))
        return pushResult(state, false);

    try {
        std::vector<prism::WorkspaceId> workspaces;
        workspaces.reserve(count);
        for (std::size_t i = 0; i < count; ++i) {
            lua_rawgeti(state, 1, static_cast<lua_Integer>(i + 1));
            if (!lua_isinteger(state, -1)) {
                lua_pop(state, 1);
                return pushResult(state, false);
            }
            workspaces.push_back(lua_tointeger(state, -1));
            lua_pop(state, 1);
        }
        core.setWorkspaces(std::move(workspaces));
        requestFrame();
    } catch (...) {
        return pushResult(state, false);
    }
    return pushResult(state, true);
}

int begin(lua_State* state) noexcept {
    if (lua_type(state, 1) != LUA_TSTRING || !lua_isinteger(state, 2))
        return pushResult(state, false);

    std::size_t length;
    const auto* name = lua_tolstring(state, 1, &length);
    const std::string_view directionName{name, length};
    prism::Direction direction;
    if (directionName == "up")
        direction = prism::Direction::Up;
    else if (directionName == "down")
        direction = prism::Direction::Down;
    else if (directionName == "horizontal")
        direction = prism::Direction::Horizontal;
    else
        return pushResult(state, false);

    const auto accepted = core.begin(direction, lua_tointeger(state, 2));
    if (accepted)
        requestFrame();
    return pushResult(state, accepted);
}

int update(lua_State* state) noexcept {
    double dx, dy, elapsed;
    if (!readFiniteNumber(state, 1, dx) || !readFiniteNumber(state, 2, dy) ||
        !readFiniteNumber(state, 3, elapsed) || elapsed < 0)
        return pushResult(state, false);

    core.update(dx, dy, elapsed);
    requestFrame();
    return pushResult(state, true);
}

int finish(lua_State* state) noexcept {
    if (!lua_isboolean(state, 1))
        return pushResult(state, false);

    std::optional<double> releaseVelocity;
    if (!lua_isnoneornil(state, 2)) {
        double velocity;
        if (!readFiniteNumber(state, 2, velocity))
            return pushResult(state, false);
        releaseVelocity = velocity;
    }

    core.finish(lua_toboolean(state, 1) != 0, releaseVelocity);
    requestFrame();
    return pushResult(state, true);
}

int tick(lua_State* state) noexcept {
    double elapsed;
    if (!readFiniteNumber(state, 1, elapsed) || elapsed < 0)
        return pushResult(state, false);

    core.tick(elapsed);
    requestFrame();
    return pushResult(state, true);
}

const char* phaseName(prism::Phase phase) noexcept {
    switch (phase) {
        case prism::Phase::Closed:  return "closed";
        case prism::Phase::Opening: return "opening";
        case prism::Phase::Open:    return "open";
        case prism::Phase::Closing: return "closing";
    }
    return "closed";
}

int snapshot(lua_State* state) noexcept {
    const auto current = core.snapshot();
    lua_createtable(state, 0, 6);
    lua_pushstring(state, phaseName(current.phase));
    lua_setfield(state, -2, "phase");
    lua_pushnumber(state, current.openness);
    lua_setfield(state, -2, "openness");
    lua_pushnumber(state, current.facePosition);
    lua_setfield(state, -2, "facePosition");
    pushWorkspace(state, current.frontWorkspace);
    lua_setfield(state, -2, "frontWorkspace");
    pushWorkspace(state, current.originWorkspace);
    lua_setfield(state, -2, "originWorkspace");
    lua_pushboolean(state, current.animating);
    lua_setfield(state, -2, "animating");
    return 1;
}

int reset(lua_State* state) noexcept {
    core.reset();
    lastFrame = {};
    requestFrame();
    return pushResult(state, true);
}

int takeSelection(lua_State* state) noexcept {
    pushWorkspace(state, core.takeSelection());
    return 1;
}

struct LuaBinding {
    const char* name;
    PLUGIN_LUA_FN callback;
};

constexpr std::array luaBindings{
    LuaBinding{"prismStatus", prismStatus},
    LuaBinding{"setWorkspaces", setWorkspaces},
    LuaBinding{"begin", begin},
    LuaBinding{"update", update},
    LuaBinding{"finish", finish},
    LuaBinding{"tick", tick},
    LuaBinding{"snapshot", snapshot},
    LuaBinding{"reset", reset},
    LuaBinding{"takeSelection", takeSelection},
};

void unregisterBindings(HANDLE handle, std::size_t registered) noexcept {
    while (registered > 0) {
        const auto& binding = luaBindings[--registered];
        try {
            HyprlandAPI::removeLuaFunction(handle, PRISM_NAMESPACE, binding.name);
        } catch (...) {
            // Hyprland also removes callbacks registered to this handle on unload.
        }
    }
}

} // namespace

APICALL EXPORT std::string PLUGIN_API_VERSION() {
    return HYPRLAND_API_VERSION;
}

APICALL EXPORT PLUGIN_DESCRIPTION_INFO PLUGIN_INIT(HANDLE handle) {
    if (std::string_view{__hyprland_api_get_hash()} != BUILD_ABI.data()) {
        throw std::runtime_error("Prism ABI mismatch. Rebuild against the running Hyprland version.");
    }

    PLUGIN_DESCRIPTION_INFO description{
        "Prism",
        "Workspace overview",
        "MyArch contributors",
        "3.0.0",
    };

    std::size_t registered = 0;
    try {
        for (const auto& binding : luaBindings) {
            if (!HyprlandAPI::addLuaFunction(handle, PRISM_NAMESPACE, binding.name, binding.callback))
                throw std::runtime_error(std::string{"Prism could not register Lua function "} + binding.name);
            ++registered;
        }
    } catch (...) {
        unregisterBindings(handle, registered);
        throw;
    }

    pluginHandle = handle;
    try {
        renderListener = Event::bus()->m_events.render.stage.listen(onRenderStage);
    } catch (...) {
        unregisterBindings(handle, luaBindings.size());
        pluginHandle = nullptr;
        throw;
    }
    return description;
}

APICALL EXPORT void PLUGIN_EXIT() {
    renderListener.reset();
    renderer.reset();
    if (pluginHandle) {
        unregisterBindings(pluginHandle, luaBindings.size());
        pluginHandle = nullptr;
    }
    core = {};
}
