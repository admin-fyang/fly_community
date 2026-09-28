/// 下载、保存和打开消息附件的跨平台契约。
library;

typedef TransferProgress = void Function(int received, int total);

enum FileTransferPhase { idle, downloading, ready, failed }

class FileTransferViewState {
  const FileTransferViewState({
    this.phase = FileTransferPhase.idle,
    this.progress = 0,
    this.localPath,
  });
  final FileTransferPhase phase;
  final double progress;
  final String? localPath;
}

abstract interface class FileTransferService {
  Future<String?> download({
    required String url,
    required String resourceId,
    required String filename,
    TransferProgress? onProgress,
  });

  Future<void> open(String localPath);

  Future<void> saveMedia({
    required String url,
    required String filename,
    required bool isVideo,
    TransferProgress? onProgress,
  });
}
