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

import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { Utils } from '../pages/Utils';
import { BusinessError } from '@kit.BasicServicesKit';
import common from '@ohos.app.ability.common';

/**
 * 主程序入口点。
 *
 * @author <a href="https://88250.b3log.org">Liang Ding</a>
 * @version 1.0.0.2, Oct 20, 2025
 * @since 3.1.14
 */
export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(0x0000, "siyuan", '%{public}s', 'Ability onCreate');
  }

  onDestroy(): void {
    hilog.info(0x0000, "siyuan", '%{public}s', 'Ability onDestroy');
  }

  async onWindowStageCreate(windowStage: window.WindowStage): Promise<void> {
    hilog.info(0x0000, "siyuan", '%{public}s', 'Ability onWindowStageCreate');

    let windowClass: window.Window | undefined = undefined;
    windowStage.getMainWindow((err: BusinessError, data) => {
      const errCode: number = err.code;
      if (errCode) {
        hilog.error(0x0000, "siyuan", err.message);
        return;
      }

      windowClass = data;
      try {
        windowClass.setSpecificSystemBarEnabled('navigationIndicator', false);
        if (Utils.isTablet()) {
          windowClass.setWindowLayoutFullScreen(true);
          windowClass.setSpecificSystemBarEnabled('status', false);

          windowClass.on('windowStatusChange', (statusType: window.WindowStatusType) => {
            let context = getContext(this) as common.UIAbilityContext;
            let win = context.windowStage.getMainWindowSync();
            win.setSpecificSystemBarEnabled('navigationIndicator', false);
            win.setSpecificSystemBarEnabled('status', false);
          });
        }
      } catch (exception) {
        hilog.error(0x0000, "siyuan",
          `Failed to set the system bar to be invisible. Cause code: ${exception.code}, message: ${exception.message}`);
      }
    });

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
