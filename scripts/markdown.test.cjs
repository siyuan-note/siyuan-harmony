const assert = require("node:assert/strict");
const {test} = require("node:test");
const {readFileSync} = require("node:fs");
const {resolve} = require("node:path");
const {runInNewContext} = require("node:vm");
const {createHash} = require("node:crypto");
const ts = require(require.resolve("typescript", {paths: [process.env.SIYUAN_APP_DIR || resolve(__dirname, "../../siyuan/app")]}));
const directory = resolve(__dirname, "../entry/src/main/ets/markdown");

function load(name, mocks = {}, cache = new Map()) {
    if (cache.has(name)) return cache.get(name);
    const source = readFileSync(resolve(directory, name + ".ets"), "utf8");
    const result = ts.transpileModule(source, {reportDiagnostics: true,
        compilerOptions: {module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022}});
    assert.deepEqual((result.diagnostics || []).filter(value => value.category === ts.DiagnosticCategory.Error), []);
    const module = {exports: {}};
    runInNewContext(result.outputText, {module, exports: module.exports, console, Date, Uint8Array, ArrayBuffer,
        setTimeout, clearTimeout, canIUse: () => true,
        require: id => mocks[id] || (id.startsWith("./") ? load(id.slice(2), mocks, cache) : {})});
    cache.set(name, module.exports);
    return module.exports;
}

function harness() {
    const cache = new Map();
    const {MarkdownTransactions} = load("MarkdownTransactions", {}, cache);
    const {MarkdownRegistry} = load("MarkdownRegistry", {}, cache);
    const registry = new MarkdownRegistry();
    const files = new Map();
    const records = new Map();
    const cachedRecords = new Map();
    const events = [];
    let nextId = 0;
    const controls = {chunk: 3, failAfter: Infinity, closeFailure: false, storeFailure: false, afterStoreFailure: false, reloadFailure: false, readOnly: false};
    const digest = bytes => createHash("sha256").update(bytes).digest("hex");
    const io = {
        uuid: () => "id-" + ++nextId,
        digest,
        encode(value, format, maximum = 8 * 1024 * 1024) {
            const bytes = new TextEncoder().encode((format.bom ? "\ufeff" : "") + value.replace(/\r\n|\r|\n/g, format.newline));
            if (bytes.length > maximum) throw new Error("size");
            return bytes;
        },
        decode: bytes => ({content: new TextDecoder().decode(bytes), format: {bom: false, newline: "\n"}}),
        async open(uri, writable, create) {
            if (writable && controls.readOnly) throw new Error("permission");
            if (!files.has(uri) && create) files.set(uri, {identity: "file-" + ++nextId, bytes: new Uint8Array()});
            const file = files.get(uri);
            if (!file) throw new Error("missing");
            let written = 0;
            return {
                async snapshot() { return {bytes: file.bytes.slice(), fileIdentity: file.identity, baseline: digest(file.bytes)}; },
                async truncate(size) { events.push("truncate"); const bytes = new Uint8Array(size); bytes.set(file.bytes.subarray(0, size)); file.bytes = bytes; },
                async write(bytes, offset) {
                    events.push("write");
                    if (written >= controls.failAfter) throw new Error("write failed");
                    const count = Math.min(controls.chunk, bytes.length);
                    const result = new Uint8Array(Math.max(file.bytes.length, offset + count));
                    result.set(file.bytes); result.set(bytes.subarray(0, count), offset); file.bytes = result; written += count;
                    return count;
                },
                async sync() { events.push("sync"); },
                async close() { if (controls.closeFailure && written) throw new Error("close failed"); },
            };
        },
    };
    const store = {
        read(id) { return structuredClone(cachedRecords.get(id) || {version: 1, sessionId: id, revision: -1, targetGeneration: 0, updatedAt: 0, displayName: ""}); },
        async reload(id) {
            if (controls.reloadFailure) throw new Error("read failed");
            if (records.has(id)) cachedRecords.set(id, structuredClone(records.get(id)));
            return this.read(id);
        },
        async write(record) {
            events.push("persist");
            if (controls.storeFailure) throw new Error("storage failed");
            records.set(record.sessionId, structuredClone(record));
            if (controls.afterStoreFailure) throw new Error("durable write acknowledgement lost");
            cachedRecords.set(record.sessionId, structuredClone(record));
        },
        list: () => [...records.values()],
        async remove(id) { records.delete(id); cachedRecords.delete(id); },
    };
    const session = id => new MarkdownTransactions(id, io, store, registry);
    const put = (uri, text, identity = uri) => files.set(uri, {identity, bytes: new TextEncoder().encode(text)});
    const content = uri => new TextDecoder().decode(files.get(uri).bytes);
    return {session, put, files, content, events, controls, records, store, io};
}

const source = "file://docs/source.md";
const candidate = "file://docs/copy.md";
async function open(h, id = "session-a") {
    h.put(source, "original longer text");
    const session = h.session(id);
    const result = await session.authorize(source, "source.md", true, false);
    assert.equal(result.kind, "read");
    return session;
}
function operation(session, content = "new", revision = 1) {
    const target = session.getTarget();
    return {sessionId: session.sessionId, operationId: session.sessionId + ":operation:" + revision,
        targetGeneration: session.getGeneration(), revision, content, target, expectedBaseline: target.baseline};
}

function treeHarness(text) {
    const {MarkdownTree, MarkdownTreeStore} = load("MarkdownTree");
    const nodes = new Map();
    const calls = [];
    const controls = {beforeList: undefined, restore: true, writeError: false, deniedStat: new Set(), deniedList: new Set()};
    let saved = text;
    const store = new MarkdownTreeStore(text, async value => {
        if (controls.writeError) throw new Error("space");
        saved = value;
    });
    const put = (uri, directory = false, identity = uri) => nodes.set(uri, {identity, directory, file: !directory, symlink: false});
    const io = {
        async stat(uri) {
            if (controls.deniedStat.has(uri)) throw Object.assign(new Error("permission"), {code: 13900012});
            if (!nodes.has(uri)) throw new Error("deleted"); return {...nodes.get(uri)};
        },
        async list(uri) {
            calls.push(uri);
            if (controls.deniedList.has(uri)) throw Object.assign(new Error("permission"), {code: 13900012});
            if (controls.beforeList) await controls.beforeList(uri);
            return [...nodes.keys()].filter(key => key.startsWith(uri + "/") && !key.slice(uri.length + 1).includes("/"))
                .map(key => decodeURIComponent(key.slice(uri.length + 1)));
        },
        parent: uri => uri.slice(0, uri.lastIndexOf("/")),
        name: uri => decodeURIComponent(uri.slice(uri.lastIndexOf("/") + 1)),
        join: (uri, name) => uri + "/" + encodeURIComponent(name),
        hash: text => createHash("sha256").update(text).digest("hex"),
        async restore() {return controls.restore;}, async persist() {return true;},
    };
    return {tree: new MarkdownTree(io, store), store, nodes, put, calls, controls, saved: () => saved};
}
const treeRoot = "file://docs/folder";
const treeLocation = state => ({rootId: state.rootId, generation: state.generation, nodeId: state.rootId});

