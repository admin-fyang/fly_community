<?php

declare(strict_types=1);

namespace app\model;

use app\enum\ContactType;
use Illuminate\Database\Eloquent\Model;

/**
 * 用户联系方式数据库模型。
 *
 * @property int $contact_id SQL字段：联系方式主键ID
 * @property int $user_id SQL字段：所属用户ID
 * @property ContactType $contact_type SQL字段：联系方式类型，10手机号、20邮箱
 * @property string $value_hash SQL字段：规范值的HMAC-SHA256二进制值
 * @property string $value_ciphertext SQL字段：AES-256-GCM加密后的规范值
 * @property int $cipher_key_version SQL字段：联系方式密文密钥版本
 * @property string $value_masked SQL字段：直接展示的脱敏值
 * @property int $verified_at SQL字段：联系方式验证通过时间，Unix秒
 * @property int $create_time SQL字段：创建时间，Unix秒
 * @property int $update_time SQL字段：更新时间，Unix秒
 */
final class AppUserContactModel extends Model
{
    protected $table = 'app_user_contact';
    protected $primaryKey = 'contact_id';
    public $timestamps = false;
    protected $guarded = ['contact_id'];

    protected $casts = [
        'contact_id' => 'integer',
        'user_id' => 'integer',
        'contact_type' => ContactType::class,
        'cipher_key_version' => 'integer',
        'verified_at' => 'integer',
        'create_time' => 'integer',
        'update_time' => 'integer',
    ];
}
