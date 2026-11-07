import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { KLineItem, KLineLevel, SearchSuggest, StockQuote } from '../model/StockModels';

function isAllDigits(s: string): boolean {
  if (s.length === 0) {
    return false;
  }
  for (let i = 0; i < s.length; i++) {
    const c: string = s.charAt(i);
    if (c < '0' || c > '9') {
      return false;
    }
  }
  return true;
}

/**
 * 将用户输入归一化为带市场前缀的股票/基金代码。
 * "600519" -> "sh600519"，"000001"/"300750" -> "sz000001"/"sz300750"，
 * "430047"/"832566" -> 北交所；"510300"/"588000" -> 沪市ETF，
 * "159915"/"161725" -> 深市ETF/LOF；也支持直接输入 "sh600519" 等完整前缀形式。
 */
export function normalizeStockCode(input: string): string {
  const s: string = input.trim().toLowerCase();
  if (s.length === 8) {
    const prefix: string = s.substring(0, 2);
    const digits: string = s.substring(2);
    if ((prefix === 'sh' || prefix === 'sz' || prefix === 'bj') && isAllDigits(digits)) {
      return s;
    }
    return '';
  }
  if (s.length === 6 && isAllDigits(s)) {
    const first: string = s.charAt(0);
    if (first === '6') {
      return 'sh' + s;
    }
    if (first === '0' || first === '3' || first === '1') {
      return 'sz' + s;
    }
    if (first === '4' || first === '8') {
      return 'bj' + s;
    }
    if (first === '5') {
      return 'sh' + s;
    }
    return '';
  }
  return '';
}

export class StockApi {
  private static readonly QUOTE_URL: string = 'https://qt.gtimg.cn/q=';
  private static readonly FQKLINE_URL: string =
    'https://ifzq.gtimg.cn/appstock/app/fqkline/get?param=';
  private static readonly FQKLINE_FALLBACK_URL: string =
    'https://proxy.finance.qq.com/ifzqgtimg/appstock/app/fqkline/get?param=';
  private static readonly MKLINE_URL: string =
    'https://ifzq.gtimg.cn/appstock/app/kline/mkline?param=';
  private static readonly SEARCH_URL: string =
    'https://smartbox.gtimg.cn/s3/?v=2&q=';
  private static readonly EM_KLINE_URL: string =
    'https://push2his.eastmoney.com/api/qt/stock/kline/get?';

  static async fetchQuotes(codes: string[]): Promise<StockQuote[]> {
    if (codes.length === 0) {
      return [];
    }
    const url: string = StockApi.QUOTE_URL + codes.join(',');
    const text: string = await StockApi.httpGetText(url, true);
    return StockApi.parseQuoteText(text);
  }

  static async fetchKLines(code: string, level: KLineLevel): Promise<KLineItem[]> {
    if (level === KLineLevel.M30 || level === KLineLevel.M60) {
      const mKey: string = level === KLineLevel.M30 ? 'm30' : 'm60';
      const url: string = StockApi.MKLINE_URL + code + ',' + mKey + ',,320';
      const text: string = await StockApi.httpGetText(url, false);
      const items: KLineItem[] = StockApi.parseKLineJson(text, code, level);
      if (items.length === 0) {
        throw new Error('empty kline data for ' + code);
      }
      return items;
    }
    // 日/周K：主用东财，腾讯 fqkline 全线 501 后仅作兜底
    try {
      const emItems: KLineItem[] = await StockApi.fetchEastMoneyDayWeek(code, level);
      if (emItems.length > 0) {
        return emItems;
      }
    } catch (error) {
      // 东财失败时回落腾讯
    }
    const dayKey: string = level === KLineLevel.DAY ? 'day' : 'week';
    const param: string = code + ',' + dayKey + ',,,320,qfq';
    let text: string = '';
    try {
      text = await StockApi.httpGetText(StockApi.FQKLINE_URL + param, false);
    } catch (err) {
      text = await StockApi.httpGetText(StockApi.FQKLINE_FALLBACK_URL + param, false);
    }
    const items: KLineItem[] = StockApi.parseKLineJson(text, code, level);
    if (items.length === 0) {
      throw new Error('empty kline data for ' + code);
    }
    return items;
  }

  private static emSecId(code: string): string {
    const digits: string = code.substring(2);
    if (code.indexOf('sh') === 0) {
      return '1.' + digits;
    }
    return '0.' + digits;
  }

  private static async fetchEastMoneyDayWeek(code: string,
    level: KLineLevel): Promise<KLineItem[]> {
    const klt: string = level === KLineLevel.DAY ? '101' : '102';
    const url: string = StockApi.EM_KLINE_URL + 'secid=' + StockApi.emSecId(code)
      + '&klt=' + klt + '&fqt=1&lmt=320&end=20500101'
      + '&fields1=f1,f2,f3,f4,f5,f6&fields2=f51,f52,f53,f54,f55,f56,f57';
    const text: string = await StockApi.httpGetText(url, false);
    return StockApi.parseEastMoneyKline(text);
  }

  private static parseEastMoneyKline(text: string): KLineItem[] {
    const result: KLineItem[] = [];
    const root: Record<string, Object> = JSON.parse(text) as Record<string, Object>;
    const dataNode: Record<string, Object> = root['data'] as Record<string, Object>;
    if (dataNode === null || dataNode === undefined) {
      return result;
    }
    const rows: string[] = dataNode['klines'] as string[];
    if (rows === null || rows === undefined) {
      return result;
    }
    for (const row of rows) {
      const parts: string[] = row.split(',');
      if (parts.length < 6) {
        continue;
      }
      const open: number = Number(parts[1]);
      const close: number = Number(parts[2]);
      const high: number = Number(parts[3]);
      const low: number = Number(parts[4]);
      const volume: number = Number(parts[5]);
      if (isNaN(open) || isNaN(close) || isNaN(high) || isNaN(low) || isNaN(volume)) {
        continue;
      }
      result.push(new KLineItem(parts[0], open, close, high, low, volume));
    }
    return result;
  }

