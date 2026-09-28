<?php

declare(strict_types=1);

namespace app\enum;

/**
 * IM消息附件类型。
 */
enum AttachmentType: string
{
    /** 图片附件。 */
    case Image = 'image';

    /** 普通文件附件。 */
    case File = 'file';
}
