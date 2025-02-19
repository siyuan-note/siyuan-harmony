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
import { BusinessError } from '@kit.BasicServicesKit';
import { wantAgent, WantAgent } from '@kit.AbilityKit';
import { webview } from '@kit.ArkWeb';
import napi from 'libentry.so';
import { JSHarmony } from './JSHarmony';
import { Utils } from './Utils';

/**
 * 主程序。
 *
 * @author <a href="https://88250.b3log.org">Liang Ding</a>
 * @version 1.0.1.1, Feb 19, 2025
 * @since 3.1.14
 */
@Entry
@Component
struct Main {
  controller: webview.WebviewController = new webview.WebviewController();
  @State jsHarmony: JSHarmony = new JSHarmony();

  build() {
    Row() {
      Column() {
        Web({ src: '', controller: this.controller })
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
                "openExternal",
                "changeStatusBarColor",
                "readClipboard",
                "writeClipboard",
                "writeHTMLClipboard",
                "returnDesktop",
              ]
            );
            hilog.info(0x0000, "siyuan",
              "appDir [" + appDir + "], workspaceBaseDir [" + workspaceBaseDir + "], ua [" + ua + "]");
            napi.disableFeature("ai");
            this.startKernel(appDir, workspaceBaseDir);
          })
          .onLoadIntercept((event) => {
            const url = event.data.getRequestUrl();
            if (-1 < url.indexOf("127.0.0.1")) {
              return false;
            }

            if (url.toLowerCase().startsWith("http")) {
              Utils.openWithBrowser(url);
              return true;
            }

            return true;
          });
      }
      .width("100%")
    }
    .height("100%")
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

    wantAgent.getWantAgent(wantAgentInfo).then((wantAgentObj: WantAgent) => {
      backgroundTaskManager.startBackgroundRunning(context,
        backgroundTaskManager.BackgroundMode.DATA_TRANSFER, wantAgentObj).then(() => {
        napi.startKernel(appDir, workspaceBaseDir);
        hilog.debug(0x0000, "siyuan", "kernel is running in background");
        this.waitFotKernelHttpServing();
        this.controller.loadUrl("http://127.0.0.1:6806/appearance/boot/index.html");
      }).catch((err: BusinessError) => {
        console.error(`Failed to operation startBackgroundRunning. Code is ${err.code}, message is ${err.message}`);
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
