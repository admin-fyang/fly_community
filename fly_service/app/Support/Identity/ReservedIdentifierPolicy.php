<?php

declare(strict_types=1);

namespace app\Support\Identity;

use app\exception\BusinessException;
use app\Modules\System\Domain\Repository\SystemConfigRepository;

/** 用户名与群短名共用的动态保留关键字规则；不用于名称搜索或管理员写入。 */
final class ReservedIdentifierPolicy
{
    /** 系统配置表中的共享保留关键字键。 */
    public const CONFIG_KEY = 'identity_reserved_keywords';

    /** 注入已发布配置仓储；不缓存到对象属性，避免常驻进程一直使用旧规则。 */
    public function __construct(private readonly SystemConfigRepository $configs) {}

    /** 每行一个 ASCII 标识片段，统一小写、去空行并去重；空文本表示关闭动态保留词。 */
    public static function normalizeConfig(mixed $value): string
    {
        if (!is_string($value) || strlen($value) > 65535) {
            throw new BusinessException('SYSTEM_CONFIG_VALUE_INVALID', '保留关键字必须为文本且最多65535字节', 422);
        }
        $keywords = [];
        foreach (preg_split('/\r\n|\r|\n/', $value) as $line) {
            $keyword = strtolower(trim($line));
            if ($keyword === '') continue;
            if (preg_match('/\A[a-z0-9_]{1,64}\z/', $keyword) !== 1) {
                throw new BusinessException('SYSTEM_CONFIG_VALUE_INVALID', '保留关键字每行一项，仅允许1至64位英文字母、数字和下划线', 422);
            }
            $keywords[] = $keyword;
        }
        return implode("\n", array_unique($keywords));
    }

    /** 按包含匹配，配置读取失败向上抛出，避免故障时绕过运营已发布的限制。 */
    public function containsReservedKeyword(string $identifier): bool
    {
        $config = $this->configs->allEnabled();
        $value = self::normalizeConfig($config[self::CONFIG_KEY] ?? 'flyim');
        $identifier = strtolower($identifier);
        foreach ($value === '' ? [] : explode("\n", $value) as $keyword) {
            if (str_contains($identifier, $keyword)) return true;
        }
        return false;
    }
}
