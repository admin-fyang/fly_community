<?php

declare(strict_types=1);

namespace app\Modules\Account\Http\Controller\Api\V1;

use app\Modules\Account\Application\RealtimeSessionService;
use app\Modules\Account\Domain\Repository\RealtimeDisconnector;
use Throwable;
use support\Request;
use support\Response;

/** 内部 Centrifugo 回调使用供应商协议，不套 App BaseResponse。 */
final class RealtimeSessionController
{
    /** 注入连接准入及续期应用服务。 */
    public function __construct(private readonly RealtimeSessionService $sessions, private readonly RealtimeDisconnector $disconnect)
    {
    }

    /** 返回受认证会话的订阅和短租期。 */
    public function connect(Request $request): Response
    {
        return $this->response($this->sessions->connect($request->post()));
    }

    /** 通过服务端登记校验续期，撤销后返回终止断连协议。 */
    public function refresh(Request $request): Response
    {
        $input = $request->post();
        $result = $this->sessions->refresh($input);
        if (isset($result['disconnect'])) {
            // v6.9.1 的 refresh 实现不消费 disconnect 字段；实际通过控制API发4501，再拒绝续期。
            // 应用服务的校验事务已经结束，此处没有持有会话行锁等待外部网络。
            $userId = filter_var($input['user'] ?? null, FILTER_VALIDATE_INT);
            if ($userId !== false && $userId > 0 && is_string($input['client'] ?? null)) {
                try {
                    $this->disconnect->disconnect($userId, $input['client']);
                } catch (Throwable) {
                    // 控制任务会继续重试；控制接口故障也不能通过延长租期继续授予访问权限。
                }
            }
            $result = ['result' => ['expired' => true]];
        }
        return $this->response($result);
    }

    /** 成功与拒绝均为 Centrifugo 协议响应，避免客户端获知内部异常。 */
    private function response(array $payload): Response
    {
        return new Response(200, ['Content-Type' => 'application/json'], json_encode($payload, JSON_THROW_ON_ERROR));
    }
}
