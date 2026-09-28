/// 按编译平台选择 IM 数据库实现。
library;

import 'im_database_platform_contract.dart';
import 'im_database_platform_native.dart'
    if (dart.library.html) 'im_database_platform_web.dart'
    as implementation;

export 'im_database_platform_contract.dart';

ImDatabasePlatform createImDatabasePlatform() =>
    implementation.createImDatabasePlatform();

/// 在依赖注入前完成当前平台的 SQLite 全局初始化。
///
/// Web 插件除可显式取得 [ImDatabasePlatform.factory] 外，还要求注册全局
/// databaseFactory，避免插件内部或其他共享代码调用全局 API 时工厂为空。
void initializeImDatabasePlatform() =>
    implementation.initializeImDatabasePlatform();
