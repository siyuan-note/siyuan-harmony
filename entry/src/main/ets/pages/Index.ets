import { hilog } from '@kit.PerformanceAnalysisKit';
import { webview } from '@kit.ArkWeb';
import napi from 'libentry.so';

@Entry
@Component
struct Index {
  @State message: string = 'Hello World';
  controller: webview.WebviewController = new webview.WebviewController();

  build() {
    Row() {
      Column() {
        Web({ src: '', controller: this.controller })
          .onControllerAttached(() => {
            let context = getContext();
            let filesDir = context.filesDir;
            let appDir = context.resourceDir;
            let workspaceBaseDir = filesDir + "/workspaces"

            hilog.info(0x0000, "boot", "appDir [" + appDir + "], workspaceBaseDir [" + workspaceBaseDir + "]");
            napi.startKernel(appDir, workspaceBaseDir);

            this.controller.loadUrl("http://127.0.0.1:6806/appearance/boot/index.html")
          })
      }
      .width('100%')
    }
    .height('100%')
  }
}
