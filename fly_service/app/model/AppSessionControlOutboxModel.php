<?php

declare(strict_types=1);

namespace app\model;

use Illuminate\Database\Eloquent\Model;
use app\enum\OutboxStatus;

/**
 * 设备会话管理的app_session_control_outbox表映射，不承担业务鉴权。
 *
 * @property string $session_id SQL字段：需要撤销连接的登录会话UUID，亦为幂等键
 * @property int $user_id SQL字段：目标用户ID
 * @property OutboxStatus $status SQL字段：任务状态：10待执行、20已完成、30失败重试、40死信
 * @property int $retry_count SQL字段：连续投递失败次数
 * @property int $next_retry_at SQL字段：下次执行时间，Unix秒
 * @property string|null $locked_by SQL字段：当前工作进程租约标识
 * @property int|null $locked_until SQL字段：租约截止时间，Unix秒
 * @property string|null $last_error SQL字段：最近一次安全错误码，不含凭证
 * @property int $created_at SQL字段：撤销事务提交任务的时间，Unix秒
 * @property int $updated_at SQL字段：任务最近更新时间，Unix秒
 */
final class AppSessionControlOutboxModel extends Model
{
    protected $table = 'app_session_control_outbox';
    protected $primaryKey = 'session_id';
    public $incrementing = false;
    protected $keyType = 'string';
    public $timestamps = false;
    protected $guarded = [];
    protected $casts = ['user_id' => 'integer', 'status' => OutboxStatus::class, 'retry_count' => 'integer', 'next_retry_at' => 'integer', 'locked_until' => 'integer', 'created_at' => 'integer', 'updated_at' => 'integer'];
}
