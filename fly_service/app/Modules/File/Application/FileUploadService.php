<?php

declare(strict_types=1);

namespace app\Modules\File\Application;

use app\exception\BusinessException;
use app\model\AppFileModel;
use app\model\AppFileMultipartUploadModel;
use app\Modules\System\Application\SystemConfigService;
use app\Support\Id\IdGenerator;
use app\Support\Transaction\TransactionManager;
use app\Support\Upload\UploadPolicy;
use app\utils\RustfsUtils;
use Throwable;

/**
 * RustFS 前端直传凭证签发与完成确认服务。
 */
final class FileUploadService
{
    private const MULTIPART_THRESHOLD = 20 * 1024 * 1024;
    private const MULTIPART_PART_SIZE = 8 * 1024 * 1024;
    private const MULTIPART_SESSION_TTL = 86400;
    private const PART_CREDENTIAL_TTL = 900;

    /**
     * 注入资源ID和 RustFS 能力。
     */
    public function __construct(
        private readonly IdGenerator         $ids,
        private readonly RustfsUtils         $storage,
        private readonly string              $bucket,
        private readonly SystemConfigService $systemConfig,
        private readonly TransactionManager  $transactions,
    )
    {
    }

    /**
     * 创建待上传资源并签发短期 PUT URL。
     *
     * @param array{filename:string,size:int,mime_type:string} $input
     * @return array<string,mixed>
     */
    public function createAvatarCredential(int $userId, array $input): array
    {
        $extension = match ($input['mime_type']) {
            'image/jpeg' => 'jpg',
            'image/png' => 'png',
            'image/webp' => 'webp',
        };

        return $this->createCredential($userId, $input, 'avatar', 'avatars', $extension);
    }

    /** 创建问题反馈截图上传凭证。 */
    public function createMessageCredential(int $userId, array $input): array
    {
        $configuration = $this->systemConfig->uploadPolicy();
        if (!$configuration['enabled']) {
            throw new BusinessException('FILE_UPLOAD_DISABLED', '聊天附件上传功能已关闭', 403);
        }
        $policy = new UploadPolicy(
            $configuration['upload_max'],
            $configuration['extensions'],
            $configuration['mime_types'],
        );

        $extension = $policy->assertAllowed($input);
        if ($input['size'] > self::MULTIPART_THRESHOLD) {
            return $this->createMultipartCredential($userId, $input, $extension);
        }

        return ['upload_mode' => 'single'] + $this->createCredential(
                $userId,
                $input,
                'message',
                'messages',
                $extension,
            );
    }

    /**
     * 创建聊天附件Multipart会话，客户端后续仍直接上传S3。
     *
     * @param array{filename:string,size:int,mime_type:string} $input
     * @return array<string,mixed>
     */
    private function createMultipartCredential(int $userId, array $input, string $extension): array
    {
        $resourceId = $this->ids->uuidV4();
        $objectKey = "messages/{$userId}/" . date('Y/m') . "/{$resourceId}.{$extension}";
        $uploadId = $this->storage->createMultipartUpload($objectKey, $input['mime_type']);
        $now = time();
        $expiresAt = $now + self::MULTIPART_SESSION_TTL;
        $totalParts = (int)ceil($input['size'] / self::MULTIPART_PART_SIZE);
        if ($totalParts > 10000) {
            $this->storage->abortMultipartUpload($objectKey, $uploadId);
            throw new BusinessException('FILE_MULTIPART_TOO_MANY_PARTS', '文件分片数量不能超过10000', 422);
        }

        try {
            $this->transactions->run(function () use (
                $resourceId,
                $userId,
                $input,
                $extension,
                $objectKey,
                $uploadId,
                $totalParts,
                $now,
                $expiresAt,
            ): void {
                /** @var AppFileModel $file */
                $file = AppFileModel::query()->create($this->pendingFileRow(
                    $resourceId,
                    $userId,
                    $input,
                    'message',
                    $extension,
                    $objectKey,
                    $expiresAt,
                    $now,
                ));
                AppFileMultipartUploadModel::query()->create([
                    'file_id' => (int)$file->file_id,
                    'upload_id' => $uploadId,
                    'part_size' => self::MULTIPART_PART_SIZE,
                    'total_parts' => $totalParts,
                    'status' => 10,
                    'expires_at' => $expiresAt,
                    'completed_at' => null,
                    'aborted_at' => null,
                    'create_time' => $now,
                    'update_time' => $now,
                ]);
            });
        } catch (Throwable $exception) {
            try {
                $this->storage->abortMultipartUpload($objectKey, $uploadId);
            } catch (Throwable) {
            }
            throw $exception;
        }

        return [
            'resource_id' => $resourceId,
            'upload_mode' => 'multipart',
            'upload_id' => $uploadId,
            'part_size' => self::MULTIPART_PART_SIZE,
            'total_parts' => $totalParts,
            'expires_at' => $expiresAt,
        ];
    }

