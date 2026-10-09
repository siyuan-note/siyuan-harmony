const assert = require('node:assert/strict');
const { test } = require('node:test');
const { readFileSync } = require('node:fs');
const { resolve } = require('node:path');
const { runInNewContext } = require('node:vm');
const ts = require(require.resolve('typescript', {
  paths: [process.env.SIYUAN_APP_DIR || resolve(__dirname, '../../siyuan/app')],
}));
const root = resolve(__dirname, '../entry/src/main/ets/pages');
const source = readFileSync(resolve(root, 'NativeBridgeBoundary.ets'), 'utf8');
let random = 0;
const moduleContext = { exports: {} };
runInNewContext(ts.transpileModule(source, { compilerOptions: {
  module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022,
} }).outputText, { module: moduleContext, exports: moduleContext.exports, require: id =>
  id === '@kit.CryptoArchitectureKit' ? { cryptoFramework: { createRandom: () => ({
    generateRandomSync: length => ({ data: new Uint8Array(length).fill(++random) }),
  }) } } : {} });
const api = moduleContext.exports;
const { NativeBridgeBoundary, GuardedJSHarmony, BRIDGE_METHODS, NATIVE_BRIDGE_NAME,
  isTrustedBridgeDocument, isAllowedMainDocument } = api;
const MAIN = 'http://127.0.0.1:6806/stage/build/mobile/';
const harness = (url = MAIN, child = false) => {
  const boundary = new NativeBridgeBoundary();
  let caller = url;
  const calls = [];
  const target = Object.fromEntries(BRIDGE_METHODS.map(name => [name, (...args) => {
    calls.push({ name, args });
    return name === 'getSystemFonts' ? Promise.resolve('fonts') : 'result';
  }]));
  const raw = new GuardedJSHarmony(target, {
    getLastJavascriptProxyCallingFrameUrl: () => caller,
    getUrl: () => { throw Error('Must not use top URL to authorize caller'); },
  }, boundary);
  boundary.setInstalled(true);
  const listeners = new Map();
  const timers = new Map();
  let timerID = 0;
  const window = { [NATIVE_BRIDGE_NAME]: raw,
    addEventListener: (name, callback) => listeners.set(name, callback) };
  window.top = child ? {} : window;
  const context = { window, location: new URL(url),
    setTimeout: (callback, delay) => { assert.equal(delay, 2500); timers.set(++timerID, callback); return timerID; },
    clearTimeout: id => timers.delete(id) };
  const script = boundary.bootstrapScript();
  runInNewContext(script, context);
  return { boundary, raw, window, context, calls, script, listeners, timers, setCaller: value => { caller = value; } };
};

test('only exact bridge documents, not same-host wrapper, provider, or prefix paths', () => {
  for (const path of ['/stage/build/mobile/', '/stage/build/mobile/index.html',
    '/stage/build/desktop/', '/stage/build/desktop/index.html', '/check-auth']) {
    assert.equal(isTrustedBridgeDocument('http://127.0.0.1:6806' + path + '?r=ABC#x'), true);
  }
  for (const url of ['about:blank', 'about:srcdoc', 'null', 'data:text/html,x',
    'https://127.0.0.1:6806/stage/build/mobile/',
    MAIN.replace(':6806', ':6807'), MAIN.replace('127.0.0.1', 'localhost'),
    MAIN.replace('127.0.0.1', 'user@127.0.0.1'), MAIN.replace('127.0.0.1', '127.0.0.1.evil'),
    MAIN + 'nested.html', MAIN + '../mobile/', MAIN + '%2e%2e/mobile/',
    'http://127.0.0.1:6806/check-auth-evil',
    'http://127.0.0.1:6806/stage/map/wrapper.html?provider=amap',
    'http://127.0.0.1:6806/stage/map/index.html?provider=amap']) {
    assert.equal(isTrustedBridgeDocument(url), false, url);
  }
});

