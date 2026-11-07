import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

/**
 * 图表设置持久化（Preferences）。
 */
export class SettingsStore {
  private static readonly PREF_NAME: string = 'stock_settings';
  private static readonly KEY_AXIS_FONT_SCALE: string = 'axis_font_scale';
  private static readonly KEY_THEME_ID: string = 'theme_id';
  private static readonly DEFAULT_SCALE: number = 1.0;

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
}
