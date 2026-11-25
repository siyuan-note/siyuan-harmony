import { window } from '@kit.ArkUI';
import { webview } from '@kit.ArkWeb';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const MAIN_WINDOW_CONTROLS_PROXY = 'SiYuanHarmonyWindowControls';
const DESKTOP_URL = 'http://127.0.0.1:6806/stage/build/desktop/';
const PERMISSION = '{"javascriptProxyPermission":{"urlPermissionList":[' +
  '{"scheme":"http","host":"127.0.0.1","port":"6806","path":""}]}}';

interface ControlsGeometry {
  windowWidth: number;
  rightInset: number;
  bottom: number;
  movable: boolean;
}

interface DragArea {
  left: number;
  top: number;
  right: number;
  bottom: number;
}

export class MainWindowControls {
  private wnd: window.Window;
  private web: webview.WebviewController;
  private ui: UIContext;
  private connected: boolean = false;
  private immersive: boolean = false;
  private restoreTitleBar: boolean = false;
  private publishedGeometry: string = '';
  private geometry?: ControlsGeometry;
  private dragArea?: DragArea;
  private refreshTimer: number = -1;

  constructor(wnd: window.Window, web: webview.WebviewController, ui: UIContext) {
    this.wnd = wnd;
    this.web = web;
    this.ui = ui;
  }

  register(): void {
    this.web.registerJavaScriptProxy(this, MAIN_WINDOW_CONTROLS_PROXY, ['connect', 'setDragArea'], [], PERMISSION);
  }

  dispose(): void {
    this.disconnect();
    this.web.deleteJavaScriptRegister(MAIN_WINDOW_CONTROLS_PROXY);
  }

  // 只接受主 WebView 中的工作空间桌面入口。
  private isDesktopCaller(): boolean {
    try {
      const url = this.web.getUrl();
      const page = url.split('#')[0].split('?')[0];
      return (page === DESKTOP_URL || page === DESKTOP_URL + 'index.html') &&
        this.web.getLastJavascriptProxyCallingFrameUrl() === url;
    } catch (error) {
      this.logFailure('check window controls caller', error as BusinessError);
      return false;
    }
  }

  connect(): string {
    if (!this.isDesktopCaller()) {
      return 'null';
    }
    if (!this.connected) {
      this.connected = true;
      try {
        this.wnd.on('windowSizeChange', this.scheduleRefresh);
        this.wnd.on('windowStatusChange', this.scheduleRefresh);
        this.wnd.on('windowTitleButtonRectChange', this.scheduleRefresh);
      } catch (error) {
        // 不支持三键事件的设备仍可通过窗口状态和大小变化检查能力。
        this.logFailure('listen for window geometry', error as BusinessError);
      }
    }
    this.publishedGeometry = this.refresh();
    return this.publishedGeometry;
  }

  disconnect(): void {
    if (!this.connected) {
      return;
    }
    this.connected = false;
    clearTimeout(this.refreshTimer);
    this.refreshTimer = -1;
    this.geometry = undefined;
    this.dragArea = undefined;
    this.publishedGeometry = '';
    this.restoreDecor();
    try {
      this.wnd.off('windowSizeChange', this.scheduleRefresh);
      this.wnd.off('windowStatusChange', this.scheduleRefresh);
      this.wnd.off('windowTitleButtonRectChange', this.scheduleRefresh);
    } catch (error) {
      this.logFailure('remove window geometry listeners', error as BusinessError);
    }
  }

  private scheduleRefresh = (): void => {
    if (!this.connected || this.refreshTimer !== -1) {
      return;
    }
    this.refreshTimer = setTimeout(() => {
      this.refreshTimer = -1;
      const geometry = this.refresh();
      if (geometry === this.publishedGeometry) {
        return;
      }
      this.publishedGeometry = geometry;
      const script = "window.dispatchEvent(new CustomEvent('siyuan-harmony-window-controls', {detail: " + geometry + '}))';
      this.web.runJavaScript(script).catch((error: BusinessError) => {
        this.logFailure('send window geometry', error);
      });
    }, 0);
  };

  private readGeometry(): ControlsGeometry | undefined {
    const status = this.wnd.getWindowStatus();
    const movable = status === window.WindowStatusType.FLOATING;
    if (!movable && status !== window.WindowStatusType.MAXIMIZE) {
      return undefined;
    }
    const rect = this.wnd.getTitleButtonRect();
    const windowWidth = this.ui.px2vp(this.wnd.getWindowProperties().windowRect.width);
    const rightInset = rect.right + rect.width;
    const bottom = rect.top + rect.height;
    if (![windowWidth, rightInset, bottom].every(Number.isFinite) || rect.width <= 0 || rect.height <= 0 ||
      rect.right < 0 || rect.top < 0 || rightInset >= windowWidth) {
      return undefined;
    }
    return { windowWidth, rightInset, bottom, movable };
  }

  private refresh(): string {
    try {
      const geometry = this.readGeometry();
      if (geometry) {
        if (!this.immersive) {
          if (this.wnd.getWindowDecorVisible()) {
            this.wnd.setWindowDecorVisible(false);
            this.restoreTitleBar = true;
          }
          this.immersive = !this.wnd.getWindowDecorVisible();
        }
        if (this.immersive) {
          const next = JSON.stringify(geometry);
          if (next !== this.publishedGeometry) {
            this.dragArea = undefined;
          }
          this.geometry = geometry;
          return next;
        }
      }
    } catch (error) {
      this.logFailure('read native window buttons', error as BusinessError);
    }
    this.geometry = undefined;
    this.dragArea = undefined;
    this.restoreDecor();
    return 'null';
  }

  private restoreDecor(): void {
    this.immersive = false;
    if (this.restoreTitleBar) {
      try {
        this.wnd.setWindowDecorVisible(true);
        this.restoreTitleBar = false;
      } catch (error) {
        this.logFailure('restore the window title bar', error as BusinessError);
      }
    }
  }

  setDragArea(left: number, top: number, right: number, bottom: number): void {
    if (!this.isDesktopCaller()) {
      return;
    }
    const geometry = this.geometry;
    this.dragArea = geometry?.movable && [left, top, right, bottom].every(Number.isFinite) &&
      left >= 0 && top >= 0 && right > left && bottom > top && right <= geometry.windowWidth - geometry.rightInset ?
      { left, top, right, bottom } : undefined;
  }

  handleTouch(event: TouchEvent): void {
    const area = this.dragArea;
    if (event.type !== TouchType.Down || !area) {
      return;
    }
    const touch = event.changedTouches[0];
    if (touch && touch.windowX >= area.left && touch.windowX < area.right &&
      touch.windowY >= area.top && touch.windowY < area.bottom) {
      // 系统只在原生触摸回调中开始移动窗口。
      this.wnd.startMoving().catch((error: BusinessError) => this.logFailure('start moving the window', error));
    }
  }

  private logFailure(action: string, error: BusinessError): void {
    if (error.code !== 801) {
      hilog.warn(0x0000, 'siyuan', action + ' failed: ' + error.message);
    }
  }
}
