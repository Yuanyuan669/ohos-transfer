import UIAbility from '@ohos.app.ability.UIAbility';
import AbilityConstant from '@ohos.app.ability.AbilityConstant';
import Want from '@ohos.app.ability.Want';
import window from '@ohos.window';
import { Log } from '../common/Logger';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    Log.info('transfer onCreate');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index').then(() => {
      return windowStage.getMainWindow();
    }).then((win: window.Window) => {
      // 传输页期间保持亮屏，避免锁屏导致传输中断
      win.setWindowKeepScreenOn(true);
    }).catch((e: Error) => {
      Log.warn('window init failed: ' + e.message);
    });
  }

  onWindowStageDestroy(): void {
    Log.info('transfer windowStage destroy');
  }
}
