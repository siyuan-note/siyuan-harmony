const assert = require("node:assert/strict");
const { test } = require("node:test");
const { readFileSync } = require("node:fs");
const { resolve } = require("node:path");
const { runInNewContext } = require("node:vm");
const ts = require(require.resolve("typescript", {
    paths: [process.env.SIYUAN_APP_DIR || resolve(__dirname, "../../siyuan/app")],
}));
const pages = resolve(__dirname, "../entry/src/main/ets/pages");

const deferred = () => {
    let resolve;
    let reject;
    const promise = new Promise((yes, no) => { resolve = yes; reject = no; });
    return { promise, resolve, reject };
};
const flush = async () => {
    for (let index = 0; index < 12; index++) {
        await Promise.resolve();
    }
};
const createHarness = () => {
    const events = [];
    const timers = [];
    const state = { busy: false, serving: false, terminating: false, probeError: undefined };
    const napi = {
        isHttpServing: () => state.serving,
        isKernelPortAvailable: () => {
            if (state.probeError) { throw state.probeError; }
            return !state.busy;
        },
        startKernel: (...args) => { events.push(["kernel", ...args]); state.serving = true; },
    };
    const hilog = { info() {}, debug() {}, error() { events.push(["error"]); } };
    const context = {
        setTimeout: (callback, delay) => { timers.push({ callback, delay }); return timers.length; },
        napi, hilog,
    };
    const evaluate = source => {
        const module = { exports: {} };
        const compiled = ts.transpileModule(source, { compilerOptions: {
            module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022,
        } }).outputText;
        runInNewContext(compiled, { ...context, module, exports: module.exports,
            require: id => id === "libentry.so" ? { default: napi } : { hilog } });
        return module.exports;
    };
    const { kernelStartup } = evaluate(readFileSync(resolve(pages, "KernelStartup.ets"), "utf8"));
    let want = () => Promise.resolve({});
    let background = () => Promise.resolve();
    context.kernelStartup = kernelStartup;
    context.getContext = () => ({});
    context.Utils = {
        bundleName: "test-app", isTerminating: () => state.terminating,
        getIPAddressList: () => "127.0.0.1",
        exit: () => { events.push(["exit"]); state.terminating = true; },
    };
    context.deviceInfo = { osFullName: "OpenHarmony-test" };
    context.wantAgent = {
        OperationType: { START_ABILITY: 0 }, WantAgentFlags: { UPDATE_PRESENT_FLAG: 0 },
        getWantAgent: () => { events.push(["want"]); return want(); },
    };
    context.backgroundTaskManager = {
        BackgroundMode: { DATA_TRANSFER: 0 },
        startBackgroundRunning: () => { events.push(["background"]); return background(); },
    };
    context.LANSyncMDNS = { shared: { start: () => events.push(["LAN"]) } };
    context.events = events;
    // 使用实际启动方法，避免测试替代实现掩盖生命周期回调的顺序问题。
    const mainSource = readFileSync(resolve(pages, "Main.ets"), "utf8");
    const startupMethods = mainSource.slice(mainSource.indexOf("  private async startKernel("),
        mainSource.indexOf("  private loadBootPage("));
    const httpMethod = mainSource.slice(mainSource.indexOf("  async waitFotKernelHttpServing("),
        mainSource.indexOf("  async sleep("));
    const recoveryMethod = mainSource.slice(mainSource.indexOf("  private scheduleWebViewRecovery("),
        mainSource.indexOf("  async waitFotKernelHttpServing("));
    assert.ok(startupMethods.includes("kernelStartup.start"));
    const { Main } = evaluate(`export class Main {
        pageActive = true;
        kernelStartInProgress = false;
        kernelPortWaiting = false;
        loadBootPage() { events.push(["boot-page"]); }
        startBootProgressMonitor() { events.push(["progress"]); }
        listenKeyboard() { events.push(["keyboard"]); }
        revokeMapBoundary() { events.push(["revoke"]); }
        navigateToMainPage() { events.push(["main-page"]); }
        async sleep(delay) { await new Promise(resolve => setTimeout(resolve, delay)); }
        ${startupMethods}
        ${httpMethod}
        ${recoveryMethod}
    }`);
    return { state, events, timers, napi, kernelStartup, Main,
        setWant: value => { want = value; }, setBackground: value => { background = value; },
        tick: async delay => {
            const timer = timers.shift();
            assert.ok(timer, "expected a pending timer");
            if (delay !== undefined) { assert.equal(timer.delay, delay); }
            timer.callback();
            await flush();
        } };
};
const kernelEvents = harness => harness.events.filter(event => event[0] === "kernel");

test("a free port starts immediately without a port-wait timer", async () => {
    const h = createHarness();
    const started = await h.kernelStartup.start(() => h.napi.startKernel("app"), () => true, () => {});
    assert.equal(started, true);
    assert.equal(kernelEvents(h).length, 1);
    assert.equal(h.timers.length, 0);
});

