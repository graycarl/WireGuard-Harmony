import { appTasks } from '@ohos/hvigor-ohos-plugin';
import * as fs from 'fs';
import * as path from 'path';

/**
 * 签名材料注入（方案：`config.ohos.overrides.signingConfig`）。
 *
 * 背景：`build-profile.json5` 必须入库（products/SDK/buildModeSet/modules 是构建的单一真源），
 * 但它的 `app.signingConfigs` 会被 DevEco Studio 写入**本机绝对路径 + 签名口令**。
 * 因此仓库里该字段恒为 `[]`，材料放本机不入库的 `signing-config.local.json`，在这里注入。
 *
 * 材料来源（优先级从高到低）：
 *   1. 环境变量 `WG_SIGN_*`（字段级覆盖；口令须为 DevEco 加密后的十六进制串）
 *   2. `signing-config.local.json`（本机；由 `make sign-import` 从 DevEco 写出的 build-profile 生成）
 *   3. `build-profile.json5` 的 `app.signingConfigs`（hvigor 自身兜底：DevEco 刚配完签名也能直接构建）
 *
 * ⚠️ 在 DevEco Studio 里改了签名配置后，build-profile.json5 会被重新写脏 →
 *    跑 `make sign-import` 把材料搬进本地文件并还原 build-profile.json5。
 */

const LOCAL_SIGN_FILE: string = path.resolve(__dirname, 'signing-config.local.json');

interface SigningMaterial {
  storePassword?: string;
  certpath?: string;
  keyAlias?: string;
  keyPassword?: string;
  profile?: string;
  signAlg?: string;
  storeFile?: string;
}

interface SigningConfig {
  name: string;
  type: string;
  material: SigningMaterial;
}

/** 环境变量 → material 字段的映射（值为 undefined 时视为未设置）。 */
const ENV_FIELDS: Map<string, keyof SigningMaterial> = new Map([
  ['WG_SIGN_STORE_FILE', 'storeFile'],
  ['WG_SIGN_STORE_PASSWORD', 'storePassword'],
  ['WG_SIGN_KEY_ALIAS', 'keyAlias'],
  ['WG_SIGN_KEY_PASSWORD', 'keyPassword'],
  ['WG_SIGN_CERT_PATH', 'certpath'],
  ['WG_SIGN_PROFILE', 'profile'],
  ['WG_SIGN_SIGN_ALG', 'signAlg'],
]);

function readLocalSigningConfig(): SigningConfig | undefined {
  if (!fs.existsSync(LOCAL_SIGN_FILE)) {
    return undefined;
  }
  try {
    const raw: string = fs.readFileSync(LOCAL_SIGN_FILE, 'utf-8');
    const parsed: SigningConfig = JSON.parse(raw) as SigningConfig;
    if (parsed.material === undefined || parsed.material === null) {
      throw new Error('缺少 material 字段');
    }
    return parsed;
  } catch (err) {
    const reason: string = err instanceof Error ? err.message : String(err);
    throw new Error(`${LOCAL_SIGN_FILE} 解析失败：${reason}（可删除该文件后重新用 make sign-import 生成）`);
  }
}

function withEnvOverrides(signingConfig: SigningConfig): SigningConfig {
  const material: SigningMaterial = Object.assign({}, signingConfig.material);
  ENV_FIELDS.forEach((field: keyof SigningMaterial, envName: string) => {
    const value: string | undefined = process.env[envName];
    if (value !== undefined && value.length > 0) {
      material[field] = value;
    }
  });
  return { name: signingConfig.name, type: signingConfig.type, material: material };
}

/**
 * 注入用的对象：hvigor 对 `overrides.signingConfig` 做 schema 校验，**只允许 material / type 两个键**
 * （多带 `name` 会直接 00303038 Schema validate failed，且报错指向 hvigorfile.ts）。
 * 产品侧 `products[].signingConfig: "default"` 只是「挑一套签名方案」的名字，由 hvigor 自己匹配，
 * 匹配不到 build-profile.json5 里的条目时就用本 override。
 */
function toInjectableSigningConfig(signingConfig: SigningConfig): Record<string, object> {
  return {
    type: signingConfig.type,
    material: Object.assign({}, signingConfig.material) as object,
  };
}

function buildConfig(): Record<string, object> {
  const config: Record<string, object> = { system: appTasks, plugins: [] };
  const localSigningConfig: SigningConfig | undefined = readLocalSigningConfig();
  if (localSigningConfig !== undefined) {
    config.config = {
      ohos: {
        overrides: {
          signingConfig: toInjectableSigningConfig(withEnvOverrides(localSigningConfig)),
        },
      },
    };
  }
  return config;
}

export default buildConfig();
