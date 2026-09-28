import '../../data/models/system_config_model.dart';

abstract interface class SystemConfigRepository {
  Future<SystemConfigModel> getPublicConfig();

}
