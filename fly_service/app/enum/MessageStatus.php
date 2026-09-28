<?php

declare(strict_types=1);

namespace app\enum;

/**
 * IM消息服务端状态。
 */
enum MessageStatus: int
{
    /** 正常可见消息。 */
    case Normal = 10;

    /** 已撤回消息。 */
    case Recalled = 20;

    /** 被服务端管理删除的消息。 */
    case Deleted = 30;

    /** 被风控或违规策略屏蔽的消息。 */
    case Blocked = 40;
}
