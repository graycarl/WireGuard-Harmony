/*
 * 「键 = 值」属性行解析（对应上游 tunnel/config/Attribute.java）。
 *
 * 规则（specs/config-format.md）：
 * - 键不区分大小写（由调用方小写化后比较）；
 * - `=` 两侧空白忽略；
 * - 值不得为空、首个字符不能是空白、`#` 之后为注释；
 * - 列表型值用英文逗号分隔，逗号两侧空白忽略。
 */

const LINE_PATTERN = /^(\w+)\s*=\s*([^\s#][^#]*)$/;
const LIST_SEPARATOR = /\s*,\s*/;

export class Attribute {
  readonly key: string;
  readonly value: string;

  constructor(key: string, value: string) {
    this.key = key;
    this.value = value;
  }

  /** 解析一行属性；不符合「键 = 值」形式时返回 null（调用方报语法错误）。 */
  static parse(line: string): Attribute | null {
    const matched = LINE_PATTERN.exec(line);
    if (matched === null) {
      return null;
    }
    return new Attribute(matched[1], matched[2]);
  }

  /** 按英文逗号拆分列表值。 */
  static split(value: string): string[] {
    return value.split(LIST_SEPARATOR);
  }

  /** 以 `, ` 连接列表值（导出序列化用）。 */
  static join(values: string[]): string {
    return values.join(', ');
  }
}
