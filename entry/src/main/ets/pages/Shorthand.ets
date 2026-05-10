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
import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';

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
  @StorageProp('shareInput') @Watch('onShareInputChange') shareInputProp: string = '';
  @State inputText: string = '';
  @State submitEnabled: boolean = false;

  aboutToAppear(): void {
    const shareInput = AppStorage.get("shareInput") as string ?? '';
    if (shareInput) {
      this.inputText += '\n\n' + shareInput;
      this.inputText = this.inputText.trim();
      this.submitEnabled = this.inputText.trim().length > 0;
    }
  }

  onShareInputChange(): void {
    if (this.shareInputProp) {
      this.inputText += '\n\n' + this.shareInputProp;
      this.inputText = this.inputText.trim();
      this.submitEnabled = this.inputText.trim().length > 0;
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

    this.inputText = "";
    context?.terminateSelf();
  }

  build() {
    Column() {
      Row() {
        Text($r('app.string.shorthand_label'))
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .layoutWeight(1)

        Button($r('app.string.submit'))
          .enabled(this.submitEnabled)
          .fontSize(14)
          .onClick(() => {
            this.onSubmit();
          })
      }
      .width('100%')
      .height(56)
      .padding({ left: 16, right: 8 })

      Divider()

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