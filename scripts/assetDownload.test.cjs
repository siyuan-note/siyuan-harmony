const assert = require("node:assert/strict");
const { test } = require("node:test");
const { readFileSync } = require("node:fs");
const { resolve } = require("node:path");
const { runInNewContext } = require("node:vm");
const ts = require(require.resolve("typescript", {
    paths: [process.env.SIYUAN_APP_DIR || resolve(__dirname, "../../siyuan/app")],
}));

const source = readFileSync(resolve(__dirname, "../entry/src/main/ets/pages/JSHarmony.ets"), "utf8")
    .replace("@Component", "").replace("export struct JSHarmony", "export class JSHarmony");
const compiled = ts.transpileModule(source, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 },
}).outputText;
const moduleContext = { exports: {} };
runInNewContext(compiled, { module: moduleContext, exports: moduleContext.exports, require: () => ({}) });
const { getLocalAssetDownloadPath } = moduleContext.exports;

test("local downloads preserve encoded filenames and notebook context", () => {
    assert.equal(getLocalAssetDownloadPath("http://127.0.0.1:6806/assets/movie.mp4"), "assets/movie.mp4");
    assert.equal(getLocalAssetDownloadPath(
        "http://127.0.0.1:6806/assets/%E8%A7%86%E9%A2%91.mp4?box=20261006000000-box0001&download=true#t=10"),
        "assets/%E8%A7%86%E9%A2%91.mp4?box=20261006000000-box0001&download=true");
    assert.equal(getLocalAssetDownloadPath("http://127.0.0.1:6806/assets/a%23b%3Fc.mp4?box=one%26two"),
        "assets/a%23b%3Fc.mp4?box=one%26two");
});

test("foreign origins and unsupported resource paths never enter native saving", () => {
    for (const url of ["", "assets/movie.mp4", "https://127.0.0.1:6806/assets/movie.mp4",
        "http://127.0.0.1:6807/assets/movie.mp4", "http://localhost:6806/assets/movie.mp4",
        "http://127.0.0.1.example.com:6806/assets/movie.mp4", "http://127.0.0.1:6806@evil.example/assets/movie.mp4",
        "http://user@127.0.0.1:6806/assets/movie.mp4", "file:///assets/movie.mp4",
        "http://127.0.0.1:6806/export/movie.mp4", "http://127.0.0.1:6806/assets/",
        "http://127.0.0.1:6806/assets/?box=20261006000000-box0001"]) {
        assert.equal(getLocalAssetDownloadPath(url), "");
    }
});

test("Web download callbacks invoke the existing save flow only for local assets", () => {
    const main = ts.createSourceFile("Main.ets",
        readFileSync(resolve(__dirname, "../entry/src/main/ets/pages/Main.ets"), "utf8"), ts.ScriptTarget.Latest, true);
    let callback;
    const findCallback = node => {
        if (ts.isCallExpression(node) && ts.isPropertyAccessExpression(node.expression) &&
            node.expression.name.text === "onDownloadStart") {
            callback = node.arguments[0].getText(main);
            return;
        }
        ts.forEachChild(node, findCallback);
    };
    findCallback(main);
    assert.ok(callback);
    const saved = [];
    const download = runInNewContext(ts.transpileModule(`(${callback});`, {
        compilerOptions: { target: ts.ScriptTarget.ES2022 },
    }).outputText, { getLocalAssetDownloadPath, jsHarmony: { saveExportFile: path => saved.push(path) } });
    download(undefined);
    download({ url: "https://example.com/movie.mp4" });
    download({ url: "http://127.0.0.1:6806/assets/movie.mp4?box=20261006000000-box0001" });
    assert.deepEqual(saved, ["assets/movie.mp4?box=20261006000000-box0001"]);
});
