/* SPDX-License-Identifier: AGPL-3.0-or-later */
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { webview } from '@kit.ArkWeb';
import { JSHarmony } from './JSHarmony';

export const NATIVE_BRIDGE_NAME: string = '__SiYuanNativeBridge';
export const BRIDGE_METHODS: string[] = ["exportByDefault", "saveExportFile", "saveExportFileV2", "openExternal", "openAuthURL", "getOIDCCallback", "print", "getScreenWidthPx", "getSystemFonts", "changeStatusBarColor", "readClipboard", "readHTMLClipboard", "readSiYuanHTMLClipboard", "writeClipboard", "writeHTMLClipboard", "writeSiYuanHTMLClipboard", "returnDesktop", "exit", "showKeyboard", "hideKeyboard", "setWebViewFocusable", "setNativeTextSelectionMenuDisabled", "sendNotification", "cancelNotification"];
const ORIGIN: string = 'http://127.0.0.1:6806';
const DOCUMENT_PATHS: string[] = [
  '/stage/build/mobile/', '/stage/build/mobile/index.html',
  '/stage/build/desktop/', '/stage/build/desktop/index.html', '/check-auth'
];

function randomToken(): string {
  const bytes = cryptoFramework.createRandom().generateRandomSync(32).data;
  let token = '';
  for (let i = 0; i < bytes.length; i++) {
    token += bytes[i].toString(16).padStart(2, '0');
  }
  return token;
}

export function isTrustedBridgeDocument(url: string): boolean {
  const documentURL = url.split('#', 1)[0].split('?', 1)[0];
  return DOCUMENT_PATHS.some((path: string) => documentURL === ORIGIN + path);
}

export function isAllowedMainDocument(url: string): boolean {
  const documentURL = url.split('#', 1)[0].split('?', 1)[0];
  return isTrustedBridgeDocument(url) || documentURL === ORIGIN + '/' ||
    documentURL === ORIGIN + '/appearance/boot/index.html';
}

// Permissions use prefix paths. Exact document matching below is also mandatory.
export const BRIDGE_PERMISSION: string = '{"javascriptProxyPermission":{"urlPermissionList":[' +
  DOCUMENT_PATHS.map((path: string): string =>
    '{"scheme":"http","host":"127.0.0.1","port":"6806","path":' + JSON.stringify(path) + '}').join(',') + ']}}';

export interface AVMapNativeBoundary {
  version: number;
  enabled: boolean;
}

export class NativeBridgeBoundary {
  private secret: string = randomToken();
  private installed: boolean = false;
  private documentToken: string = '';
  private generation: number = 0;

  setInstalled(installed: boolean): void {
    this.installed = installed;
    this.revokeDocument();
  }

  revokeDocument(): void {
    this.documentToken = '';
    this.generation++;
  }

  authorize(secret: string, callerURL: string): void {
    if (!this.installed || secret !== this.secret || !isTrustedBridgeDocument(callerURL)) {
      throw new Error('Untrusted native bridge caller');
    }
  }

  capability(secret: string, token: string, callerURL: string): AVMapNativeBoundary {
    this.authorize(secret, callerURL);
    return { version: 1, enabled: !!token && token === this.documentToken };
  }

  // Called only by native code after a trusted main-frame onPageEnd. runJavaScript
  // targets the main page, never an iframe; no DOM script node contains the token.
  activationScript(): string {
    this.documentToken = randomToken();
    return "(() => { const bind = window.__siyuanBindMapBoundary; return typeof bind === 'function' && bind(" +
      JSON.stringify(this.documentToken) + "); })()";
  }

  currentGeneration(): number {
    return this.generation;
  }

  // Native document-start injection runs before page scripts. Even if ArkWeb
  // injects into child frames, only a trusted top document receives the closure.
  // Function.toString() exposes variable names, never secret literal values.
  bootstrapScript(): string {
    return `(() => {
      if (window !== window.top) return;
      const allowed = ${JSON.stringify(DOCUMENT_PATHS)};
      if (location.origin !== ${JSON.stringify(ORIGIN)} || !allowed.includes(location.pathname)) return;
      const raw = window[${JSON.stringify(NATIVE_BRIDGE_NAME)}];
      if (!raw) return;
      const secret = ${JSON.stringify(this.secret)};
      let documentToken = '';
      let retired = false;
      const waiters = new Set();
      const unsupported = () => ({ version: 1, enabled: false });
      const settle = result => {
        for (const waiter of waiters) {
          clearTimeout(waiter.timer);
          waiter.resolve(result);
        }
        waiters.clear();
      };
      const revoke = () => { documentToken = ''; settle(unsupported()); };
      window.addEventListener('pagehide', () => { retired = true; revoke(); });
      window.addEventListener('pageshow', event => { if (event.persisted) retired = false; });
      const facade = Object.create(null);
      for (const method of ${JSON.stringify(BRIDGE_METHODS)}) {
        const nativeMethod = raw[method].bind(raw);
        Object.defineProperty(facade, method, { value: (...args) => nativeMethod(secret, ...args) });
      }
      const capability = raw.getAVMapNativeBoundary.bind(raw);
      Object.defineProperty(window, 'JSHarmony', { value: Object.freeze(facade) });
      const readCapability = () => {
        try { return capability(secret, documentToken); } catch (_) { return unsupported(); }
      };
      Object.defineProperty(window, 'getAVMapNativeBoundary', {
        value: () => {
          if (retired) return unsupported();
          if (documentToken) return readCapability();
          return new Promise(resolve => {
            const waiter = { resolve, timer: 0 };
            waiter.timer = setTimeout(() => {
              waiters.delete(waiter);
              resolve(unsupported());
            }, 2500);
            waiters.add(waiter);
          });
        }
      });
      Object.defineProperty(window, '__siyuanRevokeMapBoundary', { value: revoke });
      Object.defineProperty(window, '__siyuanBindMapBoundary', {
        value: token => {
          if (retired) return false;
          documentToken = token;
          const result = readCapability();
          settle(result);
          return result.enabled === true;
        }
      });
    })()`;
  }
}

