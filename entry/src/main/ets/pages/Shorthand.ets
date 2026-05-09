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
import { Want, common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import napi from 'libentry.so';

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
    // 处理分享过来的内容
    const want = AppStorage.get<Want>('shorthandWant');
    if (want) {
      this.handleWant(want);
    }
  }

  private handleWant(want: Want): void {
    const action = want.action;
    const type = (want.type) as string;
    const parameters = want.parameters as Record<string, Object>;

    if ('ohos.want.action.sendData' === action) {
      if (type && type.startsWith('text/')) {
        // 分享文本
        const text = (parameters?.shareText as string) || (want.uri as string);
        if (text) {
          this.inputText = text;
          this.submitEnabled = text.trim().length > 0;
        }
      } else if (type && (type.startsWith('image/') ||
        type.startsWith('video/') ||
        type.startsWith('audio/') ||
        type.startsWith('application/'))) {
        // 分享文件
        const fileUriList = parameters?.fileUriList as string[];
        if (fileUriList && fileUriList.length > 0) {
          this.handleFileShare(fileUriList, type);
        }
      }
    }
  }

  private getPathFromFileUri(uri: string): string {
    // 鸿蒙文件 URI 格式: file://<bundleName>/<realPath>
    // 取 bundleName 之后的部分作为真实路径
    const idx = uri.indexOf('/', 7); // 跳过 "file://"
    if (idx >= 0) {
      return uri.substring(idx);
    }
    return uri;
  }

  private async handleFileShare(uriList: string[], type: string): Promise<void> {
    const context = AppStorage.get<common.UIAbilityContext>('shorthandContext')!;
    const workspaceBaseDir = context.filesDir + '/workspaces';
    const shorthandsDir = workspaceBaseDir + '/home/.config/siyuan/shortcuts/shorthands/';
    const assetsDir = shorthandsDir + 'assets/';

    try {
      fs.mkdirSync(shorthandsDir, true);
      fs.mkdirSync(assetsDir, true);
    } catch (e) {
      hilog.error(0x0000, 'siyuan', 'create shorthands dir failed: ' + e);
    }

    for (const uri of uriList) {
      try {
        const filePath = this.getPathFromFileUri(uri);
        if (!filePath) {
          continue;
        }
        let baseName = napi.filepathBase(filePath);
        baseName = napi.filterUploadFileName(baseName);
        const fileName = napi.assetName(baseName);
        const destPath = assetsDir + fileName;

        // 复制文件
        fs.copyFileSync(filePath, destPath);

        let content = '';
        if (type.startsWith('image/')) {
          content = '![' + baseName + '](assets/' + fileName + ')';
        } else {
          content = '[' + baseName + '](assets/' + fileName + ')';
        }
        content += '\n\n';
        this.inputText += content;
      } catch (e) {
        hilog.error(0x0000, 'siyuan', 'copy shared file failed: ' + e);
      }
    }

    this.submitEnabled = this.inputText.trim().length > 0;
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
      hilog.error(0x0000, 'siyuan', 'create shorthands dir failed: ' + e);
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