test("Harmony file tree requires directory permission, filters real Markdown and naturally sorts without recursive reads", async () => {
    const h = treeHarness();
    h.put(treeRoot, true); h.put(treeRoot + "/sub", true); h.put(treeRoot + "/sub/inner.md");
    for (const name of ["10.md", "2.MARKDOWN", "note.txt", "photo.png"]) h.put(treeRoot + "/" + name);
    h.put(treeRoot + "/escape", true); h.nodes.get(treeRoot + "/escape").symlink = true;
    await h.tree.follow(treeRoot + "/2.MARKDOWN");
    assert.equal((await h.tree.state()).kind, "permission-required");
    assert.equal(h.calls.length, 0, "file grant does not enumerate its parent");
    await h.tree.choose(treeRoot);
    const state = await h.tree.state();
    const listing = await h.tree.list(treeLocation(state));
    assert.deepEqual(Array.from(listing.entries, node => node.name), ["sub", "2.MARKDOWN", "10.md"]);
    assert.ok(h.calls.every(uri => uri === treeRoot), "collapsed children stay lazy");
    assert.equal(await h.tree.file({...treeLocation(state), nodeId: state.currentNodeId}), treeRoot + "/2.MARKDOWN");
    assert.equal((await h.tree.list({...treeLocation(state), nodeId: "../../outside"})).kind, "blocked");
});

test("Harmony tree view persists bounded roots and merges updates without clobbering other fields", async () => {
    const h = treeHarness(); h.put(treeRoot, true); await h.tree.choose(treeRoot);
    const state = await h.tree.state();
    await Promise.all([h.tree.saveView({width: 320}), h.tree.saveView({visible: false}),
        h.tree.saveView({...treeLocation(state), expanded: [state.rootId]})]);
    const saved = JSON.parse(h.saved());
    assert.equal(saved.width, 320); assert.equal(saved.visible, false); assert.deepEqual(saved.roots[0].expanded, [state.rootId]);
    const other = treeHarness(h.saved()); other.put(treeRoot, true); other.put(treeRoot + "/file.md");
    await other.tree.follow(treeRoot + "/file.md");
    const restored = await other.tree.state();
    assert.equal(restored.kind, "ready"); assert.equal(restored.rootId, state.rootId); assert.equal(restored.width, 320);
    assert.equal(restored.visible, false);
    await assert.rejects(other.tree.saveView({width: 179}), /protocol/);
    await assert.rejects(other.tree.saveView({...treeLocation(restored), expanded: Array(257).fill(restored.rootId)}), /protocol/);
    const broken = treeHarness('{"version":99}');
    await assert.rejects(broken.tree.saveView({width: 300}), /protocol/);
    assert.equal(broken.saved(), '{"version":99}');
});

test("Harmony tree rejects replaced roots, stale slow lists, aliases and invalid node generations", async () => {
    const h = treeHarness(); h.put(treeRoot, true); h.put(treeRoot + "/a.md");
    const second = "file://docs/other"; h.put(second, true);
    await h.tree.choose(treeRoot); const original = await h.tree.state();
    let resume; let entered;
    const started = new Promise(resolve => entered = resolve);
    h.controls.beforeList = async uri => {if (uri === treeRoot) {entered(); await new Promise(resolve => resume = resolve);}};
    const pending = h.tree.list(treeLocation(original)); await started;
    await h.tree.choose(second); resume();
    assert.equal((await pending).kind, "blocked");
    assert.equal((await h.tree.list(treeLocation(original))).kind, "blocked");
    h.nodes.get(second).identity = "replacement";
    assert.equal((await h.tree.state()).kind, "blocked");
});

test("Harmony tree maintains root on in-root switch/manual selection, polls expanded folders and bounds directory counts", async () => {
    const h = treeHarness(); h.put(treeRoot, true); h.put(treeRoot + "/sub", true);
    await h.tree.choose(treeRoot); const state = await h.tree.state();
    const folder = (await h.tree.list(treeLocation(state))).entries[0];
    await h.tree.list({...treeLocation(state), nodeId: folder.id});
    await h.tree.saveView({...treeLocation(state), expanded: [folder.id]});
    assert.equal(await h.tree.poll(), false);
    h.put(treeRoot + "/sub/new.md"); assert.equal(await h.tree.poll(), true);
    await h.tree.follow("file://outside/file.md");
    assert.equal((await h.tree.state()).rootId, state.rootId, "explicitly chosen root survives a document outside it");
    const large = treeHarness(); large.put(treeRoot, true);
    for (let i = 0; i < 10001; i++) large.put(treeRoot + "/" + i + ".md");
    await assert.rejects(large.tree.choose(treeRoot), /size/);
});

test("Harmony default tree follows an explicitly selected Save As folder and preserves roots inside it", async () => {
    const h = treeHarness(); h.put(treeRoot, true); h.put(treeRoot + "/a.md"); h.put(treeRoot + "/b.md");
    await h.tree.follow(treeRoot + "/a.md", treeRoot);
    const state = await h.tree.state(); assert.equal(state.kind, "ready");
    await h.tree.follow(treeRoot + "/b.md");
    assert.equal((await h.tree.state()).rootId, state.rootId);
    const next = "file://docs/next"; h.put(next, true); h.put(next + "/new.md");
    await h.tree.follow(next + "/new.md", next);
    assert.notEqual((await h.tree.state()).rootId, state.rootId);
    for (let i = 0; i < 20; i++) { const uri = "file://docs/other" + i; h.put(uri, true); await h.tree.choose(uri); }
    assert.equal(JSON.parse(h.saved()).roots.length, 16);
});

test("Harmony tree replacement preserves deferred workspace exit until the new document closes", async () => {
    const {MarkdownLifetime} = load("MarkdownLifetime");
    let exited = 0;
    MarkdownLifetime.add("old", {prepare: async () => true, cancel() {}, close: async () => true});
    MarkdownLifetime.deferWorkspaceExit(async () => {exited++;});
    MarkdownLifetime.replace("old", "next");
    assert.equal(exited, 0); assert.equal(MarkdownLifetime.isActive("old"), false); assert.equal(MarkdownLifetime.isActive("next"), true);
    MarkdownLifetime.remove("next"); assert.equal(exited, 1);
});

test("Harmony workspace recreation revokes a previously deferred exit", async () => {
    const {MarkdownLifetime} = load("MarkdownLifetime");
    let exited = false;
    MarkdownLifetime.add("document", {prepare: async () => true, cancel() {}, close: async () => true});
    const token = MarkdownLifetime.workspaceToken();
    MarkdownLifetime.deferWorkspaceExit(async () => {exited = true;});
    MarkdownLifetime.workspaceOpened(); MarkdownLifetime.remove("document"); await Promise.resolve();
    assert.equal(exited, false); assert.equal(MarkdownLifetime.isCurrentWorkspace(token), false);
    MarkdownLifetime.add("another", {prepare: async () => true, cancel() {}, close: async () => true});
});

