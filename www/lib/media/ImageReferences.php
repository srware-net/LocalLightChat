<?php
declare(strict_types=1);

namespace LLC\Media;

final class ImageReferences
{
    public static function refForPosition(int $messageIndex, int $imageIndex): string
    {
        return 'img_m' . ($messageIndex + 1) . '_' . ($imageIndex + 1);
    }

    public static function available(array $messages): array
    {
        $refs = [];
        foreach ($messages as $mi => $message) {
            if (!is_array($message)) continue;
            foreach (self::attachments($message) as $ii => $_) {
                $refs[] = self::refForPosition((int)$mi, (int)$ii);
            }
        }
        return $refs;
    }

    public static function resolve(array $messages, array $refs): array
    {
        $wanted = [];
        foreach ($refs as $ref) {
            $value = trim((string)$ref);
            if ($value !== '') $wanted[] = $value;
        }
        if (!$wanted) return [];

        $map = [];
        foreach ($messages as $mi => $message) {
            if (!is_array($message)) continue;
            foreach (self::attachments($message) as $ii => $attachment) {
                $map[self::refForPosition((int)$mi, (int)$ii)] = $attachment;
            }
        }

        $out = [];
        foreach ($wanted as $ref) {
            if (!isset($map[$ref]) || !is_array($map[$ref])) {
                throw new \RuntimeException('image_edit: unknown image reference ' . $ref . '. Available: ' . implode(', ', array_keys($map)));
            }
            $out[] = $map[$ref];
        }
        return $out;
    }

    public static function inventoryLines(array $messages, int $maxWords = 10): array
    {
        $lines = [];
        foreach ($messages as $mi => $message) {
            if (!is_array($message)) continue;
            $role = strtolower(trim((string)($message['role'] ?? '')));
            $images = self::attachments($message);
            if (!$images) continue;

            $ownExcerpt = self::excerptFromContent($message['content'] ?? '', $maxWords);
            $previousUserExcerpt = $role === 'assistant'
                ? self::previousUserExcerpt($messages, (int)$mi, $maxWords)
                : '';

            foreach ($images as $ii => $attachment) {
                if (!is_array($attachment)) continue;
                $ref = self::refForPosition((int)$mi, (int)$ii);
                $messageNo = (int)$mi + 1;
                $generated = !empty($attachment['generated']);

                if ($role === 'user') {
                    $source = 'user upload from message ' . $messageNo;
                    $contextLabel = 'msg begins';
                    $excerpt = $ownExcerpt;
                } elseif ($role === 'assistant' && $generated) {
                    $source = 'assistant-generated image from message ' . $messageNo;
                    if ($previousUserExcerpt !== '') {
                        $contextLabel = 'preceding user request';
                        $excerpt = $previousUserExcerpt;
                    } else {
                        $contextLabel = 'msg begins';
                        $excerpt = $ownExcerpt;
                    }
                } elseif ($role === 'assistant') {
                    $source = 'assistant image from message ' . $messageNo;
                    $contextLabel = 'msg begins';
                    $excerpt = $ownExcerpt;
                } else {
                    $source = ($role !== '' ? $role : 'chat') . ' image from message ' . $messageNo;
                    $contextLabel = 'msg begins';
                    $excerpt = $ownExcerpt;
                }

                $line = $ref . ' — ' . $source;
                if ($excerpt !== '') $line .= ' — ' . $contextLabel . ': "' . str_replace('"', '\\"', $excerpt) . '"';
                $lines[] = $line;
            }
        }
        return $lines;
    }

    public static function attachments(array $message): array
    {
        $out = [];
        $attachments = $message['attachments'] ?? [];
        if (is_array($attachments)) {
            foreach ($attachments as $attachment) {
                if (!is_array($attachment) || (string)($attachment['type'] ?? '') !== 'image') continue;
                $out[] = $attachment;
            }
        }
        if ($out) return $out;

        $content = $message['content'] ?? null;
        if (!is_array($content)) return [];
        $index = 0;
        foreach ($content as $part) {
            if (!is_array($part) || (string)($part['type'] ?? '') !== 'image_url') continue;
            $imageUrl = $part['image_url'] ?? null;
            $url = is_array($imageUrl) ? (string)($imageUrl['url'] ?? '') : (string)$imageUrl;
            if ($url === '') continue;
            $index++;
            $attachment = ['type'=>'image', 'name'=>'image_' . $index . '.png'];
            if (str_starts_with($url, 'data:image/')) $attachment['data_url'] = $url;
            else $attachment['url'] = $url;
            $out[] = $attachment;
        }
        return $out;
    }

    private static function previousUserExcerpt(array $messages, int $beforeIndex, int $maxWords): string
    {
        for ($i = $beforeIndex - 1; $i >= 0; $i--) {
            $message = $messages[$i] ?? null;
            if (!is_array($message) || (string)($message['role'] ?? '') !== 'user') continue;
            $excerpt = self::excerptFromContent($message['content'] ?? '', $maxWords);
            if ($excerpt !== '') return $excerpt;
        }
        return '';
    }

    private static function excerptFromContent($content, int $maxWords): string
    {
        $text = '';
        if (is_string($content)) {
            $text = $content;
        } elseif (is_array($content)) {
            $chunks = [];
            foreach ($content as $part) {
                if (!is_array($part)) continue;
                $type = (string)($part['type'] ?? '');
                if (in_array($type, ['text','input_text'], true) && isset($part['text']) && is_string($part['text'])) $chunks[] = $part['text'];
            }
            $text = implode(' ', $chunks);
        }
        $text = trim($text);
        if ($text === '') return '';

        $text = preg_replace('~!\[[^\]]*\]\([^)]*\)~u', ' ', $text) ?? $text;
        $text = preg_replace('~https?://\S+~iu', ' ', $text) ?? $text;
        $text = str_replace(['```json','```JSON','```'], ' ', $text);

        $trimmed = trim($text);
        if ($trimmed !== '' && $trimmed[0] === '{') {
            $decoded = json_decode($trimmed, true);
            if (is_array($decoded)) {
                foreach (['message','content','thought'] as $key) {
                    if (isset($decoded[$key]) && is_string($decoded[$key]) && trim($decoded[$key]) !== '') {
                        $text = $decoded[$key];
                        break;
                    }
                }
            }
        }

        $text = strip_tags($text);
        $text = preg_replace('/[\r\n\t]+/u', ' ', $text) ?? $text;
        $text = preg_replace('/\s+/u', ' ', $text) ?? $text;
        $text = trim($text, " \t\n\r\0\x0B\"'`{}[]");
        if ($text === '') return '';

        $words = preg_split('/\s+/u', $text, -1, PREG_SPLIT_NO_EMPTY);
        if (!is_array($words) || !$words) return '';
        $maxWords = max(1, min(20, $maxWords));
        $clipped = array_slice($words, 0, $maxWords);
        $out = implode(' ', $clipped);
        if (count($words) > $maxWords) $out .= '…';
        if (function_exists('mb_strlen') && mb_strlen($out, 'UTF-8') > 180) {
            $out = mb_substr($out, 0, 177, 'UTF-8') . '…';
        } elseif (strlen($out) > 180) {
            $out = substr($out, 0, 177) . '…';
        }
        return $out;
    }
}
