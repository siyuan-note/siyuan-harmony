import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { Utils } from "../pages/Utils";

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(0x0000, "siyuan", '%{public}s', 'Ability onCreate');
  }

  onDestroy(): void {
    hilog.info(0x0000, "siyuan", '%{public}s', 'Ability onDestroy');
  }

  async onWindowStageCreate(windowStage: window.WindowStage): Promise<void> {
    hilog.info(0x0000, "siyuan", '%{public}s', 'Ability onWindowStageCreate');

    await Utils.initAppearance(this);
    if (Utils.isFirstRun(this)) {
      hilog.info(0x0000, "siyuan", "Loading agreement");
      windowStage.loadContent("pages/Agreement");
    } else {
      hilog.info(0x0000, "siyuan", "Loading main");
      windowStage.loadContent("pages/Main");
    }
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    hilog.info(0x0000, "siyuan", '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    // Ability has brought to foreground
    hilog.info(0x0000, "siyuan", '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    // Ability has back to background
    hilog.info(0x0000, "siyuan", '%{public}s', 'Ability onBackground');
  }
};
