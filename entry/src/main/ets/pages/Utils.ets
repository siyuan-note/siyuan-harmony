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

import { fileIo as fs } from '@kit.CoreFileKit';
import { bundleManager, common, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import napi from 'libentry.so';
import { deviceInfo } from '@kit.BasicServicesKit';
import router from '@ohos.router';
import "./Print";
import { PrintParam } from './Print';

/**
 * 工具类。
 *
 * @author <a href="https://88250.b3log.org">Liang Ding</a>
 * @version 1.1.0.0, Oct 20, 2025
 * @since 3.1.14
 */
@Component
export struct Utils {
  public static appVer =
    bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION).versionName;
  public static bundleName =
    bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION).name;

  static async print(html: string, filename: string) {
    const param = new PrintParam();
    param.html = html;
    param.filename = filename;
    router.pushUrl({
      url: "pages/Print",
      params: param,
    });
  }

  static isFirstRun(ability: UIAbility): boolean {
    const workspaceBaseDir = ability.context.filesDir + "/workspaces"
    return !fs.accessSync(workspaceBaseDir);
  }

  static openByDefaultBrowser(url: string) {
    if (!url) {
      return;
    }

    if (url.startsWith("#")) {
      return;
    }

    if (url.startsWith("/")) {
      url = "http://127.0.0.1:6806" + url;
    }

    const context = getContext() as common.UIAbilityContext;
    const wantInfo: Want = {
      action: 'ohos.want.action.viewData',
      entities: ['entity.system.browsable'],
      uri: url
    }
    context.startAbility(wantInfo);
  }

  static async initAppearance(ability: UIAbility) {
    if (!Utils.needUnzipAssets(ability)) {
      hilog.debug(0x0000, "siyuan", "Do not need unzip appearance [" + Utils.appVer + "]");
      return;
    }

    const appDir = ability.context.filesDir + "/app/";
    try {
      fs.rmdirSync(appDir);
    } catch (e) {
    }
    await Utils.unzipAsset(ability);
    const f = fs.openSync(appDir + "/VERSION", fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE);
    fs.writeSync(f.fd, Utils.appVer);
  }

  static async unzipAsset(ability: UIAbility): Promise<void> {
    hilog.debug(0x0000, "siyuan", "Unzipping appearance [" + Utils.appVer + "]");
    const appZipData = ability.context.resourceManager.getRawFileContentSync("app.zip").buffer;
    const appZip = ability.context.tempDir + "/app.zip";
    const appZipFile = fs.openSync(appZip, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE);
    fs.writeSync(appZipFile.fd, appZipData);
    fs.closeSync(appZipFile);
    const appDir = ability.context.filesDir + "/app/";
    fs.mkdirSync(appDir);
    napi.unzip(appZip, appDir);
    hilog.info(0x0000, "siyuan", "Unzipped appearance [" + Utils.appVer + "]");
  }

  static needUnzipAssets(ability: UIAbility): boolean {
    const verFilePath = ability.context.filesDir + "/app/VERSION";
    if (!fs.accessSync(verFilePath)) {
      return true
    }
    return fs.readTextSync(verFilePath) != Utils.appVer;
  }

  static isTablet(): boolean {
    return "tablet" === deviceInfo.deviceType
  }

  build() {
  }
}
