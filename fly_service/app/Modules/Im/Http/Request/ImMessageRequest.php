<?php

declare(strict_types=1);

namespace app\Modules\Im\Http\Request;

use app\enum\MessageType;
use app\exception\ValidationException;
use support\Request;

/**
 * IM消息请求解析器。
 */
final class ImMessageRequest
{
    /**
     * 解析发送文本消息请求。
     *
     * @param Request $request HTTP请求对象
     * @return array<string,mixed>
     */
    public function parseSendMessage(Request $request): array
    {
        $data = $this->body($request);
        $messageType = MessageType::tryFrom((string)($data['message_type'] ?? MessageType::Text->value));
        if (!$messageType instanceof MessageType) {
            throw new ValidationException('不支持该消息类型');
        }
        // 社区版发送入口只接受文本、图片和文件；表情作为文本消息传输。
        if (!in_array($messageType, [MessageType::Text, MessageType::Image, MessageType::File], true)) {
            throw new ValidationException('社区版仅支持文本、图片和文件消息');
        }
        $bodyText = $this->optionalText($data, 'body_text', '消息正文', 4000);
        $attachments = $this->attachments($data['attachments'] ?? [], $messageType);

        if ($messageType === MessageType::Text && $bodyText === null) {
            throw new ValidationException('文本消息正文不能为空');
        }
        foreach (['location', 'contact_card', 'group_card', 'live_call_id', 'mention_all', 'mention_user_ids'] as $unsupportedField) {
            if (array_key_exists($unsupportedField, $data) && $data[$unsupportedField] !== null && $data[$unsupportedField] !== false && $data[$unsupportedField] !== []) {
                throw new ValidationException('社区版不支持该消息字段：' . $unsupportedField);
            }
        }

        return [
            'conversation_id' => $this->requiredPositiveInt($data, 'conversation_id', '会话ID'),
            'client_msg_id' => $this->requiredString($data, 'client_msg_id', '客户端消息ID', 64),
            'message_type' => $messageType,
            'body_text' => $bodyText,
            'reply_message_id' => $this->optionalPositiveInt($data['reply_message_id'] ?? null, '引用消息ID'),
            'attachments' => $attachments,
        ];
    }

    /** @param array<string,mixed> $data */
    public function parseResolveSingleConversation(Request $request): array
    {
        return [
            'target_user_id' => $this->requiredPositiveInt($this->body($request), 'target_user_id', '目标用户ID'),
        ];
    }

    /** 解析单聊会话列表分页参数。 */
    public function parseConversationList(Request $request): array
    {
        return [
            'limit' => $this->optionalLimit($request->get('limit')),
            'before_update_time' => $this->optionalPositiveInt($request->get('before_update_time'), '分页更新时间'),
            'before_conversation_id' => $this->optionalPositiveInt($request->get('before_conversation_id'), '分页会话ID'),
        ];
    }

    /**
     * 解析消息历史请求。
     *
     * @param Request $request HTTP请求对象
     * @return array{conversation_id:int,limit:int,before_seq:int|null}
     */
    public function parseMessageHistory(Request $request, string $conversationId): array
    {
        return [
            'conversation_id' => $this->requiredPositiveInt(['conversation_id' => $conversationId], 'conversation_id', '会话ID'),
            'limit' => $this->optionalLimit($request->get('limit')),
            'before_seq' => $this->optionalPositiveInt($request->get('before_seq'), '分页消息序号'),
        ];
    }

    /**
     * 解析用户事件增量同步请求。
     *
     * @param Request $request HTTP请求对象
     * @return array{after_event_id:int,limit:int}
     */
    public function parseSync(Request $request): array
    {
        return [
            'after_event_id' => $this->requiredNonNegativeInt($request->get('after_event_id'), '同步事件游标'),
            'limit' => $this->optionalLimit($request->get('limit'), 200, 500),
        ];
    }

    /**
     * 解析设备同步ACK请求。
     *
     * @return array{device_id:string,last_ack_event_id:int}
     */
    public function parseSyncAck(Request $request): array
    {
        $data = $this->body($request);

        return [
            'device_id' => $this->requiredUuid($data['device_id'] ?? null, '设备ID'),
            'last_ack_event_id' => $this->requiredNonNegativeInt(
                $data['last_ack_event_id'] ?? null,
                '最后确认事件ID',
            ),
        ];
    }

    /**
     * 解析会话已读游标请求。
     *
     * @return array{conversation_id:int,seq:int}
     */
    public function parseReceipt(Request $request, string $conversationId): array
    {
        $data = $this->body($request);

        return [
            'conversation_id' => $this->requiredPositiveInt(
                ['conversation_id' => $conversationId],
                'conversation_id',
                '会话ID',
            ),
            'seq' => $this->requiredPositiveInt($data, 'seq', '消息序号'),
        ];
    }

