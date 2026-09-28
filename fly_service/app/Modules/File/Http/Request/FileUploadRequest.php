<?php

declare(strict_types=1);

namespace app\Modules\File\Http\Request;

use app\exception\BusinessException;
use Webman\Http\Request;

/**
 * 文件直传凭证和完成确认请求校验器。
 */
final class FileUploadRequest
{
    /**
     * 校验头像上传凭证申请。
     *
     * @return array{filename:string,size:int,mime_type:string}
     */
    public function credential(Request $request): array
    {
        $filename = $request->post('filename');
        $size = $request->post('size');
        $mimeType = strtolower((string)$request->post('mime_type', ''));
        if (!is_string($filename) || $filename === '' || mb_strlen($filename) > 191) {
            throw new BusinessException('VALIDATION_ERROR', 'filename 格式不正确', 422);
        }
        if (!is_int($size) || $size < 1 || $size > 10 * 1024 * 1024) {
            throw new BusinessException('VALIDATION_ERROR', '头像大小必须在1字节至10MB之间', 422);
        }
        if (!in_array($mimeType, ['image/jpeg', 'image/png', 'image/webp'], true)) {
            throw new BusinessException('VALIDATION_ERROR', '头像仅支持 JPEG、PNG、WebP', 422);
        }
        return ['filename' => $filename, 'size' => $size, 'mime_type' => $mimeType];
    }

    /**
     * 校验聊天附件上传凭证申请。
     *
     * @return array{filename:string,size:int,mime_type:string}
     */
    public function messageCredential(Request $request): array
    {
        $filename = $request->post('filename');
        $size = $request->post('size');
        $mimeType = strtolower((string)$request->post('mime_type', ''));
        if (!is_string($filename) || trim($filename) === '' || mb_strlen($filename) > 191) {
            throw new BusinessException('VALIDATION_ERROR', 'filename 格式不正确', 422);
        }
        if (!is_int($size) || $size < 1) {
            throw new BusinessException('VALIDATION_ERROR', '聊天附件大小必须为正整数', 422);
        }
        if (strlen($mimeType) > 128
            || preg_match('/^[a-z0-9][a-z0-9!#$&^_.+\-]*\/[a-z0-9][a-z0-9!#$&^_.+\-]*$/', $mimeType) !== 1
        ) {
            throw new BusinessException('VALIDATION_ERROR', 'mime_type 格式不正确', 422);
        }

        return ['filename' => trim($filename), 'size' => $size, 'mime_type' => $mimeType];
    }

    /**
     * 校验文件资源UUID。
     */
    public function resourceId(string $resourceId): string
    {
        if (preg_match('/^[0-9a-f-]{36}$/i', $resourceId) !== 1) {
            throw new BusinessException('VALIDATION_ERROR', 'resource_id 格式不正确', 422);
        }
        return strtolower($resourceId);
    }

    /**
     * 校验分片凭证申请。
     *
     * @return array{upload_id:string,part_numbers:list<int>}
     */
    public function multipartParts(Request $request): array
    {
        $uploadId = $this->uploadId($request->post('upload_id'));
        $partNumbers = $request->post('part_numbers');
        if (!is_array($partNumbers) || $partNumbers === [] || count($partNumbers) > 20) {
            throw new BusinessException('VALIDATION_ERROR', 'part_numbers必须包含1至20个分片编号', 422);
        }
        $normalized = [];
        foreach ($partNumbers as $partNumber) {
            if (!is_int($partNumber) || $partNumber < 1 || $partNumber > 10000) {
                throw new BusinessException('VALIDATION_ERROR', '分片编号必须为1至10000的整数', 422);
            }
            $normalized[] = $partNumber;
        }
        if (count(array_unique($normalized)) !== count($normalized)) {
            throw new BusinessException('VALIDATION_ERROR', 'part_numbers不能重复', 422);
        }
        sort($normalized, SORT_NUMERIC);

        return ['upload_id' => $uploadId, 'part_numbers' => $normalized];
    }

    /**
     * 校验Multipart完成请求中的完整有序分片ETag列表。
     *
     * @return array{upload_id:string,parts:list<array{part_number:int,etag:string}>}
     */
    public function multipartComplete(Request $request): array
    {
        $uploadId = $this->uploadId($request->post('upload_id'));
        $parts = $request->post('parts');
        if (!is_array($parts) || $parts === [] || count($parts) > 10000) {
            throw new BusinessException('VALIDATION_ERROR', 'parts必须包含1至10000个分片', 422);
        }
        $normalized = [];
        foreach ($parts as $part) {
            if (!is_array($part) || !is_int($part['part_number'] ?? null)) {
                throw new BusinessException('VALIDATION_ERROR', '分片必须包含整数part_number', 422);
            }
            $partNumber = $part['part_number'];
            $etag = $part['etag'] ?? null;
            if ($partNumber < 1 || $partNumber > 10000 || !is_string($etag)) {
                throw new BusinessException('VALIDATION_ERROR', '分片编号或ETag格式不正确', 422);
            }
            $etag = trim($etag, " \t\n\r\0\x0B\"");
            if ($etag === '' || strlen($etag) > 128 || preg_match('/[\x00-\x1F\x7F]/', $etag) === 1) {
                throw new BusinessException('VALIDATION_ERROR', 'ETag格式不正确', 422);
            }
            $normalized[] = ['part_number' => $partNumber, 'etag' => $etag];
        }
        usort($normalized, static fn(array $left, array $right): int => $left['part_number'] <=> $right['part_number']);
        if (count(array_unique(array_column($normalized, 'part_number'))) !== count($normalized)) {
            throw new BusinessException('VALIDATION_ERROR', '分片编号不能重复', 422);
        }

        return ['upload_id' => $uploadId, 'parts' => $normalized];
    }

    /**
     * 校验客户端保存的S3 upload_id。
     */
    public function uploadId(mixed $uploadId): string
    {
        if (!is_string($uploadId) || $uploadId === '' || strlen($uploadId) > 1024
            || preg_match('/[\x00-\x1F\x7F]/', $uploadId) === 1
        ) {
            throw new BusinessException('VALIDATION_ERROR', 'upload_id格式不正确', 422);
        }

        return $uploadId;
    }
}
