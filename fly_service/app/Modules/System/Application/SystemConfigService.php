<?php

declare(strict_types=1);

namespace app\Modules\System\Application;

use app\exception\BusinessException;
use app\Modules\System\Domain\Repository\SystemConfigRepository;
use DateTimeImmutable;
use DateTimeZone;
use support\Log;
use Throwable;

/** 客户端公开配置与服务端功能开关的唯一读取入口。 */
final class SystemConfigService
{
    /** @param array<string,mixed> $staticConfig 数据库不可用时的受控默认值 */
    public function __construct(
        private readonly array $staticConfig,
        private readonly ?SystemConfigRepository $repository = null,
    ) {}

    /** 读取 value_format=int 的配置，缺失、读取失败或格式错误时返回默认值。 */
    public function getInt(string $key, int $default): int
    {
        $value = $this->find($key, $default);
        return filter_var($value, FILTER_VALIDATE_INT) === false ? $default : (int)$value;
    }

    /** 读取 value_format=switch 的配置，只有 0、1 是有效值。 */
    public function getSwitch(string $key, bool $default = false): bool
    {
        $value = $this->find($key, $default);
        return in_array($value, [0, 1, '0', '1'], true) ? (int)$value === 1 : $default;
    }

    /** 读取 value_format=file 的配置。 */
    public function getFile(string $key, string $default): string
    {
        return $this->getStringValue($key, $default);
    }

    /** 读取 value_format=string 的配置。 */
    public function getString(string $key, string $default): string
    {
        return $this->getStringValue($key, $default);
    }

    /** 读取 value_format=timezones 的配置。 */
    public function getTimezones(string $key, string $default): string
    {
        return $this->getStringValue($key, $default);
    }

    /** 读取 value_format=text 的配置。 */
    public function getText(string $key, string $default): string
    {
        return $this->getStringValue($key, $default);
    }

    /** 读取 value_format=json 的配置；JSON 可以是对象、数组或标量。 */
    public function getJson(string $key, mixed $default): mixed
    {
        return $this->find($key, $default);
    }

    /** 返回客户端启动所需的公开配置。 @return array<string,mixed> */
    public function show(): array
    {
        $config = $this->publishedConfig();
        $timezone = new DateTimeZone((string)$config['timezone']);
        $now = new DateTimeImmutable('now', $timezone);
        $upload = $this->uploadPolicy($config);
        return [
            'app_name' => (string)$config['app_name'], 'logo_url' => (string)$config['logo_url'],
            'system_version' => (string)$config['system_version'], 'api_version' => 'v1',
            'config_version' => (int)$config['config_version'], 'open_upload' => (int)$upload['enabled'],
            'upload_max' => $upload['upload_max'], 'extensions' => $upload['extensions'], 'mime_types' => $upload['mime_types'],
            'timezone' => ['name' => $timezone->getName(), 'offset' => $now->format('P'), 'offset_seconds' => $timezone->getOffset($now)],
            'server_time' => $now->getTimestamp(), 'server_time_iso8601' => $now->format(DATE_RFC3339),
            'open_register' => (int)$this->enabled('open_register', $config),
            'phone_register_verification' => (int)$this->enabled('phone_register_verification', $config),
            'email_register_verification' => (int)$this->enabled('email_register_verification', $config),
            'invite_register' => (int)$this->enabled('invite_register', $config),
            'private_chat' => (int)$this->enabled('private_chat', $config),
            'open_add_friend' => (int)$this->enabled('open_add_friend', $config),
            /*'service_agreement_url' => $this->httpsUrl($config, 'service_agreement_url'),
            'privacy_policy_url' => $this->httpsUrl($config, 'privacy_policy_url'),*/
            // 'faq_url' => $this->httpsUrl($config, 'faq_url'),
            /*'content_pages' => [
                ['slug' => 'user-agreement', 'title' => '用户协议', 'api_path' => '/api/v1/system/content-pages/user-agreement'],
                ['slug' => 'privacy-policy', 'title' => '隐私政策', 'api_path' => '/api/v1/system/content-pages/privacy-policy'],
                ['slug' => 'third-party-sdk', 'title' => '第三方 SDK 清单', 'api_path' => '/api/v1/system/content-pages/third-party-sdk'],
                ['slug' => 'personal-information', 'title' => '个人信息收集清单', 'api_path' => '/api/v1/system/content-pages/personal-information'],
                ['slug' => 'minor-privacy', 'title' => '未成年人隐私保护规则', 'api_path' => '/api/v1/system/content-pages/minor-privacy'],
                ['slug' => 'community-guidelines', 'title' => '社区规范', 'api_path' => '/api/v1/system/content-pages/community-guidelines'],
            ],*/
            'user_agreement' => '/api/v1/system/content-pages/user-agreement',
            'privacy_policy' => '/api/v1/system/content-pages/privacy-policy',
            'third_party_sdk' => '/api/v1/system/content-pages/third-party-sdk',
            'personal_information' => '/api/v1/system/content-pages/personal-information',
            'minor_privacy' => '/api/v1/system/content-pages/minor-privacy',
            'community_guidelines' => '/api/v1/system/content-pages/community-guidelines',
        ];
    }

