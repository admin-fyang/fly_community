<?php

declare(strict_types=1);

namespace app\enum;

/**
 * 系统通知动作状态。
 */
enum NotificationActionStatus: int
{
    /** 无需处理，仅展示。 */
    case None = 10;

    /** 待当前用户处理。 */
    case Pending = 20;

    /** 已同意。 */
    case Accepted = 30;

    /** 已拒绝。 */
    case Rejected = 40;

    /** 已过期。 */
    case Expired = 50;

    /** 已取消。 */
    case Cancelled = 60;

    /**
     * 返回客户端稳定名称。
     */
    public function apiName(): string
    {
        return match ($this) {
            self::None => 'none',
            self::Pending => 'pending',
            self::Accepted => 'accepted',
            self::Rejected => 'rejected',
            self::Expired => 'expired',
            self::Cancelled => 'cancelled',
        };
    }
}
