<?php

declare(strict_types=1);

namespace app\Modules\Im\Http\Controller\Api\V1;

use app\Modules\Im\Application\ImDirectoryService;
use app\Modules\Im\Http\Request\ImDirectoryRequest;
use app\response\ApiResponse;
use app\Support\Auth\AuthContextHolder;
use support\Request;
use support\Response;

/** 通讯录与群资料本地投影同步接口。 */
final class ImDirectoryController
{
    /**
     * 注入目录查询服务与请求解析器。
     */
    public function __construct(
        private readonly ImDirectoryService $service,
        private readonly ImDirectoryRequest $requestParser,
    ) {
    }

    /**
     * 分页返回当前用户联系人和群目录权威快照。
     */
    public function bootstrap(Request $request): Response
    {
        $input = $this->requestParser->bootstrap($request);

        return ApiResponse::success($this->service->bootstrap(
            AuthContextHolder::get()->userId,
            $input['cursor'],
            $input['limit'],
        ));
    }

    /**
     * 批量返回当前用户可见且版本已变化的用户公开摘要。
     */
    public function changedUserBriefs(Request $request): Response
    {
        return ApiResponse::success($this->service->changedUserBriefs(
            AuthContextHolder::get()->userId,
            $this->requestParser->userBriefVersions($request),
        ));
    }
}
