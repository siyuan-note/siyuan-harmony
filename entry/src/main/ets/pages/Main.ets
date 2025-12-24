/*
 * SiYuan - 源于思考，饮水思源
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
import { BusinessError, deviceInfo } from '@kit.BasicServicesKit';
import { common, wantAgent, WantAgent } from '@kit.AbilityKit';
import { webview } from '@kit.ArkWeb';
import napi from 'libentry.so';
import { JSHarmony } from './JSHarmony';
import { Utils } from './Utils';

/**
 * 主程序。
 *
 * @author <a href="https://88250.b3log.org">Liang Ding</a>
 * @version 1.0.3.1, Dec 24, 2025
 * @since 3.1.14
 */
@Entry
@Component
struct Main {
  controller: webview.WebviewController = new webview.WebviewController();
  @State jsHarmony: JSHarmony = new JSHarmony();

  build() {
    Row() {
      Web({ src: '', controller: this.controller })
        .darkMode(WebDarkMode.Auto)
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .imageAccess(true)
        .onlineImageAccess(true)
        .cacheMode(CacheMode.Online)
        .mediaPlayGestureAccess(true)
        .mixedMode(MixedMode.All)
        .zoomAccess(false)
        .textZoomRatio(100)
        .onControllerAttached(() => {
          const context = getContext();
          const filesDir = context.filesDir;
          const appDir = filesDir;
          const workspaceBaseDir = filesDir + "/workspaces"

          const ua =
            "SiYuan/" + Utils.appVer + " https://b3log.org/siyuan Harmony " + this.controller.getUserAgent();
          this.controller.setCustomUserAgent(ua);
          this.controller.registerJavaScriptProxy(this.jsHarmony, "JSHarmony",
            [
              "exportByDefault",
              "openExternal",
              "print",
              "getScreenWidthPx",
              "changeStatusBarColor",
              "readClipboard",
              "readHTMLClipboard",
              "writeClipboard",
              "writeHTMLClipboard",
              "returnDesktop",
              "exit",
            ]
          );
          hilog.info(0x0000, "siyuan",
            "appDir [" + appDir + "], workspaceBaseDir [" + workspaceBaseDir + "], ua [" + ua + "]");
          this.startKernel(appDir, workspaceBaseDir);
        })
        .onOverrideUrlLoading((webResourceRequest) => {
          const url = webResourceRequest.getRequestUrl().toLowerCase();

          if (-1 < url.indexOf("127.0.0.1")) {
            this.controller.loadUrl(url);
            return true;
          }

          if (webResourceRequest.isMainFrame() && url.startsWith("http")) {
            Utils.openByDefaultBrowser(url);
            return true;
          }
          return false;
        })
    }
    .width("100%")
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM]);
  }

  aboutToAppear(): void {
    if (!Utils.isTablet() && !Utils.isPC()) {
      try {
        const context = this.getUIContext();
        const uiAbilityContext = context.getHostContext() as common.UIAbilityContext;
        const wnd = uiAbilityContext.windowStage.getMainWindowSync();
        wnd.setWindowLayoutFullScreen(false);
        wnd.setSpecificSystemBarEnabled('status', true);
        wnd.setSpecificSystemBarEnabled('navigationIndicator', true);
      } catch (e) {
        hilog.error(0x0000, "siyuan", "Set main window system bar failed: " + e);
      }
    }
  }

  private startKernel(appDir: string, workspaceBaseDir: string) {
    let context = getContext(this);

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
        napi.disableFeature("ai");
        hilog.info(0x0000, "siyuan", "disabled feature [ai]");
        napi.startKernel(appDir, workspaceBaseDir, localIPs, osVer);
        hilog.info(0x0000, "siyuan",
          "started kernel [appDir=" + appDir + ", workspaceBaseDir=" + workspaceBaseDir + ", localIPs=" + localIPs +
            ", osVer=" + osVer + "]");
        this.waitFotKernelHttpServing();
        this.controller.loadUrl("http://127.0.0.1:6806/appearance/boot/index.html?v=" + Utils.appVer);
        hilog.info(0x0000, "siyuan", "load boot page");
      }).catch((err: BusinessError) => {
        hilog.error(0x0000, "siyuan", "start kernel in background failed: " + err)
        Utils.exit();
      });
    });
  }

  async waitFotKernelHttpServing() {
    while (true) {
      await this.sleep(10);
      const ok = napi.isHttpServing();
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
