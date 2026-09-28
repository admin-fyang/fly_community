<?php

declare(strict_types=1);

$debug = filter_var(getenv('APP_DEBUG') ?: 'false', FILTER_VALIDATE_BOOL);
$exposeVerificationCode = filter_var(
    getenv('AUTH_EXPOSE_VERIFICATION_CODE') ?: 'true',
    FILTER_VALIDATE_BOOL,
);

return [
    'contact_lookup_key' => getenv('AUTH_CONTACT_LOOKUP_KEY') ?: '',
    'contact_encryption_key' => getenv('AUTH_CONTACT_ENCRYPTION_KEY') ?: '',
    'refresh_token_key' => getenv('AUTH_REFRESH_TOKEN_KEY') ?: '',
    'verification_code_key' => getenv('AUTH_VERIFICATION_CODE_KEY') ?: '',
    'jwt' => [
        'key_id' => getenv('AUTH_JWT_KEY_ID') ?: 'main-2026-01',
        'private_key' => getenv('AUTH_JWT_PRIVATE_KEY') ?: '',
        'public_key' => getenv('AUTH_JWT_PUBLIC_KEY') ?: '',
        'issuer' => getenv('AUTH_JWT_ISSUER') ?: 'chat-fly-service',
        'audience' => getenv('AUTH_JWT_AUDIENCE') ?: 'chat-fly-app',
        'ttl_seconds' => 2592000,
    ],
    'refresh_ttl_seconds' => 2592000,
    'verification' => [
        'driver' => getenv('AUTH_VERIFICATION_DRIVER') ?: 'fixed',
        'fixed_code' => getenv('AUTH_FIXED_VERIFICATION_CODE') ?: '',
        'expose_code' => $debug && $exposeVerificationCode,
        'ttl_seconds' => 600,
        'resend_seconds' => 60,
        'max_attempts' => 5,
    ],
];