    /** 返回注册开关，供验证码和注册用例执行服务端强制校验。 @return array<string,bool> */
    public function registrationPolicy(): array
    {
        $config = $this->publishedConfig();
        return [
            'open_register' => $this->enabled('open_register', $config),
            'phone_register_verification' => $this->enabled('phone_register_verification', $config),
            'email_register_verification' => $this->enabled('email_register_verification', $config),
            'invite_register' => $this->enabled('invite_register', $config),
        ];
    }

    /** 单聊开关由公共配置统一控制。 */
    public function strangerPrivateChatEnabled(): bool
    {
        return $this->enabled('private_chat', $this->publishedConfig());
    }


    /** 返回聊天附件上传策略。 @return array{enabled:bool,upload_max:int,extensions:list<string>,mime_types:list<string>} */
    public function uploadPolicy(?array $config = null): array
    {
        $config ??= $this->publishedConfig();
        $maximum = (int)($config['upload_max'] ?? 0);
        if ($maximum < 1) throw new \UnexpectedValueException('系统上传配置无效');
        return ['enabled' => $this->enabled('open_upload', $config), 'upload_max' => $maximum,
            'extensions' => $this->lineList($config['extensions'] ?? ''), 'mime_types' => $this->lineList($config['mime_types'] ?? '')];
    }

    /** 合并全部已启用配置；数据库故障时使用代码内安全默认值并留下诊断日志。 @return array<string,mixed> */
    private function publishedConfig(): array
    {
        if ($this->repository === null) {
            return $this->staticConfig;
        }

        try {
            return array_replace($this->staticConfig, $this->repository->allEnabled());
        } catch (Throwable $exception) {
            Log::error('system_config.database_fallback', [
                'exception_class' => $exception::class,
            ]);
            return $this->staticConfig;
        }
    }

    /** 配置不存在时返回调用方提供的默认值。 */
    private function find(string $key, mixed $default): mixed
    {
        $config = $this->publishedConfig();
        return array_key_exists($key, $config) ? $config[$key] : $default;
    }

    /** file、string、timezones、text 在存储层都使用字符串表示。 */
    private function getStringValue(string $key, string $default): string
    {
        $value = $this->find($key, $default);
        return is_string($value) ? $value : $default;
    }

    /** 开关只接受0或1，错误配置按关闭处理。 @param array<string,mixed> $config */
    private function enabled(string $key, array $config): bool
    {
        return (int)($config[$key] ?? 0) === 1;
    }

    /** 将管理端每行一项的文本转成去空、去重且小写的列表。 @return list<string> */
    private function lineList(mixed $value): array
    {
        $lines = preg_split('/\R/u', is_string($value) ? $value : '') ?: [];
        return array_values(array_unique(array_filter(array_map(static fn(string $item): string => strtolower(trim($item)), $lines), static fn(string $item): bool => $item !== '')));
    }

    /** @param array<string,mixed> $config */
    private function httpsUrl(array $config, string $key): string
    {
        $value = (string)($config[$key] ?? '');
        if (filter_var($value, FILTER_VALIDATE_URL) === false || strtolower((string)parse_url($value, PHP_URL_SCHEME)) !== 'https') {
            throw new \UnexpectedValueException('公共内容URL必须为有效HTTPS地址');
        }
        return $value;
    }

    /** 空配置保留为空，其余值转换为整数。 */
    private function nullableInt(mixed $value): ?int
    {
        return $value === null || $value === '' ? null : (int)$value;
    }
}
