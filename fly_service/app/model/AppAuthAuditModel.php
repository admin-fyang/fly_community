<?php

declare(strict_types=1);

namespace app\model;

use Illuminate\Database\Eloquent\Model;

/**
 * 认证与账号安全审计数据库模型。
 *
 * @property int $audit_id SQL字段：认证安全审计主键ID
 * @property string $request_id SQL字段：API请求ID
 * @property string $event SQL字段：安全事件代码
 * @property int $result SQL字段：审计结果，10成功、20失败、30拒绝
 * @property int|null $user_id SQL字段：已识别的用户ID
 * @property int|null $identity_type SQL字段：登录标识类型，10手机号、20邮箱、30用户名
 * @property string|null $identity_hash SQL字段：登录标识规范值的HMAC-SHA256二进制值
 * @property string|null $session_id SQL字段：相关会话UUID v4
 * @property string|null $device_id SQL字段：相关设备UUID v4
 * @property string|null $ip SQL字段：请求IP，支持IPv4和IPv6
 * @property string|null $user_agent SQL字段：请求User-Agent
 * @property string|null $reason_code SQL字段：稳定失败原因代码
 * @property array<string, mixed>|null $context SQL字段：不含敏感值的低频扩展信息
 * @property int $create_time SQL字段：创建时间，Unix秒
 */
final class AppAuthAuditModel extends Model
{
    protected $table = 'app_auth_audit';
    protected $primaryKey = 'audit_id';
    public $timestamps = false;
    protected $guarded = ['audit_id'];

    protected $casts = [
        'audit_id' => 'integer',
        'result' => 'integer',
        'user_id' => 'integer',
        'identity_type' => 'integer',
        'context' => 'array',
        'create_time' => 'integer',
    ];
}
