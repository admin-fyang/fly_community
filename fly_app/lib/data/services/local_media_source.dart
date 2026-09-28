/// 按编译平台把待发送媒体转换为播放器可读取的地址。
library;

import 'local_media_source_contract.dart';
import 'local_media_source_native.dart'
    if (dart.library.html) 'local_media_source_web.dart'
    as implementation;

export 'local_media_source_contract.dart';

LocalMediaSource createLocalMediaSource() =>
    implementation.createLocalMediaSource();
