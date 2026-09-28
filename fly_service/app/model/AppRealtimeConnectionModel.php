<?php

declare(strict_types=1);

namespace app\model;

use Illuminate\Database\Eloquent\Model;

/**
 * 设备会话管理的app_realtime_connection表映射，不承担业务鉴权。
 *
 * @property string $client_id SQL字段：Centrifugo生成的连接UUID
 * @property string $session_id SQL字段：所属FlyIM登录会话UUID
 * @property int $user_id SQL字段：所属用户ID
 * @property int $created_at SQL字段：首次准入校验时间，Unix秒
 * @property int $expires_at SQL字段：本次服务端连接租期，Unix秒
 */
final class AppRealtimeConnectionModel extends Model
{
    protected $table = 'app_realtime_connection';
    protected $primaryKey = 'client_id';
    public $incrementing = false;
    protected $keyType = 'string';
    public $timestamps = false;
    protected $guarded = [];
    protected $casts = ['user_id' => 'integer', 'created_at' => 'integer', 'expires_at' => 'integer'];
}
