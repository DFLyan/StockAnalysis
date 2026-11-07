import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

/**
 * 自选股本地持久化存储（Preferences）。
 */
export class WatchlistStore {
  private static readonly PREF_NAME: string = 'stock_watchlist';
  private static readonly KEY_CODES: string = 'watchlist_codes';

  static async loadCodes(context: common.Context): Promise<string[]> {
    const store: preferences.Preferences =
      await preferences.getPreferences(context, WatchlistStore.PREF_NAME);
    const raw: string = store.getSync(WatchlistStore.KEY_CODES, '[]') as string;
    const codes: string[] = [];
    const parsed: Object = JSON.parse(raw) as Object;
    if (Array.isArray(parsed)) {
      const rawArr: Object[] = parsed as Object[];
      for (const item of rawArr) {
        if (typeof item === 'string') {
          codes.push(item);
        }
      }
    }
    return codes;
  }

  static async saveCodes(context: common.Context, codes: string[]): Promise<void> {
    const store: preferences.Preferences =
      await preferences.getPreferences(context, WatchlistStore.PREF_NAME);
    store.putSync(WatchlistStore.KEY_CODES, JSON.stringify(codes));
    await store.flush();
  }
}
