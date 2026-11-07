import { MarketRef } from '../model/StockModels';
import { StockApi } from './StockApi';

/**
 * 全市场标的列表（东方财富公开接口，按成交额降序取前 N）。
 * 个股 fs 覆盖沪深主板/创业板/科创板；ETF fs 覆盖沪深场内 ETF。
 */
export class MarketApi {
  private static readonly CLIST_URL: string =
    'https://push2.eastmoney.com/api/qt/clist/get';
  private static readonly STOCK_FS: string = 'm:0+t:6,m:0+t:80,m:1+t:2,m:1+t:23';
  private static readonly ETF_FS: string = 'b:MK0021,b:MK0022,b:MK0023,b:MK0024';
  private static readonly PAGE_SIZE: number = 100;
  private static readonly MAX_PAGES: number = 60;

  static async fetchTopStocks(count: number, sortField: string): Promise<MarketRef[]> {
    return MarketApi.fetchPagedList(MarketApi.STOCK_FS, count, false, sortField);
  }

  static async fetchTopEtfs(count: number, sortField: string): Promise<MarketRef[]> {
    return MarketApi.fetchPagedList(MarketApi.ETF_FS, count, true, sortField);
  }

  /**
   * 按指定维度降序分页拉取，凑满 count 只为止；excludeMoneyBond 剔除 511 货币/债券基金。
   * sortField：f6 成交额 / f20 总市值 / f3 涨跌幅 / f8 换手率。
   */
  private static async fetchPagedList(fs: string, count: number,
    excludeMoneyBond: boolean, sortField: string): Promise<MarketRef[]> {
    const result: MarketRef[] = [];
    const seen: Set<string> = new Set<string>();
    let page: number = 1;
    while (result.length < count && page <= MarketApi.MAX_PAGES) {
      const url: string = MarketApi.buildUrl(fs, MarketApi.PAGE_SIZE, page, sortField);
      const text: string = await StockApi.httpGetText(url, false);
      const list: MarketRef[] = MarketApi.parseList(text);
      if (list.length === 0) {
        break;
      }
      for (const item of list) {
        if (excludeMoneyBond &&
          (item.code.indexOf('sh511') === 0 || item.code.indexOf('sz511') === 0)) {
          continue;
        }
        if (seen.has(item.code)) {
          continue;
        }
        seen.add(item.code);
        result.push(item);
        if (result.length >= count) {
          break;
        }
      }
      if (list.length < MarketApi.PAGE_SIZE) {
        break;
      }
      page++;
    }
    return result;
  }

  private static buildUrl(fs: string, pageSize: number, page: number,
    sortField: string): string {
    return MarketApi.CLIST_URL + '?pn=' + page + '&pz=' + pageSize +
      '&po=1&np=1&fltt=2&invt=2&fid=' + sortField + '&fs=' + fs +
      '&fields=f2,f3,f12,f13,f14';
  }

  private static parseList(text: string): MarketRef[] {
    const root: Record<string, Object> = JSON.parse(text) as Record<string, Object>;
    const dataNode: Record<string, Object> = root['data'] as Record<string, Object>;
    if (dataNode === null || dataNode === undefined) {
      return [];
    }
    const diffObj: Object | undefined = dataNode['diff'];
    if (diffObj === undefined || diffObj === null) {
      return [];
    }
    const rows: Array<Record<string, Object>> = diffObj as Array<Record<string, Object>>;
    const result: MarketRef[] = [];
    for (const row of rows) {
      const digitCode: string = `${row['f12']}`;
      const market: string = `${row['f13']}`;
      const name: string = `${row['f14']}`;
      const priceRaw: number = Number(row['f2']);
      if (digitCode.length !== 6) {
        continue;
      }
      if (market !== '0' && market !== '1') {
        continue;
      }
      const prefix: string = market === '1' ? 'sh' : 'sz';
      const price: number = isNaN(priceRaw) ? 0 : priceRaw;
      result.push(new MarketRef(prefix + digitCode, name, price));
    }
    return result;
  }
}
