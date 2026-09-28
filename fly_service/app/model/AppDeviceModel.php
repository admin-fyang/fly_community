<?php

declare(strict_types=1);

namespace app\model;

use Illuminate\Database\Eloquent\Model;

/**
 * 客户端安装实例数据库模型。
 *
 * @property string $device_id SQL字段：客户端安装实例UUID v4
 * @property string $platform SQL字段：平台，android、ios、web、windows、macos、linux
 * @property string $device_name SQL字段：用户可识别的设备名称
 * @property string|null $app_version SQL字段：最近使用的客户端版本
 * @property int $create_time SQL字段：设备首次出现时间，Unix秒
 * @property int $update_time SQL字段：设备最近更新时间，Unix秒
 */
final class AppDeviceModel extends Model
{
    protected $table = 'app_device';
    protected $primaryKey = 'device_id';
    public $incrementing = false;
    protected $keyType = 'string';
    public $timestamps = false;
    protected $guarded = [];

    protected $casts = [
        'create_time' => 'integer',
        'update_time' => 'integer',
    ];
}
