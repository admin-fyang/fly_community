/// 用户资料仓储实现。
library;

import '../../core/network/api_client.dart';
import '../../core/network/api_paths.dart';
import '../../domain/entities/avatar_upload.dart';
import '../../domain/entities/user_profile.dart';
import '../../domain/repositories/user_repository.dart';
import '../network/object_storage_client.dart';

class UserRepositoryImpl implements UserRepository {
  const UserRepositoryImpl(this._client, this._storageClient);

  final ApiClient _client;
  final ObjectStorageClient _storageClient;

  @override
  Future<UserProfile> getCurrentUser() {
    return _client.get<UserProfile>(
      ApiPaths.currentUser,
      decoder: (data) => UserProfile.fromJson(_jsonObject(data)),
    );
  }

  @override
  Future<UserProfile> updateCurrentUser({
    required int profileVersion,
    required String firstName,
    required String lastName,
    required String username,
    required String bio,
    required DateTime? birthday,
    required String? regionCode,
    required int birthdayVisibility,
    required int phoneVisibility,
    required int lastSeenVisibility,
  }) {
    return _client.patch<UserProfile>(
      ApiPaths.currentUser,
      data: {
        'profile_version': profileVersion,
        'first_name': firstName,
        'last_name': lastName,
        'username': username,
        'bio': bio,
        'birthday': birthday == null ? null : _date(birthday),
        'region_code': regionCode,
        'birthday_visibility': birthdayVisibility,
        'phone_visibility': phoneVisibility,
        'last_seen_visibility': lastSeenVisibility,
      },
      decoder: (data) => UserProfile.fromJson(_jsonObject(data)),
    );
  }

  @override
  Future<UserProfile> uploadAvatar(
    AvatarUploadFile file, {
    void Function(int sent, int total)? onProgress,
  }) async {
    final credential = await _client.post<AvatarUploadCredential>(
      ApiPaths.avatarUploadCredentials,
      data: {
        'filename': file.filename,
        'size': file.size,
        'mime_type': file.mimeType,
      },
      decoder: (data) => AvatarUploadCredential.fromJson(_jsonObject(data)),
    );

    await _storageClient.put(
      uploadUrl: credential.uploadUrl,
      headers: credential.headers,
      bytes: file.bytes,
      onSendProgress: onProgress,
    );

    final completed = await _client.post<CompletedUpload>(
      ApiPaths.completeUpload(credential.resourceId),
      decoder: (data) => CompletedUpload.fromJson(_jsonObject(data)),
    );
    if (completed.resourceId != credential.resourceId ||
        completed.status != 'ready') {
      throw const FormatException('头像上传完成状态不正确');
    }

    return _client.post<UserProfile>(
      ApiPaths.currentUserAvatar,
      data: {'resource_id': credential.resourceId},
      decoder: (data) => UserProfile.fromJson(_jsonObject(data)),
    );
  }

  static String _date(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year}-$month-$day';
  }

  static Map<String, dynamic> _jsonObject(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, item) => MapEntry(key.toString(), item));
    }
    throw const FormatException('data 必须为 JSON 对象');
  }
}
