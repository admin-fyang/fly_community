/// 聊天附件系统选择器。
///
/// 统一封装图片和普通文件的系统选择窗口。这里只返回文件句柄和元数据，
/// 不负责上传或创建消息，避免平台选择逻辑与 IM 业务耦合。
library;

import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';

/// 一个由系统选择器返回的本地附件。
///
/// 文件字节在真正发送该项时才读取，避免多选大文件后一次性占满内存。
class PickedChatAttachment {
  const PickedChatAttachment({
    required XFile file,
    required this.filename,
    required this.size,
    required this.mimeType,
  }) : _file = file;

  final XFile _file;
  final String filename;
  final int size;
  final String mimeType;

  String get localPath => _file.path;

  Future<List<int>> readBytes() => _file.readAsBytes();

}

/// 聊天附件选择契约，便于 Controller 测试时替换系统插件。
abstract interface class ChatAttachmentPickerService {
  Future<List<PickedChatAttachment>> pickImages();

  Future<List<PickedChatAttachment>> pickFiles();
}

/// 使用操作系统选择窗口的正式实现。
class SystemChatAttachmentPickerService implements ChatAttachmentPickerService {
  SystemChatAttachmentPickerService({ImagePicker? imagePicker})
    : _imagePicker = imagePicker ?? ImagePicker();

  final ImagePicker _imagePicker;

  @override
  Future<List<PickedChatAttachment>> pickImages() async {
    // 不传 maxWidth/maxHeight/imageQuality，直接使用系统返回的文件，
    // 不再提供“原图”开关或客户端压缩分支。
    final files = await _imagePicker.pickMultiImage(requestFullMetadata: false);
    return _describe(files);
  }

  @override
  Future<List<PickedChatAttachment>> pickFiles() async {
    final result = await FilePicker.pickFiles(
      // 禁止列表无法由系统选择器表达，因此允许选择任意文件，选择后再按
      // 公开系统配置的 no_allow_upload 给出明确反馈。
      type: FileType.any,
    );
    if (result.isEmpty) return const [];

    // PlatformFile 在各平台统一提供 XFile；Android 的 content URI 不要求
    // 转换为本地路径，读取由平台实现负责。
    final files = <PlatformFile>[];
    for (final file in result) {
      files.add(file);
    }
    return _describePlatformFiles(files);
  }

  /// FilePicker 已从 Android 文档提供器读取到权威文件大小，必须直接保留。
  ///
  /// 部分 Android `content://` URI 转为 XFile 后调用 `length()` 会返回 0，
  /// 但 PlatformFile.lengthSync() 仍是正确值；若在这里丢弃该元数据，发送前的本地
  /// 气泡会错误显示 0 B，直到服务端确认后才恢复。
  Future<List<PickedChatAttachment>> _describePlatformFiles(
    Iterable<PlatformFile> files,
  ) async {
    final result = <PickedChatAttachment>[];
    for (final platformFile in files) {
      final file = platformFile.xFile;
      final filename = platformFile.name.trim();
      if (filename.isEmpty) continue;
      final mimeType = (file.mimeType ?? lookupMimeType(filename) ?? '')
          .toLowerCase();
      result.add(
        PickedChatAttachment(
          file: file,
          filename: filename,
          size: platformFile.lengthSync() ?? await platformFile.length(),
          mimeType: mimeType,
        ),
      );
    }
    return result;
  }

  Future<List<PickedChatAttachment>> _describe(Iterable<XFile> files) async {
    final result = <PickedChatAttachment>[];
    for (final file in files) {
      final filename = file.name.trim();
      if (filename.isEmpty) continue;
      final size = await file.length();
      final mimeType = (file.mimeType ?? lookupMimeType(filename) ?? '')
          .toLowerCase();
      result.add(
        PickedChatAttachment(
          file: file,
          filename: filename,
          size: size,
          mimeType: mimeType,
        ),
      );
    }
    return result;
  }
}
