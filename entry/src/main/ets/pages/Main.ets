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
import { webview } from '@kit.ArkWeb';
import bundleManager from '@ohos.bundle.bundleManager';
import napi from 'libentry.so';
import { JSHarmony } from './JSHarmony';
import { Utils } from './Utils';

/**
 * 主程序。
 *
 * @author <a href="https://88250.b3log.org">Liang Ding</a>
 * @version 1.0.0.0, Nov 27, 2024
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
          .domStorageAccess(true)// .imageAccess(true)
            // .onlineImageAccess(true)
            // .fileAccess(true)
          .cacheMode(CacheMode.Online)// .mediaPlayGestureAccess(true)
            // .mixedMode(MixedMode.All)
            // .layoutMode(WebLayoutMode.FIT_CONTENT)
            // .zoomAccess(false)
          .textZoomRatio(100)
          .onControllerAttached(() => {
            const info =
              bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION);

            const context = getContext();
            const filesDir = context.filesDir;
            const appDir = context.resourceDir;
            const workspaceBaseDir = filesDir + "/workspaces"

            const ua =
              "SiYuan/" + info.versionName + " https://b3log.org/siyuan Harmony " + this.controller.getUserAgent();
            this.controller.setCustomUserAgent(ua);
            hilog.info(0x0000, "siyuan",
              "appDir [" + appDir + "], workspaceBaseDir [" + workspaceBaseDir + "], ua [" + ua + "]");
            napi.disableFeature("ai");
            napi.startKernel(appDir, workspaceBaseDir);
            this.waitFotKernelHttpServing();
            this.controller.loadUrl("http://127.0.0.1:6806/appearance/boot/index.html");
            this.controller.registerJavaScriptProxy(this.jsHarmony, "JSHarmony", ["openExternal"]);
          })
      }
      .width("100%")
    }
    .height("100%")
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
}
