import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { KLineItem, KLineLevel, StockQuote } from '../model/StockModels';

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

  static async fetchQuotes(codes: string[]): Promise<StockQuote[]> {
    if (codes.length === 0) {
      return [];
    }
    const url: string = StockApi.QUOTE_URL + codes.join(',');
    const text: string = await StockApi.httpGetText(url, true);
    return StockApi.parseQuoteText(text);
  }

  static async fetchKLines(code: string, level: KLineLevel): Promise<KLineItem[]> {
    let text: string = '';
    if (level === KLineLevel.M30 || level === KLineLevel.M60) {
      const mKey: string = level === KLineLevel.M30 ? 'm30' : 'm60';
      const url: string = StockApi.MKLINE_URL + code + ',' + mKey + ',,320';
      text = await StockApi.httpGetText(url, false);
    } else {
      const dayKey: string = level === KLineLevel.DAY ? 'day' : 'week';
      const param: string = code + ',' + dayKey + ',,,320,qfq';
      try {
        text = await StockApi.httpGetText(StockApi.FQKLINE_URL + param, false);
      } catch (err) {
        text = await StockApi.httpGetText(StockApi.FQKLINE_FALLBACK_URL + param, false);
      }
    }
    const items: KLineItem[] = StockApi.parseKLineJson(text, code, level);
    if (items.length === 0) {
      throw new Error('empty kline data for ' + code);
    }
    return items;
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
