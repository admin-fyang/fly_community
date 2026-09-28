<?php

declare(strict_types=1);

namespace app\model;

use Illuminate\Database\Eloquent\Model;

/**
 * 系统公开配置模型。
 *
 * @property int $id SQL字段：配置ID
 * @property string|null $key SQL字段：稳定配置键
 * @property string|null $value SQL字段：序列化后的配置值
 * @property string $value_format SQL字段：file、string、int、timezones、switch或text
 * @property int $update_time SQL字段：更新时间，Unix秒
 * @property int $create_time SQL字段：创建时间，Unix秒
 * @property string|null $name SQL字段：管理框架显示名称
 * @property string|null $remark SQL字段：配置说明
 * @property int $status SQL字段：1启用、0停用
 * @property string|null $group SQL字段：配置分组
 * @property string|null $unit SQL字段：显示单位
 */
final class AppConfigModel extends Model
{
    protected $table = 'app_config';
    protected $primaryKey = 'id';
    public $timestamps = false;
    protected $guarded = ['id'];
    protected $casts = ['id'=>'integer','update_time'=>'integer','create_time'=>'integer','status'=>'integer'];
}
