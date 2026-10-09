# Shared Web map native boundary

This change hardens the Harmony shell; it does not implement another map SDK or a
native map renderer. The shared host still owns provider URL policy, both CSP
layers, opaque SDK iframe isolation, and the typed postMessage protocol. Native
capability is not evidence of network isolation.

## Design

- Register `__SiYuanNativeBridge`, never the unguarded `JSHarmony` instance. All 24
  existing methods retain their argument/return contract through a JavaScript
  facade. The native registration includes object-level scheme/host/port/path
  permissions and an empty asynchronous-method list, preserving returned Promises.
- Every native entry validates an unguessable 256-bit controller secret and
  `getLastJavascriptProxyCallingFrameUrl()` synchronously, before any asynchronous
  work. Only exact mobile/desktop entry documents and `/check-auth` are accepted.
  Native path permissions are prefix-based, so they are not the final check.
- Native document-start injection constructs the facade before page scripts. It
  returns immediately in a child frame or a non-allowlisted document. The secret
  lives only in a closure; it is not in a DOM script node or a global variable.
  Facade methods capture native functions before page code can replace them.
  This is a secret-confined main-document facade, not a claim that ArkWeb supplies
  a main-frame identity on JS proxy calls. It assumes trusted application document
  scripts and does not attempt to defend against arbitrary main-document XSS.
- `onLoadIntercept` denies privileged entry documents in child frames and denies
  non-application main documents, including the map wrapper and SDK host.
  `onOverrideUrlLoading` never upgrades a child navigation to `loadUrl`, and never
  lowercases a navigation URL. HTTP iframe interception belongs in
  `onLoadIntercept`, because the override callback does not cover it.
- `window.getAVMapNativeBoundary()` returns an object, or a Promise while first
  waiting for the main-document handshake. It reports `{version: 1, enabled: true}` only once
  native code has injected a fresh navigation nonce into the trusted main-page
  facade at `onPageEnd`. Registration must also have succeeded. Page start, load
  failure/recovery, and disappearance revoke the nonce; appearance re-registers
  the guarded proxy, and disappearance unregisters it. An old nonce cannot
  activate a later document. The per-controller secret is separate from the
  per-navigation capability nonce.
- If injection ordering, registration, nonce handoff, or frame URL reporting does
  not behave as required, the capability is absent, throws, or is false. The
  shared client must fail closed and must not infer support from the Harmony UA.

## API evidence

Official OpenHarmony documentation (consulted 2026-10-09):

- [WebviewController](https://github.com/openharmony/docs/blob/master/en/application-dev/reference/apis-arkweb/arkts-apis-webview-WebviewController.md):
  `registerJavaScriptProxy` exposes the object to all frames; the optional
  `permission` argument and `getLastJavascriptProxyCallingFrameUrl` are API 12+.
  Do not use `getUrl` to authenticate the calling frame.
- [Web attributes](https://github.com/openharmony/docs/blob/master/en/application-dev/reference/apis-arkweb/arkts-basic-components-web-attributes.md):
  `javaScriptOnDocumentStart` is API 11+ and runs after creation of the HTML root,
  before other document content is loaded.
- [Web events](https://github.com/openharmony/docs/blob/master/en/application-dev/reference/apis-arkweb/arkts-basic-components-web-events.md):
  `onPageBegin` and `onPageEnd` are main-frame events; `onLoadIntercept` includes
  iframe navigation. `onOverrideUrlLoading` does not cover HTTP(S) iframe loads
  or redirects started through `loadUrl`.
- [JS bridge permissions](https://github.com/openharmony/docs/blob/master/en/application-dev/web/arkweb-ndk-jsbridge.md):
  scheme/host/port exact matching, path prefix matching.
- [Crypto framework](https://github.com/openharmony/docs/blob/master/en/application-dev/reference/apis-crypto-architecture-kit/js-apis-cryptoFramework.md):
  `createRandom().generateRandomSync` is API 10+.

The target remains HarmonyOS API 20 and the compatible minimum API 18.

## Verification and release gates

Run `node --test scripts/*.test.cjs` (TypeScript resolved from the adjacent SiYuan
app, or set `SIYUAN_APP_DIR`). These tests execute the actual guard/facade source
and extracted navigation callbacks with mocked native APIs. They cover allowed
entry URLs, hostile hosts/ports/paths/opaque URLs, every exposed native method,
normal synchronous/Promise forwarding, child frames, function-source secrecy,
raw-method replacement, nonce revocation/recovery, and navigation non-promotion.
They do not prove ArkWeb runtime behavior.

No Harmony SDK, hvigor, ohpm, or device/emulator is present in this executor.
Native compilation and the following API 18/API 20 runtime matrix are NOT RUN:

1. Cold boot, authentication, mobile/desktop switching: verify document-start
   facade sees the registered proxy before app scripts; check clipboard, fonts,
   export, IME, OIDC, notifications, and exit. Confirm first-load map availability
   and a map opened while the main page has not reached `onPageEnd` fails closed.
2. Exercise shared opaque map SDK iframe and wrapper, about:blank/srcdoc/blob,
   provider redirects, trusted-entry redirect targets, and attempted top/popup
   navigation. Try every raw bridge method and capability with missing/forged
   secrets. No privileged side effect or top-document promotion may occur.
3. Reload, Back/Forward, switching desktop mode, navigation during pending
   activation, renderer termination/recovery, and disappear/reappear. Old
   capability nonce must fail; fresh main-document handoff must recover.
4. Verify actual frame URL and native permission behavior for opaque frames and
   redirect chains. The secret guard must still deny calls even if URL reporting
   differs from the mock. Never relax the secret or exact URL check to make a map
   render.
5. Validate shared CSP/network isolation separately; a successful native
   capability handshake says nothing about provider network access.
