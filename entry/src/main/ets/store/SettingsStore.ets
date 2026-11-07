import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { KLineLevel } from '../model/StockModels';

/**
 * 图表设置持久化（Preferences）。
 */
export class SettingsStore {
  private static readonly PREF_NAME: string = 'stock_settings';
  private static readonly KEY_AXIS_FONT_SCALE: string = 'axis_font_scale';
  private static readonly KEY_THEME_ID: string = 'theme_id';
  private static readonly KEY_LAST_SYNC: string = 'last_sync_time';
  private static readonly KEY_SCAN_COUNT: string = 'scan_count';
  private static readonly KEY_SCAN_SORT: string = 'scan_sort';
  private static readonly KEY_SCAN_LEVELS: string = 'scan_levels';
  private static readonly KEY_AI_BASE_URL: string = 'ai_base_url';
  private static readonly KEY_AI_API_KEY: string = 'ai_api_key';
  private static readonly KEY_AI_MODEL: string = 'ai_model';
  private static readonly DEFAULT_SCALE: number = 1.0;
  public static readonly DEFAULT_SCAN_COUNT: number = 200;
  public static readonly DEFAULT_SCAN_SORT: string = 'f6';
  public static readonly DEFAULT_AI_BASE_URL: string = 'https://api.deepseek.com';
  public static readonly DEFAULT_AI_MODEL: string = 'deepseek-chat';

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

  static async loadScanSort(context: common.Context): Promise<string> {
    const store: preferences.Preferences =
      await preferences.getPreferences(context, SettingsStore.PREF_NAME);
    const raw: string = store.getSync(SettingsStore.KEY_SCAN_SORT,
      SettingsStore.DEFAULT_SCAN_SORT) as string;
    if (raw === 'f6' || raw === 'f20' || raw === 'f3' || raw === 'f8') {
      return raw;
    }
    return SettingsStore.DEFAULT_SCAN_SORT;
  }

  static async saveScanSort(context: common.Context, sort: string): Promise<void> {
    const store: preferences.Preferences =
      await preferences.getPreferences(context, SettingsStore.PREF_NAME);
    store.putSync(SettingsStore.KEY_SCAN_SORT, sort);
    await store.flush();
  }

  static async loadScanLevels(context: common.Context): Promise<KLineLevel[]> {
    const store: preferences.Preferences =
      await preferences.getPreferences(context, SettingsStore.PREF_NAME);
    const raw: string = store.getSync(SettingsStore.KEY_SCAN_LEVELS,
      KLineLevel.DAY.toString()) as string;
    const result: KLineLevel[] = [];
    if (raw !== '') {
      const parts: string[] = raw.split(',');
      for (const part of parts) {
        const val: number = Number(part);
        if (isNaN(val) || val < 0 || val > 6 || Math.floor(val) !== val) {
          continue;
        }
        const level: KLineLevel = val as KLineLevel;
        if (result.indexOf(level) < 0) {
          result.push(level);
        }
      }
    }
    if (result.length === 0) {
      result.push(KLineLevel.DAY);
    }
    return result;
  }

  static async saveScanLevels(context: common.Context, levels: KLineLevel[]): Promise<void> {
    const store: preferences.Preferences =
      await preferences.getPreferences(context, SettingsStore.PREF_NAME);
    const parts: string[] = [];
    for (const level of levels) {
      parts.push(level.toString());
    }
    store.putSync(SettingsStore.KEY_SCAN_LEVELS, parts.join(','));
    await store.flush();
  }

  static async loadAiBaseUrl(context: common.Context): Promise<string> {
    const store: preferences.Preferences =
      await preferences.getPreferences(context, SettingsStore.PREF_NAME);
    const raw: string = store.getSync(SettingsStore.KEY_AI_BASE_URL,
      SettingsStore.DEFAULT_AI_BASE_URL) as string;
    if (raw === '') {
      return SettingsStore.DEFAULT_AI_BASE_URL;
    }
    return raw;
  }

  static async saveAiBaseUrl(context: common.Context, url: string): Promise<void> {
    const store: preferences.Preferences =
      await preferences.getPreferences(context, SettingsStore.PREF_NAME);
    store.putSync(SettingsStore.KEY_AI_BASE_URL, url);
    await store.flush();
  }

  static async loadAiApiKey(context: common.Context): Promise<string> {
    const store: preferences.Preferences =
      await preferences.getPreferences(context, SettingsStore.PREF_NAME);
    return store.getSync(SettingsStore.KEY_AI_API_KEY, '') as string;
  }

  static async saveAiApiKey(context: common.Context, apiKey: string): Promise<void> {
    const store: preferences.Preferences =
      await preferences.getPreferences(context, SettingsStore.PREF_NAME);
    store.putSync(SettingsStore.KEY_AI_API_KEY, apiKey);
    await store.flush();
  }

  static async loadAiModel(context: common.Context): Promise<string> {
    const store: preferences.Preferences =
      await preferences.getPreferences(context, SettingsStore.PREF_NAME);
    const raw: string = store.getSync(SettingsStore.KEY_AI_MODEL,
      SettingsStore.DEFAULT_AI_MODEL) as string;
    if (raw === '') {
      return SettingsStore.DEFAULT_AI_MODEL;
    }
    return raw;
  }

  static async saveAiModel(context: common.Context, model: string): Promise<void> {
    const store: preferences.Preferences =
      await preferences.getPreferences(context, SettingsStore.PREF_NAME);
    store.putSync(SettingsStore.KEY_AI_MODEL, model);
    await store.flush();
  }
}
