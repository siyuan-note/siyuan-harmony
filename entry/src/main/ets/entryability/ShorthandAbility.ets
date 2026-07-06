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
 * @version 1.0.0.1, Jul 6, 2026
 * @since 3.7.0
 */
export default class ShorthandAbility extends UIAbility {
  // 加载速记页面需要“分享数据解析完成”与“窗口舞台就绪”两个条件同时满足，
  // 哪一个后到就由哪一个触发 loadContent，确保页面 aboutToAppear 执行时 shareInput 已写入 AppStorage
  private windowStage: window.WindowStage | null = null;
  private shareInputResolved: boolean = false;
  private windowStageReady: boolean = false;
  private pageLoaded: boolean = false;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(0x0000, 'siyuan', 'ShorthandAbility onCreate');
    AppStorage.setOrCreate('shorthandContext', this.context);
    // 先清空上次残留的 shareInput，避免 onNewWant 复用 singleton 时页面显示旧内容
    AppStorage.setOrCreate('shareInput', '');
    this.handleWant(want);
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(0x0000, 'siyuan', 'ShorthandAbility onNewWant');
    // 复用 singleton 再次分享时，重置标志并清空 shareInput，页面侧通过 @Watch 感知新值
    this.shareInputResolved = false;
    AppStorage.setOrCreate('shareInput', '');
    this.handleWant(want);
  }

  private async handleWant(want: Want) {
    let shareInput = '';
    try {
      const data = await systemShare.getSharedData(want);
      const records = data.getRecords();
      for (const record of records) {
        if (utd.UniformDataType.HTML == record.utd) {
          const md = napi.html2Markdown(record.content);
          shareInput = md;
        } else if (utd.UniformDataType.TEXT == record.utd) {
          shareInput = record.content ?? "";
        } else {
          const text = this.handleFileRecord(record);
          shareInput = text;
        }
      }
    } catch (e) {
      // 解析失败时 shareInput 保持空串，页面仍能正常加载显示空输入框，避免界面卡死空白
      hilog.error(0x0000, 'siyuan', 'handle want failed: ' + e);
    }

    AppStorage.setOrCreate("shareInput", shareInput);
    this.shareInputResolved = true;
    this.loadShorthandPage();
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
      if (this.isImageRecord(record)) {
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

  // 判断分享记录是否为图片。record.utd 可能是 general.webp / general.jpeg 等具体子类型，
  // 不能用 == 精确匹配 general.image（会漏掉 webp 等系统未归类的格式），改用归属关系 + 扩展名双重判断
  private isImageRecord(record: systemShare.SharedRecord): boolean {
    try {
      const descriptor = utd.getUniformDataTypeDescriptorByType(record.utd);
      if (descriptor && descriptor.belongingTypeIds && descriptor.belongingTypeIds.includes(utd.UniformDataType.IMAGE)) {
        return true;
      }
    } catch (e) {
      // 某些自定义/未知 UTD 查不到描述符，走扩展名回退
    }

    const imageExts = ['.png', '.jpg', '.jpeg', '.gif', '.bmp', '.webp', '.svg', '.heif', '.heic', '.tiff', '.ico'];
    const lowerUri = record.uri.toLowerCase();
    for (const ext of imageExts) {
      if (lowerUri.endsWith(ext)) {
        return true;
      }
    }
    return false;
  }

  // 等分享数据解析完成且窗口舞台就绪后再加载页面，保证页面首屏即可读到 shareInput
  private loadShorthandPage(): void {
    if (this.pageLoaded || !this.shareInputResolved || !this.windowStageReady || null === this.windowStage) {
      return;
    }
    this.pageLoaded = true;
    this.windowStage.loadContent('pages/Shorthand');
  }

  onDestroy(): void {
    hilog.info(0x0000, 'siyuan', 'ShorthandAbility onDestroy');
  }

  async onWindowStageCreate(windowStage: window.WindowStage) {
    hilog.info(0x0000, 'siyuan', 'ShorthandAbility onWindowStageCreate');

    this.windowStage = windowStage;
    const wnd = windowStage.getMainWindowSync();
    try {
      wnd.setWindowLayoutFullScreen(true);
      wnd.setSpecificSystemBarEnabled('status', false);
      wnd.setSpecificSystemBarEnabled('navigationIndicator', false);
    } catch (e) {
      hilog.error(0x0000, 'siyuan', 'set main window system bar failed: ' + e);
    }

    this.windowStageReady = true;
    this.loadShorthandPage();
  }

  onWindowStageDestroy(): void {
    hilog.info(0x0000, 'siyuan', 'ShorthandAbility onWindowStageDestroy');
  }
};
