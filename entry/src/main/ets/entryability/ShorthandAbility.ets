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

import { AbilityConstant, UIAbility, Want, } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor as utd } from '@kit.ArkData';
import napi from 'libentry.so';
import { fileIo } from '@kit.CoreFileKit';

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
    this.handleWant(want);
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(0x0000, 'siyuan', 'ShorthandAbility onNewWant');
    this.handleWant(want);
  }

  private async handleWant(want: Want) {
    try {
      const data = await systemShare.getSharedData(want);
      const records = data.getRecords();
      let shareInput = '';
      records.forEach((record: systemShare.SharedRecord) => {
        if (utd.UniformDataType.HTML == record.utd) {
          hilog.error(0x0000, "siyuan", "handle utd html");
          const text = napi.html2Markdown(record.content);
          shareInput = text;
        } else if (utd.UniformDataType.TEXT == record.utd) {
          hilog.error(0x0000, "siyuan", "handle utd text");
          shareInput = record.content ?? "";
        } else {
          hilog.error(0x0000, "siyuan", "handle utd file " + JSON.stringify(record));
          const text = this.handleFileRecord(record);
          shareInput = text;
        }
      });
      AppStorage.SetOrCreate("shareInput", shareInput);
    } catch (e) {
      hilog.error(0x0000, 'siyuan', 'handle want failed: ' + e);
    }
  }

  private handleFileRecord(record: systemShare.SharedRecord): string {
    try {
      const context = AppStorage.get<Context>('shorthandContext');
      if (!context) {
        hilog.error(0x0000, 'siyuan', 'handle file record failed: no context');
        return "";
      }

      const workspaceBaseDir = context.filesDir + '/workspaces';
      const shorthandsDir = workspaceBaseDir + '/home/.config/siyuan/shortcuts/shorthands/';
      const assetsDir = shorthandsDir + 'assets/';

      try {
        fileIo.mkdirSync(shorthandsDir, true);
        fileIo.mkdirSync(assetsDir, true);
      } catch (e) {
        // ignore File exists
      }

      const file = fileIo.openSync(record.uri, fileIo.OpenMode.READ_ONLY);
      let baseName = napi.filepathBase(record.uri);
      baseName = napi.filterUploadFileName(baseName);
      const fileName = napi.assetName(baseName);
      const destPath = assetsDir + fileName;
      const outFile =
        fileIo.openSync(destPath, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      fileIo.copyFileSync(file.fd, outFile.fd);
      fileIo.closeSync(file);
      fileIo.closeSync(outFile);

      let ret = ""
      if (utd.UniformDataType.IMAGE == record.utd) {
        ret += '![' + baseName + '](assets/' + fileName + ')\n\n';
      } else {
        ret += '[' + baseName + '](assets/' + fileName + ')\n\n';
      }
      return ret;
    } catch (e) {
      hilog.error(0x0000, 'siyuan', 'handle file record failed: ' + e);
      return "";
    }
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
