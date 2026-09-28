<?php

declare(strict_types=1);

namespace app\Modules\Account\Http\Controller\Api\V1;

use app\Modules\Account\Application\DeviceSessionService;
use app\Modules\Account\Application\SessionRevocationService;
use app\Modules\Account\Domain\Repository\SessionSnapshotStore;
use app\Modules\Account\Http\Request\DeviceSessionRequest;
use app\response\ApiResponse;
use app\Support\Auth\AuthContextHolder;
use support\Request;
use support\Response;

/** 当前用户的登录会话列表及逐条撤销入口，禁止接受客户端用户ID。 */
final class DeviceSessionController
{
    /** 注入列表、撤销、验证及共享限流边界。 */
    public function __construct(private readonly DeviceSessionService $sessions, private readonly SessionRevocationService $revocation,
        private readonly DeviceSessionRequest $validator, private readonly SessionSnapshotStore $snapshots)
    {
    }

    /** 每页返回当前会话及快照内其他有效会话。 */
    public function index(Request $request): Response
    {
        $input = $this->validator->listing($request);
        return ApiResponse::success($this->sessions->listing(AuthContextHolder::get(), $input['limit'], $input['cursor']), 200, '成功')
            ->withHeader('Cache-Control', 'private, no-store');
    }

    /** DELETE 不读取请求体；成功响应回传实际处理的目标会话ID。 */
    public function delete(Request $request, string $session_id): Response
    {
        $auth = AuthContextHolder::get();
        $this->snapshots->assertAllowed($auth->userId);
        return ApiResponse::success($this->revocation->revoke($auth, $this->validator->sessionId($session_id),
            $request->getRemoteIp(), (string)$request->header('user-agent', '')), 200, '会话已撤销')
            ->withHeader('Cache-Control', 'private, no-store');
    }
}
