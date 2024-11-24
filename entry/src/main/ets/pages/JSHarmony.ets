import { common, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

export class JSHarmony {
  openExternal(url: string) {
    if (!url) {
      return;
    }

    if (url.startsWith("#")) {
      return;
    }

    if (url.startsWith("assets/")) {
      url = "http://127.0.0.1:6806/" + url;
    }

    if (url.startsWith("/")) {
      url = "http://127.0.0.1:6806" + url;
    }

    hilog.debug(0x0000, "siyuan", "open external [" + url + "]");
    const context = getContext() as common.UIAbilityContext;
    const wantInfo: Want = {
      action: 'ohos.want.action.viewData',
      entities: ['entity.system.browsable'],
      uri: url
    }
    context.startAbility(wantInfo);
  }
}