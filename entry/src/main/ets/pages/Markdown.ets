import { newMarkdownToken } from '../markdown/MarkdownIds';
import { webview } from '@kit.ArkWeb';
import { promptAction } from '@kit.ArkUI';
import { MarkdownHost, MarkdownNativeUI } from '../markdown/MarkdownHost';
import { MarkdownWindows } from '../markdown/MarkdownWindows';
import { MARKDOWN_PAGE, MARKDOWN_ORIGIN, MARKDOWN_RECOVERY_CONTENT_LIMIT } from '../markdown/MarkdownTypes';
import { MARKDOWN_CHANNEL_SCRIPT, markdownChannelMessage } from '../markdown/MarkdownChannel';

@CustomDialog
struct MarkdownFilenameDialog {
  controller: CustomDialogController;
  @State value: string = '';
  title: string = '';
  accept: string = '';
  cancel: string = '';
  finish: (value: string) => void = () => {};
  build() {
    Column({ space: 16 }) {
      Text(this.title).fontSize(20).fontWeight(FontWeight.Medium).width('100%')
      TextInput({ text: this.value }).onChange((value: string) => { this.value = value; }).maxLength(240)
      Row({ space: 16 }) {
        Button(this.cancel).onClick(() => { this.finish(''); this.controller.close(); })
        Button(this.accept).onClick(() => { this.finish(this.value); this.controller.close(); })
      }.width('100%').justifyContent(FlexAlign.End)
    }.padding(24)
  }
}

function markdownMime(url: string): string {
  const extension = url.slice(url.lastIndexOf('.') + 1).toLowerCase();
  const types: Record<string, string> = { 'html': 'text/html', 'js': 'application/javascript', 'css': 'text/css',
    'json': 'application/json', 'png': 'image/png', 'jpg': 'image/jpeg', 'jpeg': 'image/jpeg', 'gif': 'image/gif',
    'webp': 'image/webp', 'bmp': 'image/bmp', 'ico': 'image/x-icon', 'svg': 'image/svg+xml',
    'woff': 'font/woff', 'woff2': 'font/woff2', 'ttf': 'font/ttf' };
  return types[extension] ?? 'application/octet-stream';
}

@Entry
@Component
struct Markdown {
  @LocalStorageProp('markdownSession') sessionId: string = '';
  @LocalStorageProp('markdownFailure') failure: string = '';
  @State private filename: string = '';
  @State private protectedFailure: string = '';
  @State private surfaceDark: boolean = false;
  private filenameController?: CustomDialogController;
  private host?: MarkdownHost;
  private controller: webview.WebviewController = new webview.WebviewController();
  private port?: webview.WebMessagePort;
  private channelGeneration: number = 0;
  private channelToken: string = '';

  aboutToAppear(): void {
    this.host = MarkdownWindows.get(this.sessionId);
    this.surfaceDark = this.host?.effectiveDark() ?? false;
    this.host?.attach(this.controller, this.ui());
  }
  private resetChannel(): void {
    this.channelGeneration++;
    this.channelToken = '';
    try { this.port?.close(); } catch (error) { /* 已销毁的端口不再具有调用权限。 */ }
    this.port = undefined;
  }
  aboutToDisappear(): void { this.resetChannel(); this.host?.pageReady(''); this.host?.detachUI(this.controller); }
  onBackPress(): boolean { if (this.host) { void this.host.close(); return true; } return false; }

  private ui(): MarkdownNativeUI {
    return {
      theme: (dark: boolean) => { this.surfaceDark = dark; },
      notice: (message: string) => {
        // 新打开失败仅提示，不销毁当前文档及其桥接。
        try { this.getUIContext().getPromptAction().showToast({ message: message }); } catch (error) { }
      },
      failure: (message: string) => {
        this.resetChannel();
        this.host?.pageReady('');
        this.protectedFailure = message;
      },
      confirm: async (title: string, message: string, choices: string[]): Promise<number> => {
        const buttons: promptAction.Button[] = choices.map((label: string): promptAction.Button => {
          return { text: label, color: $r('sys.color.ohos_id_color_text_primary') };
        });
        const result = await this.getUIContext().getPromptAction().showDialog({ title: title, message: message, buttons: buttons });
        return result.index;
      },
      filename: (title: string, initial: string, accept: string, cancel: string): Promise<string> => {
        this.filename = initial;
        return new Promise<string>((resolve) => {
          this.filenameController = new CustomDialogController({
            builder: MarkdownFilenameDialog({ value: this.filename, title: title, accept: accept, cancel: cancel, finish: resolve }),
            autoCancel: true, cancel: () => resolve('')
          });
          this.filenameController.open();
        });
      }
    };
  }

