import { http } from '@kit.NetworkKit';

/**
 * OpenAI 协议兼容的大模型客户端（DeepSeek 等）。
 * POST {baseUrl}/chat/completions，Bearer 鉴权，非流式返回。
 */
export class AiClient {
  static async chat(baseUrl: string, apiKey: string, model: string,
    prompt: string): Promise<string> {
    if (apiKey === '') {
      throw new Error('未配置 API Key');
    }
    const trimmed: string = baseUrl.trim();
    const base: string = trimmed.endsWith('/')
      ? trimmed.substring(0, trimmed.length - 1) : trimmed;
    const url: string = base + '/chat/completions';
    const message: Record<string, Object> = { 'role': 'user', 'content': prompt };
    const messages: Array<Record<string, Object>> = [message];
    const body: Record<string, Object> = {
      'model': model,
      'messages': messages,
      'stream': false
    };
    const header: Record<string, string> = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ' + apiKey
    };
    const client: http.HttpRequest = http.createHttp();
    try {
      const resp: http.HttpResponse = await client.request(url, {
        method: http.RequestMethod.POST,
        header: header,
        extraData: JSON.stringify(body),
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 15000,
        readTimeout: 90000
      });
      const text: string = resp.result as string;
      if (resp.responseCode !== 200) {
        throw new Error('HTTP ' + resp.responseCode + '：'
          + AiClient.briefText(AiClient.extractApiError(text)));
      }
      return AiClient.parseContent(text);
    } finally {
      client.destroy();
    }
  }

  private static briefText(text: string): string {
    if (text === null || text === undefined) {
      return '未知错误';
    }
    if (text === '') {
      return '未知错误';
    }
    if (text.length > 160) {
      return text.substring(0, 160);
    }
    return text;
  }

  /**
   * 从错误响应 JSON 中提取 error.message（DeepSeek/OpenAI 错误格式）。
   */
  private static extractApiError(text: string): string {
    try {
      const root: Record<string, Object> = JSON.parse(text) as Record<string, Object>;
      const errObj: Object | undefined = root['error'];
      if (errObj !== undefined && errObj !== null) {
        const errRec: Record<string, Object> = errObj as Record<string, Object>;
        const msgObj: Object | undefined = errRec['message'];
        if (typeof msgObj === 'string' && msgObj !== '') {
          return msgObj;
        }
      }
    } catch (error) {
      // 非 JSON 文本
    }
    return text;
  }

  private static parseContent(text: string): string {
    const root: Record<string, Object> = JSON.parse(text) as Record<string, Object>;
    const choicesObj: Object | undefined = root['choices'];
    if (choicesObj === undefined || choicesObj === null) {
      const apiErr: string = AiClient.extractApiError(text);
      if (apiErr !== text) {
        throw new Error(apiErr);
      }
      throw new Error('AI 响应格式异常');
    }
    const choices: Array<Record<string, Object>> =
      choicesObj as Array<Record<string, Object>>;
    if (choices.length === 0) {
      throw new Error('AI 返回空结果');
    }
    const first: Record<string, Object> = choices[0];
    const msgObj: Object | undefined = first['message'];
    if (msgObj === undefined || msgObj === null) {
      throw new Error('AI 返回缺少内容');
    }
    const msg: Record<string, Object> = msgObj as Record<string, Object>;
    const contentObj: Object | undefined = msg['content'];
    if (typeof contentObj !== 'string' || contentObj === '') {
      throw new Error('AI 返回内容为空');
    }
    return contentObj;
  }
}