    /**
     * 解析撤回消息请求。
     *
     * @return array{message_id:int,reason:string|null}
     */
    public function parseRecall(Request $request, string $messageId): array
    {
        $data = $this->body($request);

        return [
            'message_id' => $this->requiredPositiveInt(
                ['message_id' => $messageId],
                'message_id',
                '消息ID',
            ),
            'reason' => $this->optionalString($data, 'reason', '撤回原因', 128),
        ];
    }

    /**
     * 解析消息路径ID。
     */
    public function parseMessageId(string $messageId): int
    {
        return $this->requiredPositiveInt(['message_id' => $messageId], 'message_id', '消息ID');
    }

    /**
     * 解析清空或删除会话使用的二选一定位参数。
     *
     * @return array{conversation_id:int|null,conversation_type:ConversationType|null,conversation_object_id:int|null}
     */
    public function parseConversationLocator(Request $request): array
    {
        $data = $this->body($request);
        $hasConversationId = array_key_exists('conversation_id', $data)
            && $data['conversation_id'] !== null
            && $data['conversation_id'] !== '';
        $hasConversationType = array_key_exists('conversation_type', $data)
            && $data['conversation_type'] !== null
            && $data['conversation_type'] !== '';
        $hasObjectId = array_key_exists('conversation_object_id', $data)
            && $data['conversation_object_id'] !== null
            && $data['conversation_object_id'] !== '';

        if ($hasConversationId && ($hasConversationType || $hasObjectId)) {
            throw new ValidationException('conversation_id与会话对象定位参数不能同时传递');
        }
        if ($hasConversationId) {
            return [
                'conversation_id' => $this->requiredPositiveInt($data, 'conversation_id', '会话ID'),
                'conversation_type' => null,
                'conversation_object_id' => null,
            ];
        }
        if (!$hasConversationType || !$hasObjectId) {
            throw new ValidationException('必须传递conversation_id，或同时传递conversation_type和conversation_object_id');
        }

        $conversationType = match ((string)$data['conversation_type']) {
            'single' => ConversationType::Single,
            default => throw new ValidationException('conversation_type仅支持single'),
        };

        return [
            'conversation_id' => null,
            'conversation_type' => $conversationType,
            'conversation_object_id' => $this->requiredPositiveInt(
                $data,
                'conversation_object_id',
                '会话对象ID',
            ),
        ];
    }

    /**
     * 解析批量清空或删除会话请求。
     *
     * @return array{conversation_ids:list<int>}
     */
    private function body(Request $request): array
    {
        $data = $request->post();
        if ($data !== []) {
            return $data;
        }

        $json = $request->rawBody();
        if ($json === '') {
            return [];
        }

        $decoded = json_decode($json, true);
        if (!is_array($decoded)) {
            throw new ValidationException('请求体必须是合法JSON对象');
        }

        return $decoded;
    }

    /**
     * 读取并去重1到100个批量会话ID。
     *
     * @param array<string,mixed> $data 请求数据
     * @return list<int>
     */
    private function requiredPositiveInt(array $data, string $key, string $label): int
    {
        if (!array_key_exists($key, $data)) {
            throw new ValidationException($label . '不能为空');
        }

        $value = $data[$key];
        if (!is_int($value) && !(is_string($value) && ctype_digit($value))) {
            throw new ValidationException($label . '必须是正整数');
        }

        $integer = (int)$value;
        if ($integer <= 0 || (string)$integer !== (string)$value) {
            throw new ValidationException($label . '必须是正整数');
        }

        return $integer;
    }

    /**
     * 读取必填字符串。
     *
     * @param array<string,mixed> $data 请求数据
     * @param string $key 字段名
     * @param string $label 中文字段名
     * @param int $maxLength 最大长度
     * @return string
     */
    private function requiredString(array $data, string $key, string $label, int $maxLength): string
    {
        if (!array_key_exists($key, $data)) {
            throw new ValidationException($label . '不能为空');
        }

        $value = trim((string)$data[$key]);
        if ($value === '') {
            throw new ValidationException($label . '不能为空');
        }

        if (mb_strlen($value, 'UTF-8') > $maxLength) {
            throw new ValidationException($label . '不能超过' . $maxLength . '个字符');
        }

        return $value;
    }

    /**
     * 读取可选字符串。
     *
     * @param array<string,mixed> $data 请求数据
     */
    private function optionalString(array $data, string $key, string $label, int $maxLength): ?string
    {
        if (!array_key_exists($key, $data) || $data[$key] === null || $data[$key] === '') {
            return null;
        }

        return $this->requiredString($data, $key, $label, $maxLength);
    }

    /**
     * 读取可选正文并保留用户输入内容。
     */
    private function optionalText(array $data, string $key, string $label, int $maxLength): ?string
    {
        if (!array_key_exists($key, $data) || $data[$key] === null || $data[$key] === '') {
            return null;
        }
        if (!is_string($data[$key]) || mb_strlen($data[$key], 'UTF-8') > $maxLength) {
            throw new ValidationException($label . '格式不正确或超过' . $maxLength . '个字符');
        }

        return $data[$key];
    }

