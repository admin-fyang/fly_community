<?php

declare(strict_types=1);

namespace app\Modules\User\Domain\Exception;

use RuntimeException;

/**
 * 用户实时在线状态暂时不可查询。
 *
 * 该异常只表达 Centrifugo 在线状态基础设施不可用，不代表目标用户离线。
 */
final class UserPresenceUnavailableException extends RuntimeException
{
}
