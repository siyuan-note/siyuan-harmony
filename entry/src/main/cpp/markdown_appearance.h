#pragma once

#include "napi/native_api.h"
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <string>

extern "C" uint64_t NewMarkdownAppearance(char *, char *) __attribute__((weak));
extern "C" char *ResolveMarkdownAppearance(uint64_t, char *, char *) __attribute__((weak));
extern "C" char *ReadMarkdownAppearanceFont(uint64_t, char *, int *) __attribute__((weak));
extern "C" void CloseMarkdownAppearance(uint64_t) __attribute__((weak));

static bool AppearanceString(napi_env env, napi_value value, std::string &out, size_t maximum) {
    napi_valuetype type;
    size_t size = 0;
    if (napi_typeof(env, value, &type) != napi_ok || type != napi_string ||
        napi_get_value_string_utf8(env, value, nullptr, 0, &size) != napi_ok || size > maximum) return false;
    out.resize(size + 1);
    if (napi_get_value_string_utf8(env, value, &out[0], size + 1, &size) != napi_ok) return false;
    out.resize(size);
    return out.find('\0') == std::string::npos;
}

static uint64_t AppearanceHandle(napi_env env, napi_value value) {
    std::string text;
    if (!AppearanceString(env, value, text, 20) || text.empty() || text.find_first_not_of("0123456789") != std::string::npos) return 0;
    try { return std::stoull(text); } catch (...) { return 0; }
}

static napi_value NewMarkdownAppearance0(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2] = {nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    std::string config, root;
    if (argc != 2 || !AppearanceString(env, args[0], config, 32768) || !AppearanceString(env, args[1], root, 32768)) {
        napi_throw_type_error(env, nullptr, "Invalid appearance roots"); return nullptr;
    }
    uint64_t handle = 0;
    if (NewMarkdownAppearance && ResolveMarkdownAppearance && ReadMarkdownAppearanceFont && CloseMarkdownAppearance) {
        handle = NewMarkdownAppearance(const_cast<char *>(config.c_str()), const_cast<char *>(root.c_str()));
    }
    napi_value result;
    const std::string text = handle ? std::to_string(handle) : "";
    napi_create_string_utf8(env, text.c_str(), text.size(), &result);
    return result;
}

struct MarkdownAppearanceWork {
    napi_async_work work = nullptr;
    napi_deferred deferred = nullptr;
    uint64_t handle = 0;
    bool font = false;
    std::string first, second;
    char *output = nullptr;
    int length = 0;
};

static void ExecuteMarkdownAppearance(napi_env, void *data) {
    auto *work = static_cast<MarkdownAppearanceWork *>(data);
    if (work->font) {
        if (ReadMarkdownAppearanceFont) work->output = ReadMarkdownAppearanceFont(work->handle, const_cast<char *>(work->first.c_str()), &work->length);
    } else if (ResolveMarkdownAppearance) {
        work->output = ResolveMarkdownAppearance(work->handle, const_cast<char *>(work->first.c_str()), const_cast<char *>(work->second.c_str()));
    }
}

static void CompleteMarkdownAppearance(napi_env env, napi_status status, void *data) {
    auto *work = static_cast<MarkdownAppearanceWork *>(data);
    napi_value result = nullptr;
    bool valid = status == napi_ok && work->output;
    if (valid && work->font) {
        valid = work->length >= 4 && work->length <= 64 * 1024 * 1024;
        void *bytes = nullptr;
        if (valid) valid = napi_create_arraybuffer(env, work->length, &bytes, &result) == napi_ok;
        if (valid) std::memcpy(bytes, work->output, work->length);
    } else if (valid) {
        valid = napi_create_string_utf8(env, work->output, NAPI_AUTO_LENGTH, &result) == napi_ok;
    }
    if (work->output) std::free(work->output);
    if (valid) napi_resolve_deferred(env, work->deferred, result);
    else {
        napi_value message, error;
        napi_create_string_utf8(env, "Workspace appearance unavailable", NAPI_AUTO_LENGTH, &message);
        napi_create_error(env, nullptr, message, &error);
        napi_reject_deferred(env, work->deferred, error);
    }
    if (work->work) napi_delete_async_work(env, work->work);
    delete work;
}

static napi_value QueueMarkdownAppearance(napi_env env, napi_callback_info info, bool font) {
    size_t argc = 3;
    napi_value args[3] = {nullptr, nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    auto *work = new MarkdownAppearanceWork();
    work->font = font;
    if (argc != (font ? 2 : 3) || !(work->handle = AppearanceHandle(env, args[0])) ||
        !AppearanceString(env, args[1], work->first, font ? 128 : 131072) ||
        (!font && !AppearanceString(env, args[2], work->second, 131072))) {
        delete work;
        napi_throw_type_error(env, nullptr, "Invalid appearance request"); return nullptr;
    }
    napi_value promise, name;
    napi_create_promise(env, &work->deferred, &promise);
    napi_create_string_utf8(env, "MarkdownAppearance", NAPI_AUTO_LENGTH, &name);
    if (napi_create_async_work(env, nullptr, name, ExecuteMarkdownAppearance, CompleteMarkdownAppearance, work, &work->work) != napi_ok ||
        napi_queue_async_work(env, work->work) != napi_ok) {
        CompleteMarkdownAppearance(env, napi_generic_failure, work);
    }
    return promise;
}

static napi_value ResolveMarkdownAppearance0(napi_env env, napi_callback_info info) {
    return QueueMarkdownAppearance(env, info, false);
}
static napi_value ReadMarkdownAppearanceFont0(napi_env env, napi_callback_info info) {
    return QueueMarkdownAppearance(env, info, true);
}
struct MarkdownAppearanceCloseWork {
    napi_async_work work = nullptr;
    uint64_t handle = 0;
};
static void ExecuteCloseMarkdownAppearance(napi_env, void *data) {
    auto *work = static_cast<MarkdownAppearanceCloseWork *>(data);
    if (CloseMarkdownAppearance) CloseMarkdownAppearance(work->handle);
}
static void CompleteCloseMarkdownAppearance(napi_env env, napi_status, void *data) {
    auto *work = static_cast<MarkdownAppearanceCloseWork *>(data);
    napi_delete_async_work(env, work->work);
    delete work;
}
static napi_value CloseMarkdownAppearance0(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value arg = nullptr;
    napi_get_cb_info(env, info, &argc, &arg, nullptr, nullptr);
    const uint64_t handle = argc == 1 ? AppearanceHandle(env, arg) : 0;
    if (handle && CloseMarkdownAppearance) {
        auto *work = new MarkdownAppearanceCloseWork();
        work->handle = handle;
        napi_value name;
        napi_create_string_utf8(env, "CloseMarkdownAppearance", NAPI_AUTO_LENGTH, &name);
        if (napi_create_async_work(env, nullptr, name, ExecuteCloseMarkdownAppearance, CompleteCloseMarkdownAppearance, work, &work->work) != napi_ok ||
            napi_queue_async_work(env, work->work) != napi_ok) {
            if (work->work) napi_delete_async_work(env, work->work);
            delete work;
            CloseMarkdownAppearance(handle);
        }
    }
    napi_value result;
    napi_get_undefined(env, &result);
    return result;
}
