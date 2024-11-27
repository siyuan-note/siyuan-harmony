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

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(0x0000, "siyuan", '%{public}s', 'Ability onWindowStageCreate');

    if (Utils.isFirstRun(this)) {
      windowStage.loadContent("pages/Agreement");
    } else {
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
