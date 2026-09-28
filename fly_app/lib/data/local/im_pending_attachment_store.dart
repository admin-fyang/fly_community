/// 按编译平台选择待上传附件暂存实现。
library;

import 'im_pending_attachment_store_contract.dart';
import 'im_pending_attachment_store_native.dart'
    if (dart.library.html) 'im_pending_attachment_store_web.dart'
    as implementation;

export 'im_pending_attachment_store_contract.dart';

ImPendingAttachmentStore createImPendingAttachmentStore() =>
    implementation.createImPendingAttachmentStore();
