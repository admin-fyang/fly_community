<?php

declare(strict_types=1);

namespace app\enum;

/**
 * IM消息类型。
 */
enum MessageType: string
{
    /** 文本消息。 */
    case Text = 'text';

    /** 图片消息。 */
    case Image = 'image';

    /** 文件消息。 */
    case File = 'file';

    /**
     * 判断消息是否必须绑定文件附件。
     */
    public function requiresAttachment(): bool
    {
        return match ($this) {
            self::Image, self::File => true,
            default => false,
        };
    }
}
