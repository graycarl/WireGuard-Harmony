#!/usr/bin/env node
/**
 * 签名材料搬运工具（配合 hvigorfile.ts 的 `config.ohos.overrides.signingConfig`）。
 *
 * 为什么需要它：
 *   `build-profile.json5` 必须入库，但 DevEco Studio 在 Project Structure > Signing Configs
 *   点 Apply 后会把「本机绝对路径 + 加密口令」写进它的 `app.signingConfigs`。
 *   本脚本把这段材料搬到本机不入库的 `signing-config.local.json`，并把 build-profile.json5
 *   还原成 `"signingConfigs": []`，从此仓库里不再出现签名材料。
 *
 * 用法（推荐走 make 目标）：
 *   node scripts/sign-config.mjs import   # 等价 make sign-import
 *   node scripts/sign-config.mjs status   # 等价 make sign-status
 *
 * 注：build-profile.json5 是 JSON5（允许注释/尾逗号），这里用「定位 + 子串解析」的方式处理，
 *     不引入 json5 依赖：先按引号感知的扫描器切出 signingConfigs 的值，再对该子串做 JSON5-lite 清洗。
 */

import * as fs from 'node:fs';
import * as path from 'node:path';
import { fileURLToPath } from 'node:url';

const PROJECT_DIR = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const BUILD_PROFILE = path.join(PROJECT_DIR, 'build-profile.json5');
const LOCAL_SIGN_FILE = path.join(PROJECT_DIR, 'signing-config.local.json');
const KEY = 'signingConfigs';

/** 去掉注释与尾逗号（字符串内的 // /* 不受影响）。 */
function stripJson5(src) {
  let out = '';
  let inString = false;
  let quote = '';
  for (let i = 0; i < src.length; i++) {
    const ch = src[i];
    if (inString) {
      out += ch;
      if (ch === '\\') {
        out += src[++i] ?? '';
      } else if (ch === quote) {
        inString = false;
      }
      continue;
    }
    if (ch === '"' || ch === "'") {
      inString = true;
      quote = ch;
      out += ch;
      continue;
    }
    if (ch === '/' && src[i + 1] === '/') {
      while (i < src.length && src[i] !== '\n') i++;
      out += '\n';
      continue;
    }
    if (ch === '/' && src[i + 1] === '*') {
      i += 2;
      while (i < src.length && !(src[i] === '*' && src[i + 1] === '/')) i++;
      i++;
      continue;
    }
    out += ch;
  }
  // 尾逗号：,] 或 ,} → 删掉逗号
  return out.replace(/,(\s*[}\]])/g, '$1');
}

/** 找到 `"signingConfigs"` 的值区间 [start, end)（end 为右括号之后）。
 *  返回 undefined = 字段不存在；抛错 = 字段存在但值不是数组（文件被写坏）。 */
function findSigningConfigsRange(src) {
  const keyIndex = src.search(new RegExp(`"${KEY}"\\s*:`));
  if (keyIndex < 0) {
    return undefined;
  }
  let i = src.indexOf(':', keyIndex) + 1;
  const colonIndex = i - 1;
  while (i < src.length && /\s/.test(src[i])) i++;
  const open = src[i];
  if (open !== '[') {
    throw new Error(`build-profile.json5 的 ${KEY} 不是数组（当前首字符为 ${JSON.stringify(open)}）—— 文件可能已被写坏，先 git checkout -- build-profile.json5`);
  }
  const closing = { '[': ']', '{': '}' };
  const valueStart = i;
  const stack = [];
  let inString = false;
  let quote = '';
  for (; i < src.length; i++) {
    const ch = src[i];
    if (inString) {
      if (ch === '\\') i++;
      else if (ch === quote) inString = false;
      continue;
    }
    if (ch === '"' || ch === "'") {
      inString = true;
      quote = ch;
      continue;
    }
    if (ch === '/' && (src[i + 1] === '/' || src[i + 1] === '*')) {
      // 值区间里出现注释：跳过（不参与括号配对）
      if (src[i + 1] === '/') {
        while (i < src.length && src[i] !== '\n') i++;
      } else {
        i += 2;
        while (i < src.length && !(src[i] === '*' && src[i + 1] === '/')) i++;
        i++;
      }
      continue;
    }
    if (ch === '[' || ch === '{') stack.push(closing[ch]);
    else if (ch === ']' || ch === '}') {
      stack.pop();
      if (stack.length === 0) {
        return { colonIndex, valueStart, end: i + 1 };
      }
    }
  }
  return undefined;
}

