<?php

declare(strict_types=1);

namespace app\Modules\System\Http\Controller\Api\V1;

use app\exception\ValidationException;
use app\Modules\System\Application\PublicSystemContentService;
use app\response\ApiResponse;
use support\Request;
use support\Response;

/** 客户端公开协议、帮助中心和在线升级接口。 */
final class SystemContentController
{
    /** 注入公开系统内容查询服务。 */
    public function __construct(private readonly PublicSystemContentService $service)
    {
    }

    /** 按固定标识返回已发布协议或规则正文。 */
    public function page(Request $r, string $slug): Response
    {
        if (preg_match('/^[a-z][a-z0-9-]{1,63}$/', $slug) !== 1) throw new ValidationException('slug格式不正确');
        return ApiResponse::success($this->service->page($slug));
    }

    /** 分页返回已发布帮助文章。 */
}