test("Harmony reopening during a deferred exit admits new documents without weakening explicit quit", async () => {
    const {MarkdownLifetime} = load("MarkdownLifetime");
    const participant = {prepare: async () => true, cancel() {}, close: async () => true};
    let finish;
    let exited = false;
    const token = MarkdownLifetime.workspaceToken();
    MarkdownLifetime.add("old", participant);
    MarkdownLifetime.deferWorkspaceExit(async () => {
        await new Promise(resolve => {finish = resolve;});
        exited = MarkdownLifetime.isCurrentWorkspace(token);
    });
    MarkdownLifetime.remove("old");
    MarkdownLifetime.workspaceOpened();
    MarkdownLifetime.add("new", participant);
    finish(); await Promise.resolve();
    assert.equal(exited, false); assert.equal(MarkdownLifetime.isActive("new"), true);
    assert.equal(await MarkdownLifetime.prepareQuit(), true);
    MarkdownLifetime.workspaceOpened();
    assert.throws(() => MarkdownLifetime.add("late", participant), /closing/);
});

test("Harmony manual root follows an outside Save As but survives ordinary outside navigation", async () => {
    const h = treeHarness(); const next = "file://docs/next";
    h.put(treeRoot, true); h.put(treeRoot + "/a.md"); h.put(next, true); h.put(next + "/b.md");
    await h.tree.choose(treeRoot); const original = await h.tree.state();
    await h.tree.follow(next + "/b.md"); assert.equal((await h.tree.state()).rootId, original.rootId);
    await h.tree.follow(treeRoot + "/a.md", treeRoot, true); assert.equal((await h.tree.state()).rootId, original.rootId);
    await h.tree.follow(next + "/b.md", next, true);
    assert.notEqual((await h.tree.state()).rootId, original.rootId); assert.equal((await h.tree.state()).currentNodeId !== undefined, true);
});

test("Harmony escaped boundary operations commit, replay and reconcile with an independent fingerprint budget", async () => {
    for (const text of ['"', '\\', '界']) {
        const h = harness(); h.controls.chunk = Infinity;
        const session = await open(h);
        const request = operation(session, text.repeat(Math.floor(8 * 1024 * 1024 / Buffer.byteLength(text))));
        h.controls.closeFailure = true;
        assert.equal((await session.write(request)).kind, "indeterminate");
        h.controls.closeFailure = false;
        assert.equal((await session.reconcile(request)).kind, "committed");
        assert.equal((await session.write(request)).kind, "committed");
        assert.equal(h.content(source), request.content);
    }
});

test("Harmony existing-window focus follows the current session and ignores closed or switched owners", async () => {
    const {MarkdownWindows} = load("MarkdownWindows");
    let focused = 0; const host = {containerId: "container", sessionId: "a", canFocus: async () => true};
    MarkdownWindows.add(host, async () => {focused++;});
    assert.equal(await MarkdownWindows.focus("a"), true);
    host.sessionId = "b";
    assert.equal(await MarkdownWindows.focus("a"), false);
    assert.equal(await MarkdownWindows.focus("b"), true);
    host.canFocus = async () => false; assert.equal(await MarkdownWindows.focus("b"), false);
    MarkdownWindows.remove("container"); assert.equal(await MarkdownWindows.focus("b"), false);
    assert.equal(focused, 2);
});

test("Harmony specified routing focuses an occupied alias and retires only its new container", async () => {
    const {MarkdownWindows} = load("MarkdownWindows");
    class Occupied extends Error {constructor(id) {super("occupied"); this.sessionId = id;}}
    let ids = 0; let focused = 0; let terminated = 0; let loads = 0;
    class Host {
        constructor() {this.containerId = "container-" + ++ids; this.sessionId = "new"; this.targetURI = "file://B";}
        async initialize() {throw new Occupied("owner");}
        async canFocus() {return true;}
        destroy() {this.destroyed = true;}
        startupError() {return "";}
    }
    const owner = new Host(); owner.sessionId = "owner";
    MarkdownWindows.add(owner, async () => {focused++;});
    const {default: Ability} = load("../entryability/MarkdownAbility", {
        "@kit.AbilityKit": {UIAbility: class {}}, "BuildProfile": {default: {DEBUG: true}},
        "@kit.ArkWeb": {webview: {WebviewController: {setWebDebuggingAccess() {}}}},
        "@kit.ArkTS": {util: {generateRandomUUID: () => "fresh-key"}},
        "../markdown/MarkdownWindows": {MarkdownWindows},
        "../markdown/MarkdownHost": {MarkdownHost: Host, MarkdownOccupiedError: Occupied},
        "../markdown/MarkdownFiles": {canonicalMarkdownURI: value => value},
        "./MarkdownStage": {markdownInstanceKey: want => want.uri}
    });
    const ability = new Ability();
    ability.context = {abilityInfo: {bundleName: "test"}, terminateSelf: async () => {terminated++;},
        resourceManager: {getStringByNameSync: () => "failure"}};
    ability.onCreate({uri: "file://alias"}, {}); await ability.initialized;
    await ability.onWindowStageCreate({loadContent: async () => {loads++;}});
    assert.equal(focused, 1); assert.equal(terminated, 1); assert.equal(loads, 0);
    assert.equal(MarkdownWindows.get(owner.containerId), owner); assert.equal(ability.failure, "");
    const starts = [];
    ability.host = new Host(); ability.context.startAbility = async want => {starts.push(want);};
    ability.onNewWant({uri: "file://A", flags: 7});
    assert.equal(starts[0].parameters.markdownInstanceKey, "fresh-key");
    assert.equal(starts[0].flags, 7); assert.equal(ability.host.targetURI, "file://B");
    Host.prototype.initialize = async () => {};
    const current = new Ability(); current.context = ability.context;
    current.onCreate({uri: "file://original-key"}, {}); await current.initialized;
    assert.equal(await MarkdownWindows.focus(current.host.sessionId), true);
    assert.equal(starts.at(-1).parameters.markdownInstanceKey, "file://original-key");
    assert.equal(starts.at(-1).parameters.markdownFocus, true);
    assert.equal(starts.at(-1).uri, "file://B", "focus carries the current URI if the system must recreate a closing owner");
});

test("Harmony specified stage reuses a supplied owner key across different URI spellings", () => {
    const {default: Stage} = load("../entryability/MarkdownStage", {"@kit.AbilityKit": {AbilityStage: class {}}});
    const stage = new Stage();
    assert.equal(stage.onAcceptWant({uri: "file://a"}), "file://a");
    assert.equal(stage.onAcceptWant({uri: "file://alias", parameters: {markdownInstanceKey: "file://a"}}), "file://a");
    const manifest = readFileSync(resolve(directory, "../../module.json5"), "utf8");
    assert.match(manifest, /"launchType": "specified"/);
    assert.match(manifest, /"srcEntry": "\.\/ets\/entryability\/MarkdownStage\.ets"/);
});

