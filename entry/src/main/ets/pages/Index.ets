/**
 * 首页（临时占位页）。
 *
 * 后续按设计文档替换为「隧道列表」页，对应上游 WireGuard-Android 的：
 *   ui/src/main/java/com/wireguard/android/activity/MainActivity.java
 *   ui/src/main/java/com/wireguard/android/fragment/TunnelListFragment.java
 */
@Entry
@Component
struct Index {
  @State title: string = 'WireGuard';
  @State subtitle: string = '工程骨架已就绪 · 隧道功能开发中';

  build() {
    Column({ space: 8 }) {
      Text(this.title)
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
      Text(this.subtitle)
        .fontSize(14)
        .fontColor('#99000000')
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }
}
