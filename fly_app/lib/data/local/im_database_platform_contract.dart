/// IM 数据库平台适配契约。
///
/// 业务数据库只依赖 sqflite_common 的通用接口，具体平台负责提供数据库工厂
/// 与数据库路径，避免在浏览器中误用移动端 sqflite 全局工厂。
library;

import 'package:sqflite_common/sqlite_api.dart';

abstract interface class ImDatabasePlatform {
  DatabaseFactory get factory;

  Future<String> resolveDatabasePath(String databaseName);
}
