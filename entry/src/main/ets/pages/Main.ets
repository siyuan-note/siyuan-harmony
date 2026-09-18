/*
 * SiYuan - From thought to insight, with agents
 * Copyright (c) 2020-present, b3log.org
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Affero General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Affero General Public License for more details.
 *
 * You should have received a copy of the GNU Affero General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

import { hilog } from '@kit.PerformanceAnalysisKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { BusinessError, deviceInfo, emitter } from '@kit.BasicServicesKit';
import { common, wantAgent, WantAgent } from '@kit.AbilityKit';
import { webview } from '@kit.ArkWeb';
import { http } from '@kit.NetworkKit';
import napi from 'libentry.so';
import { isNativeTextSelectionMenuDisabled, JSHarmony, SaveExportFileResultEventData } from './JSHarmony';
import { Utils } from './Utils';
import { window } from '@kit.ArkUI';
import { inputMethod } from '@kit.IMEKit';
import inputDevice from '@ohos.multimodalInput.inputDevice';
import { LANSyncMDNS } from './LANSyncMDNS';

interface BootProgressData {
  progress: number;
}

interface BootProgressResponse {
  data?: BootProgressData;
}

const MAIN_PAGE_LOAD_TIMEOUT: number = 30000;

/**
 * 主程序。
 *
 * @author <a href="https://88250.b3log.org">Liang Ding</a>
 * @version 1.2.0.2, Jul 27, 2026
 * @since 3.1.14
 */
@Entry
@Component
struct Main {
  controller: webview.WebviewController = new webview.WebviewController();
  jsHarmony: JSHarmony = new JSHarmony();
  @State isFocusable: boolean = false;
  @State keyBoards: Map<number, inputDevice.KeyboardType> = new Map();
  @State mediaPlaybackRequiresUserGesture: boolean = false;
  @State editMenuOptions: EditMenuOptions = {
    onCreateMenu: this.onCreateMenu,
    onMenuItemClick: this.onMenuItemClick
  };
  private bootProgressRequest?: http.HttpRequest;
  private bootProgressMonitorActive: boolean = false;
  private kernelBootCompleted: boolean = false;
  private mainPageNavigationStarted: boolean = false;
  private mainPageReady: boolean = false;
  private webViewRecoveryScheduled: boolean = false;
  private forceDefaultBootAppearance: boolean = false;
  private pageActive: boolean = true;
  private bootProgressMonitorGeneration: number = 0;
  private bootProgressPollTimerID: number = -1;
  private mainPageWatchdogID: number = -1;

  private deliverOIDCCallback(): void {
    const callback = AppStorage.get<string>('oidcCallback') ?? '';
    if (!callback) {
      return;
    }
    const script = "(() => { if (typeof window.handleOIDCCallback !== 'function') { return 'pending'; } " +
      'window.handleOIDCCallback(' + JSON.stringify(callback) + "); return 'handled'; })()";
    this.controller.runJavaScript(script).then((result: string) => {
      if (result === "handled") {
        AppStorage.delete('oidcCallback');
      }
    }).catch((error: BusinessError) => {
      hilog.error(0x0000, 'siyuan', 'deliver OIDC callback failed: ' + error.message);
    });
  }

  onCreateMenu(menuItems: Array<TextMenuItem>): Array<TextMenuItem> {
    return isNativeTextSelectionMenuDisabled() ? [] : menuItems;
  }

  onMenuItemClick(menuItem: TextMenuItem, textRange: TextRange): boolean {
    return false;
  }

  private async handlePermissionRequest(event: OnPermissionRequestEvent) {
    const request = event.request;
    const origin = request.getOrigin();
    const resources = request.getAccessibleResource();
    if ((origin !== "http://127.0.0.1:6806" && origin !== "http://127.0.0.1:6806/") ||
      resources.length !== 1 || resources[0] !== ProtectedResourceType.AUDIO_CAPTURE) {
      hilog.warn(0x0000, "siyuan",
        "deny web permission request from origin [" + origin + "], resources [" + JSON.stringify(resources) + "]");
      request.deny();
      return;
    }

    try {
      if (await Utils.requestPermissions(["ohos.permission.MICROPHONE"])) {
        request.grant(resources);
      } else {
        request.deny();
      }
    } catch (e) {
      hilog.error(0x0000, "siyuan", "request microphone permission failed: " + e);
      request.deny();
    }
  }

