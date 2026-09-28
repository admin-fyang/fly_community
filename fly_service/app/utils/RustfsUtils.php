<?php

declare(strict_types=1);

namespace app\utils;

use app\exception\BusinessException;
use Aws\Credentials\Credentials;
use Aws\Exception\AwsException;
use Aws\S3\S3Client;
use GuzzleHttp\Client;
use GuzzleHttp\ClientInterface;
use support\Log;
use Throwable;

/**
 * RustFS S3 兼容存储的预签名上传与对象核验适配器。
 */
final class RustfsUtils
{
    private S3Client $client;
    private S3Client $verifyClient;
    private ClientInterface $httpClient;

    /**
     * 校验配置并创建 S3 客户端。
     */
    public function __construct(
        private readonly string $endpoint,
        private readonly string $publicEndpoint,
        private readonly string $accessKey,
        private readonly string $secretKey,
        private readonly string $bucket,
        private readonly string $region = 'us-east-1',
        private readonly bool $pathStyle = true,
        private readonly bool $sslVerify = false,
        ?string $serverEndpoint = null,
        ?ClientInterface $httpClient = null,
    ) {
        if ($endpoint === '' || $publicEndpoint === '' || $accessKey === '' || $secretKey === '' || $bucket === '') {
            throw new BusinessException('STORAGE_CONFIG_INVALID', 'RustFS 存储配置不完整', 500);
        }
        $this->client = new S3Client([
            'version' => 'latest',
            'region' => $region,
            'endpoint' => rtrim($endpoint, '/'),
            'use_path_style_endpoint' => $pathStyle,
            'credentials' => new Credentials($accessKey, $secretKey),
            'http' => ['verify' => $sslVerify],
        ]);
        $this->verifyClient = new S3Client([
            'version' => 'latest',
            'region' => $region,
            'endpoint' => rtrim($serverEndpoint ?: $endpoint, '/'),
            'use_path_style_endpoint' => $pathStyle,
            'credentials' => new Credentials($accessKey, $secretKey),
            'http' => ['verify' => $sslVerify],
        ]);
        $this->httpClient = $httpClient ?? new Client([
            'connect_timeout' => 3,
            'http_errors' => false,
            'timeout' => 5,
            'verify' => $sslVerify,
        ]);
    }

    /**
     * 签发限定对象、类型和有效期的临时 PUT URL。
     *
     * @return array{upload_url:string,headers:array<string,string>,expires_in:int}
     */
    public function createPutCredential(string $objectKey, string $mimeType, int $expiresIn = 900): array
    {
        try {
            $command = $this->client->getCommand('PutObject', [
                'Bucket' => $this->bucket,
                'Key' => $objectKey,
                'ContentType' => $mimeType,
            ]);
            $request = $this->client->createPresignedRequest($command, "+{$expiresIn} seconds");
            return [
                'upload_url' => (string) $request->getUri(),
                'headers' => ['Content-Type' => $mimeType],
                'expires_in' => $expiresIn,
            ];
        } catch (Throwable) {
            throw new BusinessException('STORAGE_UNAVAILABLE', '暂时无法签发上传凭证', 503);
        }
    }

    /**
     * 创建S3 Multipart上传会话。
     */
    public function createMultipartUpload(string $objectKey, string $mimeType): string
    {
        try {
            $result = $this->verifyClient->createMultipartUpload([
                'Bucket' => $this->bucket,
                'Key' => $objectKey,
                'ContentType' => $mimeType,
            ]);
            $uploadId = (string)($result['UploadId'] ?? '');
            if ($uploadId === '') {
                throw new BusinessException('STORAGE_INVALID_RESPONSE', '对象存储未返回upload_id', 503);
            }

            return $uploadId;
        } catch (BusinessException $exception) {
            throw $exception;
        } catch (Throwable) {
            throw new BusinessException('STORAGE_UNAVAILABLE', '暂时无法创建分片上传会话', 503);
        }
    }

    /**
     * 为指定分片签发短期UploadPart URL。
     *
     * @return array{part_number:int,upload_url:string,headers:array<string,string>,expires_in:int}
     */
    public function createUploadPartCredential(
        string $objectKey,
        string $uploadId,
        int $partNumber,
        int $expiresIn = 900,
    ): array {
        try {
            $command = $this->client->getCommand('UploadPart', [
                'Bucket' => $this->bucket,
                'Key' => $objectKey,
                'UploadId' => $uploadId,
                'PartNumber' => $partNumber,
            ]);
            $request = $this->client->createPresignedRequest($command, "+{$expiresIn} seconds");
            $headers = [];
            foreach ($request->getHeaders() as $name => $values) {
                if (strtolower($name) !== 'host') {
                    $headers[$name] = implode(', ', $values);
                }
            }

            return [
                'part_number' => $partNumber,
                'upload_url' => (string)$request->getUri(),
                'headers' => $headers,
                'expires_in' => $expiresIn,
            ];
        } catch (Throwable) {
            throw new BusinessException('STORAGE_UNAVAILABLE', '暂时无法签发分片上传凭证', 503);
        }
    }

