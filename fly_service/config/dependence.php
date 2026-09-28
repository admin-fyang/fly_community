<?php

declare(strict_types=1);

use app\Infrastructure\Persistence\IlluminateTransactionManager;
use app\Infrastructure\Redis\RedisClientFactory;
use app\middleware\ApiTraceLogMiddleware;
use app\middleware\AuthMiddleware;
use app\Modules\Account\Application\Service\ContactNormalizer;
use app\Modules\Account\Application\Service\ContactProtector;
use app\Modules\Account\Application\Service\PasswordHasher;
use app\Modules\Account\Application\Service\UsernamePolicy;
use app\Modules\Account\Application\Service\VerificationCodeGenerator;
use app\Modules\Account\Application\Service\VerificationCodeHasher;
use app\Modules\Account\Application\UseCase\AccountSecurityService;
use app\Modules\Account\Application\UseCase\LoginWithPassword;
use app\Modules\Account\Application\UseCase\LogoutCurrentSession;
use app\Modules\Account\Application\UseCase\RegisterUser;
use app\Modules\Account\Application\UseCase\SendVerificationCode;
use app\Modules\Account\Application\Query\UsernameAvailability;
use app\Modules\Account\Domain\Repository\AuthRepository;
use app\Modules\Account\Domain\Repository\LoginRateLimiter;
use app\Modules\Account\Domain\Repository\VerificationCodeRepository;
use app\Modules\Account\Domain\Service\AccessTokenIssuer;
use app\Modules\Account\Domain\Service\VerificationCodeSender;
use app\Modules\Account\Http\Controller\Api\V1\AccountSecurityController;
use app\Modules\Account\Http\Controller\Api\V1\LogoutController;
use app\Modules\Account\Http\Controller\Api\V1\PasswordLoginController;
use app\Modules\Account\Http\Controller\Api\V1\RegisterController;
use app\Modules\Account\Http\Controller\Api\V1\VerificationCodeController;
use app\Modules\Account\Http\Controller\Api\V1\UsernameAvailabilityController;
use app\Modules\Account\Http\Request\AccountSecurityRequest;
use app\Modules\Account\Http\Request\AuthRequestValidator;
use app\Modules\Account\Infrastructure\Persistence\Eloquent\Repository\EloquentAuthRepository;
use app\Modules\Account\Infrastructure\Redis\RedisLoginRateLimiter;
use app\Modules\Account\Infrastructure\Redis\RedisVerificationCodeRepository;
use app\Modules\Account\Infrastructure\Security\EdDsaJwtAccessTokenIssuer;
use app\Modules\Account\Infrastructure\Security\FixedVerificationCodeSender;
use app\Modules\Account\Infrastructure\Security\RefreshTokenFactory;
use app\Modules\Contact\Application\ContactService;
use app\Modules\Contact\Http\Controller\Api\V1\ContactController;
use app\Modules\Contact\Http\Request\ContactRequest;
use app\Modules\File\Application\FileUploadService;
use app\Modules\File\Http\Controller\Api\V1\FileUploadController;
use app\Modules\File\Http\Request\FileUploadRequest;
use app\Modules\Im\Application\ImDirectoryProjectionBuilder;
use app\Modules\Im\Application\ImDirectoryService;
use app\Modules\Im\Application\ImEventWriter;
use app\Modules\Im\Application\ImMessageService;
use app\Modules\Im\Application\ImMessageStateService;
use app\Modules\Im\Application\ImSyncService;
use app\Modules\Im\Application\OutboxPublisherService;
use app\Modules\Im\Domain\Service\CentrifugoPublisher;
use app\Modules\Im\Domain\Service\CentrifugoTokenIssuer;
use app\Modules\Im\Http\Controller\Api\V1\ImDirectoryController;
use app\Modules\Im\Http\Controller\Api\V1\ImMessageController;
use app\Modules\Im\Http\Request\ImDirectoryRequest;
use app\Modules\Im\Http\Request\ImMessageRequest;
use app\Modules\Im\Infrastructure\Provider\HttpCentrifugoPublisher;
use app\Modules\Im\Infrastructure\Security\HmacCentrifugoTokenIssuer;
use app\Modules\Notification\Application\NotificationService;
use app\Modules\Notification\Http\Controller\Api\V1\NotificationController;
use app\Modules\Notification\Http\Request\NotificationRequest;
use app\Modules\System\Application\HtmlContentSanitizer;
use app\Modules\System\Application\PublicSystemContentService;
use app\Modules\System\Application\SystemConfigService;
use app\Modules\System\Application\TimezoneRegionCatalog;
use app\Modules\System\Domain\Repository\SystemConfigRepository;
use app\Modules\System\Http\Controller\Api\V1\SystemConfigController;
use app\Modules\System\Http\Controller\Api\V1\SystemContentController;
use app\Modules\System\Infrastructure\Redis\CachedSystemConfigRepository;
use app\Modules\User\Application\UserProfileService;
use app\Modules\User\Domain\Service\UserPresence;
use app\Modules\User\Http\Controller\Api\V1\UserProfileController;
use app\Modules\User\Http\Request\UserProfileRequest;
use app\Modules\User\Infrastructure\Redis\RedisUserPresence;
use app\Support\Id\IdGenerator;
use app\Support\Link\PublicLinkService;
use app\Support\Transaction\TransactionManager;
use app\utils\RustfsUtils;
use GuzzleHttp\Client as GuzzleClient;
use libphonenumber\PhoneNumberUtil;
use Predis\Client;
use Psr\Container\ContainerInterface;
use support\Log;


