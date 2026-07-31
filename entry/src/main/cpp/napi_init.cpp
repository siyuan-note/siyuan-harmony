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
#include <cstdlib>
#include <string>

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
        StartKernel((char *)"harmony", appDir, workspaceBaseDir, (char *)"Asia/Shanghai", localIPs, (char *)"zh-CN",
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

static napi_value Html2Markdown0(napi_env env, napi_callback_info info) {
    napi_value result;

    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    char *html = value2String(env, args[0]);

    std::promise<char *> promise;
    std::future<char *> future = promise.get_future();
    std::thread t([&promise, html]() {
        char *md = HTML2Markdown(html);
        promise.set_value(md);
    });
    t.join();

    char *md = future.get();
    napi_create_string_utf8(env, md, strlen(md), &result);

    return result;
}

static napi_value FilepathBase0(napi_env env, napi_callback_info info) {
    napi_value result;

    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    char *path = value2String(env, args[0]);

    std::promise<char *> promise;
    std::future<char *> future = promise.get_future();
    std::thread t([&promise, path]() {
        char *base = FilepathBase(path);
        promise.set_value(base);
    });
    t.join();

    char *base = future.get();
    napi_create_string_utf8(env, base, strlen(base), &result);

    return result;
}

static napi_value FilterUploadFileName0(napi_env env, napi_callback_info info) {
    napi_value result;

    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    char *name = value2String(env, args[0]);

    std::promise<char *> promise;
    std::future<char *> future = promise.get_future();
    std::thread t([&promise, name]() {
        char *filtered = FilterUploadFileName(name);
        promise.set_value(filtered);
    });
    t.join();

    char *filtered = future.get();
    napi_create_string_utf8(env, filtered, strlen(filtered), &result);

    return result;
}

static napi_value AssetName0(napi_env env, napi_callback_info info) {
    napi_value result;

    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    char *name = value2String(env, args[0]);

    std::promise<char *> promise;
    std::future<char *> future = promise.get_future();
    std::thread t([&promise, name]() {
        char *asset = AssetName(name);
        promise.set_value(asset);
    });
    t.join();

    char *asset = future.get();
    napi_create_string_utf8(env, asset, strlen(asset), &result);

    return result;
}

static napi_value GetExportFilePath0(napi_env env, napi_callback_info info) {
    napi_value result;

    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    char *exportPath = value2String(env, args[0]);

    std::promise<char *> promise;
    std::future<char *> future = promise.get_future();
    std::thread t([&promise, exportPath]() {
        char *absPath = GetExportFilePath(exportPath);
        promise.set_value(absPath);
    });
    t.join();

    char *absPath = future.get();
    if (absPath) {
        napi_create_string_utf8(env, absPath, strlen(absPath), &result);
    } else {
        napi_get_undefined(env, &result);
    }

    return result;
}

struct AcquireExportContext {
    napi_async_work work;
    napi_deferred deferred;
    char *exportPath;
    char *lease;
};

static void AcquireExportExecute(napi_env env, void *data) {
    auto *context = static_cast<AcquireExportContext *>(data);
    context->lease = AcquireExportFile(context->exportPath);
}

static void ReleaseExportLeaseJSON(const char *leaseJSON) {
    if (!leaseJSON) {
        return;
    }
    std::string json(leaseJSON);
    const std::string key = "\"leaseID\"";
    size_t position = json.find(key);
    if (position == std::string::npos) {
        return;
    }
    position = json.find(':', position + key.length());
    if (position == std::string::npos) {
        return;
    }
    position = json.find('"', position + 1);
    if (position == std::string::npos) {
        return;
    }
    const size_t end = json.find('"', position + 1);
    if (end == std::string::npos || end == position + 1) {
        return;
    }
    std::string leaseID = json.substr(position + 1, end - position - 1);
    ReleaseExportFile(const_cast<char *>(leaseID.c_str()));
}

static void AcquireExportComplete(napi_env env, napi_status status, void *data) {
    auto *context = static_cast<AcquireExportContext *>(data);
    napi_value result;
    bool leaseTransferred = false;
    if (status == napi_ok && context->lease) {
        if (napi_create_string_utf8(env, context->lease, strlen(context->lease), &result) != napi_ok) {
            ReleaseExportLeaseJSON(context->lease);
            napi_get_undefined(env, &result);
        } else {
            leaseTransferred = true;
        }
    } else {
        ReleaseExportLeaseJSON(context->lease);
        napi_get_undefined(env, &result);
    }
    if (napi_resolve_deferred(env, context->deferred, result) != napi_ok && leaseTransferred) {
        ReleaseExportLeaseJSON(context->lease);
    }
    free(context->lease);
    napi_delete_async_work(env, context->work);
    delete[] context->exportPath;
    delete context;
}

static napi_value AcquireExportFile0(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    auto *context = new AcquireExportContext();
    context->exportPath = value2String(env, args[0]);
    context->lease = nullptr;

    napi_value promise;
    napi_create_promise(env, &context->deferred, &promise);
    napi_value resourceName;
    napi_create_string_utf8(env, "AcquireExportFile", NAPI_AUTO_LENGTH, &resourceName);
    napi_create_async_work(env, nullptr, resourceName, AcquireExportExecute, AcquireExportComplete, context,
                           &context->work);
    napi_queue_async_work(env, context->work);
    return promise;
}

static napi_value ReleaseExportFile0(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    char *leaseID = value2String(env, args[0]);
    ReleaseExportFile(leaseID);
    delete[] leaseID;

    napi_value result;
    napi_get_undefined(env, &result);
    return result;
}

static napi_value GetExportFileName0(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    char *exportPath = value2String(env, args[0]);
    char *name = GetExportFileName(exportPath);
    delete[] exportPath;

    napi_value result;
    if (name) {
        napi_create_string_utf8(env, name, strlen(name), &result);
        free(name);
    } else {
        napi_get_undefined(env, &result);
    }
    return result;
}

static napi_value Language0(napi_env env, napi_callback_info info) {
    napi_value result;

    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    int32_t num;
    napi_get_value_int32(env, args[0], &num);

    std::promise<char *> promise;
    std::future<char *> future = promise.get_future();
    std::thread t([&promise, num]() {
        char *msg = Language((GoInt)num);
        promise.set_value(msg);
    });
    t.join();

    char *msg = future.get();
    napi_create_string_utf8(env, msg, strlen(msg), &result);

    return result;
}

static napi_value ShowMsg0(napi_env env, napi_callback_info info) {
    napi_value result;

    size_t argc = 2;
    napi_value args[2] = {nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    char *msg = value2String(env, args[0]);
    int32_t timeout;
    napi_get_value_int32(env, args[1], &timeout);

    std::thread t([msg, timeout]() { ShowMsg(msg, (GoInt)timeout); });
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
        {"html2Markdown", nullptr, Html2Markdown0, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"filepathBase", nullptr, FilepathBase0, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"filterUploadFileName", nullptr, FilterUploadFileName0, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"assetName", nullptr, AssetName0, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"getExportFilePath", nullptr, GetExportFilePath0, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"getExportFileName", nullptr, GetExportFileName0, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"acquireExportFile", nullptr, AcquireExportFile0, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"releaseExportFile", nullptr, ReleaseExportFile0, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"language", nullptr, Language0, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"showMsg", nullptr, ShowMsg0, nullptr, nullptr, nullptr, napi_default, nullptr},
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
