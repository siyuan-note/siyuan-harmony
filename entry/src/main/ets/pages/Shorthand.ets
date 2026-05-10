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

import { hilog } from '@kit.PerformanceAnalysisKit';
import { common, Want } from '@kit.AbilityKit';
import { fileIo, fileIo as fs } from '@kit.CoreFileKit';
import { systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor as utd } from '@kit.ArkData';
import napi from 'libentry.so';
import { BusinessError } from '@kit.BasicServicesKit';
import { Utils } from './Utils';

/**
 * 闪念速记页面。
 *
 * @author <a href="https://88250.b3log.org">Liang Ding</a>
 * @version 1.0.0.0, May 9, 2026
 * @since 3.7.0
 */
@Entry
@Component
struct Shorthand {
  @State inputText: string = '';
  @State submitEnabled: boolean = false;

  aboutToAppear(): void {
    const want = AppStorage.get<Want>('shorthandWant');
    if (want) {
      this.handleWant(want);
    }
  }

  private handleWant(want: Want) {
    systemShare.getSharedData(want)
      .then((data: systemShare.SharedData) => {
        data.getRecords().forEach((record: systemShare.SharedRecord) => {
          if (utd.UniformDataType.HTML == record.utd) {
            const md = napi.html2Markdown(record.content);
            this.inputText += md;
          } else if (utd.UniformDataType.TEXT == record.utd) {
            this.inputText += record.content
          } else {
            this.handleFileRecord(record);
          }
        });
        this.submitEnabled = this.inputText.trim().length > 0;
      })
      .catch((error: BusinessError) => {
        hilog.error(0x0000, 'siyuan', 'handle share failed: ' + error);
      });
  }

  private async handleFileRecord(record: systemShare.SharedRecord) {
    try {
      const context = Utils.getContext();
      const workspaceBaseDir = context.filesDir + '/workspaces';
      const shorthandsDir = workspaceBaseDir + '/home/.config/siyuan/shortcuts/shorthands/';
      const assetsDir = shorthandsDir + 'assets/';

      try {
        fs.mkdirSync(shorthandsDir, true);
        fs.mkdirSync(assetsDir, true);
      } catch (e) {
        // ignore File exists
      }

      const file = fileIo.openSync(record.uri, fileIo.OpenMode.READ_ONLY);
      let baseName = record.title
      baseName = napi.filterUploadFileName(baseName);
      const fileName = napi.assetName(baseName);
      const destPath = assetsDir + fileName;
      const outFile = fileIo.openSync(destPath, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE);
      fileIo.copyFileSync(file.fd, outFile.fd);
      fileIo.closeSync(file);
      fileIo.closeSync(outFile);

      if (utd.UniformDataType.IMAGE == record.utd) {
        this.inputText += '![' + baseName + '](assets/' + fileName + ')\n\n';
      } else {
        this.inputText += '[' + baseName + '](assets/' + fileName + ')\n\n';
      }
    } catch (e) {
      hilog.error(0x0000, 'siyuan', 'handle file record failed: ' + e);
    }
  }

  private onSubmit(): void {
    const text = this.inputText.trim();
    if (!text) {
      return;
    }

    const context = AppStorage.get<common.UIAbilityContext>('shorthandContext')!;
    const workspaceBaseDir = context.filesDir + '/workspaces';
    const shorthandsDir = workspaceBaseDir + '/home/.config/siyuan/shortcuts/shorthands/';

    try {
      fs.mkdirSync(shorthandsDir, true);
    } catch (e) {
      // ignore File exists
    }

    const now = Date.now();
    const filePath = shorthandsDir + now + '.md';
    try {
      const file = fs.openSync(filePath, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE);
      fs.writeSync(file.fd, text);
      fs.closeSync(file);
    } catch (e) {
      hilog.error(0x0000, 'siyuan', 'write shorthand file failed: ' + e);
    }

    // 关闭速记页面
    context?.terminateSelf();
  }

  build() {
    Column() {
      Button($r('app.string.submit'))
        .enabled(this.submitEnabled)
        .width('100%')
        .onClick(() => {
          this.onSubmit();
        })

      TextArea({
        text: this.inputText,
        placeholder: $r('app.string.shorthand_hint')
      })
        .layoutWeight(1)
        .width('100%')
        .backgroundColor(Color.Transparent)
        .padding(16)
        .onChange((value: string) => {
          this.inputText = value;
          this.submitEnabled = value.trim().length > 0;
        })
    }
    .width('100%')
    .height('100%')
  }
}