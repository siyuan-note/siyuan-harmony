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

import { webview } from '@kit.ArkWeb';
import { print } from '@kit.BasicServicesKit';
import hilog from '@ohos.hilog';

/**
 * 打印。
 *
 * @author <a href="https://88250.b3log.org">Liang Ding</a>
 * @version 1.0.0.1, Nov 21, 2025
 * @since 3.3.6
 */
@Entry
@Component
struct Print {
  controller: webview.WebviewController = new webview.WebviewController();

  build() {
    Row() {
      Web({ src: "", controller: this.controller })
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
          const params = this.getUIContext().getRouter().getParams() as PrintParam;
          this.controller.loadData(params.html, "text/html", "UTF-8", "http://127.0.0.1:6806/")
        })
        .onPageEnd(() => {
          try {
            const params = this.getUIContext().getRouter().getParams() as PrintParam;
            let webPrintDocadapter = this.controller.createWebPrintDocumentAdapter(params.filename);
            print.print(params.filename, webPrintDocadapter, null, this.getUIContext().getHostContext())
              .then((task: print.PrintTask) => {
                task.on("succeed", this.returnToMain);
                task.on("fail", this.returnToMain);
                task.on("cancel", this.returnToMain);
              }).catch((err: Error) => {
              hilog.error(0x0000, "siyuan", `Message: ${err.message}`);
            })
          } catch (error) {
            hilog.error(0x0000, "siyuan", `ErrorCode: ${error.code},  Message: ${error.message}`);
          }
        })
    }
  }

  returnToMain() {
    this.getUIContext().getRouter().back({
      url: "pages/Main"
    });
  }
}

export class PrintParam {
  html: string = ""
  filename: string = ""
}