  private intercept(request: WebResourceRequest): WebResourceResponse {
    const url = request.getRequestUrl();
    // 页面 CSP 只允许图片联网，本地虚拟来源始终由宿主处理。
    if (!request.isMainFrame() && request.getRequestMethod() === 'GET' &&
      new RegExp('^https?://').test(url) && !new RegExp('^https?://(?:[^/]*@)?siyuan-markdown[.]local(?::[0-9]+)?(?:/|$)', 'i').test(url)) {
      // SDK 文档规定返回 null 时继续加载，声明的返回类型未包含 null。
      return JSON.parse('null') as WebResourceResponse;
    }
    const response = new WebResourceResponse();
    response.setResponseIsReady(false);
    response.setResponseHeader([{ headerKey: 'Content-Security-Policy', headerValue:
      "default-src 'none'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' blob: data: http: https:; font-src 'self'; connect-src 'none'; frame-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'" },
      { headerKey: 'X-Content-Type-Options', headerValue: 'nosniff' }]);
    const host = this.host;
    if (!host) {
      response.setResponseCode(403); response.setReasonMessage('Forbidden'); response.setResponseData('');
      response.setResponseIsReady(true);
      return response;
    }
    void host.data(url).then((bytes: Uint8Array | undefined) => {
      response.setResponseCode(bytes ? 200 : 403);
      response.setReasonMessage(bytes ? 'OK' : 'Forbidden');
      response.setResponseMimeType(host.resourceMime(url) || markdownMime(url));
      response.setResponseData(bytes ? bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) : '');
    }).catch(() => {
      response.setResponseCode(404); response.setReasonMessage('Not found'); response.setResponseData('');
    }).finally(() => response.setResponseIsReady(true));
    return response;
  }

  build() {
    Column() {
      if (this.failure || this.protectedFailure || !this.host) {
        Text(this.failure || this.protectedFailure || 'Markdown').padding(24)
          .fontColor(this.host ? (this.surfaceDark ? '#ffffff' : '#222222') : $r('sys.color.ohos_id_color_text_primary'))
        if (this.protectedFailure && this.host) {
          Button(this.host.text('retry')).onClick(() => { void this.host?.retryProtected(); }).margin(12)
          Button(this.host.text('markdownRecovery')).onClick(() => { void this.host?.recoverProtected(); }).margin(12)
          Button(this.host.text('close')).onClick(() => { void this.host?.close(); }).margin(12)
        }
      } else {
        Web({ src: '', controller: this.controller })
          .backgroundColor(this.surfaceDark ? '#1e1e1e' : '#ffffff')
          .javaScriptAccess(true)
          .javaScriptOnDocumentStart([{ script: MARKDOWN_CHANNEL_SCRIPT, scriptRules: [MARKDOWN_ORIGIN] }])
          .domStorageAccess(false)
          .fileAccess(false)
          .imageAccess(true)
          .onlineImageAccess(true)
          .mixedMode(MixedMode.All)
          .cacheMode(CacheMode.None)
          .mediaPlayGestureAccess(true)
          .zoomAccess(false)
          .textZoomRatio(100)
          .onControllerAttached(() => {
            this.host?.attach(this.controller, this.ui());
            try { this.controller.loadUrl(MARKDOWN_PAGE); } catch (error) { this.host?.protect(); }
          })
          .onInterceptRequest((event) => this.intercept(event.request))
          .onOverrideUrlLoading((request) => request.getRequestUrl() !== MARKDOWN_PAGE)
          .onPermissionRequest((event) => { event?.request.deny(); })
          .onPageBegin(() => {
            this.resetChannel();
            this.host?.pageReady('');
          })
          .onPageEnd((event) => {
            if (!event || event.url !== MARKDOWN_PAGE || this.port) return;
            this.host?.pageReady(event.url);
            this.resetChannel();
            const generation = this.channelGeneration;
            try {
              this.channelToken = newMarkdownToken();
              const ports: webview.WebMessagePort[] = this.controller.createWebMessagePorts();
              this.port = ports[0];
              this.port.onMessageEvent((message: webview.WebMessage) => {
                if (generation !== this.channelGeneration || typeof message !== 'string' || message.length > MARKDOWN_RECOVERY_CONTENT_LIMIT * 8 + 256) return;
                const payload = markdownChannelMessage(message, this.channelToken);
                if (payload !== undefined) this.host?.postMessage(payload);
              });
              // 原生随机凭据只注入匹配 URL 的顶层闭包，不依赖 getUrl 证明调用 frame。
              void this.controller.runJavaScript('if(window===window.top&&location.href===' + JSON.stringify(MARKDOWN_PAGE) +
                '){window.__siyuanMarkdownConnect(' + JSON.stringify(this.channelToken) + ')}').then(() => {
                if (generation === this.channelGeneration) this.controller.postMessage('siyuan-markdown-connect', [ports[1]], MARKDOWN_ORIGIN);
              }).catch(() => { if (generation === this.channelGeneration) this.host?.protect(); });
            } catch (error) { this.host?.protect(); }
          })
          .onDownloadStart(() => {})
          .width('100%').height('100%')
      }
    }.width('100%').height('100%').backgroundColor(this.host ? (this.surfaceDark ? '#1e1e1e' : '#ffffff') : $r('app.color.bgColor'))
  }
}
