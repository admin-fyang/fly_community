<?php

declare(strict_types=1);

namespace app\enum;

/**
 * IM事件发布Outbox状态。
 */
enum OutboxStatus: int
{
    /** 事件等待首次发布。 */
    case Pending = 10;

    /** 事件已经成功发布。 */
    case Published = 20;

    /** 发布失败但仍允许重试。 */
    case FailedRetryable = 30;

    /** 发布超过重试上限，已进入死信。 */
    case FailedDead = 40;

    /** 事件对应的业务事实已经失效，发布前被静默跳过。 */
    case Skipped = 50;

    /**
     * 判断任务当前是否允许发布。
     */
    public function canPublish(): bool
    {
        return $this === self::Pending || $this === self::FailedRetryable;
    }
}
