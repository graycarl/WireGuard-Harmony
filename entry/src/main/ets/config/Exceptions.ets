/*
 * 配置解析异常（对应上游 tunnel/config/ParseException.java 与 BadConfigException.java）。
 *
 * 与上游的差异（见 specs/config-format.md「与上游的差异」）：
 * - 错误文案全部中文本地化：节名/字段名用「本地/远程/整体」「私钥」「局域网 IP 地址」等；
 * - MTU 越界报在 MTU 字段（上游错标为监听端口）；
 * - 应用过滤互斥使用明确表述，不借用「密钥无效」。
 */

/** 无法解析的字符串类别（决定「无法解析……」文案）。 */
export enum ParseClass {
  IP_ADDRESS = 'IP 地址',
  IP_NETWORK = 'IP 网络',
  ENDPOINT = '对端',
  NUMBER = '数字',
}

/** 拼出「无法解析 X」短语（中英混排处保留空格）。 */
function parsePhrase(parseClass: ParseClass): string {
  if (parseClass === ParseClass.IP_ADDRESS) {
    return '无法解析 IP 地址';
  }
  if (parseClass === ParseClass.IP_NETWORK) {
    return '无法解析 IP 网络';
  }
  if (parseClass === ParseClass.ENDPOINT) {
    return '无法解析对端';
  }
  return '无法解析数字';
}

/** 解析失败时抛出的原始异常（由上层包装为 BadConfigException）。 */
export class ParseException extends Error {
  readonly parseClass: ParseClass;
  readonly text: string;
  readonly line: string;
  readonly column: number;

  constructor(parseClass: ParseClass, text: string, line: string = '', column: number = -1) {
    super(`${parsePhrase(parseClass)} '${text}'`);
    this.name = 'ParseException';
    this.parseClass = parseClass;
    this.text = text;
    this.line = line;
    this.column = column;
  }

  /** 用于错误说明的中文短语，如「无法解析 IP 地址 'x'」。 */
  get reasonText(): string {
    return `${parsePhrase(this.parseClass)} '${this.text}'`;
  }
}

/** 配置所在节（对应上游 Section）。 */
export enum Section {
  CONFIG = 'CONFIG',
  INTERFACE = 'INTERFACE',
  PEER = 'PEER',
}

/** 出错字段（对应上游 Location；TOP_LEVEL 表示节级错误）。 */
export enum Location {
  TOP_LEVEL = 'TOP_LEVEL',
  ADDRESS = 'ADDRESS',
  ALLOWED_IPS = 'ALLOWED_IPS',
  DNS = 'DNS',
  ENDPOINT = 'ENDPOINT',
  EXCLUDED_APPLICATIONS = 'EXCLUDED_APPLICATIONS',
  INCLUDED_APPLICATIONS = 'INCLUDED_APPLICATIONS',
  LISTEN_PORT = 'LISTEN_PORT',
  MTU = 'MTU',
  PERSISTENT_KEEPALIVE = 'PERSISTENT_KEEPALIVE',
  PRE_SHARED_KEY = 'PRE_SHARED_KEY',
  PRIVATE_KEY = 'PRIVATE_KEY',
  PUBLIC_KEY = 'PUBLIC_KEY',
}

/** 出错原因（对应上游 Reason；APPLICATION_FILTER_CONFLICT 为本项目新增）。 */
export enum Reason {
  INVALID_KEY = 'INVALID_KEY',
  INVALID_NUMBER = 'INVALID_NUMBER',
  INVALID_VALUE = 'INVALID_VALUE',
  MISSING_ATTRIBUTE = 'MISSING_ATTRIBUTE',
  MISSING_SECTION = 'MISSING_SECTION',
  SYNTAX_ERROR = 'SYNTAX_ERROR',
  UNKNOWN_ATTRIBUTE = 'UNKNOWN_ATTRIBUTE',
  UNKNOWN_SECTION = 'UNKNOWN_SECTION',
  APPLICATION_FILTER_CONFLICT = 'APPLICATION_FILTER_CONFLICT',
}

/** 密钥格式错误类型（对应上游 KeyFormatException.Type）。 */
export enum KeyFormatType {
  LENGTH = 'LENGTH',
  CONTENTS = 'CONTENTS',
}

function sectionName(section: Section): string {
  if (section === Section.INTERFACE) {
    return '本地';
  }
  if (section === Section.PEER) {
    return '远程';
  }
  return '整体';
}

function locationName(location: Location): string {
  if (location === Location.ADDRESS) {
    return '局域网 IP 地址';
  }
  if (location === Location.ALLOWED_IPS) {
    return '路由的 IP 地址';
  }
  if (location === Location.DNS) {
    return 'DNS 服务器';
  }
  if (location === Location.ENDPOINT) {
    return '对端';
  }
  if (location === Location.EXCLUDED_APPLICATIONS || location === Location.INCLUDED_APPLICATIONS) {
    return '应用过滤';
  }
  if (location === Location.LISTEN_PORT) {
    return '监听端口';
  }
  if (location === Location.MTU) {
    return 'MTU';
  }
  if (location === Location.PERSISTENT_KEEPALIVE) {
    return '连接保活间隔';
  }
  if (location === Location.PRE_SHARED_KEY) {
    return '预共享密钥';
  }
  if (location === Location.PRIVATE_KEY) {
    return '私钥';
  }
  if (location === Location.PUBLIC_KEY) {
    return '公钥';
  }
  return '';
}

