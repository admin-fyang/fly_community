<?php

declare(strict_types=1);

namespace app\Modules\System\Application;

use app\exception\BusinessException;
use DOMDocument;
use DOMElement;

/** 清理管理员富文本，阻止脚本、事件属性和危险链接进入公开客户端内容。 */
final class HtmlContentSanitizer
{
    /** 返回仅包含排版语义的安全HTML。 */
    public function sanitize(string $html): string
    {
        $html = trim($html);
        if ($html === '' || mb_strlen($html) > 500000) {
            throw new BusinessException('SYSTEM_CONTENT_INVALID', '富文本内容不能为空且不能超过50万字符', 422);
        }
        $allowed = '<p><br><h1><h2><h3><h4><blockquote><strong><b><em><i><u><s><ul><ol><li><a><code><pre><hr><table><thead><tbody><tr><th><td><span><div>';
        $clean = strip_tags(preg_replace('#<(script|style)[^>]*>.*?</\1>#is', '', $html) ?? '', $allowed);
        $document = new DOMDocument('1.0', 'UTF-8');
        $previous = libxml_use_internal_errors(true);
        $document->loadHTML('<?xml encoding="UTF-8"><div id="root">'.$clean.'</div>', LIBXML_HTML_NOIMPLIED | LIBXML_HTML_NODEFDTD);
        libxml_clear_errors();
        libxml_use_internal_errors($previous);
        // 必须在属性白名单清理前保存根节点引用，因为内部定位用的 id 不属于业务HTML白名单。
        $root = $document->getElementById('root');
        if (!$root) throw new BusinessException('SYSTEM_CONTENT_INVALID', '富文本内容无法解析', 422);
        foreach ($document->getElementsByTagName('*') as $element) {
            if (!$element instanceof DOMElement) continue;
            foreach (iterator_to_array($element->attributes) as $attribute) {
                $name = strtolower($attribute->name);
                if (!in_array($name, ['href','target','rel','colspan','rowspan'], true)) {
                    $element->removeAttribute($attribute->name);
                }
            }
            if ($element->hasAttribute('href')) {
                $href = trim($element->getAttribute('href'));
                if (preg_match('#^(https?://|mailto:|tel:|/)#i', $href) !== 1) $element->removeAttribute('href');
                else {
                    $element->setAttribute('target', '_blank');
                    $element->setAttribute('rel', 'noopener noreferrer');
                }
            }
        }
        $result = '';
        foreach ($root->childNodes as $node) $result .= $document->saveHTML($node);
        return trim($result);
    }
}
