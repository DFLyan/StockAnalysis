import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

/**
 * 图表设置持久化（Preferences）。
 */
export class SettingsStore {
  private static readonly PREF_NAME: string = 'stock_settings';
  private static readonly KEY_AXIS_FONT_SCALE: string = 'axis_font_scale';
  private static readonly KEY_THEME_ID: string = 'theme_id';
  private static readonly KEY_LAST_SYNC: string = 'last_sync_time';
  private static readonly KEY_SCAN_COUNT: string = 'scan_count';
  private static readonly DEFAULT_SCALE: number = 1.0;
  public static readonly DEFAULT_SCAN_COUNT: number = 200;

  static async loadAxisFontScale(context: common.Context): Promise<number> {
    const store: preferences.Preferences =
      await preferences.getPreferences(context, SettingsStore.PREF_NAME);
    const raw: string = store.getSync(SettingsStore.KEY_AXIS_FONT_SCALE, '1') as string;
    const val: number = Number(raw);
    if (isNaN(val) || val < 0.75 || val > 2) {
      return SettingsStore.DEFAULT_SCALE;
    }
    return val;
  }

  static async saveAxisFontScale(context: common.Context, scale: number): Promise<void> {
    const store: preferences.Preferences =
      await preferences.getPreferences(context, SettingsStore.PREF_NAME);
    store.putSync(SettingsStore.KEY_AXIS_FONT_SCALE, `${scale}`);
    await store.flush();
  }

  static async loadThemeId(context: common.Context): Promise<number> {
    const store: preferences.Preferences =
      await preferences.getPreferences(context, SettingsStore.PREF_NAME);
    const raw: string = store.getSync(SettingsStore.KEY_THEME_ID, '0') as string;
    const val: number = Number(raw);
    if (isNaN(val) || val < 0 || val > 3) {
      return 0;
    }
    return Math.floor(val);
  }

  static async saveThemeId(context: common.Context, themeId: number): Promise<void> {
    const store: preferences.Preferences =
      await preferences.getPreferences(context, SettingsStore.PREF_NAME);
    store.putSync(SettingsStore.KEY_THEME_ID, `${themeId}`);
    await store.flush();
  }

  static async loadLastSyncTime(context: common.Context): Promise<string> {
    const store: preferences.Preferences =
      await preferences.getPreferences(context, SettingsStore.PREF_NAME);
    return store.getSync(SettingsStore.KEY_LAST_SYNC, '') as string;
  }

  static async saveLastSyncTime(context: common.Context, time: string): Promise<void> {
    const store: preferences.Preferences =
      await preferences.getPreferences(context, SettingsStore.PREF_NAME);
    store.putSync(SettingsStore.KEY_LAST_SYNC, time);
    await store.flush();
  }

  static async loadScanCount(context: common.Context): Promise<number> {
    const store: preferences.Preferences =
      await preferences.getPreferences(context, SettingsStore.PREF_NAME);
    const raw: string = store.getSync(SettingsStore.KEY_SCAN_COUNT, '200') as string;
    const val: number = Number(raw);
    if (isNaN(val) || val <= 0 || val > 3000) {
      return SettingsStore.DEFAULT_SCAN_COUNT;
    }
    return Math.floor(val);
  }

  static async saveScanCount(context: common.Context, count: number): Promise<void> {
    const store: preferences.Preferences =
      await preferences.getPreferences(context, SettingsStore.PREF_NAME);
    store.putSync(SettingsStore.KEY_SCAN_COUNT, `${count}`);
    await store.flush();
  }
}
