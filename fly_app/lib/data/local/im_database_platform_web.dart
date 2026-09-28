/// 浏览器使用 SQLite WASM，持久化文件由插件映射到 IndexedDB。
library;

import 'package:sqflite_common/sqlite_api.dart' show DatabaseFactory;
import 'package:sqflite_common/sqflite.dart' as sqflite_common;
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

import 'im_database_platform_contract.dart';

ImDatabasePlatform createImDatabasePlatform() => const _WebImDatabasePlatform();

bool _globalFactoryInitialized = false;

/// Web 不会像原生 sqflite 插件一样自动注册全局数据库工厂。
///
/// 必须在任何数据库访问前显式设置，否则调用全局 SQLite API 时会抛出
/// `databaseFactory not initialized`。实际 IM 数据库仍通过平台适配器打开。
void initializeImDatabasePlatform() {
  if (_globalFactoryInitialized) return;
  sqflite_common.databaseFactory = databaseFactoryFfiWeb;
  _globalFactoryInitialized = true;
}

class _WebImDatabasePlatform implements ImDatabasePlatform {
  const _WebImDatabasePlatform();

  @override
  DatabaseFactory get factory => databaseFactoryFfiWeb;

  @override
  Future<String> resolveDatabasePath(String databaseName) async => databaseName;
}
