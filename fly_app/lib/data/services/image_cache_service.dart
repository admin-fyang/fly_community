/// 社区版收到的图片缓存，使用独立 IndexedDB，按账号和资源 ID 隔离。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:idb_shim/idb_browser.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:synchronized/synchronized.dart';

class ImageCacheRequest {
  const ImageCacheRequest({
    required this.ownerId,
    required this.resourceId,
    required this.url,
    required this.totalBytes,
  });

  final String ownerId;
  final String resourceId;
  final String url;
  final int totalBytes;

  String get key =>
      base64Url.encode(utf8.encode('$ownerId|$resourceId')).replaceAll('=', '');
}

class ImageCacheService {
  ImageCacheService({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(minutes: 2),
            ),
          );

  static const _databaseName = 'flyim_community_image_cache';
  static const _storeName = 'images';
  static const _indexKey = 'flyim.community.image_cache.index.v1';
  static const _maxBytes = 512 * 1024 * 1024;

  final Dio _dio;
  final Lock _lock = Lock();
  final Map<String, Future<bool>> _downloads = {};
  Database? _database;

  Future<Database> _open() async => _database ??= await idbFactoryBrowser.open(
    _databaseName,
    version: 1,
    onUpgradeNeeded: (event) {
      if (!event.database.objectStoreNames.contains(_storeName)) {
        event.database.createObjectStore(_storeName);
      }
    },
  );

  /// 读取成功的缓存不会再请求远程地址，并补齐或更新最近访问时间。
  Future<Uint8List?> cachedBytes(ImageCacheRequest request) async {
    final database = await _open();
    final transaction = database.transaction(_storeName, idbModeReadOnly);
    final raw = await transaction
        .objectStore(_storeName)
        .getObject(request.key);
    await transaction.completed;
    final bytes = switch (raw) {
      Uint8List value => value,
      ByteBuffer value => value.asUint8List(),
      List<int> value => Uint8List.fromList(value),
      _ => null,
    };
    if (bytes == null || bytes.isEmpty) return null;
    try {
      await _lock.synchronized(() async {
        final preferences = await SharedPreferences.getInstance();
        final index = _readIndex(preferences);
        index[request.key] = (
          size: bytes.length,
          accessedAt: DateTime.now().millisecondsSinceEpoch,
        );
        await _writeIndex(preferences, index);
      });
    } catch (_) {
      // 索引写入失败时仍可显示已保存的图片。
    }
    return bytes;
  }

  /// 下载完成后再提交图片字节；同一资源的并发气泡共享一项下载任务。
  Future<bool> cache(ImageCacheRequest request) {
    final existing = _downloads[request.key];
    if (existing != null) return existing;
    final task = _cache(request);
    _downloads[request.key] = task;
    unawaited(
      task.then<void>(
        (_) {
          _downloads.remove(request.key);
        },
        onError: (Object _, StackTrace __) {
          _downloads.remove(request.key);
        },
      ),
    );
    return task;
  }

  Future<bool> _cache(ImageCacheRequest request) async {
    try {
      if (await cachedBytes(request) != null) return true;
      final response = await _dio.get<List<int>>(
        request.url,
        options: Options(responseType: ResponseType.bytes),
      );
      final data = response.data;
      if (data == null || data.isEmpty || data.length > _maxBytes) return false;
      final bytes = Uint8List.fromList(data);
      return await _lock.synchronized(() async {
        final database = await _open();
        final preferences = await SharedPreferences.getInstance();
        final index = _readIndex(preferences);
        var occupied = index.values.fold<int>(
          0,
          (total, item) => total + item.size,
        );
        final oldest = index.entries.toList()
          ..sort(
            (left, right) =>
                left.value.accessedAt.compareTo(right.value.accessedAt),
          );
        final transaction = database.transaction(_storeName, idbModeReadWrite);
        final store = transaction.objectStore(_storeName);
        for (final item in oldest) {
          if (occupied + bytes.length <= _maxBytes) break;
          await store.delete(item.key);
          occupied -= item.value.size;
          index.remove(item.key);
        }
        await store.put(bytes, request.key);
        await transaction.completed;
        index[request.key] = (
          size: bytes.length,
          accessedAt: DateTime.now().millisecondsSinceEpoch,
        );
        await _writeIndex(preferences, index);
        return true;
      });
    } catch (_) {
      return false;
    }
  }

  /// 用户主动清理时同时清空数据库与索引。
  Future<void> clear() => _lock.synchronized(() async {
    final database = await _open();
    final transaction = database.transaction(_storeName, idbModeReadWrite);
    await transaction.objectStore(_storeName).clear();
    await transaction.completed;
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_indexKey);
  });

  Map<String, ({int size, int accessedAt})> _readIndex(
    SharedPreferences preferences,
  ) {
    final raw = preferences.getString(_indexKey);
    if (raw == null) return {};
    try {
      final decoded = jsonDecode(raw) as Map;
      return decoded.map((key, value) {
        final entry = value as Map;
        return MapEntry(key.toString(), (
          size: (entry['size'] as num).toInt(),
          accessedAt: (entry['accessed_at'] as num).toInt(),
        ));
      });
    } catch (_) {
      return {};
    }
  }

  Future<void> _writeIndex(
    SharedPreferences preferences,
    Map<String, ({int size, int accessedAt})> index,
  ) => preferences.setString(
    _indexKey,
    jsonEncode(
      index.map(
        (key, value) => MapEntry(key, {
          'size': value.size,
          'accessed_at': value.accessedAt,
        }),
      ),
    ),
  );
}
