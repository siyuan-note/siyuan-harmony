import { AbilityConstant, UIAbility, Want, Configuration, ConfigurationConstant } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { webview } from '@kit.ArkWeb';
import BuildProfile from 'BuildProfile';
import { MarkdownHost } from '../markdown/MarkdownHost';
import { MarkdownWindows } from '../markdown/MarkdownWindows';

interface MarkdownPageStorage { markdownSession: string; markdownFailure: string; }

// 独立入口不导入 Main、Utils、JSHarmony 或 libentry.so，也不启动笔记工作空间。
export default class MarkdownAbility extends UIAbility {
  private host?: MarkdownHost;
  private initialized: Promise<void> = Promise.resolve();
  private failure: string = '';

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    webview.WebviewController.setWebDebuggingAccess(BuildProfile.DEBUG);
    try {
      this.host = new MarkdownHost(this.context);
      MarkdownWindows.add(this.host);
      const recovery = want.parameters?.markdownRecovery;
      this.initialized = this.host.initialize(want.uri ?? '', typeof recovery === 'string' ? recovery : '')
        .catch(() => this.fail());
    } catch (error) { this.fail(); }
  }

  private fail(): void {
    this.failure = this.host?.startupError() || this.context.resourceManager.getStringByNameSync('markdown_load_error');
    if (this.host) {
      this.host.destroy();
      MarkdownWindows.remove(this.host.containerId);
      this.host = undefined;
    }
  }

  async onWindowStageCreate(stage: window.WindowStage): Promise<void> {
    await this.initialized;
    const values: MarkdownPageStorage = { markdownSession: this.host?.containerId ?? '', markdownFailure: this.failure };
    const storage = new LocalStorage(values);
    await stage.loadContent('pages/Markdown', storage);
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
