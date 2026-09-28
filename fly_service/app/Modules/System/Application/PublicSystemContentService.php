<?php

declare(strict_types=1);

namespace app\Modules\System\Application;

use app\exception\BusinessException;
use app\model\AppContentPageModel;

/** 提供客户端公开协议与隐私内容页。 */
final class PublicSystemContentService
{
    /** @return array<string,mixed> */
    public function page(string $slug): array
    {
        $row = AppContentPageModel::query()->where('slug', $slug)->where('status', 20)->first();
        if (!$row) throw new BusinessException('SYSTEM_CONTENT_PAGE_NOT_FOUND', '内容页不存在', 404);
        return ['slug' => $row->slug, 'title' => $row->title, 'content_html' => $row->content_html, 'updated_at' => (int)$row->update_time];
    }

    /** @return array{items:list<array<string,mixed>>,total:int,page:int,page_size:int} */
}
