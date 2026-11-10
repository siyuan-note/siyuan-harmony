import { newMarkdownId } from '../markdown/MarkdownIds';
import { AbilityConstant, UIAbility, Want, Configuration, ConfigurationConstant } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { webview } from '@kit.ArkWeb';
import BuildProfile from 'BuildProfile';
import { MarkdownHost, MarkdownOccupiedError } from '../markdown/MarkdownHost';
import { MarkdownWindows } from '../markdown/MarkdownWindows';
import { canonicalMarkdownURI } from '../markdown/MarkdownFiles';
import { markdownInstanceKey } from './MarkdownStage';

interface MarkdownPageStorage { markdownSession: string; markdownFailure: string; }

// 独立入口不导入 Main、Utils、JSHarmony 或 libentry.so，也不启动笔记工作空间。
export default class MarkdownAbility extends UIAbility {
  private host?: MarkdownHost;
  private initialized: Promise<void> = Promise.resolve();
  private failure: string = '';
  private instanceKey: string = '';
  private redirected: boolean = false;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    webview.WebviewController.setWebDebuggingAccess(BuildProfile.DEBUG);
    try {
      this.instanceKey = markdownInstanceKey(want);
      this.host = new MarkdownHost(this.context);
      MarkdownWindows.add(this.host, async () => {
        await this.context.startAbility({ bundleName: this.context.abilityInfo.bundleName, abilityName: 'MarkdownAbility',
          uri: this.host?.targetURI,
          parameters: { markdownInstanceKey: this.instanceKey, markdownFocus: true } });
      });
      const recovery = want.parameters?.markdownRecovery;
      this.initialized = this.host.initialize(want.uri ?? '', typeof recovery === 'string' ? recovery : '')
        .catch(async (error: Error) => {
          if (error instanceof MarkdownOccupiedError && await MarkdownWindows.focus(error.sessionId)) {
            this.redirected = true;
            this.discardHost();
            await this.context.terminateSelf();
            return;
          }
          // 原占用者刚关闭时，重新核验一次登记和文件，而不是复用旧占用判断。
          if (error instanceof MarkdownOccupiedError && this.host) {
            try { await this.host.initialize(want.uri ?? '', ''); return; } catch (retry) { }
          }
          this.fail();
        });
    } catch (error) { this.fail(); }
  }

  private fail(): void {
    this.failure = this.host?.startupError() || this.context.resourceManager.getStringByNameSync('markdown_load_error');
    this.discardHost();
  }
  private discardHost(): void {
    if (this.host) {
      this.host.destroy();
      MarkdownWindows.remove(this.host.containerId);
      this.host = undefined;
    }
  }

  async onWindowStageCreate(stage: window.WindowStage): Promise<void> {
    await this.initialized;
    if (this.redirected) return;
    const values: MarkdownPageStorage = { markdownSession: this.host?.containerId ?? '', markdownFailure: this.failure };
    const storage = new LocalStorage(values);
    await stage.loadContent('pages/Markdown', storage);
  }

  onNewWant(want: Want): void {
    if (want.parameters?.markdownFocus === true) return;
    const uri = want.uri ?? '';
    if (this.host && uri) {
      try { if (canonicalMarkdownURI(uri) === this.host.targetURI) return; }
      catch (error) { this.host.reportOpenFailure(); return; }
    }
    // 容器内已切换到别的文件时，新的系统请求另开实例，保护当前正文。
    void this.context.startAbility({ bundleName: this.context.abilityInfo.bundleName, abilityName: 'MarkdownAbility',
      uri: uri, flags: want.flags, parameters: { markdownInstanceKey: newMarkdownId(),
        markdownRecovery: want.parameters?.markdownRecovery ?? '' } }).catch(() => this.host?.reportOpenFailure());
  }

  onBackground(): void { if (this.host) void this.host.background(); }
  onForeground(): void { if (this.host) void this.host.foreground(); }
  onConfigurationUpdate(configuration: Configuration): void {
    this.host?.setDark(configuration.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
  }
  onDestroy(): void {
    this.host?.destroy();
    if (this.host) MarkdownWindows.remove(this.host.containerId);
  }
}
