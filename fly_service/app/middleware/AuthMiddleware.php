<?php

declare(strict_types=1);

namespace app\middleware;

use app\enum\UserStatus;
use app\exception\BusinessException;
use app\model\AppUserModel;
use app\model\AppUserSessionModel;
use app\Support\Auth\AuthContext;
use app\Support\Auth\AuthContextHolder;
use Firebase\JWT\JWT;
use Firebase\JWT\Key;
use Throwable;
use Webman\Http\Request;
use Webman\Http\Response;
use Webman\MiddlewareInterface;

/**
 * 校验 Bearer Access Token、会话和账号状态。
 */
final class AuthMiddleware implements MiddlewareInterface
{
    /**
     * 注入 JWT 验签参数。
     */
    public function __construct(
        private readonly string $publicKey,
        private readonly string $issuer,
        private readonly string $audience,
    ) {
    }

    /**
     * 验证访问令牌并向请求注入不可变认证上下文。
     */
    public function process(Request $request, callable $handler): Response
    {
        $authorization = (string) $request->header('authorization', '');
        if (preg_match('/^Bearer\s+(\S+)$/i', $authorization, $matches) !== 1) {
            throw new BusinessException('AUTH_TOKEN_INVALID', '访问令牌无效', 401);
        }

        try {
            $payload = JWT::decode($matches[1], new Key($this->publicKey, 'EdDSA'));
        } catch (Throwable) {
            throw new BusinessException('AUTH_TOKEN_INVALID', '访问令牌无效或已过期', 401);
        }

        $audience = is_array($payload->aud ?? null) ? $payload->aud : [$payload->aud ?? null];
        if (($payload->iss ?? null) !== $this->issuer || !in_array($this->audience, $audience, true)) {
            throw new BusinessException('AUTH_TOKEN_INVALID', '访问令牌签发方无效', 401);
        }

        $userId = filter_var($payload->sub ?? null, FILTER_VALIDATE_INT);
        $sessionId = (string) ($payload->sid ?? '');
        $deviceId = (string) ($payload->did ?? '');
        if ($userId === false || $sessionId === '' || $deviceId === '') {
            throw new BusinessException('AUTH_TOKEN_INVALID', '访问令牌载荷无效', 401);
        }

        $session = AppUserSessionModel::query()
            ->whereKey($sessionId)
            ->where('user_id', $userId)
            ->where('device_id', $deviceId)
            ->first();
        if ($session === null || $session->revoked_at !== null || $session->expires_at <= time()) {
            throw new BusinessException('AUTH_SESSION_REVOKED', '登录会话已失效', 401);
        }

        $statusValue = AppUserModel::query()->whereKey($userId)->value('status');
        $status = $statusValue instanceof UserStatus
            ? $statusValue
            : UserStatus::tryFrom((int)$statusValue);
        $isDeletionCancellation = $status === UserStatus::PendingDelete
            && preg_match('#^/api/v1/users/me/deletion-requests/del_[0-9a-f]{32}/cancel$#', $request->path()) === 1;
        if ($status !== UserStatus::Active && !$isDeletionCancellation) {
            throw new BusinessException('ACCOUNT_DISABLED', '账号当前不可用', 403);
        }

        // 最近活跃仅表示认证请求到达，以一分钟为粒度写入，不能当作在线状态。
        $now = time();
        if ($session->last_active_at <= $now - 60) {
            AppUserSessionModel::query()->whereKey($sessionId)->whereNull('revoked_at')
                ->where('last_active_at', '<=', $now - 60)->update(['last_active_at' => $now]);
        }

        AuthContextHolder::set(new AuthContext((int) $userId, $sessionId, $deviceId));
        return $handler($request);
    }
}
