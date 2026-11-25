const assert = require("node:assert/strict");
const { readFileSync } = require("node:fs");
const { resolve } = require("node:path");
const { test } = require("node:test");
const { runInNewContext } = require("node:vm");
const ts = require(require.resolve("typescript", {
    paths: [process.env.SIYUAN_APP_DIR || resolve(__dirname, "../../siyuan/app")],
}));

const source = ts.transpileModule(readFileSync(resolve(__dirname, "../entry/src/main/ets/pages/MainWindowControls.ets"), "utf8"), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 },
}).outputText;
const desktop = "http://127.0.0.1:6806/stage/build/desktop/?r=abc";
const status = { FLOATING: 4, MAXIMIZE: 2, FULL_SCREEN: 1 };

const createControls = () => {
    const events = new Map();
    const actions = [];
    const scripts = [];
    const module = { exports: {} };
    const timers = new Map();
    let timer = 0;
    runInNewContext(source, {
        module, exports: module.exports,
        require: name => name === "@kit.ArkUI" ? { window: { WindowStatusType: status } } : { hilog: { warn() {} } },
        TouchType: { Down: 0, Up: 1 },
        setTimeout: callback => { timers.set(++timer, callback); return timer; },
        clearTimeout: id => timers.delete(id),
    });
    const state = { page: desktop, frame: desktop, status: status.FLOATING, rect: { right: 6, top: 3, width: 128, height: 34 },
        decor: true, available: true, windowWidth: 1600 };
    const wnd = {
        getWindowStatus: () => state.status,
        getTitleButtonRect: () => {
            if (!state.available) throw Object.assign(new Error("unsupported"), { code: 801 });
            return state.rect;
        },
        getWindowProperties: () => ({ windowRect: { width: state.windowWidth } }),
        getWindowDecorVisible: () => state.decor,
        setWindowDecorVisible: visible => { state.decor = visible; actions.push(visible); },
        on: (name, callback) => events.set(name, callback),
        off: (name, callback) => { assert.equal(events.get(name), callback); events.delete(name); },
        startMoving: async () => { actions.push("move"); },
    };
    const web = {
        getUrl: () => state.page,
        getLastJavascriptProxyCallingFrameUrl: () => state.frame,
        registerJavaScriptProxy: (_object, name, methods, _async, permission) => actions.push([name, Array.from(methods), JSON.parse(permission)]),
        deleteJavaScriptRegister: name => actions.push(name),
        runJavaScript: async script => { scripts.push(script); },
    };
    const controls = new module.exports.MainWindowControls(wnd, web, { px2vp: value => value / 2 });
    const drain = () => {
        for (const [id, callback] of timers) {
            timers.delete(id);
            callback();
        }
    };
    const touch = (x, y, type = 0) => controls.handleTouch({ type, changedTouches: [{ windowX: x, windowY: y }] });
    return { controls, state, events, scripts, actions, drain, touch, wnd };
};

test("workspace desktop negotiates native title geometry and restores decorations on navigation", () => {
    const { controls, state, events, scripts, actions, drain } = createControls();
    controls.register();
    assert.deepEqual(actions.shift(), ["SiYuanHarmonyWindowControls", ["connect", "setDragArea"], {
        javascriptProxyPermission: { urlPermissionList: [{ scheme: "http", host: "127.0.0.1", port: "6806", path: "" }] },
    }]);
    assert.deepEqual(JSON.parse(controls.connect()), { windowWidth: 800, rightInset: 134, bottom: 37, movable: true });
    assert.deepEqual(actions, [false]);
    state.status = status.MAXIMIZE;
    state.windowWidth = 2048;
    state.rect.width = 150;
    events.get("windowSizeChange")();
    events.get("windowTitleButtonRectChange")();
    events.get("windowStatusChange")();
    drain();
    assert.equal(scripts.length, 1);
    assert.match(scripts[0], /"windowWidth":1024,"rightInset":156,"bottom":37,"movable":false/);
    state.status = status.FULL_SCREEN;
    events.get("windowStatusChange")();
    drain();
    assert.match(scripts.at(-1), /detail: null/);
    assert.deepEqual(actions, [false, true]);
    state.status = status.FLOATING;
    events.get("windowStatusChange")();
    drain();
    assert.equal(state.decor, false);
    controls.dispose();
    assert.equal(state.decor, true);
    assert.equal(events.size, 0);
    assert.deepEqual(actions.slice(-2), [true, "SiYuanHarmonyWindowControls"]);
});

test("unsupported windows and unrelated callers keep the system title bar", () => {
    const { controls, state, events, actions, wnd } = createControls();
    state.frame = "http://127.0.0.1:6806/assets/frame.html";
    assert.equal(controls.connect(), "null");
    assert.equal(events.size, 0);
    state.frame = state.page = "http://127.0.0.1:6806/stage/build/mobile/";
    assert.equal(controls.connect(), "null");
    state.frame = state.page = desktop;
    state.available = false;
    assert.equal(controls.connect(), "null");
    assert.deepEqual(actions, []);
    state.available = true;
    wnd.setWindowDecorVisible = () => {};
    assert.equal(controls.connect(), "null");
    assert.equal(state.decor, true);
});

test("only a native down event inside the current floating-window drag area starts movement", () => {
    const { controls, state, events, touch, actions, drain } = createControls();
    controls.connect();
    controls.setDragArea(650, 0, 680, 37);
    touch(655, 10);
    assert.deepEqual(actions, [false]);
    controls.setDragArea(630, 0, 655, 37);
    touch(640, 20, 1);
    touch(628, 20);
    touch(640, 20);
    assert.deepEqual(actions, [false, "move"]);
    state.status = status.MAXIMIZE;
    events.get("windowStatusChange")();
    drain();
    touch(640, 20);
    assert.deepEqual(actions, [false, "move"]);
});
