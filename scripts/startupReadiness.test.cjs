const assert = require("node:assert/strict");
const {readFileSync} = require("node:fs");
const {resolve} = require("node:path");
const {test} = require("node:test");
const {runInNewContext} = require("node:vm");
const ts = require(require.resolve("typescript", {paths: [resolve(__dirname, "../../siyuan/app")]}));

const source = readFileSync(resolve(__dirname, "../entry/src/main/ets/pages/Main.ets"), "utf8");
const text = (source.slice(0, source.indexOf("  build() {")) + source.slice(source.indexOf("  async aboutToAppear()")))
    .replace("struct Main", "class Main");
const parsed = ts.createSourceFile("Main.ts", text, ts.ScriptTarget.Latest, true);
const declaration = parsed.statements.find(ts.isClassDeclaration);
const names = ["scheduleMainPageWatchdog", "cancelMainPageWatchdog", "pollMainPageReadiness", "scheduleReadinessPoll", "removeBootPage"];
const methods = declaration.members.filter(member => names.includes(member.name?.getText(parsed)))
    .map(member => member.getText(parsed)).join("\n");
const compiled = ts.transpileModule("class Main {" + methods + "};globalThis.Main = Main;", {
    compilerOptions: {target: ts.ScriptTarget.ES2022},
}).outputText;
const flush = async () => { for (let i = 0; i < 12; i++) await Promise.resolve(); };

const setup = (serialized = true) => {
    const timers = new Map();
    let next = 0;
    const frontend = {ready: false, failed: false, stage: "interface", pathname: "/stage/build/mobile/"};
    const context = {MAIN_PAGE_LOAD_TIMEOUT: 30000, hilog: {error() {}},
        setTimeout: (callback, delay) => { const id = ++next; timers.set(id, {callback, delay}); return id; },
        clearTimeout: id => timers.delete(id)};
    runInNewContext(compiled, context);
    const state = new context.Main();
    Object.assign(state, {kernelBootCompleted: true, pageActive: true, mainPageReady: false,
        mainPageReadinessGeneration: 0, mainPageReadinessTimerID: -1, mainPageWatchdogID: -1,
        mainPageStartupStage: "", showBootPage: true, bootWebViewAttached: true, pendingBootURL: "boot",
        controller: {runJavaScript: script => {
            const result = runInNewContext(script, {window: {siyuan: {isReady: frontend.ready}}, location: {pathname: frontend.pathname},
                document: {documentElement: {getAttribute: name => name === "data-startup-stage" ? frontend.stage : frontend.failed ? "failed" : "loading"}}});
            return Promise.resolve(serialized ? JSON.stringify(result) : result);
        }}});
    const tick = async delay => {
        const entry = [...timers].find(([, timer]) => timer.delay === delay);
        assert.ok(entry, `missing ${delay} ms timer`);
        timers.delete(entry[0]);
        entry[1].callback();
        await flush();
    };
    return {state, frontend, timers, tick};
};

for (const serialized of [true, false]) test(`native boot waits for frontend completion (${serialized ? "JSON string" : "direct result"})`, async () => {
    const f = setup(serialized);
    f.state.scheduleMainPageWatchdog();
    await flush();
    assert.equal(f.state.showBootPage, true);
    assert.equal(f.state.mainPageReady, false);
    assert.equal(f.timers.size, 2);
    f.frontend.ready = true;
    await f.tick(250);
    assert.equal(f.state.showBootPage, false);
    assert.equal(f.state.mainPageReady, true);
    assert.equal(f.timers.size, 0);
});

for (const kind of ["failed", "auth"]) test(`${kind} pages become accessible without waiting for application completion`, async () => {
    const f = setup();
    if (kind === "failed") f.frontend.failed = true;
    else f.frontend.pathname = "/check-auth";
    f.state.scheduleMainPageWatchdog();
    await flush();
    assert.equal(f.state.showBootPage, false);
    assert.equal(f.state.mainPageReady, kind === "auth");
    assert.equal(f.timers.size, 0);
});

test("late results from an obsolete navigation cannot dismiss the current boot page", async () => {
    const f = setup();
    let resolveOld;
    f.state.controller.runJavaScript = () => new Promise(resolve => { resolveOld = resolve; });
    f.state.scheduleMainPageWatchdog();
    f.state.cancelMainPageWatchdog();
    resolveOld(JSON.stringify(JSON.stringify({ready: true, failed: false, stage: ""})));
    await flush();
    assert.equal(f.state.showBootPage, true);
    assert.equal(f.timers.size, 0);
});

test("navigation failures retry without removing the boot page", async () => {
    const f = setup();
    f.state.controller.runJavaScript = () => Promise.reject(new Error("navigation pending"));
    f.state.scheduleMainPageWatchdog();
    await flush();
    assert.equal(f.state.showBootPage, true);
    assert.equal(f.timers.size, 2);
    f.state.cancelMainPageWatchdog();
    assert.equal(f.timers.size, 0);
});

test("synchronous controller failures retry until attachment or timeout", async () => {
    const f = setup();
    f.state.controller.runJavaScript = () => { throw new Error("controller not attached"); };
    f.state.scheduleMainPageWatchdog();
    await flush();
    assert.equal(f.state.showBootPage, true);
    assert.equal(f.timers.size, 2);
});

test("stage changes replace the native startup deadline", async () => {
    const f = setup();
    f.state.scheduleMainPageWatchdog();
    await flush();
    const first = [...f.timers].find(([, timer]) => timer.delay === 30000)[0];
    f.frontend.stage = "storage";
    await f.tick(250);
    assert.equal(f.timers.has(first), false);
    assert.equal(f.state.mainPageStartupStage, "storage");
    assert.equal(f.timers.size, 2);
});

test("main HTML completion no longer marks the interface ready", () => {
    const pageEnd = source.slice(source.indexOf(".onPageEnd((event)"), source.indexOf(".onErrorReceive((event)"));
    assert.doesNotMatch(pageEnd, /mainPageReady\s*=\s*true/);
    assert.doesNotMatch(pageEnd, /removeBootPage\(/);
});