test("Harmony unavailable current files clear selection while accessible siblings and root remain navigable", async () => {
    const h = treeHarness(); h.put(treeRoot, true); h.put(treeRoot + "/a.md"); h.put(treeRoot + "/b.md");
    await h.tree.follow(treeRoot + "/a.md", treeRoot);
    const original = await h.tree.state(); assert.ok(original.currentNodeId);
    h.nodes.delete(treeRoot + "/a.md");
    const deleted = await h.tree.state(); assert.equal(deleted.kind, "ready"); assert.equal(deleted.currentNodeId, undefined);
    assert.equal(deleted.rootId, original.rootId);
    h.put(treeRoot + "/a.md"); h.controls.deniedStat.add(treeRoot + "/a.md");
    const revoked = await h.tree.state(); assert.equal(revoked.kind, "ready"); assert.equal(revoked.currentNodeId, undefined);
    const entries = (await h.tree.list(treeLocation(revoked))).entries;
    assert.deepEqual(Array.from(entries, node => node.name), ["b.md"]);
    assert.equal(await h.tree.file({...treeLocation(revoked), nodeId: entries[0].id}), treeRoot + "/b.md");
    h.put(treeRoot + "/sub", true); h.put(treeRoot + "/sub/current.md");
    await h.tree.follow(treeRoot + "/sub/current.md"); assert.ok((await h.tree.state()).currentNodeId);
    h.controls.deniedList.add(treeRoot + "/sub");
    const subtree = await h.tree.state(); assert.equal(subtree.kind, "ready"); assert.equal(subtree.currentNodeId, undefined);
    assert.equal((await h.tree.list(treeLocation(subtree))).kind, "listed");
    h.controls.deniedList.add(treeRoot);
    assert.equal((await h.tree.state()).kind, "blocked", "root permission failure remains visible");
});

test("Harmony cancelling a tree candidate publishes the deferred Save As root after following it", async () => {
    const {MarkdownHost} = load("MarkdownHost");
    const host = Object.create(MarkdownHost.prototype);
    const events = [];
    Object.assign(host, {treeCandidate: {transactions: {release: async () => {events.push("released");}}},
        treeFollowAfterCancel: "file://next", transactions: {getURI: () => "file://next/new.md"},
        tree: {follow: async (uri, directory, afterSaveAs) => {events.push([uri, directory, afterSaveAs]);}},
        command: async event => {events.push(event); return true;}});
    await host.cancelTreeCandidate();
    assert.deepEqual(events, ["released", ["file://next/new.md", "file://next", true], "tree-change"]);
    assert.equal(host.treeCandidate, undefined); assert.equal(host.treeFollowAfterCancel, undefined);
});

test("Harmony actual host prepares a second session, rejects early commit and atomically swaps after release with replayable ack", async () => {
    const h = harness(); const previous = await open(h);
    h.put(candidate, "candidate body");
    const cache = new Map();
    const mocks = {"@kit.CoreFileKit": {
        fileUri: {FileUri: class {constructor(uri) {this.name = uri.slice(uri.lastIndexOf("/") + 1);}}},
        fileShare: {OperationMode: {READ_MODE: 1, WRITE_MODE: 2}, async persistPermission() {}, async activatePermission() {}, async checkPersistentPermission() {return [true];}},
    }};
    const {MarkdownHost} = load("MarkdownHost", mocks, cache);
    const {MarkdownLifetime} = load("MarkdownLifetime", mocks, cache);
    MarkdownHost.store = h.store;
    const host = Object.create(MarkdownHost.prototype);
    Object.assign(host, {transactions: previous, io: h.io, documentEpoch: 0, treeRequestEpoch: 0, treeOpening: false,
        released: false, destroyed: false, resources: new Map(), imageFiles: new Map(), languages: {}, preference: {}, lang: "en",
        tree: {async file() {return candidate;}, async follow() {}}, dark: false});
    MarkdownLifetime.add(previous.sessionId, {prepare: async () => true, cancel() {}, close: async () => true});
    await previous.putDraft({...operation(previous, "retained old draft", 1), format: {bom: false, newline: "\n"}});
    const cancelled = await host.prepareTreeOpen({});
    await host.dispatch({id: "cancel", action: "tree-cancel-open", payload: cancelled.ticket});
    assert.equal(host.treeCandidate, undefined); assert.equal(host.transactions, previous);
    const ready = await host.prepareTreeOpen({});
    assert.equal(ready.kind, "ready"); assert.notEqual(ready.sessionId, previous.sessionId);
    assert.equal(host.transactions, previous, "prepare cannot replace the active document");
    await assert.rejects(host.dispatch({id: "early", action: "tree-commit-open", payload: ready.ticket}), /protocol/);
    let finishResource;
    host.resources.set("old-token", {generation: 0});
    host.resourceAccess = {read: () => new Promise(resolve => finishResource = resolve)};
    const lateResource = host.data("https://siyuan-markdown.local/resource/" + previous.sessionId + "/old-token");
    await host.dispatch({id: "release", action: "host:releaseSession", payload: {sessionId: previous.sessionId, targetGeneration: 0}});
    const result = await host.dispatch({id: "commit", action: "tree-commit-open", payload: ready.ticket});
    finishResource(new Uint8Array([1, 2]));
    assert.equal(await lateResource, undefined, "old document resource bytes cannot cross the binding swap");
    assert.equal(result.content, "candidate body"); assert.equal(result.sessionId, ready.sessionId);
    const repeated = await host.dispatch({id: "replay", action: "tree-commit-open", payload: ready.ticket});
    assert.equal(repeated.sessionId, ready.sessionId); assert.equal(host.documentEpoch, 1);
    assert.equal(MarkdownLifetime.isActive(previous.sessionId), false); assert.equal(MarkdownLifetime.isActive(ready.sessionId), true);
    assert.equal(h.content(source), "original longer text");
    assert.equal(h.records.get(previous.sessionId).draft.content, "retained old draft");
    await host.transactions.release(); MarkdownLifetime.remove(host.sessionId);
});

test("Harmony settles stale native requests as errors instead of leaking bridge promises across document switches", async () => {
    const {MarkdownHost} = load("MarkdownHost");
    const host = Object.create(MarkdownHost.prototype);
    let finish;
    const replies = [];
    Object.assign(host, {pageGeneration: 1, documentEpoch: 1, requestIds: new Set(), currentPage: () => true,
        reply: value => replies.push(value), dispatch: () => new Promise(resolve => finish = resolve)});
    host.postMessage(JSON.stringify({id: "late-list", action: "tree-list", payload: {}}));
    host.documentEpoch++;
    finish({kind: "listed", entries: [{name: "old.md"}]});
    await new Promise(resolve => setImmediate(resolve));
    assert.equal(replies.length, 1); assert.equal(replies[0].id, "late-list");
    assert.equal(replies[0].result, undefined); assert.match(replies[0].error, /Stale/);
    assert.equal(host.requestIds.size, 0);
});

