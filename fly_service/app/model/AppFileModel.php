<?php

declare(strict_types=1);

namespace app\model;

use Illuminate\Database\Eloquent\Model;

/**
 * 文件资源数据库模型。
 *
 * @property int $file_id SQL字段：文件自增主键
 * @property string $resource_id SQL字段：对外文件资源UUID
 * @property int $cate SQL字段：旧文件分类
 * @property string|null $file_type SQL字段：旧文件类型
 * @property int $parent_id SQL字段：旧父级ID
 * @property string|null $name SQL字段：原始文件名
 * @property string|null $src SQL字段：已完成文件公开URL
 * @property int $size SQL字段：文件字节数
 * @property string|null $ext SQL字段：文件扩展名
 * @property string|null $md5 SQL字段：旧MD5字段
 * @property int $user_id SQL字段：资源所有者用户ID；0表示管理员上传的公共附件
 * @property string $purpose SQL字段：用途，general普通、avatar头像、message聊天附件
 * @property string $storage_disk SQL字段：存储驱动，rustfs
 * @property string $bucket SQL字段：对象存储桶
 * @property string $object_key SQL字段：对象存储Key
 * @property string $mime_type SQL字段：申请上传的媒体类型
 * @property string|null $etag SQL字段：对象存储ETag
 * @property int|null $upload_expires_at SQL字段：上传凭证过期时间
 * @property int $create_time SQL字段：创建时间
 * @property int $update_time SQL字段：更新时间
 * @property int $delete_time SQL字段：删除时间
 * @property int $status SQL字段：资源状态，10待上传、20已完成、30已删除
 * @property int $is_lock SQL字段：旧锁定标识
 */
final class AppFileModel extends Model
{
    protected $table = 'app_file';
    protected $primaryKey = 'file_id';
    public $timestamps = false;
    protected $guarded = ['file_id'];
    protected $casts = [
        'file_id' => 'integer',
        'cate' => 'integer',
        'parent_id' => 'integer',
        'size' => 'integer',
        'user_id' => 'integer',
        'upload_expires_at' => 'integer',
        'create_time' => 'integer',
        'update_time' => 'integer',
        'delete_time' => 'integer',
        'status' => 'integer',
        'is_lock' => 'integer',
    ];
}
