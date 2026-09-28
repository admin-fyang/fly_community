<?php

declare(strict_types=1);

/**
 * 生成本地 .env 所需的认证密钥。
 *
 * 输出包含敏感信息，只能在受控终端执行，禁止写入日志或提交仓库。
 */

$keyPair = sodium_crypto_sign_keypair();

$values = [
    'AUTH_CONTACT_LOOKUP_KEY' => base64_encode(random_bytes(32)),
    'AUTH_CONTACT_ENCRYPTION_KEY' => base64_encode(random_bytes(32)),
    'AUTH_REFRESH_TOKEN_KEY' => base64_encode(random_bytes(32)),
    'AUTH_VERIFICATION_CODE_KEY' => base64_encode(random_bytes(32)),
    'AUTH_JWT_PRIVATE_KEY' => base64_encode(sodium_crypto_sign_secretkey($keyPair)),
    'AUTH_JWT_PUBLIC_KEY' => base64_encode(sodium_crypto_sign_publickey($keyPair)),
];

foreach ($values as $name => $value) {
    fwrite(STDOUT, $name . '=' . $value . PHP_EOL);
}
