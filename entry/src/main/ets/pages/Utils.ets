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
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { PrintParam } from './Print';
import { connection } from '@kit.NetworkKit';

/**
 * 工具类。
 *
 * @author <a href="https://88250.b3log.org">Liang Ding</a>
 * @version 1.2.2.0, Dec 27, 2025
 * @since 3.1.14
 */
@Component
export struct Utils {
  public static appVer =
    bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION).versionName;
  public static appVerCode =
    bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION)
      .versionCode.toString();
  public static bundleName =
    bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION).name;

  static exit() {
    const context = Utils.getContext()
    context.terminateSelf();
    backgroundTaskManager.stopBackgroundRunning(context);

    try {
      napi.exit();
    } catch (err) {
      hilog.error(0x0000, "siyuan", "exit kernel failed: " + err);
    }
  }

  static async print(filename: string, html: string) {
    const param = new PrintParam();
    param.filename = filename;
    param.html = html;
    Utils.getUIContext().getRouter().pushUrl({
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

    const context = Utils.getContext();
    const wantInfo: Want = {
      action: 'ohos.want.action.viewData',
      entities: ['entity.system.browsable'],
      uri: url
    }
    context.startAbility(wantInfo);
  }

  static async initAppearance(ability: UIAbility) {
    if (!Utils.needUnzipAssets(ability)) {
      hilog.debug(0x0000, "siyuan", "Do not need unzip appearance [" + Utils.appVerCode + "]");
      return;
    }

    const appDir = ability.context.filesDir + "/app/";
    try {
      fs.rmdirSync(appDir);
    } catch (e) {
    }
    await Utils.unzipAsset(ability);
    const f = fs.openSync(appDir + "/VERSION", fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE);
    fs.writeSync(f.fd, Utils.appVerCode);
  }

  static async unzipAsset(ability: UIAbility): Promise<void> {
    hilog.debug(0x0000, "siyuan", "Unzipping appearance [" + Utils.appVerCode + "]");
    const appZipData = ability.context.resourceManager.getRawFileContentSync("app.zip").buffer;
    const appZip = ability.context.tempDir + "/app.zip";
    const appZipFile = fs.openSync(appZip, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE);
    fs.writeSync(appZipFile.fd, appZipData);
    fs.closeSync(appZipFile);
    const appDir = ability.context.filesDir + "/app/";
    fs.mkdirSync(appDir);
    napi.unzip(appZip, appDir);
    hilog.info(0x0000, "siyuan", "Unzipped appearance [" + Utils.appVerCode + "]");
  }

  static needUnzipAssets(ability: UIAbility): boolean {
    const verFilePath = ability.context.filesDir + "/app/VERSION";
    if (!fs.accessSync(verFilePath)) {
      return true
    }
    return fs.readTextSync(verFilePath) != Utils.appVerCode;
  }

  static isTablet(): boolean {
    return "tablet" === deviceInfo.deviceType
  }

  static isPC(): boolean {
    return "2in1" === deviceInfo.deviceType
  }

  static getIPAddressList(): string {
    try {
      let net = connection.getDefaultNetSync();
      if (!net) {
        hilog.warn(0x0000, "siyuan", "Get network failed");
        return "127.0.0.1";
      }

      let props = connection.getConnectionPropertiesSync(net);
      if (!props) {
        hilog.warn(0x0000, "siyuan", "Get network properties failed");
        return "127.0.0.1";
      }

      let ips: string[] = [];
      for (let i = 0; i < props.linkAddresses.length; i++) {
        const linkAddress = props.linkAddresses[i];
        if (linkAddress.address && 1 === linkAddress.address.family && "127.0.0.1" != linkAddress.address.address) {
          ips.push(linkAddress.address.address);
        }
      }

      ips.push("127.0.0.1");
      return ips.join(",");
    } catch (e) {
      hilog.warn(0x0000, "siyuan", "get IP address list failed: " + e)
      return "127.0.0.1";
    }
  }

  static getContext(): common.UIAbilityContext {
    const context = AppStorage.get<common.UIAbilityContext>('abilityContext');
    if (!context) {
      throw new Error("Failed to get the abilityContext")
    }
    return context;
  }

  private static uiContext: UIContext;

  static setUIContext(uiContext: UIContext) {
    Utils.uiContext = uiContext;
  }

  static getUIContext(): UIContext {
    return Utils.uiContext;
  }

  build() {
  }
}
