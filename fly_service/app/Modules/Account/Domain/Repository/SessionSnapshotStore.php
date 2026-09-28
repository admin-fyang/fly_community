<?php

declare(strict_types=1);

namespace app\Modules\Account\Domain\Repository;

/** 短期查询快照存储端口，不保存访问令牌或刷新令牌。 */
interface SessionSnapshotStore
{
    /** 保存冻结顺序及所属身份，返回不可预测的快照标识。 */
    public function create(array $snapshot): string;

    /** 读取尚未过期的快照；不存在时返回 null。 */
    public function find(string $id): ?array;

    /** 限制每个用户的列表及撤销请求，超额抛出 HTTP 429。 */
    public function assertAllowed(int $userId): void;
}
