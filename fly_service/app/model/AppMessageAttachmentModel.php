<?php

declare(strict_types=1);

namespace app\model;

use app\enum\AttachmentType;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * IM消息附件模型。
 *
 * @property int $attachment_id SQL字段：消息附件ID
 * @property int $message_id SQL字段：所属消息ID
 * @property int $file_id SQL字段：文件资源ID
 * @property AttachmentType $attachment_type SQL字段：附件类型，image图片、voice语音、video视频、file文件
 * @property string $resource_url SQL字段：已完成文件公开URL
 * @property int|null $thumbnail_file_id SQL字段：缩略图文件资源ID
 * @property string|null $thumbnail_url SQL字段：已完成缩略图公开URL
 * @property string|null $file_name SQL字段：原始文件名
 * @property string $mime_type SQL字段：文件MIME类型
 * @property int $file_size SQL字段：文件大小，单位字节
 * @property int|null $width SQL字段：图片或视频宽度，单位像素
 * @property int|null $height SQL字段：图片或视频高度，单位像素
 * @property int|null $duration_ms SQL字段：语音或视频时长，单位毫秒
 * @property array<int,float>|null $waveform SQL字段：语音波形采样数组
 * @property int $sort_order SQL字段：同一消息内附件排序，从0开始
 * @property int $create_time SQL字段：创建时间，Unix秒
 * @property-read AppFileModel $file 关联的文件资源
 * @property-read AppFileModel|null $thumbnailFile 关联的缩略图资源
 */
final class AppMessageAttachmentModel extends Model
{
    protected $table = 'app_message_attachment';
    protected $primaryKey = 'attachment_id';
    public $timestamps = false;
    protected $guarded = ['attachment_id'];
    protected $casts = [
        'attachment_id' => 'integer',
        'message_id' => 'integer',
        'file_id' => 'integer',
        'attachment_type' => AttachmentType::class,
        'thumbnail_file_id' => 'integer',
        'file_size' => 'integer',
        'width' => 'integer',
        'height' => 'integer',
        'duration_ms' => 'integer',
        'waveform' => 'array',
        'sort_order' => 'integer',
        'create_time' => 'integer',
    ];

    /**
     * 获取附件对应的文件资源。
     */
    public function file(): BelongsTo
    {
        return $this->belongsTo(AppFileModel::class, 'file_id', 'file_id');
    }

    /**
     * 获取附件对应的缩略图资源。
     */
    public function thumbnailFile(): BelongsTo
    {
        return $this->belongsTo(AppFileModel::class, 'thumbnail_file_id', 'file_id');
    }
}
