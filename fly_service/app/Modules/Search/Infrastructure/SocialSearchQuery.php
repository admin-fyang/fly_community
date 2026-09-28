<?php

declare(strict_types=1);

namespace app\Modules\Search\Infrastructure;

use app\Support\Link\PublicLinkService;

/**
 * 社区版用户公开搜索条件；用户名和昵称遵循统一的公开标识解析规则。
 */
final class SocialSearchQuery
{
    public function __construct(private readonly PublicLinkService $links)
    {
    }

    /** 增加用户查询条件；无效公开标识返回空结果，不回退模糊名称。 */
    public function user($query, string $input, string $alias = 'app_user'): void
    {
        $parsed = $this->links->parseSearch($input, 'user');
        $prefix = $alias === '' ? '' : $alias . '.';
        $query->where(function ($where) use ($parsed, $prefix): void {
            if ($parsed['kind'] === 'invalid') {
                $where->whereRaw('1 = 0');
                return;
            }
            $value = $parsed['value'];
            if ($parsed['kind'] === 'identifier') {
                $where->where($prefix . 'username', $value);
                return;
            }
            $column = $prefix . 'name';
            // 索引等值条件先缩小候选集，二进制比较保持大小写和尾部空格语义。
            $wrapped = $where->getConnection()->getQueryGrammar()->wrap($column);
            $where->where($column, $value)
                ->whereRaw("CAST($wrapped AS BINARY) = CAST(? AS BINARY)", [$value]);
        });
    }
}