    /**
     * 查询S3已经接收的全部分片，用于断点恢复和完成前校验。
     *
     * @return list<array{part_number:int,etag:string,size:int}>
     */
    public function listMultipartParts(string $objectKey, string $uploadId): array
    {
        $parts = [];
        $marker = null;
        try {
            do {
                $parameters = [
                    'Bucket' => $this->bucket,
                    'Key' => $objectKey,
                    'UploadId' => $uploadId,
                    'MaxParts' => 1000,
                ];
                if ($marker !== null) {
                    $parameters['PartNumberMarker'] = $marker;
                }
                $result = $this->verifyClient->listParts($parameters);
                foreach (($result['Parts'] ?? []) as $part) {
                    $parts[] = [
                        'part_number' => (int)$part['PartNumber'],
                        'etag' => trim((string)$part['ETag'], '"'),
                        'size' => (int)$part['Size'],
                    ];
                }
                $marker = !empty($result['IsTruncated'])
                    ? (int)($result['NextPartNumberMarker'] ?? 0)
                    : null;
            } while ($marker !== null && $marker > 0);
        } catch (AwsException $exception) {
            if ($exception->getAwsErrorCode() === 'NoSuchUpload') {
                throw new BusinessException('FILE_MULTIPART_UPLOAD_NOT_FOUND', '对象存储中的分片会话不存在', 409);
            }
            throw new BusinessException('STORAGE_UNAVAILABLE', '暂时无法查询已上传分片', 503);
        } catch (Throwable) {
            throw new BusinessException('STORAGE_UNAVAILABLE', '暂时无法查询已上传分片', 503);
        }

        return $parts;
    }

    /**
     * 请求S3按客户端提交的有序ETag列表合并对象。
     *
     * @param list<array{part_number:int,etag:string}> $parts
     */
    public function completeMultipartUpload(string $objectKey, string $uploadId, array $parts): void
    {
        try {
            $this->verifyClient->completeMultipartUpload([
                'Bucket' => $this->bucket,
                'Key' => $objectKey,
                'UploadId' => $uploadId,
                'MultipartUpload' => [
                    'Parts' => array_map(static fn (array $part): array => [
                        'PartNumber' => $part['part_number'],
                        'ETag' => '"' . trim($part['etag'], '"') . '"',
                    ], $parts),
                ],
            ]);
        } catch (AwsException $exception) {
            if ($exception->getAwsErrorCode() === 'NoSuchUpload') {
                throw new BusinessException('FILE_MULTIPART_UPLOAD_NOT_FOUND', '对象存储中的分片会话不存在', 409);
            }
            throw new BusinessException('STORAGE_UNAVAILABLE', '暂时无法完成分片上传', 503);
        } catch (Throwable) {
            throw new BusinessException('STORAGE_UNAVAILABLE', '暂时无法完成分片上传', 503);
        }
    }

    /**
     * 取消S3 Multipart会话并释放尚未合并的分片。
     */
    public function abortMultipartUpload(string $objectKey, string $uploadId): void
    {
        try {
            $this->verifyClient->abortMultipartUpload([
                'Bucket' => $this->bucket,
                'Key' => $objectKey,
                'UploadId' => $uploadId,
            ]);
        } catch (AwsException $exception) {
            if ($exception->getAwsErrorCode() === 'NoSuchUpload') {
                return;
            }
            throw new BusinessException('STORAGE_UNAVAILABLE', '暂时无法取消分片上传', 503);
        } catch (Throwable) {
            throw new BusinessException('STORAGE_UNAVAILABLE', '暂时无法取消分片上传', 503);
        }
    }