  /**
   * 名称/代码/拼音联想搜索（腾讯 smartbox，格式：市场~代码~名称~拼音~类型，^ 分隔多条）。
   */
  static async fetchSearchSuggest(keyword: string): Promise<SearchSuggest[]> {
    const url: string = StockApi.SEARCH_URL + encodeURIComponent(keyword) + '&t=all';
    const text: string = await StockApi.httpGetText(url, true);
    return StockApi.parseSearchSuggest(text);
  }

  private static parseSearchSuggest(text: string): SearchSuggest[] {
    const result: SearchSuggest[] = [];
    const start: number = text.indexOf('v_hint="');
    if (start < 0) {
      return result;
    }
    const end: number = text.lastIndexOf('"');
    if (end <= start + 8) {
      return result;
    }
    let raw: string = text.substring(start + 8, end);
    try {
      raw = JSON.parse('"' + raw + '"') as string;
    } catch (error) {
      // 非 \u 转义格式时按原始文本解析
    }
    if (raw === '') {
      return result;
    }
    const entries: string[] = raw.split('^');
    for (const entry of entries) {
      const parts: string[] = entry.split('~');
      if (parts.length < 5) {
        continue;
      }
      const market: string = parts[0];
      const code: string = parts[1];
      const name: string = parts[2];
      const type: string = parts[4];
      if (market !== 'sh' && market !== 'sz' && market !== 'bj') {
        continue;
      }
      if (code.length !== 6) {
        continue;
      }
      if (type !== 'GP-A' && type !== 'ETF' && type !== 'LOF') {
        continue;
      }
      result.push(new SearchSuggest(market + code, name, type));
    }
    return result;
  }

  static async httpGetText(url: string, isGbk: boolean): Promise<string> {
    const client: http.HttpRequest = http.createHttp();
    try {
      const resp: http.HttpResponse = await client.request(url, {
        method: http.RequestMethod.GET,
        expectDataType: isGbk ? http.HttpDataType.ARRAY_BUFFER : http.HttpDataType.STRING,
        connectTimeout: 10000,
        readTimeout: 15000
      });
      if (resp.responseCode !== 200) {
        throw new Error('http status ' + resp.responseCode);
      }
      if (isGbk) {
        const buf: ArrayBuffer = resp.result as ArrayBuffer;
        const decoder: util.TextDecoder = util.TextDecoder.create('gbk');
        return decoder.decodeToString(new Uint8Array(buf));
      }
      return resp.result as string;
    } finally {
      client.destroy();
    }
  }

  private static parseQuoteText(text: string): StockQuote[] {
    const result: StockQuote[] = [];
    const entries: string[] = text.split(';');
    for (const entry of entries) {
      const trimmed: string = entry.trim();
      if (trimmed.indexOf('~') < 0) {
        continue;
      }
      const fields: string[] = trimmed.split('~');
      const head: string = fields[0];
      const eqIndex: number = head.indexOf('=');
      if (eqIndex < 0) {
        continue;
      }
      const code: string = head.substring(2, eqIndex);
      if (code.length !== 8) {
        continue;
      }
      const name: string = fields[1];
      const price: number = Number(fields[3]);
      const prevClose: number = Number(fields[4]);
      let pct: number = 0;
      if (prevClose > 0 && price > 0) {
        pct = (price - prevClose) / prevClose * 100;
      }
      result.push(new StockQuote(code, name, price, prevClose, pct));
    }
    return result;
  }

  private static parseKLineJson(text: string, code: string, level: KLineLevel): KLineItem[] {
    const root: Record<string, Object> = JSON.parse(text) as Record<string, Object>;
    const dataNode: Record<string, Object> = root['data'] as Record<string, Object>;
    if (dataNode === null || dataNode === undefined) {
      return [];
    }
    const stockNode: Record<string, Object> = dataNode[code] as Record<string, Object>;
    if (stockNode === null || stockNode === undefined) {
      return [];
    }
    let rawRows: Array<Array<string>> = [];
    if (level === KLineLevel.DAY || level === KLineLevel.WEEK) {
      const plainKey: string = level === KLineLevel.DAY ? 'day' : 'week';
      const qfqObj: Object | undefined = stockNode['qfq' + plainKey];
      if (qfqObj !== undefined && qfqObj !== null) {
        rawRows = qfqObj as Array<Array<string>>;
      } else {
        const plainObj: Object | undefined = stockNode[plainKey];
        if (plainObj !== undefined && plainObj !== null) {
          rawRows = plainObj as Array<Array<string>>;
        }
      }
    } else {
      const mKey: string = level === KLineLevel.M30 ? 'm30' : 'm60';
      const mObj: Object | undefined = stockNode[mKey];
      if (mObj !== undefined && mObj !== null) {
        rawRows = mObj as Array<Array<string>>;
      }
    }
    const items: KLineItem[] = [];
    for (const row of rawRows) {
      if (row.length < 6) {
        continue;
      }
      const openV: number = Number(row[1]);
      const closeV: number = Number(row[2]);
      const highV: number = Number(row[3]);
      const lowV: number = Number(row[4]);
      const volV: number = Number(row[5]);
      if (isNaN(openV) || isNaN(closeV) || isNaN(highV) || isNaN(lowV)) {
        continue;
      }
      items.push(new KLineItem(row[0], openV, closeV, highV, lowV, volV));
    }
    return items;
  }
}
