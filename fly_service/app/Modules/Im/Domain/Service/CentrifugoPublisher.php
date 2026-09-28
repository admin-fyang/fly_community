<?php

declare(strict_types=1);

namespace app\Modules\Im\Domain\Service;

/**
 * Centrifugo服务端事件发布边界。
 */
interface CentrifugoPublisher
{
    /**
     * 将完整事件载荷发布到指定用户频道。
     *
     * @param string $channel Centrifugo频道
     * @param array<string,mixed> $payload 统一事件载荷
     */
    public function publish(string $channel, array $payload): void;
}