test("Harmony provider writes loop short writes, truncate old bytes and persist recovery before mutation", async () => {
    const h = harness();
    const session = await open(h);
    const request = operation(session, "short");
    assert.equal((await session.write(request)).kind, "committed");
    assert.equal(h.content(source), "short");
    assert.equal(h.events[0], "persist");
    assert.ok(h.events.filter(value => value === "write").length > 1);
    assert.equal(h.records.get("session-a").journal.original, "original longer text");
    const count = h.events.length;
    assert.equal((await session.write(request)).kind, "committed");
    assert.equal(h.events.length, count, "same operation cannot be written twice");
    assert.equal((await session.write(operation(session, "newer", 2))).kind, "committed");
    const afterNewer = h.events.filter(value => value === "write").length;
    assert.equal((await session.write(request)).kind, "blocked");
    assert.equal(h.events.filter(value => value === "write").length, afterNewer);
    assert.equal(h.content(source), "newer");
});

test("Harmony blocks external changes and alias owners before any destructive write", async () => {
    const h = harness();
    const session = await open(h);
    const request = operation(session);
    h.put(source, "external");
    assert.equal((await session.write(request)).kind, "conflict");
    assert.equal(h.content(source), "external");
    assert.equal(h.events.includes("truncate"), false);
    h.put("file://docs/alias.md", "external", source);
    const other = h.session("session-b");
    assert.equal((await other.authorize("file://docs/alias.md", "alias.md", true, false)).kind, "occupied");
});

test("Harmony Save As reserves before creating and switches only after durable binding", async () => {
    const h = harness();
    const session = await open(h);
    const selected = await session.authorize(candidate, "copy.md", false, true, {bom: false, newline: "\n"}, true);
    const other = h.session("session-b");
    assert.equal((await other.authorize(candidate, "copy.md", false, true, {bom: false, newline: "\n"}, true)).kind, "occupied");
    assert.equal(h.content(candidate), "");
    const request = {...operation(session), target: selected.target, targetGeneration: 1, expectedBaseline: selected.target.baseline};
    const reservation = session.reserve({...request, format: {bom: false, newline: "\n"}});
    request.reservationId = reservation.reservation.id;
    await session.prepare({operation: request, previousTarget: session.getTarget()});
    const receipt = await session.write(request);
    assert.equal(receipt.kind, "committed");
    assert.equal(session.getTarget().displayName, "source.md");
    assert.equal((await session.commit({operation: {...request, revision: 100}, receipt, nextTargetGeneration: 1})).kind, "blocked");
    session.releaseCandidate(selected.target.handle);
    assert.equal((await other.authorize(candidate, "copy.md", false, false)).kind, "occupied");
    h.controls.storeFailure = true;
    assert.equal((await session.commit({operation: request, receipt, nextTargetGeneration: 1})).kind, "indeterminate");
    assert.equal(session.getTarget().displayName, "source.md");
    h.controls.storeFailure = false;
    assert.equal((await session.commit({operation: request, receipt, nextTargetGeneration: 1})).kind, "committed");
    assert.equal(session.getTarget().displayName, "copy.md");
    assert.equal((await session.commit({operation: request, receipt, nextTargetGeneration: 1})).kind, "committed");
});

test("Harmony partial and close failures retain uncertain reservations and reconcile without rewriting", async () => {
    const h = harness();
    const session = await open(h);
    const request = operation(session, "new final content");
    h.controls.closeFailure = true;
    assert.equal((await session.write(request)).kind, "indeterminate");
    await assert.rejects(session.release(), /indeterminate/);
    const count = h.events.filter(value => value === "write").length;
    h.controls.closeFailure = false;
    assert.equal((await session.reconcile(request)).kind, "committed");
    assert.equal(h.events.filter(value => value === "write").length, count);
    const next = operation(session, "a different result", 2);
    h.controls.failAfter = 3;
    assert.equal((await session.write(next)).kind, "indeterminate");
    assert.equal((await session.reconcile(next)).kind, "indeterminate");
    assert.equal((await session.write(next)).kind, "indeterminate");
});

test("Harmony persistence failure never truncates and a read-only grant preserves copy editing", async () => {
    const h = harness();
    const session = await open(h);
    h.controls.storeFailure = true;
    assert.equal((await session.write(operation(session))).kind, "blocked");
    assert.equal(h.events.includes("truncate"), false);
    assert.equal(h.content(source), "original longer text");
    h.controls.storeFailure = false;
    h.controls.readOnly = true;
    h.put("file://docs/readonly.md", "read only");
    const readonly = h.session("session-readonly");
    const result = await readonly.authorize("file://docs/readonly.md", "readonly.md", false, false);
    assert.equal(result.target.writable, false);
    assert.equal((await readonly.write(operation(readonly))).error.code, "readonly");
});

test("Harmony draft tombstones reject stale updates and preparation preserves a newer source draft", async () => {
    const h = harness();
    const session = await open(h);
    const draft = {...operation(session, "latest local", 3), format: {bom: false, newline: "\n"}};
    await session.putDraft(draft);
    await session.clearDraft({sessionId: session.sessionId, targetGeneration: 0, revision: 2});
    assert.equal(h.records.get(session.sessionId).draft.content, "latest local");
    const target = await session.authorize(candidate, "copy.md", false, true, draft.format, true);
    const reserve = session.reserve({...draft, target: target.target});
    await session.prepare({operation: {...draft, revision: 2, content: "older", target: target.target,
        targetGeneration: 1, reservationId: reserve.reservation.id}});
    assert.equal(h.records.get(session.sessionId).draft.content, "latest local");
    await session.clearDraft({sessionId: session.sessionId, targetGeneration: 0, revision: 3});
    await session.putDraft(draft);
    assert.equal(h.records.get(session.sessionId).draft, undefined);
});

test("Harmony durable Save As binding never clears a newer draft from the source generation", async () => {
    const h = harness();
    const session = await open(h);
    const original = operation(session, "first", 1);
    const format = {bom: false, newline: "\n"};
    const selected = await session.authorize(candidate, "copy.md", false, true, format, true);
    const reservation = session.reserve({...original, target: selected.target, format});
    const request = {...original, target: selected.target, expectedBaseline: selected.target.baseline,
        targetGeneration: 1, reservationId: reservation.reservation.id};
    await session.prepare({operation: request});
    const receipt = await session.write(request);
    await session.putDraft({...original, operationId: "session-a:newer", content: "new input", revision: 2, format});
    await session.commit({operation: request, receipt, nextTargetGeneration: 1});
    await session.clearDraft({sessionId: session.sessionId, revision: 1, targetGeneration: 1});
    assert.equal(h.records.get(session.sessionId).draft.content, "new input");
    assert.equal(h.records.get(session.sessionId).draft.targetGeneration, 1);
    assert.equal(h.records.get(session.sessionId).revision, 2);
});

