/// 联系人页。
///
/// 快捷入口 + 按字母分组的联系人列表 + 右侧字母索引条。
library;

import 'package:flychat/shared/widgets/navigation/app_page_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../main_navigation/main_navigation_insets.dart';

import '../../core/constants/app_constants.dart';
import '../../core/extensions/context_extension.dart';
import '../../core/theme/app_sizes.dart';
import '../../data/enums/top_bar_mode.dart';
import '../../data/models/contact_model.dart';
import '../../routes/app_routes.dart';
import '../../shared/widgets/empty/app_empty_state.dart';
import '../../shared/widgets/search/app_search_app_bar.dart';
import '../../shared/widgets/skeleton/app_skeleton.dart';
import 'contacts_controller.dart';
import 'widgets/contact_group_header.dart';
import 'widgets/contact_index_bar.dart';
import 'widgets/contact_item.dart';

/// 联系人页
///
/// 普通态：快捷入口 + A–Z 吸顶分组 + 右侧索引条；搜索态：扁平过滤列表。
class ContactsPage extends StatefulWidget {
  const ContactsPage({super.key, this.embeddedInMainShell = false});

  final bool embeddedInMainShell;

  @override
  State<ContactsPage> createState() => _ContactsPageState();
}

class _ContactsPageState extends State<ContactsPage> {
  final ContactsController controller = Get.find<ContactsController>();
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// 索引条点击：按固定行高累加偏移，跳到对应分组
  void _jumpTo(String letter) {
    if (!controller.hasGroup(letter)) return;
    final groups = controller.groups;

    // 计算滚动的目标位置偏移量，快速入口的高度作为初始偏移值
    double offset = 0;
    for (final g in groups) {
      if (g.letter == letter) break;
      offset +=
          ContactGroupHeaderDelegate.height +
          g.items.length * ContactItem.height;
    }
    // 更新当前处于高亮/激活状态的字母索引值
    controller.setActiveLetter(letter);
    if (!_scroll.hasClients) return;
    _scroll.animateTo(
      offset.clamp(0, _scroll.position.maxScrollExtent),
      duration: AppConstants.animNormal,
      curve: Curves.easeOut,
    );
  }

  /// 进入用户详情(好友 / 陌生人由详情数据决定布局)
  void _openDetail(ContactModel contact) {
    Get.toNamed(AppRoutes.contactDetail, arguments: contact);
  }

