/*
 * 锁屏认证（specs/privacy-security.md）。
 *
 * 规则：
 * - 生物识别或锁屏凭证（PIN/图案/密码）均可；
 * - 设备无任何认证能力（未录入/不支持）→ 直接通过、不阻断（spec 明确定案）；
 * - 单次识别失败 → 「认证失败」；系统错误 → 「认证失败：<原因>」；取消 → 无提示。
 */

import { userAuth } from '@kit.UserAuthenticationKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { secureRandomBytes } from '../crypto/PlatformRandom';
import { Logger } from '../util/Logger';

const TAG = 'AuthGuard';

export enum AuthResultKind {
  SUCCESS = 0,
  FAILED = 1,
  CANCELLED = 2,
  ERROR = 3
}

export interface AuthResult {
  kind: AuthResultKind;
  /** 已本地化文案；SUCCESS/CANCELLED 为空串 */
  message: string;
}

function reasonForCode(code: number): string {
  if (code === userAuth.UserAuthResultCode.FAIL) {
    return '认证失败';
  }
  if (code === userAuth.UserAuthResultCode.GENERAL_ERROR) {
    return '系统错误';
  }
  if (code === userAuth.UserAuthResultCode.TIMEOUT) {
    return '认证超时';
  }
  if (code === userAuth.UserAuthResultCode.TYPE_NOT_SUPPORT) {
    return '认证方式不支持';
  }
  if (code === userAuth.UserAuthResultCode.TRUST_LEVEL_NOT_SUPPORT) {
    return '认证安全级别不支持';
  }
  if (code === userAuth.UserAuthResultCode.BUSY) {
    return '认证服务忙';
  }
  if (code === userAuth.UserAuthResultCode.INVALID_PARAMETERS) {
    return '认证参数无效';
  }
  if (code === userAuth.UserAuthResultCode.LOCKED) {
    return '认证失败次数过多，已被锁定';
  }
  return `系统错误（${code}）`;
}

export class AuthGuard {
  /**
   * 请求锁屏认证。title 为系统认证界面标题（如「查看私钥前需要通过认证」）。
   * 无认证能力时直接返回 SUCCESS。
   */
  static async authenticate(title: string): Promise<AuthResult> {
    if (!AuthGuard.hasCapability()) {
      Logger.info(TAG, '设备无锁屏认证能力，直接放行');
      return { kind: AuthResultKind.SUCCESS, message: '' };
    }
    let instance: userAuth.UserAuthInstance;
    try {
      const authParam: userAuth.AuthParam = {
        challenge: secureRandomBytes(32),
        authType: [userAuth.UserAuthType.FINGERPRINT, userAuth.UserAuthType.FACE,
          userAuth.UserAuthType.PIN],
        authTrustLevel: userAuth.AuthTrustLevel.ATL3
      };
      const widgetParam: userAuth.WidgetParam = { title: title };
      instance = userAuth.getUserAuthInstance(authParam, widgetParam);
    } catch (e) {
      const error = e as BusinessError;
      Logger.error(TAG, `创建认证实例失败：${error.message}`);
      return { kind: AuthResultKind.ERROR, message: `认证失败：${error.message}` };
    }

    return new Promise<AuthResult>((resolve: (result: AuthResult) => void): void => {
      let settled = false;
      const finish = (result: AuthResult): void => {
        if (!settled) {
          settled = true;
          resolve(result);
        }
      };
      const callback: userAuth.IAuthCallback = {
        onResult: (result: userAuth.UserAuthResult): void => {
          if (result.result === userAuth.UserAuthResultCode.SUCCESS) {
            finish({ kind: AuthResultKind.SUCCESS, message: '' });
          } else if (result.result === userAuth.UserAuthResultCode.CANCELED) {
            finish({ kind: AuthResultKind.CANCELLED, message: '' });
          } else if (result.result === userAuth.UserAuthResultCode.FAIL) {
            finish({ kind: AuthResultKind.FAILED, message: '认证失败' });
          } else if (result.result === userAuth.UserAuthResultCode.LOCKED) {
            finish({ kind: AuthResultKind.FAILED, message: '认证失败：认证失败次数过多，已被锁定' });
          } else {
            finish({ kind: AuthResultKind.ERROR, message: `认证失败：${reasonForCode(result.result)}` });
          }
        }
      };
      instance.on('result', callback);
      try {
        instance.start();
      } catch (e) {
        const error = e as BusinessError;
        Logger.error(TAG, `发起认证失败：${error.message}`);
        finish({ kind: AuthResultKind.ERROR, message: `认证失败：${error.message}` });
      }
    });
  }

  /** 设备是否存在可用的锁屏认证能力（PIN/生物识别任一）。 */
  private static hasCapability(): boolean {
    const types: userAuth.UserAuthType[] = [
      userAuth.UserAuthType.PIN,
      userAuth.UserAuthType.FINGERPRINT,
      userAuth.UserAuthType.FACE
    ];
    for (const type of types) {
      try {
        userAuth.getAvailableStatus(type, userAuth.AuthTrustLevel.ATL3);
        return true;
      } catch (e) {
        // 该方式不可用（未录入/不支持），继续检查下一种
      }
    }
    return false;
  }
}
