const assert = require("node:assert/strict");
const { test } = require("node:test");
const { readFileSync } = require("node:fs");
const { resolve } = require("node:path");
const { runInNewContext } = require("node:vm");
const ts = require(require.resolve("typescript", {
    paths: [process.env.SIYUAN_APP_DIR || resolve(__dirname, "../../siyuan/app")],
}));

const createHarness = (saveCookie) => {
    const events = [];
    let timeout;
    const bundleManager = {
        BundleFlag: { GET_BUNDLE_INFO_WITH_APPLICATION: 0 },
        getBundleInfoForSelfSync: () => ({ versionName: "test", versionCode: 1, name: "test" }),
    };
    const mocks = {
        "@kit.AbilityKit": { bundleManager },
        "@kit.ArkWeb": { webview: { WebCookieManager: {
            saveCookieAsync: () => { events.push("save"); return saveCookie(); },
        } } },
        "@kit.PerformanceAnalysisKit": { hilog: {
            info() {}, error() { events.push("error"); },
        } },
        "./LANSyncMDNS": { LANSyncMDNS: { shared: { stop() {} } } },
        "@kit.BackgroundTasksKit": { backgroundTaskManager: { stopBackgroundRunning() {} } },
        "libentry.so": { default: {
            isHttpServing: () => false,
            exit: () => events.push("exit"),
        } },
    };
    // 转译实际退出实现，以模拟原生服务和定时器验证异步顺序。
    const source = readFileSync(resolve(__dirname, "../entry/src/main/ets/pages/Utils.ets"), "utf8")
        .replace("@Component", "").replace("export struct Utils", "export class Utils");
    const compiled = ts.transpileModule(source, {
        compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 },
    }).outputText;
    const module = { exports: {} };
    runInNewContext(compiled, {
        module, exports: module.exports, require: id => mocks[id] || {},
        setTimeout: (callback, delay) => {
            assert.equal(delay, 2000);
            timeout = callback;
            return 1;
        },
        clearTimeout: () => { timeout = undefined; },
    });
    const { Utils } = module.exports;
    Utils.getContext = () => ({ terminateSelf: () => events.push("terminate") });
    return { Utils, events, expire: () => timeout(), hasTimer: () => timeout !== undefined };
};

for (const method of ["exit", "exitFromAbilityDestroy"]) {
    test(`${method} waits for persistence and ignores duplicate exit requests`, async () => {
        let complete;
        const harness = createHarness(() => new Promise(resolve => { complete = resolve; }));
        const pending = harness.Utils[method]();
        await harness.Utils.exit();
        await harness.Utils.exitFromAbilityDestroy();
        assert.deepEqual(harness.events, ["save"]);
        complete();
        await pending;
        assert.deepEqual(harness.events, method === "exit" ? ["save", "terminate", "exit"] : ["save", "exit"]);
        assert.equal(harness.hasTimer(), false);
    });

    for (const synchronous of [false, true]) {
        test(`${method} continues after ${synchronous ? "synchronous" : "asynchronous"} persistence failure`, async () => {
            const harness = createHarness(() => {
                if (synchronous) {
                    throw new Error("Unavailable");
                }
                return Promise.reject(new Error("Unavailable"));
            });
            await harness.Utils[method]();
            assert.equal(harness.events.filter(event => event === "error").length, 1);
            assert.equal(harness.events.filter(event => event === "exit").length, 1);
            assert.equal(harness.hasTimer(), false);
        });
    }

    test(`${method} times out and ignores late persistence completion`, async () => {
        let complete;
        const harness = createHarness(() => new Promise(resolve => { complete = resolve; }));
        const pending = harness.Utils[method]();
        harness.expire();
        await pending;
        complete();
        await Promise.resolve();
        assert.equal(harness.events.filter(event => event === "error").length, 1);
        assert.equal(harness.events.filter(event => event === "exit").length, 1);
        assert.equal(harness.hasTimer(), false);
    });
}