    /**
     * 创建指定用途的待上传文件资源。
     *
     * @param array{filename:string,size:int,mime_type:string} $input
     * @return array<string,mixed>
     */
    private function createCredential(
        int    $userId,
        array  $input,
        string $purpose,
        string $directory,
        string $extension,
    ): array
    {
        $resourceId = $this->ids->uuidV4();
        $objectKey = "{$directory}/{$userId}/" . date('Y/m') . "/{$resourceId}.{$extension}";
        $expiresIn = 900;
        $credential = $this->storage->createPutCredential($objectKey, $input['mime_type'], $expiresIn);
        $now = time();

        AppFileModel::query()->create($this->pendingFileRow(
            $resourceId,
            $userId,
            $input,
            $purpose,
            $extension,
            $objectKey,
            $now + $expiresIn,
            $now,
        ));

        return ['resource_id' => $resourceId] + $credential;
    }

    /**
     * 构造待上传文件资源行，单次PUT和Multipart共享同一资源事实。
     *
     * @param array{filename:string,size:int,mime_type:string} $input
     * @return array<string,mixed>
     */
    private function pendingFileRow(
        string $resourceId,
        int    $userId,
        array  $input,
        string $purpose,
        string $extension,
        string $objectKey,
        int    $expiresAt,
        int    $now,
    ): array
    {
        return [
            'resource_id' => $resourceId,
            'cate' => 1,
            'file_type' => $input['mime_type'],
            'parent_id' => 0,
            'name' => $input['filename'],
            'src' => null,
            'size' => $input['size'],
            'ext' => $extension,
            'md5' => null,
            'user_id' => $userId,
            'purpose' => $purpose,
            'storage_disk' => 'rustfs',
            'bucket' => $this->bucket,
            'object_key' => $objectKey,
            'mime_type' => $input['mime_type'],
            'etag' => null,
            'upload_expires_at' => $expiresAt,
            'create_time' => $now,
            'update_time' => $now,
            'delete_time' => 0,
            'status' => 10,
            'is_lock' => 0,
        ];
    }

    /**
     * 核验对象并将待上传资源标记为已完成。
     *
     * @return array<string,mixed>
     */
    public function complete(int $userId, string $resourceId): array
    {
        $resource = AppFileModel::query()
            ->where('resource_id', $resourceId)
            ->where('user_id', $userId)
            ->first();
        if ($resource === null || !in_array($resource->purpose, ['avatar', 'message'], true)) {
            throw new BusinessException('FILE_RESOURCE_INVALID', '文件资源不存在', 404);
        }
        if ($resource->status === 20) {
            return ['resource_id' => $resourceId, 'url' => $resource->src, 'status' => 'ready'];
        }
        if (AppFileMultipartUploadModel::query()->where('file_id', (int)$resource->file_id)->exists()) {
            throw new BusinessException('FILE_UPLOAD_MODE_MISMATCH', '分片上传请使用Multipart完成接口', 409);
        }
        if ($resource->status !== 10 || $resource->upload_expires_at < time()) {
            throw new BusinessException('FILE_UPLOAD_EXPIRED', '上传凭证已过期', 410);
        }

        $verified = $this->storage->verifyObject($resource->object_key, $resource->size, $resource->mime_type);
        AppFileModel::query()->whereKey($resource->file_id)->where('status', 10)->update([
            'src' => $verified['public_url'],
            'etag' => $verified['etag'],
            'status' => 20,
            'update_time' => time(),
        ]);
        return ['resource_id' => $resourceId, 'url' => $verified['public_url'], 'status' => 'ready'];
    }

    /**
     * 为客户端指定的一批分片签发直传URL。
     *
     * @param list<int> $partNumbers 分片编号，单次最多20个
     * @return array<string,mixed>
     */
    public function createPartCredentials(
        int    $userId,
        string $resourceId,
        string $uploadId,
        array  $partNumbers,
    ): array
    {
        [$file, $session] = $this->activeMultipart($userId, $resourceId, $uploadId);
        $parts = [];
        foreach ($partNumbers as $partNumber) {
            if ($partNumber > (int)$session->total_parts) {
                throw new BusinessException('FILE_MULTIPART_PART_INVALID', '分片编号超过文件总分片数', 422);
            }
            $parts[] = $this->storage->createUploadPartCredential(
                (string)$file->object_key,
                (string)$session->upload_id,
                $partNumber,
                self::PART_CREDENTIAL_TTL,
            );
        }

        return [
            'resource_id' => $resourceId,
            'upload_id' => (string)$session->upload_id,
            'expires_in' => self::PART_CREDENTIAL_TTL,
            'parts' => $parts,
        ];
    }

