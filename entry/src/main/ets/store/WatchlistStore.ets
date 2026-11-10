import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

/**
 * 自选股分组：一只股票最多属于一个分组（codes 不在任何分组中即为「未分组」）。
 */
export class WatchlistGroup {
  name: string;
  codes: string[];

  constructor(name: string, codes: string[]) {
    this.name = name;
    this.codes = codes;
  }
}

/**
 * 自选股本地持久化存储（Preferences）。
 */
export class WatchlistStore {
  private static readonly PREF_NAME: string = 'stock_watchlist';
  private static readonly KEY_CODES: string = 'watchlist_codes';
  private static readonly KEY_GROUPS: string = 'watchlist_groups';

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

  static async loadGroups(context: common.Context): Promise<WatchlistGroup[]> {
    const store: preferences.Preferences =
      await preferences.getPreferences(context, WatchlistStore.PREF_NAME);
    const raw: string = store.getSync(WatchlistStore.KEY_GROUPS, '[]') as string;
    const groups: WatchlistGroup[] = [];
    try {
      const parsed: Object = JSON.parse(raw) as Object;
      if (!Array.isArray(parsed)) {
        return groups;
      }
      const rawArr: Object[] = parsed as Object[];
      for (const item of rawArr) {
        if (typeof item !== 'object' || item === null) {
          continue;
        }
        const rec: Record<string, Object> = item as Record<string, Object>;
        const nameVal: Object | undefined = rec['name'];
        if (typeof nameVal !== 'string' || nameVal === '') {
          continue;
        }
        const codes: string[] = [];
        const codesVal: Object | undefined = rec['codes'];
        if (Array.isArray(codesVal)) {
          const codeArr: Object[] = codesVal as Object[];
          for (const c of codeArr) {
            if (typeof c === 'string') {
              codes.push(c);
            }
          }
        }
        groups.push(new WatchlistGroup(nameVal, codes));
      }
    } catch (error) {
      return groups;
    }
    return groups;
  }

  static async saveGroups(context: common.Context, groups: WatchlistGroup[]): Promise<void> {
    const store: preferences.Preferences =
      await preferences.getPreferences(context, WatchlistStore.PREF_NAME);
    store.putSync(WatchlistStore.KEY_GROUPS, JSON.stringify(groups));
    await store.flush();
  }

  /** 新建分组：重名返回 false。 */
  static async createGroup(context: common.Context, name: string): Promise<boolean> {
    const groups: WatchlistGroup[] = await WatchlistStore.loadGroups(context);
    for (const g of groups) {
      if (g.name === name) {
        return false;
      }
    }
    groups.push(new WatchlistGroup(name, []));
    await WatchlistStore.saveGroups(context, groups);
    return true;
  }

  /** 删除分组：组内股票保留在自选（成为未分组）。 */
  static async deleteGroup(context: common.Context, name: string): Promise<void> {
    const groups: WatchlistGroup[] = await WatchlistStore.loadGroups(context);
    const kept: WatchlistGroup[] = [];
    for (const g of groups) {
      if (g.name !== name) {
        kept.push(g);
      }
    }
    await WatchlistStore.saveGroups(context, kept);
  }

  /**
   * 添加个股并归入分组：group 为空串表示不分组（从所有分组移出）；
   * 个股只属于一个分组，加入新分组时自动移出原分组。
   */
  static async addToGroup(context: common.Context, code: string, group: string): Promise<void> {
    const codes: string[] = await WatchlistStore.loadCodes(context);
    if (codes.indexOf(code) < 0) {
      codes.push(code);
      await WatchlistStore.saveCodes(context, codes);
    }
    if (group === '') {
      await WatchlistStore.removeFromAllGroups(context, code);
      return;
    }
    const groups: WatchlistGroup[] = await WatchlistStore.loadGroups(context);
    let found: boolean = false;
    for (const g of groups) {
      const idx: number = g.codes.indexOf(code);
      if (g.name === group) {
        found = true;
        if (idx < 0) {
          g.codes.push(code);
        }
      } else if (idx >= 0) {
        g.codes.splice(idx, 1);
      }
    }
    if (!found) {
      groups.push(new WatchlistGroup(group, [code]));
    }
    await WatchlistStore.saveGroups(context, groups);
  }

  /** 批量添加个股并归入同一分组（识图批量添加场景）。 */
  static async addToGroupBatch(context: common.Context,
    codes: string[], group: string): Promise<void> {
    const existing: string[] = await WatchlistStore.loadCodes(context);
    let changed: boolean = false;
    for (const c of codes) {
      if (existing.indexOf(c) < 0) {
        existing.push(c);
        changed = true;
      }
    }
    if (changed) {
      await WatchlistStore.saveCodes(context, existing);
    }
    const groups: WatchlistGroup[] = await WatchlistStore.loadGroups(context);
    for (const g of groups) {
      const kept: string[] = [];
      for (const c of g.codes) {
        if (codes.indexOf(c) >= 0) {
          continue;
        }
        kept.push(c);
      }
      if (g.name === group) {
        for (const c of codes) {
          if (kept.indexOf(c) < 0) {
            kept.push(c);
          }
        }
      }
      g.codes = kept;
    }
    if (group !== '') {
      let found: boolean = false;
      for (const g of groups) {
        if (g.name === group) {
          found = true;
        }
      }
      if (!found) {
        groups.push(new WatchlistGroup(group, codes.slice()));
      }
    }
    await WatchlistStore.saveGroups(context, groups);
  }

  /** 从自选移除：同时从主列表与所有分组中删除。 */
  static async removeCode(context: common.Context, code: string): Promise<void> {
    const codes: string[] = await WatchlistStore.loadCodes(context);
    const idx: number = codes.indexOf(code);
    if (idx >= 0) {
      codes.splice(idx, 1);
      await WatchlistStore.saveCodes(context, codes);
    }
    await WatchlistStore.removeFromAllGroups(context, code);
  }

  private static async removeFromAllGroups(context: common.Context,
    code: string): Promise<void> {
    const groups: WatchlistGroup[] = await WatchlistStore.loadGroups(context);
    let changed: boolean = false;
    for (const g of groups) {
      const idx: number = g.codes.indexOf(code);
      if (idx >= 0) {
        g.codes.splice(idx, 1);
        changed = true;
      }
    }
    if (changed) {
      await WatchlistStore.saveGroups(context, groups);
    }
  }
}
