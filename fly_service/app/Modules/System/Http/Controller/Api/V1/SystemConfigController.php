<?php

declare(strict_types=1);

namespace app\Modules\System\Http\Controller\Api\V1;

use app\Modules\System\Application\SystemConfigService;
use app\response\ApiResponse;
use support\Response;

/**
 * 客户端公开系统配置控制器。
 */
final class SystemConfigController
{
    /**
     * 注入系统配置应用服务。
     */
    public function __construct(
        private readonly SystemConfigService $service,
    ) {
    }

    /**
     * 获取客户端启动所需的公开系统配置。
     */
    public function show(): Response
    {
        return ApiResponse::success($this->service->show());
    }
}