test("Harmony renderer reconstruction finishes a written candidate only after durable binding succeeds", async () => {
    const h = harness();
    const session = await open(h);
    const original = operation(session, "copy text", 1);
    const format = {bom: false, newline: "\n"};
    const selected = await session.authorize(candidate, "copy.md", false, true, format, true);
    const reservation = session.reserve({...original, target: selected.target, format});
    const request = {...original, target: selected.target, expectedBaseline: selected.target.baseline,
        targetGeneration: 1, reservationId: reservation.reservation.id};
    await session.prepare({operation: request});
    const receipt = await session.write(request);
    h.controls.storeFailure = true;
    assert.equal((await session.commit({operation: request, receipt, nextTargetGeneration: 1})).kind, "indeterminate");
    session.beginRenderer();
    assert.equal(await session.recoverPending(), false);
    assert.equal(session.getTarget().displayName, "source.md");
    const writes = h.events.filter(value => value === "write").length;
    h.controls.storeFailure = false;
    assert.equal(await session.recoverPending(), true);
    assert.equal(session.getTarget().displayName, "copy.md");
    assert.equal(h.events.filter(value => value === "write").length, writes);
});

test("Harmony standalone ability has precise file routing, no workspace dependency and private backup exclusion", () => {
    const entry = readFileSync(resolve(directory, "../entryability/MarkdownAbility.ets"), "utf8");
    const page = readFileSync(resolve(directory, "../pages/Markdown.ets"), "utf8");
    assert.doesNotMatch(entry, /^import .*?(?:Utils|JSHarmony|libentry|pages\/Main)/m);
    assert.doesNotMatch(page, /registerJavaScriptProxy/);
    assert.match(page, /createWebMessagePorts/);
    assert.match(page, /postMessage\('siyuan-markdown-connect', \[ports\[1\]\], MARKDOWN_ORIGIN\)/);
    assert.match(page, /onOverrideUrlLoading/);
    assert.match(page, /frame-src 'none'/);
    const module = readFileSync(resolve(directory, "../../module.json5"), "utf8");
    assert.match(module, /general\.markdown/);
    assert.match(module, /FILE_ACCESS_PERSIST/);
    const backup = JSON.parse(readFileSync(resolve(directory, "../../resources/base/profile/backup_config.json"), "utf8"));
    assert.ok(backup.excludes.some(value => value.includes("el2/base/files/markdown-private")));
});

test("Harmony bridge channel exists only in the fixed top frame and queues until native port delivery", () => {
    const {MARKDOWN_CHANNEL_SCRIPT, markdownChannelMessage} = load("MarkdownChannel");
    const page = "https://siyuan-markdown.local/stage/build/markdown/index.html";
    const make = (topFrame, href) => {
        const events = new Map();
        const window = {addEventListener: (name, callback) => events.set(name, callback), removeEventListener: name => events.delete(name)};
        window.top = topFrame ? window : {};
        runInNewContext(MARKDOWN_CHANNEL_SCRIPT, {window, location: {href}});
        return {window, events};
    };
    assert.equal(make(false, page).window.siyuanMarkdownNative, undefined);
    assert.equal(make(true, "https://external.example/").window.siyuanMarkdownNative, undefined);
    const h = make(true, page);
    const messages = [];
    h.window.siyuanMarkdownNative.postMessage("bootstrap");
    assert.deepEqual(messages, []);
    h.events.get("message")({data: "siyuan-markdown-connect", ports: [{postMessage: value => messages.push(value)}]});
    assert.deepEqual(messages, []);
    h.window.__siyuanMarkdownConnect("native-only-token");
    h.window.siyuanMarkdownNative.postMessage("save");
    assert.deepEqual(messages.map(value => JSON.parse(value)), [
        {token: "native-only-token", message: "bootstrap"}, {token: "native-only-token", message: "save"},
    ]);
    assert.equal(h.events.has("message"), false);
    assert.equal(markdownChannelMessage(messages[0], "native-only-token"), "bootstrap");
    assert.equal(markdownChannelMessage(messages[0], "next-document-token"), undefined);
    assert.equal(markdownChannelMessage(messages[0], ""), undefined);
    assert.equal(markdownChannelMessage("null", "native-only-token"), undefined);
    assert.equal(markdownChannelMessage("{broken", "native-only-token"), undefined);
    assert.equal(markdownChannelMessage(JSON.stringify({token:"native-only-token",message:{action:"save"}}), "native-only-token"), undefined);
});

test("Harmony process exit preserves documents on veto and waits for prepared close", async () => {
    const {MarkdownLifetime} = load("MarkdownLifetime");
    const events = [];
    MarkdownLifetime.add("first", {prepare: async () => {events.push("first prepare"); return true;},
        cancel: () => events.push("first cancel"), close: async () => {events.push("first close"); return true;}});
    MarkdownLifetime.add("second", {prepare: async () => false, cancel: () => events.push("second cancel"), close: async () => true});
    assert.equal(await MarkdownLifetime.prepareQuit(), false);
    assert.deepEqual(events, ["first prepare", "first cancel", "second cancel"]);
    assert.equal(MarkdownLifetime.isActive("second"), true);
    let workspaceExited = false;
    assert.equal(MarkdownLifetime.deferWorkspaceExit(async () => {workspaceExited = true;}), true);
    MarkdownLifetime.remove("second");
    assert.equal(workspaceExited, false);
    assert.equal(await MarkdownLifetime.prepareQuit(), true);
    assert.equal(events.at(-1), "first close");
    MarkdownLifetime.remove("first");
    await Promise.resolve();
    assert.equal(workspaceExited, true);
});

