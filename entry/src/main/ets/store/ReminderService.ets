import { notificationManager } from '@kit.NotificationKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { common } from '@kit.AbilityKit';
import { SettingsStore } from './SettingsStore';
import { WatchlistStore } from './WatchlistStore';
import { StockApi } from '../data/StockApi';
import { MacdAnalyzer } from '../analysis/MacdAnalyzer';
import {
  DivergenceInfo,
  DivergenceType,
  KLineItem,
  KLineLevel,
  MacdPoint,
  StockQuote,
  kLineLevelLabel
} from '../model/StockModels';

const DOMAIN = 0x0000;
const TAG = 'ReminderService';
const MAX_NOTIFY_CODES: number = 8;
const MAX_KEYS: number = 600;

/**
 * 背离提醒服务：应用运行期间按设定间隔检测自选股全部所选级别，
 * 相对已提醒快照（key = code|级别|类型|B点日期）发现新背离时发送系统通知。
 * 首次检测仅建立基线快照，不提醒历史背离。
 */
export class ReminderService {
  private static timerId: number = -1;
  private static ticking: boolean = false;
  private static nextNoticeId: number = 1001;

  /** 应用启动时调用：设置已开启则恢复定时检测。 */
  static async start(context: common.Context): Promise<void> {
    ReminderService.stop();
    const enabled: boolean = await SettingsStore.loadReminderEnabled(context);
    if (!enabled) {
      return;
    }
    const intervalMin: number = await SettingsStore.loadReminderIntervalMin(context);
    ReminderService.timerId = setInterval(() => {
      ReminderService.tick(context);
    }, intervalMin * 60 * 1000);
    ReminderService.tick(context);
  }

  /** 停止定时检测。 */
  static stop(): void {
    if (ReminderService.timerId >= 0) {
      clearInterval(ReminderService.timerId);
      ReminderService.timerId = -1;
    }
  }

  /** 设置变化后重启定时器。 */
  static async restart(context: common.Context): Promise<void> {
    ReminderService.stop();
    await ReminderService.start(context);
  }

  /** 申请通知授权（首次调用弹系统授权框，之后静默）。 */
  static async ensureNotificationEnabled(): Promise<boolean> {
    try {
      await notificationManager.requestEnableNotification();
      return true;
    } catch (error) {
      return false;
    }
  }

  private static async tick(context: common.Context): Promise<void> {
    if (ReminderService.ticking) {
      return;
    }
    ReminderService.ticking = true;
    try {
      const enabled: boolean = await SettingsStore.loadReminderEnabled(context);
      if (!enabled) {
        return;
      }
      const codes: string[] = await WatchlistStore.loadCodes(context);
      if (codes.length === 0) {
        return;
      }
      const levels: KLineLevel[] = await SettingsStore.loadReminderLevels(context);
      const divFilter: string = await SettingsStore.loadReminderDivType(context);
      const baselineDone: boolean = await SettingsStore.loadReminderBaselineDone(context);
      const notifiedKeys: string[] = await SettingsStore.loadReminderNotifiedKeys(context);

      // 通知里显示股票名称：批量拉一次报价，失败则退化为代码
      const quoteCodes: string[] = [];
      const quoteNames: string[] = [];
      try {
        const quotes: StockQuote[] = await StockApi.fetchQuotes(codes);
        for (const quote of quotes) {
          quoteCodes.push(quote.code);
          quoteNames.push(quote.name);
        }
      } catch (error) {
        // 名称拉取失败不影响检测
      }

      const hitCodes: string[] = [];
      const hitTexts: string[][] = [];
      for (const code of codes) {
        for (const level of levels) {
          let klines: KLineItem[];
          try {
            klines = await StockApi.fetchKLines(code, level);
          } catch (error) {
            continue; // 单标的拉取失败忽略，等待下次
          }
          if (klines.length < 35) {
            continue;
          }
          const macd: MacdPoint[] = MacdAnalyzer.calcMacd(klines);
          const divs: DivergenceInfo[] = MacdAnalyzer.detectDivergence(klines, macd, level);
          for (const div of divs) {
            if (divFilter === 'top' && div.divType !== DivergenceType.TOP) {
              continue;
            }
            if (divFilter === 'bottom' && div.divType !== DivergenceType.BOTTOM) {
              continue;
            }
            const key: string = code + '|' + level + '|' + div.divType + '|' + div.dateB;
            if (notifiedKeys.indexOf(key) >= 0) {
              continue;
            }
            notifiedKeys.push(key);
            if (!baselineDone) {
              continue; // 基线阶段只记录不提醒
            }
            ReminderService.pushHit(hitCodes, hitTexts, code, level, div);
          }
        }
      }

      if (notifiedKeys.length > MAX_KEYS) {
        const kept: string[] = notifiedKeys.slice(notifiedKeys.length - MAX_KEYS);
        await SettingsStore.saveReminderNotifiedKeys(context, kept);
      } else {
        await SettingsStore.saveReminderNotifiedKeys(context, notifiedKeys);
      }
      if (!baselineDone) {
        await SettingsStore.saveReminderBaselineDone(context, true);
      }
      if (hitCodes.length > 0) {
        await ReminderService.publish(hitCodes, hitTexts, quoteCodes, quoteNames);
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'tick failed: %{public}s', `${error}`);
    } finally {
      ReminderService.ticking = false;
    }
  }

  private static pushHit(hitCodes: string[], hitTexts: string[][],
    code: string, level: KLineLevel, div: DivergenceInfo): void {
    const text: string = kLineLevelLabel(level) + ' · ' +
      (div.divType === DivergenceType.TOP ? '顶背离' : '底背离');
    const index: number = hitCodes.indexOf(code);
    if (index < 0) {
      hitCodes.push(code);
      const firstTexts: string[] = [text];
      hitTexts.push(firstTexts);
      return;
    }
    const texts: string[] = hitTexts[index];
    if (texts.indexOf(text) < 0) {
      texts.push(text);
    }
  }

  private static async publish(hitCodes: string[], hitTexts: string[][],
    quoteCodes: string[], quoteNames: string[]): Promise<void> {
    const count: number = Math.min(MAX_NOTIFY_CODES, hitCodes.length);
    for (let i = 0; i < count; i++) {
      const code: string = hitCodes[i];
      let name: string = code;
      const nameIndex: number = quoteCodes.indexOf(code);
      if (nameIndex >= 0 && quoteNames[nameIndex] !== '') {
        name = quoteNames[nameIndex];
      }
      const request: notificationManager.NotificationRequest = {
        id: ReminderService.nextNoticeId,
        content: {
          notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
          normal: {
            title: name + ' 出现新背离',
            text: hitTexts[i].join('；'),
            additionalText: '股票分析 · 背离提醒'
          }
        }
      };
      ReminderService.nextNoticeId++;
      try {
        await notificationManager.publish(request);
      } catch (error) {
        hilog.warn(DOMAIN, TAG, 'publish failed: %{public}s', `${error}`);
      }
    }
  }
}
