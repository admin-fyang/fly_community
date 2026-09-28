<?php

declare(strict_types=1);

namespace app\model;

use Illuminate\Database\Eloquent\Model;

/**
 * Refresh Token轮换记录数据库模型。
 *
 * @property string $token_id SQL字段：Refresh Token UUID v4
 * @property string $session_id SQL字段：所属登录会话UUID v4
 * @property string $token_hash SQL字段：Refresh Token的HMAC-SHA256二进制值
 * @property int $token_version SQL字段：会话内Refresh Token轮换版本
 * @property int $issued_at SQL字段：签发时间，Unix秒
 * @property int $expires_at SQL字段：过期时间，Unix秒
 * @property int|null $consumed_at SQL字段：首次成功刷新时间，Unix秒
 * @property int|null $reused_at SQL字段：已消费Token再次出现时间，Unix秒
 */
final class AppUserSessionTokenModel extends Model
{
    protected $table = 'app_user_session_token';
    protected $primaryKey = 'token_id';
    public $incrementing = false;
    protected $keyType = 'string';
    public $timestamps = false;
    protected $guarded = [];

    protected $casts = [
        'token_version' => 'integer',
        'issued_at' => 'integer',
        'expires_at' => 'integer',
        'consumed_at' => 'integer',
        'reused_at' => 'integer',
    ];
}
