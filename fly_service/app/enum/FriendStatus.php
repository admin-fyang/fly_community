<?php

declare(strict_types=1);

namespace app\enum;

/**
 * 好友关系状态。
 */
enum FriendStatus: int
{
    /** 已拉黑。 */
    case Blocked = -2;

    /** 已删除。 */
    case Deleted = -1;

    /** 历史待同意状态，新业务不写入。 */
    case Pending = 0;

    /** 正常好友。 */
    case Friend = 1;

    /**
     * 返回客户端稳定名称。
     */
    public function apiName(): string
    {
        return match ($this) {
            self::Blocked => 'blocked',
            self::Deleted => 'deleted',
            self::Pending => 'pending',
            self::Friend => 'friend',
        };
    }
}
