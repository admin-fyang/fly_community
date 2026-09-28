<?php

declare(strict_types=1);

namespace app\Modules\Account\Domain\Exception;

use RuntimeException;

/**
 * 极低概率的服务端随机公开标识冲突，允许注册用例整体重试。
 */
final class GeneratedIdentityCollisionException extends RuntimeException
{
}
