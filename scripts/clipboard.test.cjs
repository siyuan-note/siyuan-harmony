const assert = require("node:assert/strict");
const { test } = require("node:test");
const { readFileSync } = require("node:fs");
const { resolve } = require("node:path");
const { runInNewContext } = require("node:vm");
// 使用思源前端已安装的 TypeScript；非相邻检出可通过 SIYUAN_APP_DIR 指定 app 目录。
const ts = require(require.resolve("typescript", {
    paths: [process.env.SIYUAN_APP_DIR || resolve(__dirname, "../../siyuan/app")],
}));

const load = (name, mocks) => {
    const source = readFileSync(resolve(__dirname, "../entry/src/main/ets/pages", name + ".ets"), "utf8")
        .replace("@Component", "").replace("export struct JSHarmony", "export class JSHarmony");
    const compiled = ts.transpileModule(source, {
        compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 },
    }).outputText;
    const module = { exports: {} };
    runInNewContext(compiled, { module, exports: module.exports, require: id => mocks[id] || {} });
    return module.exports;
};

const clipboard = load("Clipboard", {
    "@kit.ArkTS": { util: {
        Base64Helper: class {
            encodeToStringSync(bytes) { return Buffer.from(bytes).toString("base64"); }
            decodeSync(value) { return Buffer.from(value, "base64"); }
        },
        TextEncoder: class { encodeInto(value) { return new TextEncoder().encode(value); } },
        TextDecoder: class {
            decodeWithStream(value) { return new TextDecoder("utf-8", { fatal: true }).decode(value); }
        },
    } },
});

const createHarness = () => {
    let data;
    let fail = false;
    const pasteboard = {
        MIMETYPE_TEXT_HTML: "text/html", MIMETYPE_TEXT_PLAIN: "text/plain",
        createData: (type, value) => {
            const records = new Map([[type, value]]);
            return {
                addRecord: (mime, content) => records.set(mime, content),
                getPrimaryHtml: () => records.get("text/html"),
                getPrimaryText: () => records.get("text/plain"),
            };
        },
        getSystemPasteboard: () => ({
            setDataSync: value => { if (fail) { throw new Error("Denied"); } data = value; },
            getDataSync: () => data,
        }),
    };
    const { JSHarmony } = load("JSHarmony", {
        "./Clipboard": clipboard,
        "@kit.BasicServicesKit": { pasteboard },
        "@ohos.hilog": { default: { error() {} } },
    });
    return { api: new JSHarmony(), fail: () => { fail = true; }, getData: () => data };
};

test("native rich clipboard contains independent plain text and hidden internal HTML", () => {
    const harness = createHarness();
    const plain = "剪切实验 😀";
    const html = `<p>${plain}</p>`;
    const internal = `<div data-type="NodeParagraph">${plain}</div>`;
    assert.equal(harness.api.writeSiYuanHTMLClipboard(plain, html, internal), true);
    assert.equal(harness.api.readClipboard(), plain);
    assert.equal(harness.api.readSiYuanHTMLClipboard(), internal);
    const stored = harness.getData().getPrimaryHtml();
    assert.equal(stored.replace(/<!--.*?-->/g, ""), html);
    assert.equal(harness.api.readHTMLClipboard(), stored);
});

test("native reader converts legacy HTML and preserves ambiguous or literal markers", () => {
    const harness = createHarness();
    const html = "<p>正文</p>";
    const internal = '<div data-type="NodeParagraph">正文</div>';
    harness.api.writeHTMLClipboard("正文", html + "__@text/siyuan@__" + internal);
    assert.equal(harness.api.readHTMLClipboard(), clipboard.buildClipboardHTML(html, internal));
    assert.equal(harness.api.readSiYuanHTMLClipboard(), internal);
    for (const value of ["<p>__@text/siyuan@__</p>", html + "__@text/siyuan@__" + internal + "__@text/siyuan@__"]) {
        assert.equal(clipboard.parseClipboardHTML(value).textHTML, value);
        assert.equal(clipboard.parseClipboardHTML(value).siyuanHTML, "");
    }
});

test("native write failure is reported and preserves the previous clipboard", () => {
    const harness = createHarness();
    assert.equal(harness.api.writeClipboard("保留内容"), true);
    harness.fail();
    assert.equal(harness.api.writeHTMLClipboard("新内容", "<p>新内容</p>"), false);
    assert.equal(harness.api.writeSiYuanHTMLClipboard("新内容", "<p>新内容</p>", "<div>新内容</div>"), false);
    assert.equal(harness.api.writeClipboard("新内容"), false);
    assert.equal(harness.api.readClipboard(), "保留内容");
});

test("invalid UTF-8 metadata preserves external HTML", () => {
    const html = "<!--data-siyuan='/w=='--><p>保留内容</p>";
    assert.equal(clipboard.parseClipboardHTML(html).textHTML, html);
    assert.equal(clipboard.parseClipboardHTML(html).siyuanHTML, "");
});
