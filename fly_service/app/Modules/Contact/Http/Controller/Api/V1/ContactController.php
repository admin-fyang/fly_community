<?php

declare(strict_types=1);

namespace app\Modules\Contact\Http\Controller\Api\V1;

use app\Modules\Contact\Application\ContactService;
use app\Modules\Contact\Http\Request\ContactRequest;
use app\response\ApiResponse;
use app\Support\Auth\AuthContextHolder;
use support\Request;
use support\Response;

/**
 * 联系人和用户社交资料接口。
 */
final class ContactController
{
    /**
     * 注入联系人服务和请求解析器。
     */
    public function __construct(
        private readonly ContactService $service,
        private readonly ContactRequest $requestParser,
    )
    {
    }

    /**
     * 获取联系人列表。
     */
    public function list(Request $request): Response
    {
        $auth = AuthContextHolder::get();
        $data = $this->requestParser->list($request);

        return ApiResponse::success($this->service->list($auth->userId, $data['limit'], $data['cursor']));
    }

    /**
     * 搜索用户。
     */
    public function searchUsers(Request $request): Response
    {
        $auth = AuthContextHolder::get();
        $data = $this->requestParser->search($request);

        return ApiResponse::success($this->service->searchUsers(
            $auth->userId,
            $data['keyword'],
            $data['limit'],
            $data['country_code'],
        ));
    }

    /**
     * 查看用户资料。
     */
    public function profile(Request $request, string $user_id): Response
    {
        $auth = AuthContextHolder::get();

        return ApiResponse::success($this->service->profile(
            $auth->userId,
            $this->requestParser->userId($user_id),
        ));
    }

    /**
     * 发起好友申请。
     */
    public function requestFriend(Request $request): Response
    {
        $auth = AuthContextHolder::get();
        $data = $this->requestParser->friendRequest($request);

        return ApiResponse::success($this->service->sendFriendRequest(
            $auth->userId,
            $data['target_user_id'],
            $data['remark'],
        ), 201);
    }

    /**
     * 修改联系人备注。
     */
    public function updateRemark(Request $request, string $user_id): Response
    {
        $auth = AuthContextHolder::get();
        $data = $this->requestParser->remark($request);

        return ApiResponse::success($this->service->updateRemark(
            $auth->userId,
            $this->requestParser->userId($user_id),
            $data['remark'],
        ));
    }

    /**
     * 修改联系人个人设置。
     */
    public function updateSettings(Request $request, string $user_id): Response
    {
        $auth = AuthContextHolder::get();
        $data = $this->requestParser->settings($request);

        return ApiResponse::success($this->service->updateSettings(
            $auth->userId,
            $this->requestParser->userId($user_id),
            $data['is_pinned'],
            $data['is_muted'],
        ));
    }

    /**
     * 删除联系人。
     */
    public function delete(Request $request, string $user_id): Response
    {
        $auth = AuthContextHolder::get();

        return ApiResponse::success($this->service->delete(
            $auth->userId,
            $this->requestParser->userId($user_id),
        ));
    }

    /**
     * 拉黑用户。
     */
    public function block(Request $request, string $user_id): Response
    {
        $auth = AuthContextHolder::get();

        return ApiResponse::success($this->service->block(
            $auth->userId,
            $this->requestParser->userId($user_id),
        ));
    }

    /**
     * 取消拉黑用户。
     */
    public function unblock(Request $request, string $user_id): Response
    {
        $auth = AuthContextHolder::get();

        return ApiResponse::success($this->service->unblock(
            $auth->userId,
            $this->requestParser->userId($user_id),
        ));
    }
}
