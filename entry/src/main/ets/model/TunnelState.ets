/**
 * 隧道连接状态（UI 视角，见 docs/dev-contracts.md §5）。
 *
 * TOGGLE 瞬态不在模型内表达：开关在连接结果确定前由 AppStore.toggling() 禁用（契约 §6）。
 * 序列化为小写串，与 IPC 公共事件 payload（契约 §9）的 state 字段一致。
 */
export enum TunnelState {
  DOWN = 'down',
  UP = 'up'
}
