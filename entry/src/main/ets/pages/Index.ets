import { hilog } from '@kit.PerformanceAnalysisKit';
import { webview } from '@kit.ArkWeb';
import bundleManager from '@ohos.bundle.bundleManager';
import { fileIo as fs } from '@kit.CoreFileKit';
import napi from 'libentry.so';
import { JSHarmony } from './JSHarmony';

@Entry
@Component
struct Index {
  controller: webview.WebviewController = new webview.WebviewController();
  @State jsHarmony: JSHarmony = new JSHarmony();

  build() {
    Row() {
      Column() {
        Web({ src: '', controller: this.controller })
          .javaScriptAccess(true)
          .domStorageAccess(true)
          // .imageAccess(true)
          // .onlineImageAccess(true)
          // .fileAccess(true)
          .cacheMode(CacheMode.Online)
          // .mediaPlayGestureAccess(true)
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
            const isFirstRun = this.isFirstRun();
            hilog.info(0x0000, "siyuan",
              "appDir [" + appDir + "], workspaceBaseDir [" + workspaceBaseDir + "], ua [" + ua + "], first run [" +
                isFirstRun + "]");
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

  isFirstRun() {
    const context = getContext();
    const workspaceBaseDir = context.filesDir + "/workspaces"
    return !fs.accessSync(workspaceBaseDir);
  }

  async waitFotKernelHttpServing() {
    while (true) {
      await this.sleep(10);
      const ok = napi.isHttpServing()
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
