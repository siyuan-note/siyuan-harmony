/*
 * SiYuan - From thought to insight, with agents
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
import { ShorthandDraftStore } from '../shorthand/ShorthandDraftStore';

/**
 * 闪念速记页面。
 *
 * @author <a href="https://88250.b3log.org">Liang Ding</a>
 * @version 1.0.0.1, Jul 6, 2026
 * @since 3.7.0
 */
@Entry
@Component
struct Shorthand {
  @StorageLink('shorthandText') @Watch('onInputTextChange') inputText: string = '';
  @StorageLink('shorthandPending') @Watch('onPendingChange') pendingInputCount: number = 0;
  @State submitEnabled: boolean = false;
  @State submitting: boolean = false;
  @State submitSucceeded: boolean = false;
  @State submitPulse: boolean = false;

  aboutToAppear(): void {
    this.refreshSubmitEnabled();
  }

  aboutToDisappear(): void {
    ShorthandDraftStore.flush().catch((error: Error) => {
      hilog.error(0x0000, 'siyuan', 'flush shorthand draft failed: ' + error.message);
    });
  }

  onInputTextChange(): void {
    ShorthandDraftStore.schedule(this.inputText);
    this.refreshSubmitEnabled();
  }

  onPendingChange(): void {
    this.refreshSubmitEnabled();
  }

  private async onSubmit(): Promise<void> {
    if (this.submitting || 0 < this.pendingInputCount) {
      return;
    }
    const rawText = this.inputText;
    const text = this.inputText.trim();
    if (!text) {
      return;
    }

    this.submitting = true;
    this.refreshSubmitEnabled();

    const context = AppStorage.get<common.UIAbilityContext>('shorthandContext')!;
    const workspaceBaseDir = context.filesDir + '/workspaces';
    const shorthandsDir = workspaceBaseDir + '/home/.config/siyuan/shortcuts/shorthands/';

    try {
      const expectedRevision = await ShorthandDraftStore.saveNow(rawText);
      try {
        fs.mkdirSync(shorthandsDir, true);
      } catch (error) {
        if (!fs.accessSync(shorthandsDir)) {
          throw new Error('Create shorthand directory failed: ' + error);
        }
      }

      let timestamp = Date.now();
      let filePath = shorthandsDir + timestamp + '.md';
      while (fs.accessSync(filePath)) {
        timestamp++;
        filePath = shorthandsDir + timestamp + '.md';
      }
      const committedRevision = await ShorthandDraftStore.promote(filePath, expectedRevision);
      if (0 < this.pendingInputCount || !ShorthandDraftStore.isCurrentRevision(committedRevision)) {
        this.inputText = ShorthandDraftStore.getText();
        this.submitting = false;
        this.refreshSubmitEnabled();
        return;
      }
    } catch (error) {
      hilog.error(0x0000, 'siyuan', 'write shorthand file failed: ' + error);
      this.submitting = false;
      this.refreshSubmitEnabled();
      return;
    }

    this.inputText = '';
    this.submitSucceeded = true;
    animateTo({ duration: 180, curve: Curve.EaseOut }, () => {
      this.submitPulse = true;
    });
    setTimeout(() => {
      animateTo({ duration: 180, curve: Curve.EaseOut }, () => {
        this.submitPulse = false;
      });
    }, 180);
    await new Promise<void>(resolve => setTimeout(resolve, 750));
    try {
      await context.terminateSelf();
    } catch (error) {
      hilog.error(0x0000, 'siyuan', 'terminate shorthand failed: ' + error);
    }
  }

  private refreshSubmitEnabled(): void {
    this.submitEnabled = !this.submitting && 0 === this.pendingInputCount && 0 < this.inputText.trim().length;
  }

  build() {
    Column() {
      Row() {
        Text($r('app.string.shorthand_label'))
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .layoutWeight(1)

        Button(this.submitSucceeded ? $r('app.string.saved') : $r('app.string.submit'))
          .enabled(this.submitEnabled || this.submitSucceeded)
          .fontSize(14)
          .scale({ x: this.submitPulse ? 1.08 : 1, y: this.submitPulse ? 1.08 : 1 })
          .accessibilityText(this.submitSucceeded ? $r('app.string.saved_accessibility') : $r('app.string.submit'))
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
        })
    }
    .width('100%')
    .height('100%')
  }
}