test("a port occupied for 30 seconds delays every kernel side effect until release", async () => {
    const h = createHarness();
    h.state.busy = true;
    const main = new h.Main();
    const pending = main.startKernel("app", "workspace");
    await flush();
    for (let index = 0; index < 150; index++) {
        assert.equal(main.kernelPortWaiting, true);
        assert.equal(kernelEvents(h).length, 0);
        assert.equal(h.events.some(event => event[0] === "LAN" || event[0] === "boot-page"), false);
        await h.tick(200);
    }
    h.state.busy = false;
    await h.tick(200);
    await h.tick(10);
    await pending;
    assert.deepEqual(kernelEvents(h), [["kernel", "app", "workspace", "127.0.0.1", "test"]]);
    assert.equal(main.kernelPortWaiting, false);
    assert.equal(h.events.some(event => event[0] === "boot-page"), true);
    assert.equal(h.events.some(event => event[0] === "exit"), false);
});

test("concurrent startup requests initialize the process only once", async () => {
    const h = createHarness();
    h.state.busy = true;
    const start = () => h.napi.startKernel("app");
    const first = h.kernelStartup.start(start, () => true, () => {});
    const second = h.kernelStartup.start(start, () => true, () => {});
    assert.equal(h.timers.length, 1);
    h.state.busy = false;
    await h.tick(200);
    assert.equal(await first, true);
    assert.equal(await second, true);
    assert.equal(kernelEvents(h).length, 1);
});

test("destroying a waiting page cancels its startup and clears its waiting state", async () => {
    const h = createHarness();
    h.state.busy = true;
    const main = new h.Main();
    const pending = main.startKernel("app", "workspace");
    await flush();
    main.pageActive = false;
    h.state.busy = false;
    await h.tick(200);
    await pending;
    assert.equal(kernelEvents(h).length, 0);
    assert.equal(main.kernelPortWaiting, false);
    assert.equal(h.timers.length, 0);
});

test("process termination cancels startup even before page disappearance", async () => {
    const h = createHarness();
    h.state.busy = true;
    const main = new h.Main();
    const pending = main.startKernel("app", "workspace");
    await flush();
    h.state.terminating = true;
    await h.tick(200);
    await pending;
    assert.equal(kernelEvents(h).length, 0);
    assert.equal(h.events.some(event => event[0] === "exit"), false);
});

test("a new page can resume after an older startup request is cancelled", async () => {
    const h = createHarness();
    let firstActive = true;
    h.state.busy = true;
    const first = h.kernelStartup.start(() => h.napi.startKernel("old"), () => firstActive, () => {});
    const second = h.kernelStartup.start(() => h.napi.startKernel("new"), () => true, () => {});
    firstActive = false;
    h.state.busy = false;
    await h.tick(200);
    assert.equal(await first, false);
    assert.equal(await second, true);
    assert.deepEqual(kernelEvents(h), [["kernel", "new"]]);
});

test("a reused process does not wait on its own listener or start a second background task", async () => {
    const h = createHarness();
    h.state.serving = true;
    h.state.busy = true;
    const main = new h.Main();
    const pending = main.startKernel("app", "workspace");
    await flush();
    await h.tick(10);
    await pending;
    assert.equal(kernelEvents(h).length, 0);
    assert.equal(h.events.some(event => event[0] === "background"), false);
    assert.equal(h.events.some(event => event[0] === "boot-page"), true);
});

for (const phase of ["want", "background"]) {
    test(`cancellation while ${phase} authorization is pending prevents later kernel startup`, async () => {
        const h = createHarness();
        const authorization = deferred();
        if (phase === "want") { h.setWant(() => authorization.promise); }
        else { h.setBackground(() => authorization.promise); }
        const main = new h.Main();
        const pending = main.startKernel("app", "workspace");
        await flush();
        main.pageActive = false;
        authorization.resolve({});
        await pending;
        assert.equal(kernelEvents(h).length, 0);
        assert.equal(h.timers.length, 0);
    });
}

test("unexpected probe errors never proceed with kernel initialization", async () => {
    const h = createHarness();
    h.state.probeError = new Error("EMFILE");
    const main = new h.Main();
    await main.startKernel("app", "workspace");
    assert.equal(kernelEvents(h).length, 0);
    assert.equal(h.events.some(event => event[0] === "exit"), true);
    assert.equal(main.kernelStartInProgress, false);
});

test("closing a page while HTTP serving starts prevents late WebView navigation", async () => {
    const h = createHarness();
    const main = new h.Main();
    const pending = main.startKernel("app", "workspace");
    await flush();
    main.pageActive = false;
    await h.tick(10);
    await pending;
    assert.equal(kernelEvents(h).length, 1);
    assert.equal(h.events.some(event => event[0] === "boot-page"), false);
});

test("renderer recovery during the port wait never loads the previous process boot page", async () => {
    const h = createHarness();
    h.state.busy = true;
    const main = new h.Main();
    const pending = main.startKernel("app", "workspace");
    main.scheduleWebViewRecovery();
    await flush();
    await h.tick(300);
    assert.equal(h.events.some(event => event[0] === "boot-page" || event[0] === "progress"), false);
    assert.equal(main.kernelPortWaiting, true);
    h.state.busy = false;
    await h.tick(200);
    await h.tick(10);
    await pending;
    assert.equal(h.events.some(event => event[0] === "boot-page"), true);
});

test("renderer recovery still reloads the boot page when this process is serving", async () => {
    const h = createHarness();
    h.state.serving = true;
    const main = new h.Main();
    main.scheduleWebViewRecovery();
    await h.tick(300);
    assert.equal(h.events.some(event => event[0] === "boot-page"), true);
    assert.equal(h.events.some(event => event[0] === "progress"), true);
});
