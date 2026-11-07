import { authentication } from '@kit.AccountKit';
import { cloudDatabase } from '@kit.CloudFoundationKit';
import { common } from '@kit.AbilityKit';

/**
 * AGC 云同步数据对象：对应 AGC 云数据库对象类型 WatchlistRecord
 * （字段 openId / codes / updateTime，openId 建为主键）。
 */
export class WatchlistRecord extends cloudDatabase.DatabaseObject {
  openId: string = '';
  codes: string = '';
  updateTime: number = 0;

  naturalbase_ClassName(): string {
    return 'WatchlistRecord';
  }
}

/**
 * 华为账号云同步（AGC 完整接入）。
 * 生效前提：
 * 1. AGC 创建项目，应用包名一致，开通云数据库并创建对象类型 WatchlistRecord；
 * 2. agconnect-services.json 放入 entry 目录，DevEco 配置签名；
 * 3. module.json5 metadata.client_id 替换为 AGC 下发的 Client ID；
 * 4. 华为账号体系仅真机可用。
 * 未配置时所有调用抛出异常，由 UI 层转为友好提示。
 */
export class CloudSync {
  private static readonly ZONE_NAME: string = 'StockAnalysisZone';

  /**
   * 华为账号登录，返回 openID。
   * forceLogin=false 用于静默检查登录态；true 会拉起登录/授权页。
   */
  static async login(context: common.Context, forceLogin: boolean): Promise<string> {
    const provider: authentication.HuaweiIDProvider = new authentication.HuaweiIDProvider();
    const request: authentication.LoginWithHuaweiIDRequest =
      provider.createLoginWithHuaweiIDRequest();
    request.forceLogin = forceLogin;
    const controller: authentication.AuthenticationController =
      new authentication.AuthenticationController(context);
    const response: authentication.AuthenticationResponse =
      await controller.executeRequest(request);
    const loginResp: authentication.LoginWithHuaweiIDResponse =
      response as authentication.LoginWithHuaweiIDResponse;
    const credential: authentication.LoginWithHuaweiIDCredential | undefined =
      loginResp.data;
    if (credential === undefined) {
      throw new Error('empty login credential');
    }
    return credential.openID;
  }

  /**
   * 申请 profile 授权获取昵称，失败由调用方兜底为"华为用户"。
   */
  static async fetchNickname(context: common.Context): Promise<string> {
    const provider: authentication.HuaweiIDProvider = new authentication.HuaweiIDProvider();
    const request: authentication.AuthorizationWithHuaweiIDRequest =
      provider.createAuthorizationWithHuaweiIDRequest();
    request.scopes = ['profile', 'openid'];
    request.forceAuthorization = true;
    const controller: authentication.AuthenticationController =
      new authentication.AuthenticationController(context);
    const response: authentication.AuthenticationResponse =
      await controller.executeRequest(request);
    const authResp: authentication.AuthorizationWithHuaweiIDResponse =
      response as authentication.AuthorizationWithHuaweiIDResponse;
    const credential: authentication.AuthorizationWithHuaweiIDCredential | undefined =
      authResp.data;
    if (credential !== undefined && credential.nickName !== undefined
      && credential.nickName !== '') {
      return credential.nickName;
    }
    return '华为用户';
  }

  /**
   * 上传自选股到云端（按 openId upsert 单条记录）。
   */
  static async uploadWatchlist(context: common.Context, openId: string,
    codes: string[]): Promise<void> {
    const zone: cloudDatabase.DatabaseZone = cloudDatabase.zone(CloudSync.ZONE_NAME);
    const record: WatchlistRecord = new WatchlistRecord();
    record.openId = openId;
    record.codes = JSON.stringify(codes);
    record.updateTime = Date.now();
    const count: number = await zone.upsert(record);
    if (count <= 0) {
      throw new Error('cloud upsert 0 records');
    }
  }

  /**
   * 从云端拉取自选股代码列表，云端无记录返回空数组。
   */
  static async downloadWatchlist(context: common.Context,
    openId: string): Promise<string[]> {
    const zone: cloudDatabase.DatabaseZone = cloudDatabase.zone(CloudSync.ZONE_NAME);
    const query: cloudDatabase.DatabaseQuery<WatchlistRecord> =
      new cloudDatabase.DatabaseQuery(WatchlistRecord);
    query.equalTo('openId', openId).limit(1);
    const rows: WatchlistRecord[] = await zone.query(query);
    const result: string[] = [];
    if (rows.length === 0) {
      return result;
    }
    const raw: string = rows[0].codes;
    if (raw === '') {
      return result;
    }
    const arr: Object[] = JSON.parse(raw) as Object[];
    for (const item of arr) {
      if (typeof item === 'string' && item !== '') {
        result.push(item);
      }
    }
    return result;
  }
}
