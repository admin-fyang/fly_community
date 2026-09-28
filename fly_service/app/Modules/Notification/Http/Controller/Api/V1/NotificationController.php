<?php

declare(strict_types=1);

namespace app\Modules\Notification\Http\Controller\Api\V1;

use app\Modules\Notification\Application\NotificationService;
use app\Modules\Notification\Http\Request\NotificationRequest;
use app\response\ApiResponse;
use app\Support\Auth\AuthContextHolder;
use support\Request;
use support\Response;

/**
 * 系统通知控制器。
 */
final class NotificationController
{
    /**
     * 注入系统通知应用服务和请求解析器。
     */
    public function __construct(
        private readonly NotificationService $service,
        private readonly NotificationRequest $requestParser,
    ) {
    }

    /**
     * 获取当前用户通知列表。
     */
    public function list(Request $request): Response
    {
        $auth = AuthContextHolder::get();
        $data = $this->requestParser->parseList($request);

        return ApiResponse::success($this->service->list(
            $auth->userId,
            $data['limit'],
            $data['before_notification_id'],
        ));
    }

    /**
     * 获取当前用户未读通知数量。
     */
    public function unreadCount(Request $request): Response
    {
        $auth = AuthContextHolder::get();

        return ApiResponse::success($this->service->unreadCount($auth->userId));
    }

    /**
     * 标记单条通知为已读。
     */
    public function read(Request $request, string $notification_id): Response
    {
        $auth = AuthContextHolder::get();

        return ApiResponse::success($this->service->markRead(
            $auth->userId,
            $this->requestParser->parseNotificationId($notification_id),
        ));
    }

    /**
     * 标记全部通知为已读。
     */
    public function readAll(Request $request): Response
    {
        $auth = AuthContextHolder::get();

        return ApiResponse::success($this->service->markAllRead($auth->userId));
    }

    /**
     * 处理当前用户可操作通知。
     */
    public function handle(Request $request, string $notification_id): Response
    {
        $auth = AuthContextHolder::get();
        $data = $this->requestParser->parseHandle($request);

        return ApiResponse::success($this->service->handle(
            $auth->userId,
            $this->requestParser->parseNotificationId($notification_id),
            $data['action'],
            $data['reason'],
        ));
    }

    /**
     * 仅对当前用户删除通知。
     */
    public function deleteForMe(Request $request, string $notification_id): Response
    {
        $auth = AuthContextHolder::get();

        return ApiResponse::success($this->service->deleteForMe(
            $auth->userId,
            $this->requestParser->parseNotificationId($notification_id),
        ));
    }
}
