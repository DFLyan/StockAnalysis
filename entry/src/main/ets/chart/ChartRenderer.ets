import {
  DivergenceInfo,
  DivergenceType,
  KLineItem,
  MacdPoint
} from '../model/StockModels';

/**
 * K线 / MACD 画布渲染器。红涨绿跌，背离点在图上以标记线与圆点标出。
 * fontScale 为坐标轴字号缩放（0.75 ~ 2.0），字体、轴留白与刻度间距随之联动。
 */
export class ChartRenderer {
  private static readonly UP_COLOR: string = '#E62E4C';
  private static readonly DOWN_COLOR: string = '#1DBF60';
  private static readonly GRID_COLOR: string = '#252A38';
  private static readonly AXIS_LINE_COLOR: string = '#2C3140';
  private static readonly AXIS_TEXT_COLOR: string = '#A6ADBE';
  private static readonly TOP_DIV_COLOR: string = '#B388FF';
  private static readonly BOTTOM_DIV_COLOR: string = '#4DD0E1';
  private static readonly DIF_COLOR: string = '#F0F0F0';
  private static readonly DEA_COLOR: string = '#FFB74D';
  private static readonly NICE_TICK_STEPS: number[] = [1, 2, 4, 8, 16, 32, 64, 128, 256];

  private static fontPx(base: number, fontScale: number): string {
    return Math.max(8, Math.round(base * fontScale)) + 'px sans-serif';
  }

  /**
   * 右侧留白按可见区价格标签的实际字符数动态计算（每字符约 0.6em），
   * 字号放大时不再产生大片空白；K线与 MACD 图共用同一结果以保持纵向对齐。
   */
  static axisPadRight(klines: KLineItem[], start: number, end: number,
    fontScale: number): number {
    if (klines.length === 0 || end - start < 2) {
      return Math.round(30 * fontScale) + 30;
    }
    let minV: number = klines[start].low;
    let maxV: number = klines[start].high;
    for (let i = start; i < end; i++) {
      if (klines[i].low < minV) {
        minV = klines[i].low;
      }
      if (klines[i].high > maxV) {
        maxV = klines[i].high;
      }
    }
    const span: number = Math.max(maxV - minV, 0.01);
    minV = minV - span * 0.05;
    maxV = maxV + span * 0.05;
    let maxChars: number = 0;
    for (let g = 0; g <= 4; g++) {
      const label: string = (maxV - (maxV - minV) * g / 4).toFixed(2);
      if (label.length > maxChars) {
        maxChars = label.length;
      }
    }
    const pad: number = Math.round(maxChars * 7.2 * fontScale + 10);
    if (pad < 40) {
      return 40;
    }
    return pad;
  }

  /**
   * 时间轴刻度与数据索引锚定（i % step === 0），
   * 因此拖动平移时标签会跟随内容移动；步长按标签最小间距（随字号缩放）自动调整。
   */
  private static pickTickStep(perBar: number, fontScale: number): number {
    const minLabelPx: number = 74 * fontScale;
    for (const s of ChartRenderer.NICE_TICK_STEPS) {
      if (s * perBar >= minLabelPx) {
        return s;
      }
    }
    return 512;
  }

  private static axisDateText(date: string): string {
    if (date.indexOf('-') >= 0) {
      return date.substring(5, 10);
    }
    if (date.length >= 12) {
      return date.substring(4, 6) + '-' + date.substring(6, 8) + ' ' +
        date.substring(8, 10) + ':' + date.substring(10, 12);
    }
    return date;
  }

