const assert = require("node:assert/strict");
const { test } = require("node:test");
const { readFileSync } = require("node:fs");
const { resolve } = require("node:path");
const { runInNewContext } = require("node:vm");
const ts = require(require.resolve("typescript", {
    paths: [process.env.SIYUAN_APP_DIR || resolve(__dirname, "../../siyuan/app")],
}));

const load = (names, descriptors) => {
    const calls = [];
    const exports = {};
    const text = {
        SystemFontType: { ALL: 1 },
        FontWeight: { W100: 0, W400: 3, W900: 8 },
        getSystemFontFullNamesByType: async type => {
            calls.push(["list", type]);
            return names;
        },
        getFontDescriptorByFullName: async (name, type) => {
            calls.push([name, type]);
            if (descriptors[name] instanceof Error) throw descriptors[name];
            return descriptors[name];
        },
    };
    const source = readFileSync(resolve(__dirname, "../entry/src/main/ets/pages/SystemFont.ets"), "utf8");
    runInNewContext(ts.transpileModule(source, {
        compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 },
    }).outputText, {
        exports,
        require: id => id === "@kit.ArkGraphics2D" ? { text } : { hilog: { warn() {} } },
    });
    return { calls, fonts: async () => JSON.parse(await exports.loadSystemFonts()) };
};

test("native enumeration includes installed fonts and converts engine weights to CSS weights", async () => {
    const harness = load(["System Regular", "Installed Mono"], {
        "System Regular": { fontFamily: "HarmonyOS Sans", fullName: "System Regular", weight: 3 },
        "Installed Mono": { fontFamily: "安装的等宽字体", weight: 6, monoSpace: true, postScriptName: "InstalledMono" },
    });
    const fonts = await harness.fonts();
    assert.equal(fonts.length, 2);
    assert.ok(harness.calls.every(call => call[1] === 1));
    assert.equal(fonts.find(font => font.family === "HarmonyOS Sans").weight, 400);
    const installed = fonts.find(font => font.family === "安装的等宽字体");
    assert.equal(installed.weight, 700);
    assert.equal(installed.spacing, "monospace");
    assert.ok(installed.aliases.includes("InstalledMono"));
});

test("duplicate names, italic styles and unreadable descriptors preserve upright family choices", async () => {
    const harness = load(["Italic", "Regular", "Regular", "Unreadable", "Internal"], {
        Italic: { fontFamily: "Family", fullName: "Family Italic", weight: 3, italic: 1 },
        Regular: { fontFamily: "Family", fullName: "Family Regular", weight: 3, italic: 0 },
        Unreadable: new Error("unavailable"),
        Internal: { fontFamily: ".Internal", weight: 3 },
    });
    const fonts = await harness.fonts();
    assert.equal(fonts.length, 1);
    assert.equal(fonts[0].displayName, "Family Regular");
    assert.ok(fonts[0].aliases.includes("Family Italic"));
    assert.equal(harness.calls.filter(call => call[0] === "Regular").length, 1);
});

test("font bridge returns its promise through the synchronous proxy method list", () => {
    const main = readFileSync(resolve(__dirname, "../entry/src/main/ets/pages/Main.ets"), "utf8");
    assert.match(main, /registerJavaScriptProxy\(this.jsHarmony, "JSHarmony",[\s\S]*?"getSystemFonts"/);
    const bridge = readFileSync(resolve(__dirname, "../entry/src/main/ets/pages/JSHarmony.ets"), "utf8");
    assert.match(bridge, /getSystemFonts\(\): Promise<string>\s*\{\s*return loadSystemFonts\(\);/);
});
