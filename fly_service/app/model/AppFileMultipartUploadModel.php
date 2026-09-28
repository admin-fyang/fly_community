<?php

declare(strict_types=1);

namespace app\model;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * S3 Multipart聊天附件上传会话模型。
 *
 * @property int $multipart_id SQL字段：分片上传会话主键ID
 * @property int $file_id SQL字段：关联文件资源ID
 * @property string $upload_id SQL字段：S3上传会话ID
 * @property int $part_size SQL字段：客户端分片大小，字节
 * @property int $total_parts SQL字段：文件总分片数，范围1至10000
 * @property int $status SQL字段：上传状态，10上传中、15合并中、20已完成、30已取消、40已过期
 * @property int $expires_at SQL字段：Multipart会话过期时间，Unix秒
 * @property int|null $completed_at SQL字段：完成合并时间，Unix秒
 * @property int|null $aborted_at SQL字段：取消或过期清理时间，Unix秒
 * @property int $create_time SQL字段：创建时间，Unix秒
 * @property int $update_time SQL字段：更新时间，Unix秒
 * @property-read AppFileModel $file 关联文件资源
 */
final class AppFileMultipartUploadModel extends Model
{
    protected $table = 'app_file_multipart_upload';
    protected $primaryKey = 'multipart_id';
    public $timestamps = false;
    protected $guarded = ['multipart_id'];
    protected $casts = [
        'multipart_id' => 'integer',
        'file_id' => 'integer',
        'part_size' => 'integer',
        'total_parts' => 'integer',
        'status' => 'integer',
        'expires_at' => 'integer',
        'completed_at' => 'integer',
        'aborted_at' => 'integer',
        'create_time' => 'integer',
        'update_time' => 'integer',
    ];

    /**
     * 获取分片会话对应的文件资源。
     */
    public function file(): BelongsTo
    {
        return $this->belongsTo(AppFileModel::class, 'file_id', 'file_id');
    }
}