test("Harmony codec preserves BOM/newlines and rejects malformed UTF-8 and incomplete surrogate pairs", () => {
    const {HarmonyMarkdownIO} = load("MarkdownFiles", {"@kit.ArkTS": {util: {
        TextDecoder: {create: (encoding, options) => ({decodeToString: bytes => new TextDecoder(encoding, options).decode(bytes)})},
        TextEncoder: class {encodeInto(text) {return new TextEncoder().encode(text);}},
    }}});
    const io = new HarmonyMarkdownIO();
    const encoded = new TextEncoder().encode("\ufefffirst\r\nsecond\r\n");
    const decoded = io.decode(encoded);
    assert.equal(decoded.content, "first\nsecond\n");
    assert.equal(decoded.format.bom, true);
    assert.equal(decoded.format.newline, "\r\n");
    assert.deepEqual(io.encode(decoded.content, decoded.format), encoded);
    assert.throws(() => io.decode(new Uint8Array([0xc3, 0x28])), /encoding/);
    assert.throws(() => io.decode(new Uint8Array([0, 1])), /encoding/);
    assert.throws(() => io.encode("bad\ud800", {bom: false, newline: "\n"}), /encoding/);
    const {MARKDOWN_LIMIT, MARKDOWN_ASSET_LIMIT, MARKDOWN_IMAGE_LIMIT} = load("MarkdownTypes");
    assert.equal(MARKDOWN_LIMIT, 8 * 1024 * 1024);
    assert.equal(io.encode("x".repeat(MARKDOWN_LIMIT), {bom: false, newline: "\n"}).byteLength, MARKDOWN_LIMIT);
    assert.throws(() => io.encode("x".repeat(MARKDOWN_LIMIT + 1), {bom: false, newline: "\n"}), /size/);
    assert.throws(() => io.encode("x".repeat(MARKDOWN_LIMIT - 2), {bom: true, newline: "\n"}), /size/);
    assert.throws(() => io.decode(new Uint8Array(MARKDOWN_LIMIT + 1)), /size/);
    const recoveryLimit = 16 * 1024 * 1024;
    assert.equal(io.encode("x".repeat(MARKDOWN_LIMIT + 1), {bom:false,newline:"\n"}, recoveryLimit).length, MARKDOWN_LIMIT + 1);
    assert.throws(() => io.encode("\u00e9".repeat(recoveryLimit / 2 + 1), {bom:false,newline:"\n"}, recoveryLimit), /size/);
    assert.ok(MARKDOWN_ASSET_LIMIT > 4463625);
    assert.equal(MARKDOWN_IMAGE_LIMIT, 32 * 1024 * 1024);
});

test("Harmony preferences preserve malformed and unknown versions and serialize concurrent patches", async () => {
    const {MarkdownPreferenceStore} = load("MarkdownPreferences");
    for (const text of ["{broken", '{"version":2,"value":{"mode":"ir","theme":"dark","fontSize":16}}']) {
        const writes = [];
        const preferences = new MarkdownPreferenceStore(text, async value => writes.push(value));
        await assert.rejects(preferences.update({theme: "light"}), /unavailable/);
        assert.deepEqual(writes, []);
    }
    const writes = [];
    let rejectWrite = true;
    const preferences = new MarkdownPreferenceStore(undefined, async value => {
        if (rejectWrite) throw new Error("disk full");
        writes.push(JSON.parse(value));
    });
    await assert.rejects(preferences.update({theme: "dark"}), /disk full/);
    assert.equal(preferences.get().theme, "system");
    rejectWrite = false;
    await Promise.all([preferences.update({theme: "dark"}), preferences.update({mode: "sv"})]);
    assert.equal(writes.at(-1).version, 1);
    assert.equal(preferences.get().theme, "dark");
    assert.equal(preferences.get().mode, "sv");
});

function resourceHarness() {
    const {MarkdownResourceAccess} = load("MarkdownResources");
    const bytes = new Uint8Array([137, 80, 78, 71, 13, 10, 26, 10]);
    const nodes = new Map([
        ["file://docs/images", {identity: "root", directory: true, symlink: false}],
        ["file://docs/images/sub", {identity: "sub", directory: true, symlink: false}],
        ["file://docs/images/sub/a.png", {identity: "image", directory: false, symlink: false}],
        ["file://docs/images/sub/b.png", {identity: "sibling", directory: false, symlink: false}],
    ]);
    const controls = {fdIdentity: "image", afterRead: undefined};
    let reads = 0;
    const io = {
        async stat(uri) {const info = nodes.get(uri); if (!info) throw new Error("missing"); return {...info};},
        async open() {
            return {async fileIdentity() {return controls.fdIdentity;},
                async snapshot() {reads++; controls.afterRead?.(); return {bytes, fileIdentity: controls.fdIdentity};}, async close() {}};
        },
    };
    return {access: new MarkdownResourceAccess(io), nodes, controls, reads: () => reads, bytes};
}

test("Harmony resource tokens recheck ancestry, fd identity, target generation and raster MIME", async () => {
    const uri = "file://docs/images/sub/a.png";
    const root = "file://docs/images";
    const h = resourceHarness();
    const grant = await h.access.capture(uri, root, 3);
    assert.equal(grant.mime, "image/png");
    assert.deepEqual(await h.access.read(grant, 3), h.bytes);
    let reads = h.reads();
    await assert.rejects(h.access.read(grant, 4), /expired/);
    assert.equal(h.reads(), reads);
    h.nodes.get(root + "/sub").identity = "replacement";
    await assert.rejects(h.access.read(grant, 3), /scope/);
    assert.equal(h.reads(), reads);
    h.nodes.get(root + "/sub").identity = "sub";
    h.controls.fdIdentity = "outside";
    await assert.rejects(h.access.read(grant, 3), /identity/);
    assert.equal(h.reads(), reads);
    h.controls.fdIdentity = "image";
    h.controls.afterRead = () => {h.nodes.get(root).symlink = true;};
    await assert.rejects(h.access.read(grant, 3), /scope/);
    const exact = resourceHarness();
    assert.equal((await exact.access.capture(uri, "", 3, "image")).ancestry.length, 0);
    await assert.rejects(exact.access.capture(root + "/sub/b.png", "", 3, "image"), /identity/);
    await assert.rejects(exact.access.capture(uri, "", 3), /permission/);
    const {markdownImageMime} = load("MarkdownResources");
    assert.equal(markdownImageMime(new TextEncoder().encode('<svg onload="attack()"/>')), "");
});

test("Harmony image import verifies reserved identity and close before returning an inserted reference", async () => {
    const {copyMarkdownImage} = load("MarkdownResources");
    const source = new Uint8Array([137, 80, 78, 71, 13, 10, 26, 10]);
    let destination = new Uint8Array();
    let identity = "reserved";
    let failClose = false;
    let writes = 0;
    const digest = bytes => createHash("sha256").update(bytes).digest("hex");
    const io = {digest, async open(uri, writable) {
        const original = uri === "source";
        return {
            async snapshot() {const bytes = original ? source : destination; return {bytes, baseline: digest(bytes), fileIdentity: original ? "source" : identity};},
            async write(bytes, offset) {
                writes++; const length = Math.min(3, bytes.length); const output = new Uint8Array(offset + length);
                output.set(destination); output.set(bytes.subarray(0, length), offset); destination = output; return length;
            },
            async truncate() {}, async sync() {}, async close() {if (writable && failClose) throw new Error("close failed");},
        };
    }};
    identity = "replacement";
    await assert.rejects(copyMarkdownImage(io, "source", "destination", "reserved"), /target changed/);
    assert.equal(writes, 0);
    identity = "reserved"; failClose = true;
    await assert.rejects(copyMarkdownImage(io, "source", "destination", "reserved"), /close failed/);
    failClose = false; destination = new Uint8Array();
    assert.equal(await copyMarkdownImage(io, "source", "destination", "reserved"), "reserved");
    assert.deepEqual(destination, source);
});

