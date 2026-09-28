import '../../core/network/api_client.dart';
import '../../core/network/api_paths.dart';
import '../../domain/repositories/system_config_repository.dart';
import '../models/system_config_model.dart';

class SystemConfigRepositoryImpl implements SystemConfigRepository {
  const SystemConfigRepositoryImpl(this._client);

  final ApiClient _client;

  @override
  Future<SystemConfigModel> getPublicConfig() {
    return _client.get<SystemConfigModel>(
      ApiPaths.systemConfig,
      requiresAuth: false,
      decoder: (data) => SystemConfigModel.fromJson(_object(data)),
    );
  }


}

Map<String, dynamic> _object(Object? value) =>
    value is Map
        ? value.map((key, item) => MapEntry(key.toString(), item))
        : const {};