  /// 滚动到列表顶部，并清除激活状态的索引字母
  void _jumpToTop() {
    controller.setActiveLetter('');
    if (_scroll.hasClients) {
      _scroll.animateTo(
        0,
        duration: AppConstants.animNormal,
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      extendBodyBehindAppBar: true,
      readActivity: controller.pageReads,
      // 头部搜索栏，根据是否处于搜索状态切换 appBar 展示样式
      appBar: AppSearchAppBar(
        title: '联系人',

        showLeading: !widget.embeddedInMainShell,

        mode: controller.topBarMode,
        onBack: Get.back,
        onOpenSearch: controller.openSearch,
        onCloseSearch: controller.closeSearch,
        onChanged: controller.updateKeyword,
      ),
      // 悬浮操作按钮，用于点击进入全局搜索/查找用户添加好友
      floatingActionButton: Obx(
        () => controller.canAddFriend
            ? Padding(
                padding: EdgeInsets.only(
                  bottom:
                      (MainNavigationInsets.bottomOf(context) -
                              MediaQuery.paddingOf(context).bottom)
                          .clamp(0.0, double.infinity),
                ),
                child: FloatingActionButton(
                  backgroundColor: context.tokens.brand,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  highlightElevation: 0,
                  shape: const CircleBorder(),
                  // 进入全局搜索:查找用户 / 陌生人 / 群并添加
                  onPressed: () => Get.toNamed(AppRoutes.contactSearch),
                  child: const Icon(Icons.person_search_outlined, size: 22),
                ),
              )
            : const SizedBox.shrink(),
      ),
      // 使用 Obx 响应式更新 body 内容 (搜索态 vs 普通分组态)
      body: Obx(() {
        final isSearch = controller.topBarMode.value == TopBarMode.search;
        return isSearch ? _searchList(context) : _groupedBody(context);
      }),
    );
  }

  /// 构建非搜索状态下的联系人分组主体内容列表
  Widget _groupedBody(BuildContext context) {
    final groups = controller.groups;
    final isLoading = controller.isLoading.value;
    // 只有在数据加载中且当前列表为空时，才显示首次加载骨架屏
    final showInitialSkeleton = isLoading && groups.isEmpty;

    return Stack(
      children: [
        CustomScrollView(
          controller: _scroll,
          slivers: [
            SliverToBoxAdapter(
              child: SizedBox(height: appTopBarInset(context)),
            ),
            ...[
              // 骨架屏或普通列表顶部，都需要展示快捷入口(如新朋友、群聊等)
              if (showInitialSkeleton)
                ..._contactSkeletonSlivers(context)
              else if (groups.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Padding(
                    padding: EdgeInsets.only(
                      bottom: MainNavigationInsets.bottomOf(context),
                    ),
                    child: _emptyContacts(context),
                  ),
                )
              else
                // 逐个渲染以首字母分组的吸顶头部和联系人列表
                for (final g in groups) ...[
                  SliverPersistentHeader(
                    pinned: false,
                    delegate: ContactGroupHeaderDelegate(
                      g.letter,
                      backgroundColor: context.semanticColors.backgroundGrouped,
                      textColor: context.semanticColors.textSecondary,
                    ),
                  ),
                  SliverList.builder(
                    itemCount: g.items.length,
                    itemBuilder: (_, i) => ContactItem(
                      contact: g.items[i],
                      onTap: () => _openDetail(g.items[i]),
                    ),
                  ),
                ],
              if (showInitialSkeleton || groups.isNotEmpty)
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: MainNavigationInsets.bottomOf(context),
                  ),
                ),
            ],
          ],
        ),
        // 右侧索引条：只有在非骨架屏且列表有数据时才进行渲染
        if (!showInitialSkeleton && groups.isNotEmpty)
          Positioned(
            top: appTopBarInset(context),
            bottom: MainNavigationInsets.bottomOf(context),
            right: 0,
            child: Obx(
              () => ContactIndexBar(
                activeLetter: controller.activeLetter.value,
                onSelect: _jumpTo,
                onTapStar: _jumpToTop,
              ),
            ),
          ),
      ],
    );
  }

  /// 构建骨架屏的 Sliver 列表，包含若干组伪头部和伪条目
  List<Widget> _contactSkeletonSlivers(BuildContext context) {
    return [SliverToBoxAdapter(child: const _ContactSkeletonList())];
  }

  /// 构建联系人列表为空时的空状态提示页面
  Widget _emptyContacts(BuildContext context) {
    return const AppEmptyState(
      message: '暂无联系人',
      description: '可以通过搜索添加联系人，或先加入群组。',
      padding: EdgeInsets.fromLTRB(32, 40, 32, 88),
    );
  }

  /// 构建搜索结果过滤列表（不带快捷入口和首字母分组）
  Widget _searchList(BuildContext context) {
    final list = controller.filtered;
    if (list.isEmpty) {
      return Padding(
        padding: EdgeInsets.only(
          bottom: MainNavigationInsets.bottomOf(context),
        ),
        child: const Center(child: AppEmptyState(message: '未找到联系人')),
      );
    }
    return ListView.builder(
      padding: (EdgeInsets.only(
        bottom: MainNavigationInsets.bottomOf(context),
      )).add(EdgeInsets.only(top: appTopBarInset(context))),
      itemCount: list.length,
      itemBuilder: (_, i) =>
          ContactItem(contact: list[i], onTap: () => _openDetail(list[i])),
    );
  }
}

class _ContactSkeletonList extends StatelessWidget {
  const _ContactSkeletonList();

  @override
  Widget build(BuildContext context) {
    return AppSkeletonScope(
      child: Column(
        children: [
          for (var groupIndex = 0; groupIndex < 2; groupIndex++) ...[
            const _ContactSkeletonHeader(),
            for (var itemIndex = 0; itemIndex < 4; itemIndex++)
              const _ContactSkeletonItem(),
          ],
        ],
      ),
    );
  }
}

class _ContactSkeletonHeader extends StatelessWidget {
  const _ContactSkeletonHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: ContactGroupHeaderDelegate.height,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: AppSizes.paddingLg),
      child: const AppSkeletonBlock(width: 36, height: 10),
    );
  }
}

class _ContactSkeletonItem extends StatelessWidget {
  const _ContactSkeletonItem();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: ContactItem.height,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSizes.paddingLg),
        child: Row(
          children: [
            const AppSkeletonBlock.circle(size: 44),
            const SizedBox(width: AppSizes.paddingItem),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const AppSkeletonBlock(width: 120, height: 13),
                  const SizedBox(height: 8),
                  const AppSkeletonBlock(width: 188, height: 10),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
