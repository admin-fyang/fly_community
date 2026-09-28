<?php

declare(strict_types=1);

namespace app\Modules\Im\Http\Controller\Api\V1;

use app\Modules\Im\Application\ImMessageService;
use app\Modules\Im\Application\ImMessageStateService;
use app\Modules\Im\Application\ImSyncService;
use app\Modules\Im\Domain\Service\CentrifugoTokenIssuer;
use app\Modules\Im\Http\Request\ImMessageRequest;
use app\response\ApiResponse;
use app\Support\Auth\AuthContextHolder;
use support\Request;
use support\Response;

/**
 * IM消息控制器。
 */
final class ImMessageController
{
    /**
     * @param ImMessageService $service IM消息应用服务
     * @param ImSyncService $syncService IM增量同步应用服务
     * @param ImMessageStateService $stateService IM消息状态应用服务
     * @param CentrifugoTokenIssuer $centrifugoTokenIssuer Centrifugo连接Token签发器
     * @param string $centrifugoPublicWebSocketUrl Centrifugo客户端WebSocket地址
     * @param ImMessageRequest $messageRequest IM消息请求解析器
     */
    public function __construct(
        private readonly ImMessageService $service,
        private readonly ImSyncService $syncService,
        private readonly ImMessageStateService $stateService,
        private readonly CentrifugoTokenIssuer $centrifugoTokenIssuer,
        private readonly string $centrifugoPublicWebSocketUrl,
        private readonly ImMessageRequest $messageRequest,
    ) {
    }

    /**
     * 发送单聊或群聊消息。
     *
     * @param Request $request HTTP请求对象
     * @return Response
     */
    public function sendMessage(Request $request): Response
    {
        $auth = AuthContextHolder::get();
        $data = $this->messageRequest->parseSendMessage($request);

        return ApiResponse::success($this->service->sendMessage($auth->userId, $data));
    }

    /**
     * 将源会话消息或收藏快照逐条转发到一个已有目标会话。
     */
    public function resolveSingleConversation(Request $request): Response
    {
        $auth = AuthContextHolder::get();
        $data = $this->messageRequest->parseResolveSingleConversation($request);

        return ApiResponse::success($this->service->resolveSingleConversation(
            $auth->userId,
            $data['target_user_id'],
        ));
    }

    /**
     * 解析群聊会话，并在共享会话被误删时按有效群关系完成重建。
     */
    public function listConversations(Request $request): Response
    {
        $auth = AuthContextHolder::get();
        $data = $this->messageRequest->parseConversationList($request);

        return ApiResponse::success($this->service->listConversations(
            $auth->userId,
            $data['limit'],
            $data['before_update_time'],
            $data['before_conversation_id'],
        ));
    }

    /**
     * 获取会话消息历史。
     *
     * @param Request $request HTTP请求对象
     * @return Response
     */
    public function listMessages(Request $request, string $conversation_id): Response
    {
        $auth = AuthContextHolder::get();
        $data = $this->messageRequest->parseMessageHistory($request, $conversation_id);

        return ApiResponse::success($this->service->listMessages(
            $auth->userId,
            $data['conversation_id'],
            $data['limit'],
            $data['before_seq'],
        ));
    }

    /**
     * 按事件游标同步当前设备的IM变化。
     *
     * @param Request $request HTTP请求对象
     * @return Response
     */
    public function sync(Request $request): Response
    {
        $auth = AuthContextHolder::get();
        $data = $this->messageRequest->parseSync($request);

        return ApiResponse::success($this->syncService->sync(
            $auth->userId,
            $data['after_event_id'],
            $data['limit'],
        ));
    }

    /**
     * 确认当前设备已经在本地事务中完整应用的事件位置。
     */
    public function acknowledgeSync(Request $request): Response
    {
        $auth = AuthContextHolder::get();
        $data = $this->messageRequest->parseSyncAck($request);

        return ApiResponse::success($this->syncService->acknowledge(
            $auth->userId,
            $auth->deviceId,
            $data['device_id'],
            $data['last_ack_event_id'],
        ));
    }

    /**
     * 获取当前设备的Centrifugo短期连接凭证。
     *
     * @param Request $request HTTP请求对象
     * @return Response
     */
    public function createCentrifugoToken(Request $request): Response
    {
        $auth = AuthContextHolder::get();
        $now = time();
        $ttl = $this->centrifugoTokenIssuer->ttlSeconds();
        $expiresAt = $now + $ttl;
        $refreshLeeway = min(60, max(10, intdiv($ttl, 5)));

        return ApiResponse::success([
            'token' => $this->centrifugoTokenIssuer->issue(
                $auth->userId,
                $auth->deviceId,
                $auth->sessionId,
                $now,
            ),
            'token_type' => 'centrifugo_connection',
            'authentication_mode' => (bool)config('device_sessions.realtime_proxy_enabled') ? 'proxy' : 'jwt',
            'websocket_url' => $this->centrifugoPublicWebSocketUrl,
            'channel' => 'private-user:' . $auth->userId,
            'subscription_mode' => 'server_side',
            'expires_at' => $expiresAt,
            'expires_in' => $ttl,
            'refresh_after' => $expiresAt - $refreshLeeway,
        ]);
    }

    /**
     * 上报当前用户的会话已读游标。
     */
    public function markRead(Request $request, string $conversation_id): Response
    {
        $auth = AuthContextHolder::get();
        $data = $this->messageRequest->parseReceipt($request, $conversation_id);

        return ApiResponse::success($this->stateService->markRead(
            $auth->userId,
            $data['conversation_id'],
            $data['seq'],
        ));
    }

    /**
     * 撤回当前用户发送的消息。
     */
    public function recallMessage(Request $request, string $message_id): Response
    {
        $auth = AuthContextHolder::get();
        $data = $this->messageRequest->parseRecall($request, $message_id);

        return ApiResponse::success($this->stateService->recallMessage(
            $auth->userId,
            $data['message_id'],
            $data['reason'],
        ));
    }

    /**
     * 仅对当前用户删除消息。
     */
    public function deleteMessageForMe(Request $request, string $message_id): Response
    {
        $auth = AuthContextHolder::get();

        return ApiResponse::success($this->stateService->deleteMessageForMe(
            $auth->userId,
            $this->messageRequest->parseMessageId($message_id),
        ));
    }

    /**
     * 清空当前用户的会话聊天记录。
     */
    public function deleteConversation(Request $request): Response
    {
        $auth = AuthContextHolder::get();
        $locator = $this->messageRequest->parseConversationLocator($request);

        return ApiResponse::success($this->stateService->deleteConversation(
            $auth->userId,
            $locator,
        ));
    }

    /**
     * 批量清空当前用户的聊天记录。
     */
}