function reasonName(reason: Reason, keyFormat: KeyFormatType | null): string {
  if (reason === Reason.INVALID_KEY) {
    return keyFormat === KeyFormatType.CONTENTS ? '密钥中含错误字符' : '密钥长度错误';
  }
  if (reason === Reason.INVALID_NUMBER) {
    return '数字无效';
  }
  if (reason === Reason.INVALID_VALUE) {
    return '数值无效';
  }
  if (reason === Reason.MISSING_ATTRIBUTE) {
    return '缺失属性';
  }
  if (reason === Reason.MISSING_SECTION) {
    return '缺失节';
  }
  if (reason === Reason.SYNTAX_ERROR) {
    return '语法错误';
  }
  if (reason === Reason.UNKNOWN_ATTRIBUTE) {
    return '未知属性';
  }
  if (reason === Reason.UNKNOWN_SECTION) {
    return '未知节';
  }
  return '应用过滤的两种模式不能同时设置';
}

/** 按出错字段追加的说明文案（specs/config-format.md 错误描述方式表）。 */
function reasonExplanation(reason: Reason, location: Location, keyFormat: KeyFormatType | null): string {
  if (reason === Reason.INVALID_KEY && keyFormat === KeyFormatType.LENGTH) {
    return '：WireGuard 的 Base64 密钥长度必须为 44 个字符（32 字节）';
  }
  if (reason === Reason.INVALID_VALUE) {
    if (location === Location.LISTEN_PORT) {
      return '：必须为有效的 UDP 端口号';
    }
    if (location === Location.PERSISTENT_KEEPALIVE) {
      return '：必须为 0–65535 的整数';
    }
    if (location === Location.MTU) {
      return '：必须为非负整数';
    }
  }
  return '';
}

/**
 * 配置内容非法。message 即为完整的中文用户可见文案，例如：
 * 「在 本地 的 私钥 字段发生了 密钥长度错误 的问题：WireGuard 的 Base64 密钥长度必须为 44 个字符（32 字节）」
 */
export class BadConfigException extends Error {
  readonly sectionKey: Section;
  /** 出错字段（英文枚举；TOP_LEVEL 表示节级错误）。 */
  readonly fieldKey: Location;
  readonly reasonKey: Reason;
  readonly keyFormatType: KeyFormatType | null;
  readonly parseClass: ParseClass | null;
  readonly text: string;

  constructor(section: Section, field: Location, reason: Reason, text: string = '',
              keyFormatType: KeyFormatType | null = null, parseClass: ParseClass | null = null) {
    super(BadConfigException.buildMessage(section, field, reason, text, keyFormatType, parseClass));
    this.name = 'BadConfigException';
    this.sectionKey = section;
    this.fieldKey = field;
    this.reasonKey = reason;
    this.text = text;
    this.keyFormatType = keyFormatType;
    this.parseClass = parseClass;
  }

  static buildMessage(section: Section, field: Location, reason: Reason, text: string,
                      keyFormatType: KeyFormatType | null, parseClass: ParseClass | null): string {
    const sectionText = sectionName(section);
    let reasonText: string;
    let explanation = '';
    if (reason === Reason.INVALID_VALUE && parseClass !== null) {
      // 「无法解析 IP 地址 'x'」等：原因短语已包含出错文本，不再重复附加说明。
      reasonText = `${parsePhrase(parseClass)} '${text}'`;
    } else {
      reasonText = reasonName(reason, keyFormatType);
      explanation = reasonExplanation(reason, field, keyFormatType);
    }
    const head = field === Location.TOP_LEVEL
      ? `在 ${sectionText} 发生了 ${reasonText} 的问题`
      : `在 ${sectionText} 的 ${locationName(field)} 字段发生了 ${reasonText} 的问题`;
    return head + explanation;
  }

  /** 节级错误（语法/未知属性/未知节/缺失节）。 */
  static sectionError(section: Section, reason: Reason, text: string = ''): BadConfigException {
    return new BadConfigException(section, Location.TOP_LEVEL, reason, text);
  }

  /** 无法解析某字段的值。 */
  static parseError(section: Section, field: Location, parseClass: ParseClass, text: string): BadConfigException {
    return new BadConfigException(section, field, Reason.INVALID_VALUE, text, null, parseClass);
  }

  /** 密钥格式错误。 */
  static keyError(section: Section, field: Location, type: KeyFormatType): BadConfigException {
    return new BadConfigException(section, field, Reason.INVALID_KEY, '', type);
  }

  /** 数值语义非法/越界。 */
  static valueError(section: Section, field: Location, text: string): BadConfigException {
    return new BadConfigException(section, field, Reason.INVALID_VALUE, text);
  }

  /** 出错节的中文名（本地/远程/整体）。 */
  get location(): string {
    return sectionName(this.sectionKey);
  }

  /** 出错字段的中文名；节级错误返回 undefined。 */
  get field(): string | undefined {
    const name = locationName(this.fieldKey);
    return name === '' ? undefined : name;
  }

  /** 中文原因，如「密钥长度错误」「无法解析 IP 地址 'x'」。 */
  get reason(): string {
    if (this.reasonKey === Reason.INVALID_VALUE && this.parseClass !== null) {
      return `${parsePhrase(this.parseClass)} '${this.text}'`;
    }
    return reasonName(this.reasonKey, this.keyFormatType);
  }
}
