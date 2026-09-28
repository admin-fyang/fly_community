<?php

declare(strict_types=1);

namespace app\Modules\Account\Domain\Repository;

/** 实时会话定向断连外部边界，禁止省略连接ID退化为账号级断连。 */
interface RealtimeDisconnector
{
    /** 对指定用户的单条连接发送 4501；失败必须抛出异常交给 Outbox 重试。 */
    public function disconnect(int $userId, string $clientId): void;
}