test('every registered method requires a secret before side effects', () => {
  const h = harness();
  for (const name of BRIDGE_METHODS) {
    assert.throws(() => h.raw[name]('forged', 'x'), /Untrusted/);
  }
  assert.throws(() => h.raw.getAVMapNativeBoundary('forged', 'x'), /Untrusted/);
  assert.equal(h.calls.length, 0);
  assert.deepEqual(Object.getOwnPropertyNames(GuardedJSHarmony.prototype)
    .filter(name => !['constructor', 'authorize', 'getAVMapNativeBoundary'].includes(name)).sort(),
  Array.from(BRIDGE_METHODS).sort());
});

test('normal bridge keeps arguments, synchronous results and Promise results', async () => {
  const h = harness();
  assert.equal(h.window.JSHarmony.readClipboard(), 'result');
  assert.equal(h.window.JSHarmony.writeSiYuanHTMLClipboard('a', '<b>', 'c'), 'result');
  assert.equal(await h.window.JSHarmony.getSystemFonts(), 'fonts');
  assert.deepEqual(h.calls[1], { name: 'writeSiYuanHTMLClipboard', args: ['a', '<b>', 'c'] });
});

test('even a stolen facade fails actual child-frame URL authentication', () => {
  const h = harness();
  for (const url of ['about:srcdoc', 'about:blank', 'https://webapi.amap.com/',
    'http://127.0.0.1:6806/stage/map/wrapper.html']) {
    h.setCaller(url);
    assert.throws(() => h.window.JSHarmony.readClipboard(), /Untrusted/);
  }
  assert.equal(h.calls.length, 0);
});

test('document-start installs no facade in children, including trusted-path children', () => {
  for (const url of [MAIN, 'http://127.0.0.1:6806/stage/map/wrapper.html', 'about:blank']) {
    const h = harness(url, true);
    assert.equal(h.window.JSHarmony, undefined);
    assert.equal(h.window.getAVMapNativeBoundary, undefined);
  }
  assert.equal(harness('http://127.0.0.1:6806/stage/map/wrapper.html').window.JSHarmony, undefined);
});

test('secret stays in closure, cannot be recovered through function source or replaced raw methods', () => {
  const h = harness();
  const secret = /const secret = "(\w+)"/.exec(h.script)[1];
  for (const method of BRIDGE_METHODS) {
    assert.equal(h.window.JSHarmony[method].toString().includes(secret), false);
  }
  assert.equal(h.window.getAVMapNativeBoundary.toString().includes(secret), false);
  h.raw.readClipboard = () => { throw Error('replacement captured secret'); };
  assert.equal(h.window.JSHarmony.readClipboard(), 'result');
  assert.equal(Object.isFrozen(h.window.JSHarmony), true);
});

test('capability needs main-page nonce handshake; navigation/recovery/destroy revoke it', async () => {
  const h = harness();
  const pending = h.window.getAVMapNativeBoundary();
  assert.equal(typeof pending.then, 'function');
  assert.equal(runInNewContext(h.boundary.activationScript(), h.context), true);
  assert.equal((await pending).enabled, true);
  assert.equal(h.timers.size, 0);
  assert.equal(h.window.getAVMapNativeBoundary().version, 1);
  assert.equal(h.window.getAVMapNativeBoundary().enabled, true);
  h.boundary.revokeDocument();
  assert.equal(h.window.getAVMapNativeBoundary().enabled, false);
  runInNewContext(h.boundary.activationScript(), h.context);
  assert.equal(h.window.getAVMapNativeBoundary().enabled, true);
  h.boundary.setInstalled(false);
  assert.equal(h.window.getAVMapNativeBoundary().enabled, false);
  assert.throws(() => h.window.JSHarmony.readClipboard(), /Untrusted/);
  h.boundary.setInstalled(true);
  assert.equal(h.window.getAVMapNativeBoundary().enabled, false);
  runInNewContext(h.boundary.activationScript(), h.context);
  assert.equal(h.window.getAVMapNativeBoundary().enabled, true);
});