    /**
     * 通过 HeadObject 核验前端直传对象的大小和媒体类型。
     *
     * @return array{size:int,mime_type:string,etag:?string,public_url:string}
     */
    public function verifyObject(string $objectKey, int $expectedSize, string $expectedMimeType): array
    {
        $publicUrl = $this->publicObjectUrl($objectKey);
        $s3Exception = null;
        try {
            $result = $this->verifyClient->headObject(['Bucket' => $this->bucket, 'Key' => $objectKey]);
            $size = (int) ($result['ContentLength'] ?? -1);
            $mimeType = strtolower((string) ($result['ContentType'] ?? ''));
            if ($size !== $expectedSize || $mimeType !== strtolower($expectedMimeType)) {
                throw new BusinessException('FILE_UPLOAD_MISMATCH', '上传文件与申请信息不一致', 422);
            }
            return [
                'size' => $size,
                'mime_type' => $mimeType,
                'etag' => isset($result['ETag']) ? trim((string) $result['ETag'], '"') : null,
                'public_url' => $publicUrl,
            ];
        } catch (BusinessException $exception) {
            throw $exception;
        } catch (Throwable $throwable) {
            $s3Exception = $throwable;
            $this->warning('rustfs.s3_head.failed', [
                'bucket' => $this->bucket,
                'object_key' => $objectKey,
                'exception_class' => $throwable::class,
                'http_status' => $throwable instanceof AwsException ? $throwable->getStatusCode() : null,
                'aws_error_code' => $throwable instanceof AwsException ? $throwable->getAwsErrorCode() : null,
                'message' => $throwable->getMessage(),
            ]);
        }

        $publicObject = $this->verifyPublicObject($publicUrl, $expectedSize, $expectedMimeType);
        if ($publicObject !== null) {
            return $publicObject;
        }

        if ($s3Exception instanceof AwsException && $s3Exception->getStatusCode() === 403) {
            throw new BusinessException('STORAGE_VERIFY_FORBIDDEN', '暂时无法核验已上传的文件', 503);
        }
        if ($s3Exception instanceof AwsException && $s3Exception->getStatusCode() === 404) {
            throw new BusinessException('FILE_UPLOAD_NOT_FOUND', '未找到已上传的文件', 422);
        }

        throw new BusinessException('STORAGE_UNAVAILABLE', '暂时无法核验已上传的文件', 503);
    }

    /**
     * 构造对象公开访问地址。
     */
    public function publicObjectUrl(string $objectKey): string
    {
        return rtrim($this->publicEndpoint, '/') . '/' . $this->bucket . '/' . ltrim($objectKey, '/');
    }

    /** 流式计算已上传对象SHA-256，避免安装包整体加载进PHP内存。 */
    public function objectSha256(string $objectKey): string
    {
        try {
            $result = $this->verifyClient->getObject(['Bucket' => $this->bucket, 'Key' => $objectKey]);
            $body = $result['Body'];
            $hash = hash_init('sha256');
            while (!$body->eof()) {
                hash_update($hash, $body->read(1024 * 1024));
            }
            return hash_final($hash);
        } catch (Throwable) {
            throw new BusinessException('STORAGE_UNAVAILABLE', '暂时无法计算安装包摘要', 503);
        }
    }

    /**
     * 删除指定对象；S3 对不存在对象的删除也是成功，保证管理端重复请求幂等。
     */
    public function deleteObject(string $objectKey): void
    {
        try {
            $this->verifyClient->deleteObject(['Bucket' => $this->bucket, 'Key' => $objectKey]);
        } catch (Throwable) {
            throw new BusinessException('STORAGE_UNAVAILABLE', '暂时无法删除文件', 503);
        }
    }

    /**
     * 使用公开地址核验对象大小和媒体类型；公开地址不可访问时返回null。
     *
     * @return array{size:int,mime_type:string,etag:?string,public_url:string}|null
     */
    private function verifyPublicObject(string $publicUrl, int $expectedSize, string $expectedMimeType): ?array
    {
        try {
            $response = $this->httpClient->request('HEAD', $publicUrl);
        } catch (Throwable $throwable) {
            $this->warning('rustfs.public_head.failed', [
                'public_url' => $publicUrl,
                'exception_class' => $throwable::class,
                'message' => $throwable->getMessage(),
            ]);
            return null;
        }

        if ($response->getStatusCode() < 200 || $response->getStatusCode() >= 300) {
            $this->warning('rustfs.public_head.unavailable', [
                'public_url' => $publicUrl,
                'http_status' => $response->getStatusCode(),
                'content_length' => $response->getHeaderLine('Content-Length'),
                'content_type' => $response->getHeaderLine('Content-Type'),
            ]);
            return null;
        }

        $size = (int) ($response->getHeaderLine('Content-Length') ?: -1);
        $mimeType = strtolower(trim(explode(';', $response->getHeaderLine('Content-Type'))[0]));
        if ($size !== $expectedSize || $mimeType !== strtolower($expectedMimeType)) {
            $this->warning('rustfs.public_head.mismatch', [
                'public_url' => $publicUrl,
                'expected_size' => $expectedSize,
                'actual_size' => $size,
                'expected_mime_type' => strtolower($expectedMimeType),
                'actual_mime_type' => $mimeType,
            ]);
            throw new BusinessException('FILE_UPLOAD_MISMATCH', '上传文件与申请信息不一致', 422);
        }

        return [
            'size' => $size,
            'mime_type' => $mimeType,
            'etag' => $response->getHeaderLine('ETag') !== '' ? trim($response->getHeaderLine('ETag'), '"') : null,
            'public_url' => $publicUrl,
        ];
    }

    /**
     * 写入诊断日志；测试环境未加载日志配置时忽略日志失败。
     *
     * @param array<string,mixed> $context
     */
    private function warning(string $message, array $context): void
    {
        if (!function_exists('config') || !is_array(config('log'))) {
            return;
        }

        try {
            Log::warning($message, $context);
        } catch (Throwable) {
        }
    }
}
