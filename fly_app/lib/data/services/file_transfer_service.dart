/// 按编译平台选择附件传输实现。
library;

import 'file_transfer_service_contract.dart';
import 'file_transfer_service_native.dart'
    if (dart.library.html) 'file_transfer_service_web.dart'
    as implementation;

export 'file_transfer_service_contract.dart';

FileTransferService createFileTransferService() =>
    implementation.createFileTransferService();
