/// 通用分页结果。
///
/// 后端列表接口返回 items + next_cursor / next_before_notification_id。
/// 页面需要游标决定是否继续加载，Repository 不能只丢出 items。
class PagedResult<T> {
  const PagedResult({
    required this.items,
    this.nextCursor,
    this.snapshotRevision,
  });

  final List<T> items;
  final String? nextCursor;
  final String? snapshotRevision;

  bool get hasMore => nextCursor != null && nextCursor!.isNotEmpty;
}