    /**
     * 查询S3真实已上传分片，客户端据此恢复上传进度。
     *
     * @return array<string,mixed>
     */
    public function multipartStatus(int $userId, string $resourceId): array
    {
        [$file, $session] = $this->ownedMultipart($userId, $resourceId);
        if ((int)$session->status === 20) {
            return $this->multipartCompletedResponse($file, $session);
        }
        $this->assertMultipartUploading($file, $session);

        return [
            'resource_id' => $resourceId,
            'upload_id' => (string)$session->upload_id,
            'part_size' => (int)$session->part_size,
            'total_parts' => (int)$session->total_parts,
            'status' => 'uploading',
            'expires_at' => (int)$session->expires_at,
            'uploaded_parts' => $this->storage->listMultipartParts(
                (string)$file->object_key,
                (string)$session->upload_id,
            ),
        ];
    }

    /**
     * 校验客户端ETag与S3真实分片后完成对象合并。
     *
     * @param list<array{part_number:int,etag:string}> $parts
     * @return array<string,mixed>
     */
    public function completeMultipart(
        int    $userId,
        string $resourceId,
        string $uploadId,
        array  $parts,
    ): array
    {
        [$file, $session] = $this->ownedMultipart($userId, $resourceId);
        if ((string)$session->upload_id !== $uploadId) {
            throw new BusinessException('FILE_MULTIPART_UPLOAD_MISMATCH', 'upload_id与文件资源不匹配', 409);
        }
        if ((int)$session->status === 20 || (int)$file->status === 20) {
            return $this->multipartCompletedResponse($file, $session);
        }
        $this->assertMultipartUploading($file, $session, allowCompleting: true);

        if ((int)$session->status === 10) {
            $actualParts = $this->storage->listMultipartParts((string)$file->object_key, $uploadId);
            $this->assertCompleteParts($file, $session, $parts, $actualParts);
            $changed = AppFileMultipartUploadModel::query()
                ->whereKey((int)$session->multipart_id)
                ->where('status', 10)
                ->update(['status' => 15, 'update_time' => time()]);
            if ($changed !== 1) {
                throw new BusinessException('FILE_MULTIPART_STATE_CONFLICT', '分片上传状态已变化，请重试', 409);
            }
            $session->status = 15;
            $this->storage->completeMultipartUpload((string)$file->object_key, $uploadId, $parts);
        }

        try {
            $verified = $this->storage->verifyObject(
                (string)$file->object_key,
                (int)$file->size,
                (string)$file->mime_type,
            );
        } catch (BusinessException $exception) {
            if ((int)$session->status === 15 && $exception->businessCode() === 'FILE_UPLOAD_NOT_FOUND') {
                try {
                    // ListParts仍成功说明Complete请求没有生效，可以安全恢复为上传中后重试。
                    $this->storage->listMultipartParts((string)$file->object_key, (string)$session->upload_id);
                    AppFileMultipartUploadModel::query()
                        ->whereKey((int)$session->multipart_id)
                        ->where('status', 15)
                        ->update(['status' => 10, 'update_time' => time()]);
                } catch (BusinessException $listException) {
                    if ($listException->businessCode() !== 'FILE_MULTIPART_UPLOAD_NOT_FOUND') {
                        throw $listException;
                    }
                    // UploadId消失但对象暂不可见时保持合并中，避免重复Complete破坏幂等。
                }
                throw new BusinessException(
                    'FILE_MULTIPART_COMPLETE_RETRY',
                    '对象尚未完成合并，请重新提交完成请求',
                    503,
                );
            }
            throw $exception;
        }
        $now = time();
        $this->finalizeMultipart($file, $session, $verified, $now);

        // 同步当前进程内模型状态，确保首次完成与后续幂等查询返回完全相同的结构。
        $file->src = $verified['public_url'];
        $file->status = 20;
        $session->status = 20;

        return $this->multipartCompletedResponse($file, $session);
    }