return [
    \app\Modules\Account\Domain\Repository\SessionSnapshotStore::class => static fn(ContainerInterface $c) => new \app\Modules\Account\Infrastructure\Redis\RedisSessionSnapshotStore(
        $c->get(Client::class), config('device_sessions.snapshot_ttl_seconds'), config('device_sessions.requests_per_minute'),
    ),
    \app\Modules\Account\Application\DeviceSessionService::class => static fn(ContainerInterface $c) => new \app\Modules\Account\Application\DeviceSessionService(
        $c->get(\app\Modules\Account\Domain\Repository\SessionSnapshotStore::class), config('device_sessions.snapshot_max_sessions'),
    ),
    \app\Modules\Account\Application\SessionRevocationService::class => static fn(ContainerInterface $c) => new \app\Modules\Account\Application\SessionRevocationService(
        $c->get(TransactionManager::class),
    ),
    \app\Modules\Account\Http\Request\DeviceSessionRequest::class => static fn() => new \app\Modules\Account\Http\Request\DeviceSessionRequest(),
    \app\Modules\Account\Http\Controller\Api\V1\DeviceSessionController::class => static fn(ContainerInterface $c) => new \app\Modules\Account\Http\Controller\Api\V1\DeviceSessionController(
        $c->get(\app\Modules\Account\Application\DeviceSessionService::class), $c->get(\app\Modules\Account\Application\SessionRevocationService::class),
        $c->get(\app\Modules\Account\Http\Request\DeviceSessionRequest::class), $c->get(\app\Modules\Account\Domain\Repository\SessionSnapshotStore::class),
    ),
    \app\Modules\Account\Application\RealtimeSessionService::class => static fn(ContainerInterface $c) => new \app\Modules\Account\Application\RealtimeSessionService(
        $c->get(TransactionManager::class), config('centrifugo.token_hmac_secret'), config('device_sessions.connection_check_seconds'), config('centrifugo.presence_shard_count'),
    ),
    \app\Modules\Account\Http\Controller\Api\V1\RealtimeSessionController::class => static fn(ContainerInterface $c) => new \app\Modules\Account\Http\Controller\Api\V1\RealtimeSessionController(
        $c->get(\app\Modules\Account\Application\RealtimeSessionService::class), $c->get(\app\Modules\Account\Domain\Repository\RealtimeDisconnector::class),
    ),
    \app\middleware\RealtimeProxyGuardMiddleware::class => static fn() => new \app\middleware\RealtimeProxyGuardMiddleware(
        config('device_sessions.proxy_secret'), config('device_sessions.realtime_proxy_enabled'),
    ),
    \app\Modules\Account\Domain\Repository\RealtimeDisconnector::class => static fn() => new \app\Modules\Account\Infrastructure\Provider\HttpRealtimeDisconnector(
        new GuzzleClient(), config('centrifugo.api_url'), config('centrifugo.api_key'),
    ),
    \app\Modules\Account\Application\SessionControlService::class => static fn(ContainerInterface $c) => new \app\Modules\Account\Application\SessionControlService(
        $c->get(\app\Modules\Account\Domain\Repository\RealtimeDisconnector::class),
    ),
    IdGenerator::class => static fn(): IdGenerator => new IdGenerator(),
    PhoneNumberUtil::class => static fn(): PhoneNumberUtil => PhoneNumberUtil::getInstance(),
    Client::class => static fn(): Client => (new RedisClientFactory())->create(config('redis')),
    SystemConfigRepository::class => static fn(ContainerInterface $container): SystemConfigRepository => new CachedSystemConfigRepository(
        $container->get(Client::class),
    ),

    TimezoneRegionCatalog::class => static fn(): TimezoneRegionCatalog => new TimezoneRegionCatalog(public_path('timezone_phone_regions_zh.json')),
    HtmlContentSanitizer::class => static fn(): HtmlContentSanitizer => new HtmlContentSanitizer(),
    ContactNormalizer::class => static fn(ContainerInterface $container): ContactNormalizer => new ContactNormalizer(
        $container->get(PhoneNumberUtil::class),
    ),
    ContactProtector::class => static fn(): ContactProtector => new ContactProtector(
        config('auth.contact_lookup_key'),
        config('auth.contact_encryption_key'),
    ),
    VerificationCodeHasher::class => static fn(): VerificationCodeHasher => new VerificationCodeHasher(
        config('auth.verification_code_key'),
    ),
    VerificationCodeGenerator::class => static fn(): VerificationCodeGenerator => new VerificationCodeGenerator(
        config('app.debug'),
        config('auth.verification.driver'),
        config('auth.verification.fixed_code'),
    ),
    PasswordHasher::class => static fn(): PasswordHasher => new PasswordHasher(),
    RefreshTokenFactory::class => static fn(ContainerInterface $container): RefreshTokenFactory => new RefreshTokenFactory(
        $container->get(IdGenerator::class),
        config('auth.refresh_token_key'),
        config('auth.refresh_ttl_seconds'),
    ),

    VerificationCodeRepository::class => static fn(ContainerInterface $container): VerificationCodeRepository => new RedisVerificationCodeRepository(
        $container->get(Client::class),
    ),
    LoginRateLimiter::class => static fn(ContainerInterface $container): LoginRateLimiter => new RedisLoginRateLimiter(
        $container->get(Client::class),
    ),
    VerificationCodeSender::class => static fn(): VerificationCodeSender => new FixedVerificationCodeSender(
        config('app.debug'),
    ),
    AccessTokenIssuer::class => static fn(ContainerInterface $container): AccessTokenIssuer => new EdDsaJwtAccessTokenIssuer(
        $container->get(IdGenerator::class),
        config('auth.jwt.private_key'),
        config('auth.jwt.key_id'),
        config('auth.jwt.issuer'),
        config('auth.jwt.audience'),
        config('auth.jwt.ttl_seconds'),
    ),
    TransactionManager::class => static fn(): TransactionManager => new IlluminateTransactionManager(),
    AuthRepository::class => static fn(ContainerInterface $container): AuthRepository => new EloquentAuthRepository(
        $container->get(IdGenerator::class),
        $container->get(RefreshTokenFactory::class),
    ),

    \app\Support\Identity\ReservedIdentifierPolicy::class => static fn(ContainerInterface $container): \app\Support\Identity\ReservedIdentifierPolicy => new \app\Support\Identity\ReservedIdentifierPolicy(
        $container->get(SystemConfigRepository::class),
    ),
    UsernamePolicy::class => static fn(ContainerInterface $container): UsernamePolicy => new UsernamePolicy(
        $container->get(\app\Support\Identity\ReservedIdentifierPolicy::class),
    ),
    UsernameAvailability::class => static fn(ContainerInterface $container): UsernameAvailability => new UsernameAvailability(
        $container->get(UsernamePolicy::class),
        $container->get(AuthRepository::class),
    ),

    SendVerificationCode::class => static fn(ContainerInterface $container): SendVerificationCode => new SendVerificationCode(
        $container->get(ContactNormalizer::class),
        $container->get(ContactProtector::class),
        $container->get(VerificationCodeGenerator::class),
        $container->get(VerificationCodeHasher::class),
        $container->get(VerificationCodeRepository::class),
        $container->get(VerificationCodeSender::class),
        $container->get(AuthRepository::class),
        $container->get(IdGenerator::class),
        config('auth.verification.ttl_seconds'),
        config('auth.verification.resend_seconds'),
        config('auth.verification.expose_code'),
        $container->get(SystemConfigService::class),
    ),
    RegisterUser::class => static fn(ContainerInterface $container): RegisterUser => new RegisterUser(
        $container->get(ContactNormalizer::class),
        $container->get(ContactProtector::class),
        $container->get(VerificationCodeHasher::class),
        $container->get(VerificationCodeRepository::class),
        $container->get(PasswordHasher::class),
        $container->get(UsernamePolicy::class),
        $container->get(AuthRepository::class),
        $container->get(TransactionManager::class),
        $container->get(AccessTokenIssuer::class),
        $container->get(IdGenerator::class),
        config('auth.verification.max_attempts'),
        $container->get(SystemConfigService::class),
    ),
    LoginWithPassword::class => static fn(ContainerInterface $container): LoginWithPassword => new LoginWithPassword(
        $container->get(ContactNormalizer::class),
        $container->get(ContactProtector::class),
        $container->get(PasswordHasher::class),
        $container->get(AuthRepository::class),
        $container->get(LoginRateLimiter::class),
        $container->get(TransactionManager::class),
        $container->get(AccessTokenIssuer::class),
    ),

    AuthRequestValidator::class => static fn(): AuthRequestValidator => new AuthRequestValidator(),
    VerificationCodeController::class => static fn(ContainerInterface $container): VerificationCodeController => new VerificationCodeController(
        $container->get(SendVerificationCode::class),
        $container->get(AuthRequestValidator::class),
    ),
    RegisterController::class => static fn(ContainerInterface $container): RegisterController => new RegisterController(
        $container->get(RegisterUser::class),
        $container->get(AuthRequestValidator::class),
    ),
    UsernameAvailabilityController::class => static fn(ContainerInterface $container): UsernameAvailabilityController => new UsernameAvailabilityController(
        $container->get(UsernameAvailability::class),
    ),
    PasswordLoginController::class => static fn(ContainerInterface $container): PasswordLoginController => new PasswordLoginController(
        $container->get(LoginWithPassword::class),
        $container->get(AuthRequestValidator::class),
    ),
    ApiTraceLogMiddleware::class => static fn(ContainerInterface $container): ApiTraceLogMiddleware => new ApiTraceLogMiddleware(
        $container->get(IdGenerator::class),
    ),
    AuthMiddleware::class => static fn(): AuthMiddleware => new AuthMiddleware(
        config('auth.jwt.public_key'),
        config('auth.jwt.issuer'),
        config('auth.jwt.audience'),
    ),
    LogoutCurrentSession::class => static fn(ContainerInterface $container): LogoutCurrentSession => new LogoutCurrentSession(
        $container->get(\app\Modules\Account\Application\SessionRevocationService::class),
    ),
    LogoutController::class => static fn(ContainerInterface $container): LogoutController => new LogoutController(
        $container->get(LogoutCurrentSession::class),
    ),
    \app\Modules\Search\Infrastructure\SocialSearchQuery::class => static fn(ContainerInterface $container): \app\Modules\Search\Infrastructure\SocialSearchQuery => new \app\Modules\Search\Infrastructure\SocialSearchQuery(
        $container->get(PublicLinkService::class),
        $container->get(ContactNormalizer::class),
        $container->get(ContactProtector::class),
    ),
    PublicLinkService::class => static fn(): PublicLinkService => new PublicLinkService(
        getenv('APP_URL'),
    ),
    SystemConfigService::class => static fn(ContainerInterface $container): SystemConfigService => new SystemConfigService(
        config('system'),
        $container->get(SystemConfigRepository::class),
    ),

    SystemConfigController::class => static fn(ContainerInterface $container): SystemConfigController => new SystemConfigController(
        $container->get(SystemConfigService::class),
    ),
    PublicSystemContentService::class => static fn(): PublicSystemContentService => new PublicSystemContentService(),
    SystemContentController::class => static fn(ContainerInterface $container): SystemContentController => new SystemContentController(
        $container->get(PublicSystemContentService::class),
    ),
    UserProfileService::class => static fn(ContainerInterface $container): UserProfileService => new UserProfileService(
        $container->get(PublicLinkService::class),
        $container->get(UsernamePolicy::class),
        $container->get(TransactionManager::class),
        $container->get(ImEventWriter::class),
    ),
    UserProfileRequest::class => static fn(): UserProfileRequest => new UserProfileRequest(),
    UserProfileController::class => static fn(ContainerInterface $container): UserProfileController => new UserProfileController(
        $container->get(UserProfileService::class),
        $container->get(UserProfileRequest::class),
    ),
    RustfsUtils::class => static fn(): RustfsUtils => new RustfsUtils(
        config('rustfs.endpoint'),
        config('rustfs.public_endpoint'),
        config('rustfs.access_key'),
        config('rustfs.secret_key'),
        config('rustfs.bucket'),
        config('rustfs.region'),
        config('rustfs.path_style'),
        config('rustfs.ssl_verify'),
        serverEndpoint: config('rustfs.server_endpoint'),
    ),
    FileUploadService::class => static fn(ContainerInterface $container): FileUploadService => new FileUploadService(
        $container->get(IdGenerator::class),
        $container->get(RustfsUtils::class),
        config('rustfs.bucket'),
        $container->get(SystemConfigService::class),
        $container->get(TransactionManager::class),
    ),
    FileUploadRequest::class => static fn(): FileUploadRequest => new FileUploadRequest(),
    FileUploadController::class => static fn(ContainerInterface $container): FileUploadController => new FileUploadController(
        $container->get(FileUploadService::class),
        $container->get(FileUploadRequest::class),
    ),

    AccountSecurityService::class => static fn(ContainerInterface $container): AccountSecurityService => new AccountSecurityService(
        $container->get(ContactNormalizer::class),
        $container->get(ContactProtector::class),
        $container->get(VerificationCodeHasher::class),
        $container->get(VerificationCodeRepository::class),
        $container->get(PasswordHasher::class),
        $container->get(AuthRepository::class),
        $container->get(TransactionManager::class),
        $container->get(IdGenerator::class),
        config('auth.verification.max_attempts'),
    ),
    AccountSecurityRequest::class => static fn(): AccountSecurityRequest => new AccountSecurityRequest(),
    AccountSecurityController::class => static fn(ContainerInterface $container): AccountSecurityController => new AccountSecurityController(
        $container->get(AccountSecurityService::class),
        $container->get(AccountSecurityRequest::class),
    ),
    ImEventWriter::class => static fn(): ImEventWriter => new ImEventWriter(),
    ImMessageService::class => static fn(ContainerInterface $container): ImMessageService => new ImMessageService(
        $container->get(TransactionManager::class),
        $container->get(ImEventWriter::class),
        $container->get(SystemConfigService::class),
    ),
    ImMessageStateService::class => static fn(ContainerInterface $container): ImMessageStateService => new ImMessageStateService(
        $container->get(TransactionManager::class),
        $container->get(ImEventWriter::class),
    ),
    ImSyncService::class => static fn(): ImSyncService => new ImSyncService(),
    CentrifugoTokenIssuer::class => static fn(): CentrifugoTokenIssuer => new HmacCentrifugoTokenIssuer(
        config('centrifugo.enabled'),
        config('centrifugo.token_hmac_secret'),
        config('centrifugo.token_ttl_seconds'),
        config('centrifugo.presence_shard_count'),
    ),
    CentrifugoPublisher::class => static fn(): CentrifugoPublisher => new HttpCentrifugoPublisher(
        new GuzzleClient(),
        config('centrifugo.enabled'),
        config('centrifugo.api_url'),
        config('centrifugo.api_key'),
        config('centrifugo.request_timeout_seconds'),
    ),
    UserPresence::class => static fn(ContainerInterface $container): UserPresence => new RedisUserPresence(
        $container->get(Client::class),
        config('centrifugo.presence_listener_stale_seconds'),
    ),
    OutboxPublisherService::class => static fn(ContainerInterface $container): OutboxPublisherService => new OutboxPublisherService(
        $container->get(CentrifugoPublisher::class),
        config('centrifugo.outbox_batch_size'),
        config('centrifugo.outbox_max_retries'),
        config('centrifugo.outbox_retry_base_seconds'),
        config('centrifugo.outbox_retry_max_seconds'),
        config('centrifugo.outbox_lock_seconds'),
    ),
    ImMessageRequest::class => static fn(): ImMessageRequest => new ImMessageRequest(),
    ImDirectoryRequest::class => static fn(): ImDirectoryRequest => new ImDirectoryRequest(),
    ImDirectoryProjectionBuilder::class => static fn(ContainerInterface $container): ImDirectoryProjectionBuilder => new ImDirectoryProjectionBuilder(
        $container->get(PublicLinkService::class),
    ),
    ImDirectoryService::class => static fn(ContainerInterface $container): ImDirectoryService => new ImDirectoryService(
        $container->get(ImDirectoryProjectionBuilder::class),
    ),
    ImDirectoryController::class => static fn(ContainerInterface $container): ImDirectoryController => new ImDirectoryController(
        $container->get(ImDirectoryService::class),
        $container->get(ImDirectoryRequest::class),
    ),
    ImMessageController::class => static fn(ContainerInterface $container): ImMessageController => new ImMessageController(
        $container->get(ImMessageService::class),
        $container->get(ImSyncService::class),
        $container->get(ImMessageStateService::class),
        $container->get(CentrifugoTokenIssuer::class),
        config('centrifugo.public_ws_url'),
        $container->get(ImMessageRequest::class),
    ),
    NotificationService::class => static fn(ContainerInterface $container): NotificationService => new NotificationService(
        $container->get(TransactionManager::class),
        $container->get(ImEventWriter::class),
        $container->get(ImDirectoryProjectionBuilder::class),
        $container->get(PublicLinkService::class),
    ),
    NotificationRequest::class => static fn(): NotificationRequest => new NotificationRequest(),
    NotificationController::class => static fn(ContainerInterface $container): NotificationController => new NotificationController(
        $container->get(NotificationService::class),
        $container->get(NotificationRequest::class),
    ),
    ContactService::class => static fn(ContainerInterface $container): ContactService => new ContactService(
        $container->get(TransactionManager::class),
        $container->get(ImEventWriter::class),
        $container->get(ImDirectoryProjectionBuilder::class),
        $container->get(PublicLinkService::class),
        $container->get(UserPresence::class),
        $container->get(SystemConfigService::class),
        $container->get(\app\Modules\Search\Infrastructure\SocialSearchQuery::class),
    ),
    ContactRequest::class => static fn(): ContactRequest => new ContactRequest(),
    ContactController::class => static fn(ContainerInterface $container): ContactController => new ContactController(
        $container->get(ContactService::class),
        $container->get(ContactRequest::class),
    ),
];