  static drawKLineChart(ctx: CanvasRenderingContext2D, klines: KLineItem[],
    divergences: DivergenceInfo[], startIndex: number, endIndex: number,
    fontScale: number, crosshairIndex: number): void {
    const w: number = ctx.width;
    const h: number = ctx.height;
    if (w <= 0 || h <= 0 || klines.length === 0) {
      return;
    }
    ctx.clearRect(0, 0, w, h);
    const start: number = Math.max(0, startIndex);
    const end: number = Math.min(klines.length, endIndex);
    if (end - start < 2) {
      return;
    }
    const count: number = end - start;
    const padLeft: number = 6;
    const padRight: number = ChartRenderer.axisPadRight(klines, start, end, fontScale);
    const padTop: number = 14;
    const padBottom: number = Math.round(28 * fontScale);
    const plotW: number = w - padLeft - padRight;
    const plotH: number = h - padTop - padBottom;
    if (plotW <= 0 || plotH <= 0) {
      return;
    }

    let minV: number = klines[start].low;
    let maxV: number = klines[start].high;
    for (let i = start; i < end; i++) {
      if (klines[i].low < minV) {
        minV = klines[i].low;
      }
      if (klines[i].high > maxV) {
        maxV = klines[i].high;
      }
    }
    const span: number = Math.max(maxV - minV, 0.01);
    minV = minV - span * 0.05;
    maxV = maxV + span * 0.05;

    ctx.strokeStyle = ChartRenderer.GRID_COLOR;
    ctx.lineWidth = 1;
    ctx.fillStyle = ChartRenderer.AXIS_TEXT_COLOR;
    ctx.font = ChartRenderer.fontPx(12, fontScale);
    ctx.textAlign = 'left';
    for (let g = 0; g <= 4; g++) {
      const gy: number = padTop + plotH * g / 4;
      ctx.beginPath();
      ctx.moveTo(padLeft, gy);
      ctx.lineTo(w - padRight, gy);
      ctx.stroke();
      const price: number = maxV - (maxV - minV) * g / 4;
      ctx.fillText(price.toFixed(2), w - padRight + 4, gy + 4);
    }

    const step: number = plotW / count;
    const bodyW: number = Math.max(1, step * 0.66);
    for (let i = start; i < end; i++) {
      const bar: KLineItem = klines[i];
      const idx: number = i - start;
      const cx: number = padLeft + step * (idx + 0.5);
      const up: boolean = bar.close >= bar.open;
      const color: string = up ? ChartRenderer.UP_COLOR : ChartRenderer.DOWN_COLOR;
      ctx.strokeStyle = color;
      ctx.fillStyle = color;
      ctx.lineWidth = 1;
      const yHigh: number = padTop + (maxV - bar.high) / (maxV - minV) * plotH;
      const yLow: number = padTop + (maxV - bar.low) / (maxV - minV) * plotH;
      ctx.beginPath();
      ctx.moveTo(cx, yHigh);
      ctx.lineTo(cx, yLow);
      ctx.stroke();
      const yO: number = padTop + (maxV - bar.open) / (maxV - minV) * plotH;
      const yC: number = padTop + (maxV - bar.close) / (maxV - minV) * plotH;
      const topY: number = Math.min(yO, yC);
      const bodyH: number = Math.max(Math.abs(yC - yO), 1);
      ctx.fillRect(cx - bodyW / 2, topY, bodyW, bodyH);
    }

    // 底部时间轴：轴线 + 与数据索引锚定的刻度标签（拖动时跟随移动）
    ctx.strokeStyle = ChartRenderer.AXIS_LINE_COLOR;
    ctx.lineWidth = 1;
    ctx.beginPath();
    ctx.moveTo(padLeft, h - padBottom);
    ctx.lineTo(w - padRight, h - padBottom);
    ctx.stroke();

    const perBar: number = plotW / count;
    const tickStep: number = ChartRenderer.pickTickStep(perBar, fontScale);
    const tickLen: number = Math.max(4, Math.round(4 * fontScale));
    const xLabelY: number = h - Math.round(padBottom * 0.32);
    ctx.fillStyle = ChartRenderer.AXIS_TEXT_COLOR;
    ctx.font = ChartRenderer.fontPx(11, fontScale);
    ctx.textAlign = 'center';
    for (let i = start; i < end; i++) {
      if (i % tickStep !== 0) {
        continue;
      }
      const idx: number = i - start;
      const cx: number = padLeft + step * (idx + 0.5);
      if (cx < padLeft + 2 || cx > w - padRight - 2) {
        continue;
      }
      ctx.fillText(ChartRenderer.axisDateText(klines[i].date), cx, xLabelY);
      ctx.strokeStyle = ChartRenderer.AXIS_LINE_COLOR;
      ctx.beginPath();
      ctx.moveTo(cx, h - padBottom);
      ctx.lineTo(cx, h - padBottom + tickLen);
      ctx.stroke();
    }
    ctx.textAlign = 'left';

    for (const div of divergences) {
      if (div.indexA < start || div.indexB >= end) {
        continue;
      }
      const xa: number = padLeft + step * (div.indexA - start + 0.5);
      const xb: number = padLeft + step * (div.indexB - start + 0.5);
      const ya: number = padTop + (maxV - div.priceA) / (maxV - minV) * plotH;
      const yb: number = padTop + (maxV - div.priceB) / (maxV - minV) * plotH;
      const color: string = div.divType === DivergenceType.TOP
        ? ChartRenderer.TOP_DIV_COLOR : ChartRenderer.BOTTOM_DIV_COLOR;
      ctx.globalAlpha = 0.85;
      ctx.strokeStyle = color;
      ctx.lineWidth = 1.2;
      ctx.beginPath();
      ctx.moveTo(xa, ya);
      ctx.lineTo(xb, yb);
      ctx.stroke();
      ctx.fillStyle = color;
      ctx.beginPath();
      ctx.arc(xa, ya, 3, 0, Math.PI * 2);
      ctx.fill();
      ctx.beginPath();
      ctx.arc(xb, yb, 3, 0, Math.PI * 2);
      ctx.fill();
      ctx.font = ChartRenderer.fontPx(12, fontScale);
      const label: string = div.divType === DivergenceType.TOP ? '顶背离' : '底背离';
      if (div.divType === DivergenceType.TOP) {
        ctx.fillText(label, xb + 5, Math.max(padTop + 10, yb - 6));
      } else {
        ctx.fillText(label, xb + 5, Math.min(h - padBottom - 4, yb + 12));
      }
      ctx.globalAlpha = 1;
    }

    // 点击十字光标：竖线 + 收盘价横线 + 圆点 + 右侧价格标签
    if (crosshairIndex >= start && crosshairIndex < end) {
      const cx: number = padLeft + step * (crosshairIndex - start + 0.5);
      const bar: KLineItem = klines[crosshairIndex];
      const yClose: number = padTop + (maxV - bar.close) / (maxV - minV) * plotH;
      ctx.globalAlpha = 0.55;
      ctx.strokeStyle = '#C9D1E0';
      ctx.lineWidth = 1;
      ctx.setLineDash([4, 3]);
      ctx.beginPath();
      ctx.moveTo(cx, padTop);
      ctx.lineTo(cx, h - padBottom);
      ctx.stroke();
      ctx.beginPath();
      ctx.moveTo(padLeft, yClose);
      ctx.lineTo(w - padRight, yClose);
      ctx.stroke();
      ctx.setLineDash([]);
      ctx.globalAlpha = 1;
      ctx.fillStyle = '#C9D1E0';
      ctx.beginPath();
      ctx.arc(cx, yClose, 3.5, 0, Math.PI * 2);
      ctx.fill();
      const tagH: number = Math.round(12 * fontScale) + 6;
      ctx.fillStyle = '#2A5BD7';
      ctx.fillRect(w - padRight + 1, yClose - tagH / 2, padRight - 3, tagH);
      ctx.fillStyle = '#FFFFFF';
      ctx.font = ChartRenderer.fontPx(11, fontScale);
      ctx.textAlign = 'center';
      ctx.fillText(bar.close.toFixed(2), w - padRight + (padRight - 3) / 2,
        yClose + tagH * 0.35);
      ctx.textAlign = 'left';
    }
  }