function readProfileSigningConfigs() {
  const src = fs.readFileSync(BUILD_PROFILE, 'utf-8');
  const range = findSigningConfigsRange(src);
  if (range === undefined) {
    return { src, range: undefined, configs: [] };
  }
  let configs = [];
  const raw = stripJson5(src.slice(range.valueStart, range.end)).trim();
  if (raw !== '[]') {
    try {
      configs = JSON.parse(raw);
    } catch (err) {
      throw new Error(`解析 build-profile.json5 的 ${KEY} 失败：${err.message}`);
    }
    if (!Array.isArray(configs)) {
      throw new Error(`build-profile.json5 的 ${KEY} 解析结果不是数组，已中止（未改动任何文件）`);
    }
    if (configs.length > 0 && (configs[0].material === undefined || configs[0].material === null)) {
      throw new Error(`build-profile.json5 的 ${KEY}[0] 缺少 material 字段，已中止（未改动任何文件）`);
    }
  }
  return { src, range, configs };
}

function readLocalSigningConfig() {
  if (!fs.existsSync(LOCAL_SIGN_FILE)) {
    return undefined;
  }
  return JSON.parse(fs.readFileSync(LOCAL_SIGN_FILE, 'utf-8'));
}

function mask(secret) {
  if (typeof secret !== 'string' || secret.length === 0) return '(空)';
  return `${secret.slice(0, 8)}…（${secret.length} 字符）`;
}

function describe(config) {
  const m = config.material ?? {};
  return [
    `  name        : ${config.name} / ${config.type}`,
    `  storeFile   : ${m.storeFile}`,
    `  certpath    : ${m.certpath}`,
    `  profile     : ${m.profile}`,
    `  keyAlias    : ${m.keyAlias} (signAlg=${m.signAlg})`,
    `  keyPassword : ${mask(m.keyPassword)}`,
    `  storePassword: ${mask(m.storePassword)}`,
  ].join('\n');
}

function cmdImport() {
  const { src, range, configs } = readProfileSigningConfigs();
  if (configs.length === 0) {
    const local = readLocalSigningConfig();
    console.log(
      local
        ? `✅ build-profile.json5 已是 "signingConfigs": []，本地签名材料在 signing-config.local.json：\n${describe(local)}`
        : `ℹ️ 未发现签名材料：build-profile.json5 的 ${KEY} 为空，也没有 signing-config.local.json。\n   请先在 DevEco Studio 里配一次签名（Project Structure > Signing Configs > 勾选 Automatically generate signature > Apply），再跑本命令。`,
    );
    return;
  }
  const config = configs[0];
  fs.writeFileSync(LOCAL_SIGN_FILE, `${JSON.stringify(config, undefined, 2)}\n`, 'utf-8');
  // 连 `:` 后的空白一起规范化，确保还原后与入库版本逐字节一致（否则 git 仍有一行空白 diff）
  const cleaned = `${src.slice(0, range.colonIndex + 1)} []${src.slice(range.end)}`;
  fs.writeFileSync(BUILD_PROFILE, cleaned, 'utf-8');
  console.log(`✅ 已把签名材料搬到 signing-config.local.json（该文件已 gitignore），并把 build-profile.json5 还原为 "signingConfigs": []`);
  console.log(describe(config));
  console.log('   注：Git 仓库里现在只剩 build-profile.json5 的这一行改动（应为 0 改动）。');
}

function cmdStatus() {
  const { configs } = readProfileSigningConfigs();
  const local = readLocalSigningConfig();
  if (configs.length > 0) {
    console.log('⚠️ build-profile.json5 里又出现了签名材料（DevEco Studio 写脏的）→ 跑 `make sign-import` 搬运并还原。');
    console.log(describe(configs[0]));
    return;
  }
  if (local === undefined) {
    console.log('ℹ️ 未配置签名：构建会跳过签名（SignHap WARN），产物为 entry-default-unsigned.hap。');
    return;
  }
  console.log('✅ build-profile.json5 干净（"signingConfigs": []），签名材料来自本机 signing-config.local.json：');
  console.log(describe(local));
  for (const file of [local.material?.storeFile, local.material?.certpath, local.material?.profile]) {
    if (typeof file === 'string' && !fs.existsSync(file)) {
      console.log(`⚠️ 材料文件不存在：${file}`);
    }
  }
  const envKeys = ['WG_SIGN_STORE_FILE', 'WG_SIGN_STORE_PASSWORD', 'WG_SIGN_KEY_ALIAS', 'WG_SIGN_KEY_PASSWORD', 'WG_SIGN_CERT_PATH', 'WG_SIGN_PROFILE', 'WG_SIGN_SIGN_ALG'].filter(
    (k) => process.env[k],
  );
  if (envKeys.length > 0) {
    console.log(`   注：环境变量覆盖生效中 → ${envKeys.join(', ')}`);
  }
}

const command = process.argv[2] ?? 'import';
switch (command) {
  case 'import':
    cmdImport();
    break;
  case 'status':
    cmdStatus();
    break;
  default:
    console.log('用法：node scripts/sign-config.mjs [import|status]');
    process.exit(2);
}
