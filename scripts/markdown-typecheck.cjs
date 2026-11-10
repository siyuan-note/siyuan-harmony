// 使用已安装 SDK 做非构建检查；--arkts --ui 同时检查 ArkTS 1.0 和独立 ArkUI 页面。
const {readFileSync, writeFileSync, readdirSync, mkdtempSync, rmSync, existsSync} = require("node:fs");
const path = require("node:path");
const {tmpdir} = require("node:os");
const sdk = path.join(process.env.DEVECO_STUDIO_HOME || "D:/Program Files/Huawei/DevEco Studio", "sdk/default/openharmony/ets");
if (!existsSync(sdk)) throw new Error("Set DEVECO_STUDIO_HOME to check the Harmony SDK contracts");
const arkts = process.argv.includes("--arkts");
const ts = arkts ? require(path.join(sdk, "build-tools/ets-loader/node_modules/typescript")) :
    require(require.resolve("typescript", {paths: [process.env.SIYUAN_APP_DIR || path.resolve(__dirname, "../../siyuan/app")]}));
const temporary = mkdtempSync(path.join(tmpdir(), "siyuan-harmony-markdown-types-"));
try {
    const directory = path.resolve(__dirname, "../entry/src/main/ets/markdown");
    const roots = readdirSync(directory).filter(name => name.endsWith(".ets")).map(name => {
        const target = path.join(temporary, arkts ? name : name.replace(/\.ets$/, ".ts"));
        writeFileSync(target, readFileSync(path.join(directory, name), "utf8").replaceAll("'../pages/SystemFont'", "'./SystemFont'"));
        return target;
    });
    const fontSource = path.join(temporary, arkts ? "SystemFont.ets" : "SystemFont.ts");
    writeFileSync(fontSource, readFileSync(path.join(directory, "../pages/SystemFont.ets"), "utf8"));
    roots.push(fontSource);
    if (arkts && process.argv.includes("--ui")) {
        for (const relative of ["../pages/Markdown.ets", "../entryability/MarkdownAbility.ets", "../entryability/MarkdownStage.ets"]) {
            const target = path.join(temporary, path.basename(relative));
            writeFileSync(target, readFileSync(path.join(directory, relative), "utf8").replaceAll("'../markdown/", "'./"));
            roots.push(target);
        }
        for (const file of readdirSync(path.join(sdk, "build-tools/ets-loader/declarations"))) {
            if (file.endsWith(".d.ts")) roots.push(path.join(sdk, "build-tools/ets-loader/declarations", file));
        }
    }
    const ambient = path.join(temporary, "environment.d.ts");
    writeFileSync(ambient, "declare function canIUse(capability:string):boolean;\ndeclare module 'BuildProfile' {const profile:{DEBUG:boolean};export default profile;}\n");
    roots.push(ambient);
    const options = {noEmit: true, skipLibCheck: true, strict: false, strictNullChecks: true, allowNonTsExtensions: true, allowSyntheticDefaultImports: true,
        module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021,
        paths: {"@kit.*": [path.join(sdk, "kits/@kit.*.d.ts")], "@ohos.*": [path.join(sdk, "api/@ohos.*.d.ts")],
            "libentry.so": [path.resolve(__dirname, "../entry/src/main/cpp/types/libentry/Index.d.ts")]},
        types: [], lib: ["lib.es2021.d.ts"]};
    let builder;
    let program;
    if (arkts) {
        Object.assign(options, {incremental: true, tsBuildInfoFile: path.join(temporary, "check.tsbuildinfo"), needDoArkTsLinter: true,
            experimentalDecorators: true, ets: JSON.parse(readFileSync(path.join(sdk, "build-tools/ets-loader/tsconfig.json"), "utf8")).compilerOptions.ets});
        builder = ts.createIncrementalProgram({rootNames: roots, options});
        program = builder.getProgram();
    } else program = ts.createProgram(roots, options);
    const allDiagnostics = ts.getPreEmitDiagnostics(program);
    const warnings = allDiagnostics.filter(value => value.category !== ts.DiagnosticCategory.Error);
    if (process.argv.includes("--warnings") && warnings.length) {
        console.warn(ts.formatDiagnosticsWithColorAndContext(warnings, {
            getCanonicalFileName: value => value, getCurrentDirectory: () => temporary, getNewLine: () => "\n",
        }));
    }
    const diagnostics = allDiagnostics.filter(value => value.category === ts.DiagnosticCategory.Error);
    if (arkts) diagnostics.push(...ts.ArkTSLinter_1_0.runArkTSLinter(builder, undefined, undefined, "ArkTS_1_0"));
    if (diagnostics.length) {
        console.error(ts.formatDiagnosticsWithColorAndContext(diagnostics, {
            getCanonicalFileName: value => value, getCurrentDirectory: () => temporary, getNewLine: () => "\n",
        }));
        process.exitCode = 1;
    } else console.log("Harmony Markdown SDK contracts" + (arkts ? " and ArkTS 1.0" : "") +
        (process.argv.includes("--ui") ? " including ArkUI page" : "") + " typecheck passed" +
        (warnings.length ? ` (${warnings.length} SDK warning diagnostics; use --warnings to inspect)` : ""));
} finally {
    if (path.dirname(path.resolve(temporary)) !== path.resolve(tmpdir()) || !path.basename(temporary).startsWith("siyuan-harmony-markdown-types-")) {
        throw new Error("Unsafe temporary directory");
    }
    rmSync(temporary, {recursive: true, force: true});
}
