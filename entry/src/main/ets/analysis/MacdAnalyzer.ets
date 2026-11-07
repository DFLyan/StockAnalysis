import {
  DivergenceInfo,
  DivergenceType,
  KLineItem,
  KLineLevel,
  MacdPoint,
  kLineLevelLabel
} from '../model/StockModels';

/**
 * MACD（12,26,9）计算与多级别背离检测。
 *
 * 背离判定：基于分形枢轴点（左右各 k 根K线内的极值点），
 * 顶背离 = 股价枢轴高点创新高，而对应 DIF 枢轴高点走低；
 * 底背离 = 股价枢轴低点创新低，而对应 DIF 枢轴低点抬高。
 */
export class MacdAnalyzer {
  private static readonly PIVOT_WINDOW: number = 3;
  private static readonly MAX_PIVOT_GAP: number = 80;
  private static readonly MAX_REPORT_COUNT: number = 4;

  static calcMacd(klines: KLineItem[]): MacdPoint[] {
    const result: MacdPoint[] = [];
    let ema12: number = 0;
    let ema26: number = 0;
    let dea: number = 0;
    for (let i = 0; i < klines.length; i++) {
      const closeVal: number = klines[i].close;
      if (i === 0) {
        ema12 = closeVal;
        ema26 = closeVal;
        dea = 0;
      } else {
        ema12 = (ema12 * 11 + closeVal * 2) / 13;
        ema26 = (ema26 * 25 + closeVal * 2) / 27;
        dea = (dea * 8 + (ema12 - ema26) * 2) / 10;
      }
      const dif: number = ema12 - ema26;
      const bar: number = 2 * (dif - dea);
      result.push(new MacdPoint(dif, dea, bar));
    }
    return result;
  }

  static detectDivergence(klines: KLineItem[], macd: MacdPoint[], level: KLineLevel): DivergenceInfo[] {
    if (klines.length !== macd.length || klines.length < MacdAnalyzer.PIVOT_WINDOW * 2 + 2) {
      return [];
    }
    const results: DivergenceInfo[] = [];
    const pivotHighs: number[] =
      MacdAnalyzer.findPivotIndexes(klines, true, MacdAnalyzer.PIVOT_WINDOW);
    const pivotLows: number[] =
      MacdAnalyzer.findPivotIndexes(klines, false, MacdAnalyzer.PIVOT_WINDOW);

    for (let i = 0; i < pivotHighs.length - 1; i++) {
      const i1: number = pivotHighs[i];
      const i2: number = pivotHighs[i + 1];
      if (i2 - i1 > MacdAnalyzer.MAX_PIVOT_GAP) {
        continue;
      }
      const priceA: number = klines[i1].high;
      const priceB: number = klines[i2].high;
      const difA: number = macd[i1].dif;
      const difB: number = macd[i2].dif;
      if (difA > 0 && priceB > priceA && difB < difA - Math.abs(difA) * 0.02) {
        results.push(MacdAnalyzer.buildInfo(DivergenceType.TOP, level,
          klines, i1, i2, priceA, priceB, difA, difB));
      }
    }

    for (let i = 0; i < pivotLows.length - 1; i++) {
      const i1: number = pivotLows[i];
      const i2: number = pivotLows[i + 1];
      if (i2 - i1 > MacdAnalyzer.MAX_PIVOT_GAP) {
        continue;
      }
      const priceA: number = klines[i1].low;
      const priceB: number = klines[i2].low;
      const difA: number = macd[i1].dif;
      const difB: number = macd[i2].dif;
      if (difA < 0 && priceB < priceA && difB > difA + Math.abs(difA) * 0.02) {
        results.push(MacdAnalyzer.buildInfo(DivergenceType.BOTTOM, level,
          klines, i1, i2, priceA, priceB, difA, difB));
      }
    }

    results.sort((a: DivergenceInfo, b: DivergenceInfo): number => b.indexB - a.indexB);
    const limited: DivergenceInfo[] = [];
    const count: number = Math.min(MacdAnalyzer.MAX_REPORT_COUNT, results.length);
    for (let i = 0; i < count; i++) {
      limited.push(results[i]);
    }
    return limited;
  }

  private static findPivotIndexes(klines: KLineItem[], isHigh: boolean, k: number): number[] {
    const idx: number[] = [];
    const n: number = klines.length;
    for (let i = k; i < n - k; i++) {
      let ok: boolean = true;
      for (let j = 1; j <= k; j++) {
        if (isHigh) {
          if (klines[i].high < klines[i - j].high || klines[i].high < klines[i + j].high) {
            ok = false;
            break;
          }
        } else {
          if (klines[i].low > klines[i - j].low || klines[i].low > klines[i + j].low) {
            ok = false;
            break;
          }
        }
      }
      if (ok) {
        idx.push(i);
      }
    }
    return idx;
  }

  private static displayDate(date: string): string {
    if (date.length === 12 && date.indexOf('-') < 0) {
      return date.substring(0, 4) + '-' + date.substring(4, 6) + '-' + date.substring(6, 8) +
        ' ' + date.substring(8, 10) + ':' + date.substring(10, 12);
    }
    return date;
  }

  private static buildInfo(divType: DivergenceType, level: KLineLevel,
    klines: KLineItem[], i1: number, i2: number,
    priceA: number, priceB: number, difA: number, difB: number): DivergenceInfo {
    const dateA: string = MacdAnalyzer.displayDate(klines[i1].date);
    const dateB: string = MacdAnalyzer.displayDate(klines[i2].date);
    let desc: string;
    if (divType === DivergenceType.TOP) {
      desc = `【${kLineLevelLabel(level)} · 顶背离】${dateA} → ${dateB}：` +
        `股价高点 ${priceA.toFixed(2)} → ${priceB.toFixed(2)} 创出新高，` +
        `但 DIF 由 ${difA.toFixed(2)} 回落至 ${difB.toFixed(2)}，未能同步创新高。` +
        `上行动能减弱，警惕短期回调风险。`;
    } else {
      desc = `【${kLineLevelLabel(level)} · 底背离】${dateA} → ${dateB}：` +
        `股价低点 ${priceA.toFixed(2)} → ${priceB.toFixed(2)} 创出新低，` +
        `但 DIF 由 ${difA.toFixed(2)} 抬升至 ${difB.toFixed(2)}，低点逐步走高。` +
        `下跌动能衰竭，关注反弹机会。`;
    }
    return new DivergenceInfo(divType, level, i1, i2, dateA, dateB,
      priceA, priceB, difA, difB, desc);
  }
}
