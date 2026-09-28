<?php

declare(strict_types=1);

namespace app\Modules\System\Domain\Repository;

/**
 * 已发布系统配置仓储。
 *
 * 数据库是唯一事实源，基础设施实现可以使用 Redis 缓存完整配置快照。
 */
interface SystemConfigRepository
{
    /** @return array<string, mixed> 返回全部已启用且已按 value_format 解码的配置。 */
    public function allEnabled(): array;

    /** 数据库事务提交后失效旧快照并立即以数据库最新值重建缓存。 */
    public function refresh(): void;
}
