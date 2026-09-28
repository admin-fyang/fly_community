/// 全局目标多选页使用的最小展示快照。
///
/// 该模型只描述 UI 展示数据，不依赖联系人、会话或群成员等具体业务模型，
/// 各业务层负责在进入页面前完成数据映射。
class AppMultiSelectItem {
  const AppMultiSelectItem({
    required this.id,
    required this.title,
    this.subtitle = '',
    this.avatarUrl,
    this.disabled = false,
    this.highlightSubtitle = false,
  });

  final String id;
  final String title;
  final String subtitle;
  final String? avatarUrl;
  final bool disabled;
  final bool highlightSubtitle;
}