    /**
     * 取消当前用户的Multipart上传并释放S3分片。
     *
     * @return array{resource_id:string,status:string}
     */
    public function abortMultipart(int $userId, string $resourceId, string $uploadId): array
    {
        [$file, $session] = $this->ownedMultipart($userId, $resourceId);
        if ((string)$session->upload_id !== $uploadId) {
            throw new BusinessException('FILE_MULTIPART_UPLOAD_MISMATCH', 'upload_id与文件资源不匹配', 409);
        }
        if ((int)$session->status === 20 || (int)$session->status === 15) {
            throw new BusinessException('FILE_MULTIPART_STATE_CONFLICT', '正在合并或已经完成的上传不能取消', 409);
        }
        if (in_array((int)$session->status, [30, 40], true)) {
            return ['resource_id' => $resourceId, 'status' => 'aborted'];
        }

        $this->storage->abortMultipartUpload((string)$file->object_key, (string)$session->upload_id);
        $this->markMultipartStopped($file, $session, 30);

        return ['resource_id' => $resourceId, 'status' => 'aborted'];
    }

    /**
     * 清理一批过期Multipart会话，供后台Worker周期调用。
     *
     * @return array{attempted:int,completed:int,aborted:int,failed:int}
     */
    public function cleanupExpiredMultipart(int $limit = 20): array
    {
        $sessions = AppFileMultipartUploadModel::query()
            ->with('file')
            ->whereIn('status', [10, 15])
            ->where('expires_at', '<=', time())
            ->orderBy('multipart_id')
            ->limit($limit)
            ->get();
        $aborted = 0;
        $completed = 0;
        $failed = 0;
        foreach ($sessions as $session) {
            $file = $session->file;
            if (!$file instanceof AppFileModel) {
                continue;
            }
            try {
                if ((int)$session->status === 15) {
                    try {
                        $verified = $this->storage->verifyObject(
                            (string)$file->object_key,
                            (int)$file->size,
                            (string)$file->mime_type,
                        );
                        $this->finalizeMultipart($file, $session, $verified, time());
                        ++$completed;
                    } catch (BusinessException $exception) {
                        if ($exception->businessCode() !== 'FILE_UPLOAD_NOT_FOUND') {
                            throw $exception;
                        }
                        $this->storage->abortMultipartUpload(
                            (string)$file->object_key,
                            (string)$session->upload_id,
                        );
                        $this->markMultipartStopped($file, $session, 40);
                        ++$aborted;
                    }
                    continue;
                }
                $this->storage->abortMultipartUpload((string)$file->object_key, (string)$session->upload_id);
                $this->markMultipartStopped($file, $session, 40);
                ++$aborted;
            } catch (Throwable) {
                ++$failed;
            }
        }

        return [
            'attempted' => $sessions->count(),
            'completed' => $completed,
            'aborted' => $aborted,
            'failed' => $failed,
        ];
    }

    /**
     * 原子提交Multipart完成事实和最终对象元数据。
     *
     * @param array{size:int,mime_type:string,etag:?string,public_url:string} $verified
     */
    private function finalizeMultipart(
        AppFileModel                $file,
        AppFileMultipartUploadModel $session,
        array                       $verified,
        int                         $now,
    ): void
    {
        $this->transactions->run(function () use ($file, $session, $verified, $now): void {
            AppFileModel::query()->whereKey((int)$file->file_id)->where('status', 10)->update([
                'src' => $verified['public_url'],
                'etag' => $verified['etag'],
                'status' => 20,
                'update_time' => $now,
            ]);
            AppFileMultipartUploadModel::query()->whereKey((int)$session->multipart_id)->update([
                'status' => 20,
                'completed_at' => $now,
                'update_time' => $now,
            ]);
        });
    }

    /**
     * 读取属于当前用户的Multipart文件与会话。
     *
     * @return array{AppFileModel,AppFileMultipartUploadModel}
     */
    private function ownedMultipart(int $userId, string $resourceId): array
    {
        $file = AppFileModel::query()
            ->where('resource_id', $resourceId)
            ->where('user_id', $userId)
            ->where('purpose', 'message')
            ->first();
        if (!$file instanceof AppFileModel) {
            throw new BusinessException('FILE_RESOURCE_INVALID', '聊天附件资源不存在', 404);
        }
        $session = AppFileMultipartUploadModel::query()->where('file_id', (int)$file->file_id)->first();
        if (!$session instanceof AppFileMultipartUploadModel) {
            throw new BusinessException('FILE_UPLOAD_MODE_MISMATCH', '该资源不是Multipart上传', 409);
        }

        return [$file, $session];
    }

    /**
     * 读取并校验仍可上传的Multipart会话。
     *
     * @return array{AppFileModel,AppFileMultipartUploadModel}
     */
    private function activeMultipart(int $userId, string $resourceId, string $uploadId): array
    {
        [$file, $session] = $this->ownedMultipart($userId, $resourceId);
        if ((string)$session->upload_id !== $uploadId) {
            throw new BusinessException('FILE_MULTIPART_UPLOAD_MISMATCH', 'upload_id与文件资源不匹配', 409);
        }
        $this->assertMultipartUploading($file, $session);

        return [$file, $session];
    }

