<?php

declare(strict_types=1);

namespace app\Support\Link;

use app\exception\BusinessException;

/**
 * 用户与群聊公开路径、URL及搜索输入解析服务。
 */
final class PublicLinkService
{
    /**
     * 注入公开链接域名。
     */
    public function __construct(
        private readonly string $baseUrl,
    ) {
    }

    /**
     * 返回用户资料路径。
     */
    public function userPath(string $username): string
    {
        return '/u/' . $username;
    }

    /**
     * 返回用户资料完整URL。
     */
    public function userUrl(string $username): string
    {
        return $this->url($this->userPath($username));
    }

    /**
     * 返回群聊邀请路径。
     */
    public function groupPath(string $slug): string
    {
        return '/g/' . strtolower(str_starts_with($slug, '/g/') ? substr($slug, 3) : $slug);
    }

    /**
     * 返回群聊邀请完整URL。
     */
    public function groupUrl(string $slug): string
    {
        return $this->url($this->groupPath($slug));
    }

    /**
     * 将本站静态资源路径转换为客户端可直接访问的完整URL。
     */
    public function assetUrl(string $path): string
    {
        if (filter_var($path, FILTER_VALIDATE_URL) !== false) {
            return $path;
        }
        return $this->url('/' . ltrim($path, '/'));
    }

    /**
     * 从用户名、用户Path或完整URL中解析用户名。
     */
    public function usernameFromSearch(string $input): ?string
    {
        $parsed = $this->parseSearch($input, 'user');
        return $parsed['kind'] === 'identifier' ? $parsed['value'] : null;
    }

    /**
     * 从Slug、群Path或完整URL中解析群Slug。
     */
    public function groupSlugFromSearch(string $input): ?string
    {
        $parsed = $this->parseSearch($input, 'group');
        return $parsed['kind'] === 'identifier' ? $parsed['value'] : null;
    }

    /**
     * 统一搜索语义：普通文本只匹配名称，显式标识必须合法且类型一致。
     * 完整链接必须同源，不接受认证信息、查询参数、片段或编码路径。
     * @return array{kind: string, value: string}
     */
    public function parseSearch(string $input, string $type): array
    {
        $value = preg_replace('/^[\s\p{Z}]+|[\s\p{Z}]+$/u', '', $input) ?? '';
        $invalid = ['kind' => 'invalid', 'value' => ''];
        if ($value === '') return $invalid;
        if (preg_match('~^[a-zA-Z][a-zA-Z0-9+.-]*:~', $value)) {
            $base = parse_url($this->baseUrl);
            $url = parse_url($value);
            if (!is_array($base) || !is_array($url)
                || !in_array(strtolower($url['scheme'] ?? ''), ['http', 'https'], true)
                || strtolower($base['scheme'] ?? '') !== strtolower($url['scheme'] ?? '')
                || strtolower($base['host'] ?? '') !== strtolower($url['host'] ?? '')
                || ($base['port'] ?? (strtolower($base['scheme'] ?? '') === 'https' ? 443 : 80)) !== ($url['port'] ?? (strtolower($url['scheme'] ?? '') === 'https' ? 443 : 80))
                || isset($url['user'], $url['pass']) || isset($url['user']) || isset($url['query']) || isset($url['fragment'])) return $invalid;
            $value = $url['path'] ?? '';
            if (!str_starts_with($value, '/')) return $invalid;
        }
        if (str_starts_with($value, '/')) {
            $prefix = $type === 'user' ? '/u/' : '/g/';
            if (!str_starts_with($value, $prefix)) return $invalid;
            $value = substr($value, 3);
        } elseif (str_starts_with($value, '@')) {
            $value = substr($value, 1);
        } else {
            return ['kind' => 'name', 'value' => $value];
        }
        $pattern = $type === 'user' ? '/^[a-zA-Z][a-zA-Z0-9_]{4,31}$/D' : '/^[a-zA-Z0-9_]{1,64}$/D';
        return preg_match($pattern, $value) === 1
            ? ['kind' => 'identifier', 'value' => strtolower($value)] : $invalid;
    }

    /**
     * 拼接公开域名和资源路径。
     */
    private function url(string $path): string
    {
        $baseUrl = rtrim(trim($this->baseUrl), '/');
        if ($baseUrl === '') {
            throw new BusinessException('PUBLIC_LINK_URL_NOT_CONFIGURED', '公开链接域名未配置', 500);
        }

        return $baseUrl . $path;
    }

}