// All registered calls validate the actual calling frame synchronously before
// delegating, including methods returning a Promise. getUrl() is not authority.
export class GuardedJSHarmony {
  private target: JSHarmony;
  private controller: webview.WebviewController;
  private boundary: NativeBridgeBoundary;

  constructor(target: JSHarmony, controller: webview.WebviewController, boundary: NativeBridgeBoundary) {
    this.target = target;
    this.controller = controller;
    this.boundary = boundary;
  }

  private authorize(secret: string): void {
    this.boundary.authorize(secret, this.controller.getLastJavascriptProxyCallingFrameUrl());
  }

  getAVMapNativeBoundary(secret: string, token: string): AVMapNativeBoundary {
    return this.boundary.capability(secret, token, this.controller.getLastJavascriptProxyCallingFrameUrl());
  }

  exportByDefault(secret: string, url: string): void {
    this.authorize(secret);
    return this.target.exportByDefault(url);
  }

  saveExportFile(secret: string, url: string): Promise<void> {
    this.authorize(secret);
    return this.target.saveExportFile(url);
  }

  saveExportFileV2(secret: string, url: string, requestID: string): Promise<void> {
    this.authorize(secret);
    return this.target.saveExportFileV2(url, requestID);
  }

  openExternal(secret: string, url: string): void {
    this.authorize(secret);
    return this.target.openExternal(url);
  }

  openAuthURL(secret: string, url: string): void {
    this.authorize(secret);
    return this.target.openAuthURL(url);
  }

  getOIDCCallback(secret: string): string {
    this.authorize(secret);
    return this.target.getOIDCCallback();
  }

  print(secret: string, title: string, html: string): Promise<void> {
    this.authorize(secret);
    return this.target.print(title, html);
  }

  getScreenWidthPx(secret: string): Promise<number> {
    this.authorize(secret);
    return this.target.getScreenWidthPx();
  }

  getSystemFonts(secret: string): Promise<string> {
    this.authorize(secret);
    return this.target.getSystemFonts();
  }

  changeStatusBarColor(secret: string, color: string, appearanceMode: number): void {
    this.authorize(secret);
    return this.target.changeStatusBarColor(color, appearanceMode);
  }

  readClipboard(secret: string): string {
    this.authorize(secret);
    return this.target.readClipboard();
  }

  readHTMLClipboard(secret: string): string {
    this.authorize(secret);
    return this.target.readHTMLClipboard();
  }

  readSiYuanHTMLClipboard(secret: string): string {
    this.authorize(secret);
    return this.target.readSiYuanHTMLClipboard();
  }

  writeClipboard(secret: string, text: string): boolean {
    this.authorize(secret);
    return this.target.writeClipboard(text);
  }

  writeHTMLClipboard(secret: string, text: string, html: string): boolean {
    this.authorize(secret);
    return this.target.writeHTMLClipboard(text, html);
  }

  writeSiYuanHTMLClipboard(secret: string, text: string, html: string, siyuanHTML: string): boolean {
    this.authorize(secret);
    return this.target.writeSiYuanHTMLClipboard(text, html, siyuanHTML);
  }

  returnDesktop(secret: string): void {
    this.authorize(secret);
    return this.target.returnDesktop();
  }

  exit(secret: string): void {
    this.authorize(secret);
    return this.target.exit();
  }

  showKeyboard(secret: string): void {
    this.authorize(secret);
    return this.target.showKeyboard();
  }

  hideKeyboard(secret: string): void {
    this.authorize(secret);
    return this.target.hideKeyboard();
  }

  setWebViewFocusable(secret: string, focusable: boolean): void {
    this.authorize(secret);
    return this.target.setWebViewFocusable(focusable);
  }

  setNativeTextSelectionMenuDisabled(secret: string, disabled: boolean): void {
    this.authorize(secret);
    return this.target.setNativeTextSelectionMenuDisabled(disabled);
  }

  sendNotification(secret: string, channel: string, title: string, body: string, delayInSeconds: number): Promise<number> {
    this.authorize(secret);
    return this.target.sendNotification(channel, title, body, delayInSeconds);
  }

  cancelNotification(secret: string, id: number): Promise<void> {
    this.authorize(secret);
    return this.target.cancelNotification(id);
  }
}
