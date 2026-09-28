<?php

declare(strict_types=1);

namespace app\model;

use Illuminate\Database\Eloquent\Model;

/**
 * 账号注销冷静期申请模型。
 *
 * @property string $deletion_request_id SQL字段：对外账号注销申请ID
 * @property int $user_id SQL字段：申请注销的用户ID
 * @property int $status SQL字段：注销状态，10冷静期中、20已取消、30已生效
 * @property int|null $pending_user_id SQL字段：仅冷静期记录参与唯一约束的用户ID
 * @property int $requested_at SQL字段：申请时间，Unix秒
 * @property int $effective_at SQL字段：计划生效时间，Unix秒
 * @property int|null $cancelled_at SQL字段：取消时间，Unix秒
 * @property int $create_time SQL字段：创建时间，Unix秒
 * @property int $update_time SQL字段：更新时间，Unix秒
 */
final class AppAccountDeletionRequestModel extends Model
{
    protected $table = 'app_account_deletion_request';
    protected $primaryKey = 'deletion_request_id';
    public $incrementing = false;
    protected $keyType = 'string';
    public $timestamps = false;
    protected $guarded = [];
    protected $casts = ['user_id' => 'integer', 'status' => 'integer', 'pending_user_id' => 'integer', 'requested_at' => 'integer', 'effective_at' => 'integer', 'cancelled_at' => 'integer', 'create_time' => 'integer', 'update_time' => 'integer'];
}
