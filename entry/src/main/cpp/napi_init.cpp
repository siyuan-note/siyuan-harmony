#include "napi/native_api.h"
#include "string.h"
#include "thread"
#include "libkernel.h"

static char *value2String(napi_env env, napi_value value) {
    size_t len = 0;
    napi_get_value_string_utf8(env, value, nullptr, 0, &len);
    char *buf = new char[len + 1];
    napi_get_value_string_utf8(env, value, buf, len + 1, &len);
    return buf;
}

static napi_value StartKernel0(napi_env env, napi_callback_info info) {
    napi_value result;

    size_t argc = 2;
    napi_value args[2] = {nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    char *appDir = (value2String(env, args[0]));
    char *workspaceBaseDir = value2String(env, args[1]);

    std::thread t([appDir, workspaceBaseDir]() {
        StartKernel((char *)"harmony", appDir, workspaceBaseDir, (char *)"Asia/Shanghai", (char *)"127.0.0.1",
                    (char *)"zh_CN", (char *)"5.0");
    });
    t.join();

    return result;
}

static napi_value IsHttpServing0(napi_env env, napi_callback_info info) {
    napi_value result;

    GoUint8 ret;
    std::thread t([&ret]() {
        ret = IsHttpServing();
    });
    t.join();
    
    napi_create_uint32(env, ret, &result);
    return result;
}

static napi_value DisableFeature0(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    char *feature = value2String(env, args[0]);

    std::thread t([feature]() { DisableFeature(feature); });
    t.join();

    return NULL;
}

static napi_value Unzip0(napi_env env, napi_callback_info info) {
     napi_value result;

    size_t argc = 2;
    napi_value args[2] = {nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    char *zipPath = value2String(env, args[0]);
    char *dest = value2String(env, args[1]);

    std::thread t([zipPath, dest]() {
        Unzip(zipPath, dest);
    });
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
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    return exports;
}
EXTERN_C_END

static napi_module demoModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "entry",
    .nm_priv = ((void *)0),
    .reserved = {0},
};

extern "C" __attribute__((constructor)) void RegisterEntryModule(void) { napi_module_register(&demoModule); }
