/// IO 平台 SQLite 适配器。
///
/// 当前仓只支持 Android/iOS 原生运行环境，统一使用 sqflite 插件。
library;

import 'dart:io';

import 'package:sqflite/sqflite.dart' as mobile_sqflite;
import 'package:sqflite_common/sqlite_api.dart' show DatabaseFactory;

import 'im_database_platform_contract.dart';

ImDatabasePlatform createImDatabasePlatform() =>
    const _MobileImDatabasePlatform();

/// Android/iOS 的 sqflite 插件由 Flutter 自动注册，无需额外初始化。
void initializeImDatabasePlatform() {}

class _MobileImDatabasePlatform implements ImDatabasePlatform {
  const _MobileImDatabasePlatform();

  @override
  DatabaseFactory get factory => mobile_sqflite.databaseFactory;

  @override
  Future<String> resolveDatabasePath(String databaseName) async {
    final directory = await mobile_sqflite.getDatabasesPath();
    return '$directory${Platform.pathSeparator}$databaseName';
  }
}