    /**
     * 断言Multipart会话处于可继续处理状态，并在过期时立即释放S3分片。
     */
    private function assertMultipartUploading(
        AppFileModel                $file,
        AppFileMultipartUploadModel $session,
        bool                        $allowCompleting = false,
    ): void
    {
        // 后台清理只改变本地持久化状态；查询时必须稳定返回过期业务码，不能退化为状态冲突。
        if ((int)$session->status === 40) {
            throw new BusinessException('FILE_UPLOAD_EXPIRED', '分片上传会话已过期', 410);
        }
        if ((int)$session->status === 10 && (int)$session->expires_at <= time()) {
            $this->storage->abortMultipartUpload((string)$file->object_key, (string)$session->upload_id);
            $this->markMultipartStopped($file, $session, 40);
            throw new BusinessException('FILE_UPLOAD_EXPIRED', '分片上传会话已过期', 410);
        }
        $allowed = $allowCompleting ? [10, 15] : [10];
        if ((int)$file->status !== 10 || !in_array((int)$session->status, $allowed, true)) {
            throw new BusinessException('FILE_MULTIPART_STATE_CONFLICT', '分片上传状态不允许当前操作', 409);
        }
    }

    /**
     * 对比客户端提交分片与S3事实，并严格验证每片大小。
     *
     * @param list<array{part_number:int,etag:string}> $submitted
     * @param list<array{part_number:int,etag:string,size:int}> $actual
     */
    private function assertCompleteParts(
        AppFileModel                $file,
        AppFileMultipartUploadModel $session,
        array                       $submitted,
        array                       $actual,
    ): void
    {
        if (count($submitted) !== (int)$session->total_parts || count($actual) !== count($submitted)) {
            throw new BusinessException('FILE_MULTIPART_PARTS_INCOMPLETE', '已上传分片数量不完整', 422);
        }
        $actualByNumber = [];
        foreach ($actual as $part) {
            $actualByNumber[$part['part_number']] = $part;
        }
        foreach ($submitted as $index => $part) {
            $expectedNumber = $index + 1;
            $stored = $actualByNumber[$expectedNumber] ?? null;
            $expectedSize = min(
                (int)$session->part_size,
                (int)$file->size - (($expectedNumber - 1) * (int)$session->part_size),
            );
            if (
                $part['part_number'] !== $expectedNumber
                || !is_array($stored)
                || !hash_equals(strtolower($stored['etag']), strtolower(trim($part['etag'], '"')))
                || $stored['size'] !== $expectedSize
            ) {
                throw new BusinessException('FILE_MULTIPART_PART_MISMATCH', '客户端分片信息与S3记录不一致', 422);
            }
        }
    }

    /**
     * 将取消或过期会话及文件资源原子标记为不可用。
     */
    private function markMultipartStopped(
        AppFileModel                $file,
        AppFileMultipartUploadModel $session,
        int                         $status,
    ): void
    {
        $now = time();
        $this->transactions->run(function () use ($file, $session, $status, $now): void {
            AppFileMultipartUploadModel::query()->whereKey((int)$session->multipart_id)->update([
                'status' => $status,
                'aborted_at' => $now,
                'update_time' => $now,
            ]);
            AppFileModel::query()->whereKey((int)$file->file_id)->where('status', 10)->update([
                'status' => 30,
                'delete_time' => $now,
                'update_time' => $now,
            ]);
        });
    }

    /**
     * 返回已完成Multipart资源的幂等响应。
     *
     * @return array{resource_id:string,upload_id:string,status:string,resource_url:string,mime_type:string,size:int}
     */
    private function multipartCompletedResponse(
        AppFileModel                $file,
        AppFileMultipartUploadModel $session,
    ): array
    {
        if ((int)$file->status !== 20 || (int)$session->status !== 20) {
            throw new BusinessException('FILE_MULTIPART_STATE_CONFLICT', '文件与分片会话完成状态不一致', 409);
        }
        if (!is_string($file->src) || $file->src === '') {
            throw new BusinessException('FILE_MULTIPART_STATE_CONFLICT', '已完成文件缺少最终访问地址', 409);
        }

        return [
            'resource_id' => (string)$file->resource_id,
            'upload_id' => (string)$session->upload_id,
            'status' => 'completed',
            'resource_url' => $file->src,
            'mime_type' => (string)$file->mime_type,
            'size' => (int)$file->size,
        ];
    }
}
