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

/**
 * 闪念速记入口。
 *
 * @author <a href="https://88250.b3log.org">Liang Ding</a>
 * @version 1.0.0.0, May 9, 2026
 * @since 3.7.0
 */
export default class ShorthandAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(0x0000, 'siyuan', 'ShorthandAbility onCreate');
    AppStorage.setOrCreate('shorthandContext', this.context);
    AppStorage.setOrCreate('shorthandWant', want);
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(0x0000, 'siyuan', 'ShorthandAbility onNewWant');
    AppStorage.setOrCreate('shorthandWant', want);
  }

  onDestroy(): void {
    hilog.info(0x0000, 'siyuan', 'ShorthandAbility onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(0x0000, 'siyuan', 'ShorthandAbility onWindowStageCreate');

    const wnd = windowStage.getMainWindowSync();
    try {
      wnd.setWindowLayoutFullScreen(true);
      wnd.setSpecificSystemBarEnabled('status', false);
      wnd.setSpecificSystemBarEnabled('navigationIndicator', false);
    } catch (e) {
      hilog.error(0x0000, 'siyuan', 'set main window system bar failed: ' + e);
    }

    windowStage.loadContent('pages/Shorthand');
  }

  onWindowStageDestroy(): void {
    hilog.info(0x0000, 'siyuan', 'ShorthandAbility onWindowStageDestroy');
  }
};