const mainSource = readFileSync(resolve(root, 'Main.ets'), 'utf8');
const mainAST = ts.createSourceFile('Main.ets', mainSource, ts.ScriptTarget.Latest, true);
function callback(name, context) {
  let found;
  const visit = node => {
    if (ts.isCallExpression(node) && ts.isPropertyAccessExpression(node.expression) &&
      node.expression.name.text === name) found = node.arguments[0].getText(mainAST);
    ts.forEachChild(node, visit);
  };
  visit(mainAST);
  assert.ok(found, name);
  return runInNewContext(ts.transpileModule(`(${found});`, { compilerOptions: {
    target: ts.ScriptTarget.ES2022,
  } }).outputText, context);
}
const request = (url, main) => ({ getRequestUrl: () => url, isMainFrame: () => main });
test('real navigation callbacks never promote child frames or reload/case-fold URLs', () => {
  const opened = [];
  const ctx = { isAllowedMainDocument, Utils: { openByDefaultBrowser: url => opened.push(url) },
    controller: { loadUrl: () => { throw Error('frame promotion'); } } };
  const intercept = callback('onLoadIntercept', ctx);
  const override = callback('onOverrideUrlLoading', ctx);
  assert.equal(intercept({ data: request(MAIN, false) }), true);
  assert.equal(intercept({ data: request('http://127.0.0.1:6806/', false) }), true);
  for (const path of ['wrapper', 'index']) {
    const url = `http://127.0.0.1:6806/stage/map/${path}.html?provider=amap`;
    assert.equal(intercept({ data: request(url, false) }), false);
    assert.equal(intercept({ data: request(url, true) }), true);
    assert.equal(override(request(url, false)), false);
  }
  assert.equal(override(request(MAIN + '?r=MixedCase', true)), false);
  assert.equal(override(request('https://evil.example/?127.0.0.1', true)), true);
  assert.deepEqual(opened, ['https://evil.example/?127.0.0.1']);
  assert.equal(intercept({ data: request('https://evil.example/', true) }), true);
});

test('wiring uses guarded proxy, native permissions, doc-start bootstrap and revocation', () => {
  assert.match(mainSource, /registerJavaScriptProxy\(this.guardedBridge, NATIVE_BRIDGE_NAME/);
  assert.match(mainSource, /\[\], BRIDGE_PERMISSION/);
  assert.match(mainSource, /javaScriptOnDocumentStart\(this.bridgeScripts\)/);
  assert.match(mainSource, /onPageBegin\(\(event\) => \{\s*this.revokeMapBoundary\(\)/);
  assert.match(mainSource, /scheduleWebViewRecovery\(\): void \{\s*this.revokeMapBoundary\(\)/);
  assert.match(mainSource, /deleteJavaScriptRegister\(NATIVE_BRIDGE_NAME\)/);
  assert.doesNotMatch(source, /controller\.getUrl\(/);
  for (const rule of JSON.parse(api.BRIDGE_PERMISSION).javascriptProxyPermission.urlPermissionList) {
    assert.equal(rule.scheme, 'http'); assert.equal(rule.host, '127.0.0.1'); assert.equal(rule.port, '6806');
    assert.ok(rule.path.length > 1); assert.ok(!rule.path.startsWith('/stage/map'));
  }
});


test('first-load wait times out below shared host timeout, and explicit retry can succeed', async () => {
  const h = harness();
  const first = h.window.getAVMapNativeBoundary();
  for (const timer of h.timers.values()) timer();
  h.timers.clear();
  assert.equal((await first).enabled, false);
  const retry = h.window.getAVMapNativeBoundary();
  runInNewContext(h.boundary.activationScript(), h.context);
  assert.equal((await retry).enabled, true);
  assert.equal((await first).enabled, false);
  assert.equal(h.timers.size, 0);
});

test('pagehide or native revocation resolves every pending waiter false and clears timers', async () => {
  for (const native of [false, true]) {
    const h = harness();
    const first = h.window.getAVMapNativeBoundary();
    const second = h.window.getAVMapNativeBoundary();
    if (native) {
      h.boundary.revokeDocument();
      h.window.__siyuanRevokeMapBoundary();
    } else {
      h.listeners.get('pagehide')();
    }
    assert.equal((await first).enabled, false);
    assert.equal((await second).enabled, false);
    assert.equal(h.timers.size, 0);
    if (!native) {
      assert.equal(runInNewContext(h.boundary.activationScript(), h.context), false);
      assert.equal(h.window.getAVMapNativeBoundary().enabled, false);
    }
    assert.equal((await first).enabled, false);
  }
});
