<?php

declare(strict_types=1);

namespace app\Support\Upload;

use app\exception\BusinessException;

/** 根据 app_config 对文件上传执行统一的大小、扩展名和 MIME 黑名单校验。 */
final class UploadPolicy
{
    private const BYTES_PER_MB = 1024 * 1024;
    /** @var list<string> */ private readonly array $blockedExtensions;
    /** @var list<string> */ private readonly array $blockedMimeTypes;

    /** @param list<string> $blockedExtensions @param list<string> $blockedMimeTypes */
    public function __construct(private readonly int $maxMegabytes, array $blockedExtensions, array $blockedMimeTypes)
    {
        if ($maxMegabytes < 1) throw new \InvalidArgumentException('upload_max 必须大于0');
        $this->blockedExtensions = $this->normalizeExtensions($blockedExtensions);
        $this->blockedMimeTypes = $this->normalizeMimeTypes($blockedMimeTypes);
    }

    /** @param array{filename:string,size:int,mime_type:string} $input */
    public function assertAllowed(array $input): string
    {
        if ($input['size'] > $this->maxMegabytes * self::BYTES_PER_MB) {
            throw new BusinessException('FILE_UPLOAD_TOO_LARGE', "文件大小不能超过{$this->maxMegabytes}MB", 422);
        }
        $extension = strtolower((string)pathinfo($input['filename'], PATHINFO_EXTENSION));
        if ($extension !== '' && preg_match('/^[a-z0-9][a-z0-9_-]{0,15}$/', $extension) !== 1) {
            throw new BusinessException('FILE_EXTENSION_INVALID', '文件扩展名格式不正确', 422);
        }
        if ($extension !== '' && in_array($extension, $this->blockedExtensions, true)) {
            throw new BusinessException('FILE_EXTENSION_NOT_ALLOWED', '不允许上传该文件扩展名', 422);
        }
        if (in_array(strtolower($input['mime_type']), $this->blockedMimeTypes, true)) {
            throw new BusinessException('FILE_MIME_TYPE_NOT_ALLOWED', '不允许上传该MIME类型', 422);
        }
        return $extension === '' ? 'bin' : $extension;
    }

    /** @param list<string> $values @return list<string> */
    private function normalizeExtensions(array $values): array
    {
        $result=[]; foreach($values as $value){$value=strtolower(ltrim(trim($value),'.'));if($value!=='')$result[$value]=true;} return array_keys($result);
    }

    /** @param list<string> $values @return list<string> */
    private function normalizeMimeTypes(array $values): array
    {
        $result=[]; foreach($values as $value){$value=strtolower(trim($value));if($value!=='')$result[$value]=true;} return array_keys($result);
    }
}
