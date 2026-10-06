/*
 * 导入流程的纯逻辑（specs/tunnel-import.md）。
 *
 * 本文件禁止 import 任何 @kit：文件类型判定、名称派生/清理、名称校验、
 * 批量结果汇总文案都在这里，便于本地单测；平台相关（选择器/解包/扫码/弹窗）
 * 在 ImportService 中。
 */

import { isValidTunnelName } from '../config/Names';

/** 导入文件类型（判定顺序见 specs/tunnel-import.md §文件类型判定顺序）。 */
export enum ImportFileKind {
  IMAGE = 'image',
  CONF = 'conf',
  ZIP = 'zip',
  UNKNOWN = 'unknown'
}

const IMAGE_EXTENSIONS: string[] = ['png', 'jpg', 'jpeg', 'webp', 'bmp', 'gif', 'heic', 'heif', 'tif', 'tiff'];

/** 取文件名的扩展名（小写，不含点）；无扩展名返回空串。 */
export function fileExtension(fileName: string): string {
  const base = baseName(fileName);
  const dot = base.lastIndexOf('.');
  if (dot <= 0 || dot === base.length - 1) {
    return '';
  }
  return base.substring(dot + 1).toLowerCase();
}

/** 取路径（或 uri）最后一段；自动去掉查询串并做 URL 解码。 */
export function baseName(pathOrUri: string): string {
  let text = pathOrUri;
  const query = text.indexOf('?');
  if (query >= 0) {
    text = text.substring(0, query);
  }
  const slash = text.lastIndexOf('/');
  if (slash >= 0) {
    text = text.substring(slash + 1);
  }
  try {
    return decodeURIComponent(text);
  } catch (e) {
    return text;
  }
}

/** 是否图片扩展名。 */
export function isImageFileName(fileName: string): boolean {
  return IMAGE_EXTENSIONS.includes(fileExtension(fileName));
}

/** 按扩展名判定导入类型（图片优先于 .conf/.zip，specs/tunnel-import.md）。 */
export function classifyFileName(fileName: string): ImportFileKind {
  if (isImageFileName(fileName)) {
    return ImportFileKind.IMAGE;
  }
  const ext = fileExtension(fileName);
  if (ext === 'conf') {
    return ImportFileKind.CONF;
  }
  if (ext === 'zip') {
    return ImportFileKind.ZIP;
  }
  return ImportFileKind.UNKNOWN;
}

/** 去掉导入文件名中的 .conf/.zip 扩展名，得到隧道名称候选。 */
export function deriveTunnelName(fileName: string): string {
  const base = baseName(fileName);
  const dot = base.lastIndexOf('.');
  if (dot <= 0) {
    return base;
  }
  const ext = base.substring(dot + 1).toLowerCase();
  if (ext === 'conf' || ext === 'zip') {
    return base.substring(0, dot);
  }
  return base;
}

/**
 * 把任意文件名净化成合法的隧道名候选（命名对话框预填用）：
 * 仅保留 ASCII 字母/数字及 `_ = + . -`，截断到 15 字符（specs/tunnel-import.md
 * 「预填清理后的名称」）。
 */
export function sanitizeTunnelName(raw: string): string {
  let out = '';
  for (let i = 0; i < raw.length && out.length < 15; i++) {
    const ch = raw.charAt(i);
    if ((ch >= 'A' && ch <= 'Z') || (ch >= 'a' && ch <= 'z') || (ch >= '0' && ch <= '9') ||
      ch === '_' || ch === '=' || ch === '+' || ch === '.' || ch === '-') {
      out += ch;
    }
  }
  return out;
}

/** 名称校验：合法返回 null，否则返回对话框行内错误文案（不含「无法导入隧道：」前缀）。 */
export function nameValidationError(name: string, existingNames: string[]): string | null {
  if (!isValidTunnelName(name)) {
    return '名称无效';
  }
  if (existingNames.includes(name)) {
    return `名称 '${name}' 已存在`;
  }
  return null;
}

/** 解析失败 → 「无法导入隧道：<解析错误>」。 */
export function importParseFailure(reason: string): string {
  return `无法导入隧道：${reason}`;
}

/**
 * 批量导入汇总提示（specs/tunnel-import.md §方式二 + 有意修正上游
 * 「只要存在成功项就不再显示失败原因」）：
 * - 无 .conf：「无法导入隧道：未找到配置」；
 * - 全部成功且仅 1 条：「导入了 '<名称>'」；
 * - 全部成功多条：「导入了 N 个隧道」；
 * - 部分成功：「导入了 M 项中的 N 项，<最后一条失败原因>」；
 * - 全部失败：「无法导入隧道：<最后一条原因>」。
 */
export function summarizeBatch(succeededNames: string[], failureReasons: string[]): string {
  const total = succeededNames.length + failureReasons.length;
  if (total === 0) {
    return '无法导入隧道：未找到配置';
  }
  if (failureReasons.length === 0) {
    if (succeededNames.length === 1) {
      return `导入了 '${succeededNames[0]}'`;
    }
    return `导入了 ${succeededNames.length} 个隧道`;
  }
  const reason = failureReasons[failureReasons.length - 1];
  if (succeededNames.length === 0) {
    return reason;
  }
  return `导入了 ${total} 项中的 ${succeededNames.length} 项，${reason}`;
}

/** 单条导入成功的提示（单文件/扫码，specs/tunnel-import.md）。 */
export function singleImportSuccess(name: string): string {
  return `导入了 '${name}'`;
}
