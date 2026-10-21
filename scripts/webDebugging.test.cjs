const assert = require("node:assert/strict");
const { test } = require("node:test");
const { readFileSync } = require("node:fs");
const { resolve } = require("node:path");
const { runInNewContext } = require("node:vm");
const ts = require(require.resolve("typescript", {
    paths: [process.env.SIYUAN_APP_DIR || resolve(__dirname, "../../siyuan/app")],
}));

const load = debug => {
    const calls = [];
    const exports = {};
    const modules = {
        "@kit.AbilityKit": { UIAbility: class { context = {}; } },
        "@kit.BasicServicesKit": {},
        "@kit.PerformanceAnalysisKit": { hilog: { info() {} } },
        "@kit.ArkUI": {},
        "@kit.ArkWeb": { webview: { WebviewController: {
            setWebDebuggingAccess: enabled => calls.push(["web-debugging", enabled]),
        } } },
        "BuildProfile": { __esModule: true, default: { DEBUG: debug } },
        "../pages/Utils": { Utils: {
            initAppearance: async () => {},
            isFirstRun: () => false,
        } },
    };
    const source = readFileSync(resolve(__dirname, "../entry/src/main/ets/entryability/EntryAbility.ets"), "utf8");
    runInNewContext(ts.transpileModule(source, {
        compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 },
    }).outputText, {
        exports,
        require: id => {
            assert.ok(modules[id], `unexpected dependency: ${id}`);
            return modules[id];
        },
        AppStorage: { setOrCreate() {} },
    });
    return { ability: new exports.default(), calls };
};

for (const debug of [true, false]) {
    test(`${debug ? "debug" : "release"} startup configures WebView debugging before loading its page`, async () => {
        const { ability, calls } = load(debug);
        ability.onCreate({}, {});
        await ability.onWindowStageCreate({
            getMainWindowSync: () => ({ setWindowLayoutFullScreen() {}, setSpecificSystemBarEnabled() {} }),
            loadContent: page => calls.push(["load", page]),
        });
        assert.deepEqual(calls, [["web-debugging", debug], ["load", "pages/Main"]]);
    });
}
