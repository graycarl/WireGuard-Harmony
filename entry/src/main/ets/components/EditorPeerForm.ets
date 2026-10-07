/*
 * 编辑器中单个 Peer 卡片的可观察表单状态（ArkUI V2：@ObservedV2 + @Trace）。
 *
 * 为什么单独一层：Peer 列表用 ForEach(stable key) 渲染，字段级修改必须由
 * @Trace 直接驱动对应 TextInput 更新，而不能依赖整列表重建（否则输入框失焦）。
 * 纯数据/转换逻辑在 EditorUtils.ets（可本地单测），本类只承载可观察字段。
 */

import { Peer } from '../config/Peer';
import { PeerDraft, emptyPeerDraft, peerToDraft } from './EditorUtils';

@ObservedV2
export class EditorPeerForm {
  @Trace id: string = '';
  @Trace publicKey: string = '';
  @Trace presharedKey: string = '';
  @Trace allowedIPsText: string = '';
  @Trace endpointText: string = '';
  @Trace keepaliveText: string = '';
  @Trace excludeLan: boolean = false;

  static fromDraft(draft: PeerDraft): EditorPeerForm {
    const form = new EditorPeerForm();
    form.id = draft.id;
    form.publicKey = draft.publicKey;
    form.presharedKey = draft.presharedKey;
    form.allowedIPsText = draft.allowedIPsText;
    form.endpointText = draft.endpointText;
    form.keepaliveText = draft.keepaliveText;
    form.excludeLan = draft.excludeLan;
    return form;
  }

  static fromPeer(peer: Peer): EditorPeerForm {
    return EditorPeerForm.fromDraft(peerToDraft(peer));
  }

  static empty(): EditorPeerForm {
    return EditorPeerForm.fromDraft(emptyPeerDraft());
  }

  toDraft(): PeerDraft {
    const draft: PeerDraft = {
      id: this.id,
      publicKey: this.publicKey,
      presharedKey: this.presharedKey,
      allowedIPsText: this.allowedIPsText,
      endpointText: this.endpointText,
      keepaliveText: this.keepaliveText,
      excludeLan: this.excludeLan
    };
    return draft;
  }
}