test("Harmony exit freezes new document admission while awaiting preparation", async () => {
    const {MarkdownLifetime} = load("MarkdownLifetime");
    let finish;
    MarkdownLifetime.add("first", {prepare: () => new Promise(resolve => {finish = resolve;}), cancel() {}, close: async () => true});
    const pending = MarkdownLifetime.prepareQuit();
    assert.throws(() => MarkdownLifetime.add("late", {prepare: async () => true, cancel() {}, close: async () => true}), /closing/);
    finish(false);
    assert.equal(await pending, false);
    assert.doesNotThrow(() => MarkdownLifetime.add("late", {prepare: async () => true, cancel() {}, close: async () => true}));
});

test("Harmony classifies offline separately from deletion and retains editor format when confirming overwrite", async () => {
    const {markdownErrorCode} = load("MarkdownTypes");
    assert.equal(markdownErrorCode({code: 13900044}), "offline");
    assert.equal(markdownErrorCode({code: 13900002}), "deleted");
    assert.equal(markdownErrorCode({code: 13900025}), "space");
    assert.equal(markdownErrorCode({code: 13900012}), "permission");
    assert.equal(markdownErrorCode({code: 13900042}), "unavailable");
    const h = harness();
    const session = await open(h);
    const request = operation(session, "local\ncontent", 1);
    request.target.format = {bom: true, newline: "\r\n"};
    h.put(source, "external", source);
    const read = await session.read(request);
    const result = await session.write({...request, expectedBaseline: read.target.baseline});
    assert.equal(result.kind, "committed");
    assert.deepEqual(h.files.get(source).bytes, new TextEncoder().encode("\ufefflocal\r\ncontent"));
    assert.equal(session.getTarget().format.bom, true);
});

test("Harmony recovery chooses the latest durable revision and requires a one-time native transfer", () => {
    const {latestMarkdownRecovery, MarkdownRecoveryTransfers} = load("MarkdownRecovery");
    const draft = {content: "older", revision: 2, format: {bom: false, newline: "\n"}};
    const journal = {...draft, revision: 3, content: "newer written content"};
    assert.equal(latestMarkdownRecovery({draft, journal: {operation: journal}}).content, "newer written content");
    assert.equal(latestMarkdownRecovery({draft: {...draft, revision: 4, content: "latest input"}, journal: {operation: journal}}).content, "latest input");
    assert.throws(() => latestMarkdownRecovery({draft: {...draft, content: null}}), /format/);
    const transfers = new MarkdownRecoveryTransfers();
    assert.throws(() => transfers.consume("record-id", 1), /unavailable/);
    transfers.grant("native-token", "record-id", 1);
    assert.equal(transfers.consume("native-token", 2), "record-id");
    assert.throws(() => transfers.consume("native-token", 3), /unavailable/);
    transfers.grant("expired", "record-id", 1);
    assert.throws(() => transfers.consume("expired", 30001), /unavailable/);
});

test("Harmony persists an 8 MiB plus one draft independently and rejects only the original-file write", async () => {
    const h = harness();
    const session = await open(h);
    const request = {...operation(session, "x".repeat(8 * 1024 * 1024 + 1)), format: {bom: false, newline: "\n"}};
    await session.putDraft(request);
    assert.equal(h.records.get(session.sessionId).draft.content, request.content);
    const result = await session.write(request);
    assert.equal(result.kind, "blocked");
    assert.equal(result.error.code, "size");
    assert.equal(h.content(source), "original longer text");
    assert.equal((await session.write(operation(session, "trimmed", 2))).kind, "committed");
    assert.equal(h.content(source), "trimmed");
    await assert.rejects(session.putDraft({...request, revision: 3, content: "x".repeat(16 * 1024 * 1024 + 1)}), /size/);
    assert.equal(h.records.get(session.sessionId).draft.content, request.content);
});

async function prepareWrittenCandidate(h, session) {
    const original = operation(session, "candidate", 1);
    const format = {bom: false, newline: "\n"};
    await session.putDraft({...original, format});
    const selected = await session.authorize(candidate, "copy.md", false, true, format, true);
    const reserved = session.reserve({...original, target: selected.target, format});
    const request = {...original, target: selected.target, expectedBaseline: selected.target.baseline,
        targetGeneration: 1, reservationId: reserved.reservation.id};
    await session.prepare({operation: request});
    const receipt = await session.write(request);
    return {request, receipt, transfer: {operation: request, receipt, nextTargetGeneration: 1}};
}

test("Harmony verifies a durable binding after a lost acknowledgement and rebases every later source draft", async () => {
    const h = harness();
    const session = await open(h);
    const {transfer} = await prepareWrittenCandidate(h, session);
    h.controls.afterStoreFailure = true;
    assert.equal((await session.commit(transfer)).kind, "indeterminate");
    assert.equal(session.getGeneration(), 0);
    assert.equal(h.records.get(session.sessionId).targetGeneration, 1);
    h.controls.afterStoreFailure = false;
    const late = {...operation(session, "late source text", 2), format: {bom: false, newline: "\n"}};
    await session.putDraft(late);
    assert.equal(h.records.get(session.sessionId).draft.content, "late source text");
    assert.equal(h.records.get(session.sessionId).draft.targetGeneration, 1);
    assert.equal((await session.commit(transfer)).kind, "committed");
    await session.clearDraft({sessionId: session.sessionId, targetGeneration: 1, revision: 2});
    await session.putDraft({...late, revision: 3, content: "late after clear"});
    assert.equal(h.records.get(session.sessionId).draft.content, "late after clear");
    assert.equal(h.records.get(session.sessionId).draft.targetGeneration, 1);
});

test("Harmony rejects draft acknowledgements while the durable binding cannot be verified", async () => {
    const h = harness();
    const session = await open(h);
    const {transfer} = await prepareWrittenCandidate(h, session);
    h.controls.afterStoreFailure = true;
    h.controls.reloadFailure = true;
    assert.equal((await session.commit(transfer)).kind, "indeterminate");
    await assert.rejects(session.putDraft({...operation(session, "not acknowledged", 2), format: {bom: false, newline: "\n"}}), /protocol/);
    assert.notEqual(h.records.get(session.sessionId).draft.content, "not acknowledged");
    h.controls.afterStoreFailure = false;
    h.controls.reloadFailure = false;
    assert.equal(await session.recoverPending(), true);
    assert.equal(session.getGeneration(), 1);
});

test("Harmony completed-operation replay requires the original expected baseline and full request", async () => {
    const h = harness();
    const session = await open(h);
    const request = operation(session, "written", 1);
    assert.equal((await session.write(request)).kind, "committed");
    assert.equal((await session.write({...request, expectedBaseline: "different"})).kind, "blocked");
    assert.equal((await session.write({...request, target: {...request.target, displayName: "other.md"}})).kind, "blocked");
    assert.equal((await session.write(request)).kind, "committed");
});