    /**
     * 校验富媒体附件列表。
     *
     * @return list<array<string,mixed>>
     */
    private function attachments(mixed $value, MessageType $messageType): array
    {
        if (!$messageType->requiresAttachment()) {
            if ($value !== [] && $value !== null) {
                throw new ValidationException('文本消息不能携带附件');
            }
            return [];
        }
        if (!is_array($value) || $value === [] || !array_is_list($value)) {
            throw new ValidationException('附件消息必须提供attachments数组');
        }
        $maximum = $messageType === MessageType::Image ? 9 : 1;
        if (count($value) > $maximum) {
            throw new ValidationException('当前消息类型附件数量不能超过' . $maximum);
        }

        $result = [];
        foreach ($value as $index => $attachment) {
            if (!is_array($attachment)) {
                throw new ValidationException('附件格式不正确');
            }
            $resourceId = strtolower(trim((string)($attachment['resource_id'] ?? '')));
            if (preg_match('/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/', $resourceId) !== 1) {
                throw new ValidationException('附件resource_id格式不正确');
            }
            $thumbnailResourceId = $attachment['thumbnail_resource_id'] ?? null;
            if ($thumbnailResourceId !== null) {
                $thumbnailResourceId = strtolower(trim((string)$thumbnailResourceId));
                if ($messageType !== MessageType::Image || preg_match('/^[0-9a-f-]{36}$/', $thumbnailResourceId) !== 1) {
                    throw new ValidationException('缩略图resource_id格式不正确');
                }
            }
            foreach (['duration_ms', 'waveform'] as $unsupportedField) {
                if (isset($attachment[$unsupportedField])) {
                    throw new ValidationException('社区版附件不支持' . $unsupportedField);
                }
            }
            $result[] = [
                'resource_id' => $resourceId,
                'thumbnail_resource_id' => $thumbnailResourceId,
                'width' => $this->optionalBoundedInt($attachment['width'] ?? null, '附件宽度', 1, 100000),
                'height' => $this->optionalBoundedInt($attachment['height'] ?? null, '附件高度', 1, 100000),
                'duration_ms' => null,
                'waveform' => null,
                'sort_order' => $index,
            ];
        }
        return $result;
    }

    /** 读取附件尺寸的可选范围整数。 */
    private function optionalBoundedInt(mixed $value, string $label, int $minimum, int $maximum): ?int
    {
        if ($value === null || $value === '') {
            return null;
        }
        if ((!is_int($value) && !is_string($value)) || !ctype_digit((string)$value)) {
            throw new ValidationException($label . '必须是整数');
        }
        $integer = (int)$value;
        if ($integer < $minimum || $integer > $maximum) {
            throw new ValidationException($label . '超出允许范围');
        }

        return $integer;
    }

    /**
     * 读取指定范围的坐标值。
     */
    private function optionalLimit(mixed $value, int $default = 20, int $maximum = 100): int
    {
        if ($value === null || $value === '') {
            return $default;
        }

        if (!is_string($value) && !is_int($value)) {
            throw new ValidationException('分页条数必须是正整数');
        }

        $limit = (int)$value;
        if ($limit <= 0 || $limit > $maximum || (string)$limit !== (string)$value) {
            throw new ValidationException('分页条数必须在1到' . $maximum . '之间');
        }

        return $limit;
    }

    /**
     * 读取可选正整数。
     *
     * @param mixed $value 输入值
     * @param string $label 中文字段名
     * @return int|null
     */
    private function optionalPositiveInt(mixed $value, string $label): ?int
    {
        if ($value === null || $value === '') {
            return null;
        }

        if (!is_string($value) && !is_int($value)) {
            throw new ValidationException($label . '必须是正整数');
        }

        $integer = (int)$value;
        if ($integer <= 0 || (string)$integer !== (string)$value) {
            throw new ValidationException($label . '必须是正整数');
        }

        return $integer;
    }

    /**
     * 读取必填非负整数。
     *
     * @param mixed $value 输入值
     * @param string $label 中文字段名
     * @return int
     */
    private function requiredNonNegativeInt(mixed $value, string $label): int
    {
        if (!is_string($value) && !is_int($value)) {
            throw new ValidationException($label . '必须是非负整数');
        }

        if ((string)$value === '' || !ctype_digit((string)$value)) {
            throw new ValidationException($label . '必须是非负整数');
        }

        $integer = (int)$value;
        if ($integer < 0 || (string)$integer !== (string)$value) {
            throw new ValidationException($label . '必须是非负整数');
        }

        return $integer;
    }

    /**
     * 读取必填UUID v4设备ID。
     *
     * @param mixed $value 输入值
     * @param string $label 中文字段名
     * @return string
     */
    private function requiredUuid(mixed $value, string $label): string
    {
        $uuid = strtolower(trim((string)$value));
        if (preg_match('/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/', $uuid) !== 1) {
            throw new ValidationException($label . '必须是有效的UUID v4');
        }

        return $uuid;
    }

}
