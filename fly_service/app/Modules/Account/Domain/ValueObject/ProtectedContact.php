<?php

declare(strict_types=1);

namespace app\Modules\Account\Domain\ValueObject;

use app\enum\ContactType;

/**
 * 可安全落库和查询的联系方式数据。
 */
final readonly class ProtectedContact
{
    /**
     * 创建可安全持久化和查询的联系方式值对象。
     */
    public function __construct(
        public ContactType $type,
        public string $valueHash,
        public string $ciphertext,
        public int $cipherKeyVersion,
        public string $masked,
    ) {
    }
}
