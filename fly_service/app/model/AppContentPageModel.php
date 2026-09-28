<?php

declare(strict_types=1);

namespace app\model;

use Illuminate\Database\Eloquent\Model;

/**
 * 客户端公开协议与规则内容页模型。
 *
 * @property int $page_id SQL字段：内容页ID
 * @property string $slug SQL字段：稳定内容页标识
 * @property string $title SQL字段：内容页标题
 * @property string $content_html SQL字段：清理后的富文本HTML
 * @property int $status SQL字段：状态，10草稿、20已发布
 * @property int|null $published_at SQL字段：最近发布时间，Unix秒
 * @property int $create_time SQL字段：创建时间，Unix秒
 * @property int $update_time SQL字段：更新时间，Unix秒
 */
final class AppContentPageModel extends Model
{
    protected $table = 'app_content_page';
    protected $primaryKey = 'page_id';
    public $timestamps = false;
    protected $guarded = ['page_id'];
    protected $casts = ['page_id'=>'integer','status'=>'integer','published_at'=>'integer','create_time'=>'integer','update_time'=>'integer'];
}