  build() {
    Row() {
      Web({ src: '', controller: this.controller })
        .editMenuOptions(this.editMenuOptions)
        .darkMode(WebDarkMode.Auto)
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .imageAccess(true)
        .onlineImageAccess(true)
        .cacheMode(CacheMode.Online)
        .mediaPlayGestureAccess(this.mediaPlaybackRequiresUserGesture)
        .mixedMode(MixedMode.All)
        .zoomAccess(false)
        .textZoomRatio(100)
        .backgroundColor($r('app.color.bgColor'))
        .focusable(this.isFocusable)
        .onPermissionRequest((event) => {
          if (event) {
            this.handlePermissionRequest(event);
          }
        })
        .onPageBegin((event) => {
          const url = event?.url;
          if (url && url.startsWith("http://127.0.0.1:6806/") &&
            0 > url.indexOf("/appearance/boot/")) {
            this.mediaPlaybackRequiresUserGesture = true;
            this.mainPageNavigationStarted = true;
            this.mainPageReady = false;
          }
        })
        .onPageEnd((event) => {
          const url = event?.url;
          if (this.isReadyMainPage(url)) {
            this.stopBootProgressMonitor();
            this.kernelBootCompleted = true;
            this.mainPageNavigationStarted = true;
            this.mainPageReady = true;
            this.forceDefaultBootAppearance = false;
            this.cancelMainPageWatchdog();
          }
        })
        .onErrorReceive((event) => {
          if (event && event.request.isMainFrame()) {
            hilog.error(0x0000, "siyuan",
              "main frame load failed [url=" + event.request.getRequestUrl() + "]");
            this.forceDefaultBootAppearance = true;
            this.mainPageReady = false;
            this.scheduleWebViewRecovery();
          }
        })
        .onHttpErrorReceive((event) => {
          if (event && event.request.isMainFrame()) {
            hilog.error(0x0000, "siyuan",
              "main frame HTTP error [url=" + event.request.getRequestUrl() + "]");
            this.forceDefaultBootAppearance = true;
            this.mainPageReady = false;
            this.scheduleWebViewRecovery();
          }
        })
        .onRenderExited(() => {
          hilog.error(0x0000, "siyuan", "web render process exited");
          this.forceDefaultBootAppearance = true;
          this.mainPageNavigationStarted = false;
          this.mainPageReady = false;
          this.scheduleWebViewRecovery();
        })
        .onRenderProcessNotResponding((data) => {
          if (this.mainPageReady || this.webViewRecoveryScheduled) {
            return;
          }
          hilog.error(0x0000, "siyuan", "web render process is not responding during startup [process=" +
            data.pid + ", reason=" + data.reason + "]");
          this.forceDefaultBootAppearance = true;
          this.mainPageNavigationStarted = false;
          this.mainPageReady = false;
          try {
            this.controller.terminateRenderProcess();
          } catch (e) {
            hilog.error(0x0000, "siyuan", "terminate unresponsive web render process failed: " + e);
          }
          this.scheduleWebViewRecovery();
        })
        .onControllerAttached(() => {
          const context = Utils.getContext();
          const filesDir = context.filesDir;
          const appDir = filesDir;
          const workspaceBaseDir = filesDir + "/workspaces"

          const ua =
            "SiYuan/" + Utils.appVer + " https://b3log.org/siyuan Harmony " + this.controller.getUserAgent();
          this.controller.setCustomUserAgent(ua);
          this.controller.registerJavaScriptProxy(this.jsHarmony, "JSHarmony",
            [
              "exportByDefault",
              "saveExportFile",
              "saveExportFileV2",
              "openExternal",
              "openAuthURL",
              "getOIDCCallback",
              "print",
              "getScreenWidthPx",
              "changeStatusBarColor",
              "readClipboard",
              "readHTMLClipboard",
              "readSiYuanHTMLClipboard",
              "writeClipboard",
              "writeHTMLClipboard",
              "writeSiYuanHTMLClipboard",
              "returnDesktop",
              "exit",
              "showKeyboard",
              "hideKeyboard",
              "setWebViewFocusable",
              "setNativeTextSelectionMenuDisabled",
              "sendNotification",
              "cancelNotification",
            ]
          );

          emitter.on("isFocusableTrue", () => {
            this.isFocusable = true;
          });

          emitter.on("isFocusableFalse", () => {
            this.isFocusable = false;
            try {
              inputMethod.getController().stopInputSession();
            } catch (e) {
              hilog.error(0x0000, "siyuan", "stop input method session failed: " + e)
            }
          });

          emitter.on("systemLocked", () => {
            this.controller.runJavaScript("javascript:window.lockscreenByMode && window.lockscreenByMode()");
          });

          emitter.on("oidcCallback", () => {
            this.deliverOIDCCallback();
          });

          this.deliverOIDCCallback();

          emitter.on<SaveExportFileResultEventData>("saveExportFileResult", (eventData) => {
            const requestID = eventData.data?.requestID;
            const resultJSON = eventData.data?.resultJSON;
            if (!requestID || !resultJSON) {
              return;
            }
            const argumentsJSON = JSON.stringify([requestID, resultJSON]);
            this.controller.runJavaScript(
              "javascript:window.handleSaveExportFileResult && " +
                "window.handleSaveExportFileResult.apply(null," + argumentsJSON + ");");
          });

          hilog.info(0x0000, "siyuan",
            "appDir [" + appDir + "], workspaceBaseDir [" + workspaceBaseDir + "], ua [" + ua + "], isPhone [" +
            Utils.isPhone() + "]");
          this.startKernel(appDir, workspaceBaseDir);
        })
        .onOverrideUrlLoading((webResourceRequest) => {
          const url = webResourceRequest.getRequestUrl().toLowerCase();

          if (-1 < url.indexOf("127.0.0.1") && 0 > url.indexOf("openExternal")) {
            this.controller.loadUrl(url);
            return true;
          }

          if (webResourceRequest.isMainFrame() && url.startsWith("http")) {
            Utils.openByDefaultBrowser(url);
            return true;
          }
          return false;
        })
        .onTouch((event: TouchEvent) => {
          // 手指抬起时通知前端，用于清除长按多选定时器
          if (event.type === TouchType.Up) {
            this.controller.runJavaScript("javascript:window.dispatchEvent(new Event('nativePhysicalTouchUp'))");
          }
        })
    }
    .width("100%")
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM]);
  }

  async aboutToAppear() {
    this.pageActive = true;
    try {
      Utils.setUIContext(this.getUIContext());
    } catch (e) {
      hilog.error(0x0000, "siyuan", "set ui context failed: " + e);
    }

    await Utils.requestPermissions(["ohos.permission.READ_PASTEBOARD"]);

    if (!Utils.isPhone()) {
      this.isFocusable = true;
    }

    inputDevice.getDeviceList().then(data => {
      for (let i = 0; i < data.length; ++i) {
        inputDevice.getKeyboardType(data[i]).then(type => {
          if (type === inputDevice.KeyboardType.ALPHABETIC_KEYBOARD) {
            this.keyBoards.set(data[i], type);
            this.isFocusable = true;
          }
        });
      }
    });

    inputDevice.on("change", (data) => {
      inputDevice.getKeyboardType(data.deviceId).then((type) => {
        if (type === inputDevice.KeyboardType.ALPHABETIC_KEYBOARD && data.type === 'add') {
          this.keyBoards.set(data.deviceId, type);
          this.isFocusable = true;
        }
      });
      if (this.keyBoards.get(data.deviceId) === inputDevice.KeyboardType.ALPHABETIC_KEYBOARD &&
        data.type === 'remove') {
        this.keyBoards.delete(data.deviceId);
      }
    });

    if (napi.isHttpServing()) {
      if (this.kernelBootCompleted) {
        this.mainPageNavigationStarted = false;
        this.navigateToMainPage();
      } else {
        if (this.forceDefaultBootAppearance) {
          this.loadBootPage();
        }
        this.startBootProgressMonitor();
      }
    }
  }

  aboutToDisappear(): void {
    this.pageActive = false;
    this.cancelMainPageWatchdog();
    this.stopBootProgressMonitor();
  }

  private stopBootProgressMonitor(): void {
    this.bootProgressMonitorActive = false;
    this.bootProgressMonitorGeneration++;
    if (0 <= this.bootProgressPollTimerID) {
      clearTimeout(this.bootProgressPollTimerID);
      this.bootProgressPollTimerID = -1;
    }
    const request = this.bootProgressRequest;
    this.bootProgressRequest = undefined;
    if (request) {
      try {
        request.destroy();
      } catch (e) {
        hilog.debug(0x0000, "siyuan", "destroy boot progress request failed: " + e);
      }
    }
  }

  // 移动端容器启用桌面模式时，前端加载的是桌面 bundle（/stage/build/desktop/），
  // 它依赖 WebView 自身管理软键盘，不会调用 showKeyboard 桥接。此时不能禁用 WebView 焦点，
  // 否则软键盘收起一次后就再也无法重新获取焦点。https://github.com/siyuan-note/siyuan/issues/18028
  private isDesktopMode(): boolean {
    try {
      const url = this.controller.getUrl();
      return null != url && -1 < url.indexOf("/stage/build/desktop/");
    } catch (e) {
      return false;
    }
  }

  private listenKeyboard() {
    if (!Utils.isPhone()) {
      return;
    }

    if (0 < this.keyBoards.size) {
      return;
    }

    window.getLastWindow(this.getUIContext().getHostContext()).then(currentWindow => {
      currentWindow.on('keyboardHeightChange', (height) => {
        if (window.WindowStatusType.FLOATING === currentWindow.getWindowStatus()) {
          return;
        }

        if (height > 0) {
          this.controller.runJavaScript("javascript:showKeyboardToolbar()");
          this.isFocusable = true;
        } else {
          this.controller.runJavaScript("javascript:hideKeyboardToolbar()")
          // 桌面模式和物理键盘输入依赖 WebView 保持焦点，否则软键盘收起后无法继续输入
          if (1 > this.keyBoards.size && !this.isDesktopMode()) {
            this.isFocusable = false;
          }
        }
      });
    });
  }

  private startKernel(appDir: string, workspaceBaseDir: string) {
    let context = getContext(this) as common.UIAbilityContext;

    let wantAgentInfo: wantAgent.WantAgentInfo = {
      wants: [
        {
          bundleName: Utils.bundleName,
          abilityName: "EntryAbility"
        }
      ],
      actionType: wantAgent.OperationType.START_ABILITY,
      requestCode: 0,
      actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
    };

    hilog.info(0x0000, "siyuan", "start kernel in background");

    wantAgent.getWantAgent(wantAgentInfo).then((wantAgentObj: WantAgent) => {
      backgroundTaskManager.startBackgroundRunning(context,
        backgroundTaskManager.BackgroundMode.DATA_TRANSFER, wantAgentObj).then(() => {
        const localIPs = Utils.getIPAddressList();
        hilog.info(0x0000, "siyuan", "get local ips [" + localIPs + "]");
        const osVer: string = deviceInfo.osFullName.replace("OpenHarmony-", "");
        napi.startKernel(appDir, workspaceBaseDir, localIPs, osVer);
        LANSyncMDNS.shared.start(context);
        hilog.info(0x0000, "siyuan",
          "started kernel [appDir=" + appDir + ", workspaceBaseDir=" + workspaceBaseDir + ", localIPs=" + localIPs +
            ", osVer=" + osVer + "]");
        this.waitFotKernelHttpServing().then(() => {
          this.loadBootPage();
          this.startBootProgressMonitor();
          hilog.info(0x0000, "siyuan", "load boot page");
        });

        this.listenKeyboard();
      }).catch((err: BusinessError) => {
        hilog.error(0x0000, "siyuan", "start kernel in background failed: " + err)
        void Utils.exit();
      });
    });
  }

  private loadBootPage(): void {
    this.mediaPlaybackRequiresUserGesture = false;
    this.mainPageNavigationStarted = false;
    this.mainPageReady = false;
    const safeParameter = this.forceDefaultBootAppearance ? "&appearance=0" : "";
    try {
      this.controller.loadUrl("http://127.0.0.1:6806/appearance/boot/index.html?v=" + Utils.appVer + safeParameter);
    } catch (e) {
      hilog.error(0x0000, "siyuan", "load boot page failed: " + e);
      this.forceDefaultBootAppearance = true;
      this.scheduleWebViewRecovery();
    }
  }

  private startBootProgressMonitor(): void {
    if (!this.pageActive) {
      return;
    }
    if (this.kernelBootCompleted) {
      this.navigateToMainPage();
      return;
    }
    if (this.bootProgressMonitorActive) {
      return;
    }

    this.bootProgressMonitorActive = true;
    const generation = ++this.bootProgressMonitorGeneration;
    this.pollBootProgress(generation);
  }

  private pollBootProgress(generation: number): void {
    if (!this.bootProgressMonitorActive || generation !== this.bootProgressMonitorGeneration) {
      return;
    }

    const request = http.createHttp();
    this.bootProgressRequest = request;
    request.request("http://127.0.0.1:6806/api/system/bootProgress", {
      method: http.RequestMethod.GET,
      expectDataType: http.HttpDataType.STRING,
      usingCache: false,
      connectTimeout: 1000,
      readTimeout: 1000
    }, (error: BusinessError, response: http.HttpResponse) => {
      if (this.bootProgressRequest === request) {
        this.bootProgressRequest = undefined;
      }
      try {
        request.destroy();
      } catch (e) {
        hilog.debug(0x0000, "siyuan", "destroy boot progress request failed: " + e);
      }

      let completed = false;
      if (!error && 200 === response.responseCode && typeof response.result === "string") {
        try {
          const result = JSON.parse(response.result) as BootProgressResponse;
          completed = (result.data?.progress ?? 0) >= 100;
        } catch (e) {
          completed = false;
        }
      }

      if (!this.bootProgressMonitorActive || generation !== this.bootProgressMonitorGeneration) {
        return;
      }
      if (completed) {
        this.stopBootProgressMonitor();
        this.kernelBootCompleted = true;
        this.navigateToMainPage();
        return;
      }
      this.bootProgressPollTimerID = setTimeout(() => {
        this.bootProgressPollTimerID = -1;
        this.pollBootProgress(generation);
      }, 200);
    });
  }

  private navigateToMainPage(): void {
    if (!this.kernelBootCompleted || !this.pageActive) {
      return;
    }
    this.scheduleMainPageWatchdog();
    if (this.mainPageReady) {
      this.mainPageNavigationStarted = true;
      this.cancelMainPageWatchdog();
      return;
    }
    if (this.mainPageNavigationStarted) {
      return;
    }

    this.mediaPlaybackRequiresUserGesture = true;
    this.mainPageNavigationStarted = true;
    this.mainPageReady = false;
    this.forceDefaultBootAppearance = false;
    try {
      this.controller.loadUrl("http://127.0.0.1:6806/");
    } catch (e) {
      hilog.error(0x0000, "siyuan", "load main page failed: " + e);
      this.mainPageNavigationStarted = false;
      this.scheduleWebViewRecovery();
    }
  }

  private isReadyMainPage(url?: string): boolean {
    return !!url && (-1 < url.indexOf("/stage/build/") || -1 < url.indexOf("/check-auth"));
  }

  private scheduleMainPageWatchdog(): void {
    if (!this.kernelBootCompleted || !this.pageActive) {
      return;
    }
    this.cancelMainPageWatchdog();
    this.mainPageWatchdogID = setTimeout(() => {
      this.mainPageWatchdogID = -1;
      if (!this.kernelBootCompleted || !this.pageActive) {
        return;
      }
      if (this.mainPageReady) {
        return;
      }

      hilog.error(0x0000, "siyuan", "main page load timed out, reload it");
      this.mainPageNavigationStarted = false;
      this.navigateToMainPage();
    }, MAIN_PAGE_LOAD_TIMEOUT);
  }

  private cancelMainPageWatchdog(): void {
    if (0 <= this.mainPageWatchdogID) {
      clearTimeout(this.mainPageWatchdogID);
      this.mainPageWatchdogID = -1;
    }
  }

  private scheduleWebViewRecovery(): void {
    if (this.webViewRecoveryScheduled) {
      return;
    }
    this.mainPageReady = false;
    this.webViewRecoveryScheduled = true;
    setTimeout(() => {
      this.webViewRecoveryScheduled = false;
      if (!this.pageActive) {
        return;
      }
      if (this.kernelBootCompleted) {
        this.mainPageNavigationStarted = false;
        this.navigateToMainPage();
      } else {
        this.mainPageNavigationStarted = false;
        this.forceDefaultBootAppearance = true;
        this.loadBootPage();
        this.startBootProgressMonitor();
      }
    }, 300);
  }

  async waitFotKernelHttpServing() {
    while (true) {
      await this.sleep(10);
      const ok = await napi.isHttpServing();
      hilog.debug(0x0000, "siyuan", "http serving [" + ok + "]");
      if (ok) {
        break;
      }
    }
  }

  async sleep(mills: number) {
    await new Promise<void>(resolve => setTimeout(resolve, mills))
  }

  onBackPress(): boolean | void {
    hilog.debug(0x0000, "siyuan", "on back pressed")
    this.controller.runJavaScript("javascript:window.goBack ? window.goBack() : window.history.back()");
    return true;
  }
}
