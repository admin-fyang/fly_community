<?php

declare(strict_types=1);

namespace app\Modules\User\Domain\Service;

use InvalidArgumentException;

/**
 * Centrifugo Presence频道分片算法。
 *
 * PHP与Listener必须使用同一算法：SHA-256前4字节按网络字节序解释为uint32后取模。
 */
final class PresenceShard
{
    /**
     * 返回指定用户的Presence分片频道。
     */
    public static function channel(int $userId, int $shardCount): string
    {
        if ($userId <= 0 || $shardCount <= 0) {
            throw new InvalidArgumentException('Presence分片参数必须为正整数');
        }
        $parts = unpack('Nvalue', substr(hash('sha256', (string)$userId, true), 0, 4));
        $value = is_array($parts) ? (int)$parts['value'] : 0;
        return 'presence:' . str_pad((string)($value % $shardCount), 4, '0', STR_PAD_LEFT);
    }
}
