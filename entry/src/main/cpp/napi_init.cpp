/*
 * SiYuan - 源于思考，饮水思源
 * Copyright (c) 2020-present, b3log.org
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Affero General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Affero General Public License for more details.
 *
 * You should have received a copy of the GNU Affero General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

#include "libkernel.h"
#include "napi/native_api.h"
#include "string.h"
#include "thread"
#include "future"

static char *value2String(napi_env env, napi_value value) {
    size_t len = 0;
    napi_get_value_string_utf8(env, value, nullptr, 0, &len);
    char *buf = new char[len + 1];
    napi_get_value_string_utf8(env, value, buf, len + 1, &len);

    return buf;
}

static napi_value StartKernel0(napi_env env, napi_callback_info info) {
    napi_value result;

    size_t argc = 4;
    napi_value args[4] = {nullptr, nullptr, nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    char *appDir = (value2String(env, args[0]));
    char *workspaceBaseDir = value2String(env, args[1]);
    char *localIPs = value2String(env, args[2]);
    char *osVer = value2String(env, args[3]);
    std::thread t([appDir, workspaceBaseDir, localIPs, osVer]() {
        StartKernel((char *)"harmony", appDir, workspaceBaseDir, (char *)"Asia/Shanghai", localIPs, (char *)"zh_CN",
                    osVer);
    });
    t.join();

    return result;
}

static napi_value IsHttpServing0(napi_env env, napi_callback_info info) {
    napi_value result;

    std::promise<GoUint8> promise;
    std::future<GoUint8> future = promise.get_future();
    std::thread t([&promise]() {
        GoUint8 ok = IsHttpServing();
        promise.set_value(ok);
    });
    t.join();

    GoUint8 ret = future.get();
    napi_create_uint32(env, ret, &result);

    return result;
}

static napi_value DisableFeature0(napi_env env, napi_callback_info info) {
    napi_value result;

    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    char *feature = value2String(env, args[0]);

    std::thread t([feature]() { DisableFeature(feature); });
    t.join();

    return result;
}

static napi_value Unzip0(napi_env env, napi_callback_info info) {
    napi_value result;

    size_t argc = 2;
    napi_value args[2] = {nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    char *zipPath = value2String(env, args[0]);
    char *dest = value2String(env, args[1]);

    std::thread t([zipPath, dest]() { Unzip(zipPath, dest); });
    t.join();

    return result;
}

static napi_value GetAssetAbsPath0(napi_env env, napi_callback_info info) {
    napi_value result;

    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    char *relativePath = value2String(env, args[0]);

    std::promise<char *> promise;
    std::future<char *> future = promise.get_future();
    std::thread t([&promise, relativePath]() {
        char *absPath = GetAssetAbsPath(relativePath);
        promise.set_value(absPath);
    });
    t.join();

    char *absPath = future.get();
    napi_create_string_utf8(env, absPath, strlen(absPath), &result);

    return result;
}

static napi_value GetCurrentWorkspacePath0(napi_env env, napi_callback_info info) {
    napi_value result;

    std::promise<char *> promise;
    std::future<char *> future = promise.get_future();
    std::thread t([&promise]() {
        char *workspace = GetCurrentWorkspacePath();
        promise.set_value(workspace);
    });
    t.join();

    char *workspace = future.get();
    napi_create_string_utf8(env, workspace, strlen(workspace), &result);

    return result;
}

static napi_value Exit0(napi_env env, napi_callback_info info) {
    napi_value result;

    std::thread t([]() { Exit(); });
    t.join();

    return result;
}

EXTERN_C_START
static napi_value Init(napi_env env, napi_value exports) {
    napi_property_descriptor desc[] = {
        {"startKernel", nullptr, StartKernel0, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"isHttpServing", nullptr, IsHttpServing0, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"disableFeature", nullptr, DisableFeature0, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"unzip", nullptr, Unzip0, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"getAssetAbsPath", nullptr, GetAssetAbsPath0, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"getCurrentWorkspacePath", nullptr, GetCurrentWorkspacePath0, nullptr, nullptr, nullptr, napi_default,
         nullptr},
        {"exit", nullptr, Exit0, nullptr, nullptr, nullptr, napi_default, nullptr},
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    return exports;
}
EXTERN_C_END

static napi_module kernelModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "entry",
    .nm_priv = ((void *)0),
    .reserved = {0},
};

extern "C" __attribute__((constructor)) void RegisterEntryModule(void) { napi_module_register(&kernelModule); }