  static drawMacdChart(ctx: CanvasRenderingContext2D, klines: KLineItem[],
    macdPoints: MacdPoint[], divergences: DivergenceInfo[],
    startIndex: number, endIndex: number, fontScale: number,
    crosshairIndex: number): void {
    const w: number = ctx.width;
    const h: number = ctx.height;
    if (w <= 0 || h <= 0 || macdPoints.length === 0) {
      return;
    }
    ctx.clearRect(0, 0, w, h);
    const start: number = Math.max(0, startIndex);
    const end: number = Math.min(macdPoints.length, endIndex);
    if (end - start < 2) {
      return;
    }
    const count: number = end - start;
    const padLeft: number = 6;
    const padRight: number = ChartRenderer.axisPadRight(klines, start, end, fontScale);
    const padTop: number = 10;
    const padBottom: number = Math.round(28 * fontScale);
    const plotW: number = w - padLeft - padRight;
    const plotH: number = h - padTop - padBottom;
    if (plotW <= 0 || plotH <= 0) {
      return;
    }

    let minV: number = 0;
    let maxV: number = 0;
    for (let i = start; i < end; i++) {
      const p: MacdPoint = macdPoints[i];
      const candidates: number[] = [p.dif, p.dea, p.bar];
      for (const c of candidates) {
        if (c < minV) {
          minV = c;
        }
        if (c > maxV) {
          maxV = c;
        }
      }
    }
    const range: number = Math.max(maxV - minV, 0.0001);
    minV = minV - range * 0.08;
    maxV = maxV + range * 0.08;

    ctx.strokeStyle = ChartRenderer.GRID_COLOR;
    ctx.lineWidth = 1;
    ctx.fillStyle = ChartRenderer.AXIS_TEXT_COLOR;
    ctx.font = ChartRenderer.fontPx(12, fontScale);
    ctx.textAlign = 'left';
    for (let g = 0; g <= 2; g++) {
      const gy: number = padTop + plotH * g / 2;
      ctx.beginPath();
      ctx.moveTo(padLeft, gy);
      ctx.lineTo(w - padRight, gy);
      ctx.stroke();
      const val: number = maxV - (maxV - minV) * g / 2;
      ctx.fillText(val.toFixed(2), w - padRight + 4, gy + 4);
    }

    const step: number = plotW / count;
    const barW: number = Math.max(1, step * 0.5);
    const yZero: number = padTop + (maxV - 0) / (maxV - minV) * plotH;
    for (let i = start; i < end; i++) {
      const p: MacdPoint = macdPoints[i];
      const idx: number = i - start;
      const cx: number = padLeft + step * (idx + 0.5);
      const yv: number = padTop + (maxV - p.bar) / (maxV - minV) * plotH;
      const color: string = p.bar >= 0 ? ChartRenderer.UP_COLOR : ChartRenderer.DOWN_COLOR;
      ctx.fillStyle = color;
      ctx.fillRect(cx - barW / 2, Math.min(yZero, yv), barW, Math.max(Math.abs(yv - yZero), 1));
    }

    ctx.lineWidth = 1.2;
    ctx.strokeStyle = ChartRenderer.DIF_COLOR;
    ctx.beginPath();
    for (let i = start; i < end; i++) {
      const idx: number = i - start;
      const cx: number = padLeft + step * (idx + 0.5);
      const cy: number = padTop + (maxV - macdPoints[i].dif) / (maxV - minV) * plotH;
      if (i === start) {
        ctx.moveTo(cx, cy);
      } else {
        ctx.lineTo(cx, cy);
      }
    }
    ctx.stroke();

    ctx.strokeStyle = ChartRenderer.DEA_COLOR;
    ctx.beginPath();
    for (let i = start; i < end; i++) {
      const idx: number = i - start;
      const cx: number = padLeft + step * (idx + 0.5);
      const cy: number = padTop + (maxV - macdPoints[i].dea) / (maxV - minV) * plotH;
      if (i === start) {
        ctx.moveTo(cx, cy);
      } else {
        ctx.lineTo(cx, cy);
      }
    }
    ctx.stroke();

    // 底部时间轴：与 K 线图一致，锚定数据索引，拖动时跟随移动
    ctx.strokeStyle = ChartRenderer.AXIS_LINE_COLOR;
    ctx.lineWidth = 1;
    ctx.beginPath();
    ctx.moveTo(padLeft, h - padBottom);
    ctx.lineTo(w - padRight, h - padBottom);
    ctx.stroke();

    const perBar: number = plotW / count;
    const tickStep: number = ChartRenderer.pickTickStep(perBar, fontScale);
    const tickLen: number = Math.max(4, Math.round(4 * fontScale));
    const xLabelY: number = h - Math.round(padBottom * 0.32);
    ctx.fillStyle = ChartRenderer.AXIS_TEXT_COLOR;
    ctx.font = ChartRenderer.fontPx(11, fontScale);
    ctx.textAlign = 'center';
    for (let i = start; i < end; i++) {
      if (i % tickStep !== 0 || i >= klines.length) {
        continue;
      }
      const idx: number = i - start;
      const cx: number = padLeft + step * (idx + 0.5);
      if (cx < padLeft + 2 || cx > w - padRight - 2) {
        continue;
      }
      ctx.fillText(ChartRenderer.axisDateText(klines[i].date), cx, xLabelY);
      ctx.strokeStyle = ChartRenderer.AXIS_LINE_COLOR;
      ctx.beginPath();
      ctx.moveTo(cx, h - padBottom);
      ctx.lineTo(cx, h - padBottom + tickLen);
      ctx.stroke();
    }
    ctx.textAlign = 'left';

    for (const div of divergences) {
      if (div.indexA < start || div.indexB >= end) {
        continue;
      }
      const xa: number = padLeft + step * (div.indexA - start + 0.5);
      const xb: number = padLeft + step * (div.indexB - start + 0.5);
      const ya: number = padTop + (maxV - div.difA) / (maxV - minV) * plotH;
      const yb: number = padTop + (maxV - div.difB) / (maxV - minV) * plotH;
      const color: string = div.divType === DivergenceType.TOP
        ? ChartRenderer.TOP_DIV_COLOR : ChartRenderer.BOTTOM_DIV_COLOR;
      ctx.globalAlpha = 0.85;
      ctx.strokeStyle = color;
      ctx.lineWidth = 1.2;
      ctx.beginPath();
      ctx.moveTo(xa, ya);
      ctx.lineTo(xb, yb);
      ctx.stroke();
      ctx.fillStyle = color;
      ctx.beginPath();
      ctx.arc(xa, ya, 3, 0, Math.PI * 2);
      ctx.fill();
      ctx.beginPath();
      ctx.arc(xb, yb, 3, 0, Math.PI * 2);
      ctx.fill();
      ctx.globalAlpha = 1;
    }

    // 与 K 线图同步的十字光标竖线
    if (crosshairIndex >= start && crosshairIndex < end) {
      const cx: number = padLeft + step * (crosshairIndex - start + 0.5);
      ctx.globalAlpha = 0.55;
      ctx.strokeStyle = '#C9D1E0';
      ctx.lineWidth = 1;
      ctx.setLineDash([4, 3]);
      ctx.beginPath();
      ctx.moveTo(cx, padTop);
      ctx.lineTo(cx, h - padBottom);
      ctx.stroke();
      ctx.setLineDash([]);
      ctx.globalAlpha = 1;
    }
  }
}
