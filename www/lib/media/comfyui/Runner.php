<?php
declare(strict_types=1);

namespace LLC\Media\ComfyUI;

final class Runner
{
    /**
     * Queue a workflow and wait until at least one image output is available.
     * WebSocket events drive live node/progress/error status; /history remains the
     * authoritative completion/output fallback when WebSocket delivery is absent.
     *
     * Options:
     *   cancel_meta_factory: callable(string $promptId): array
     *     Returns activity metadata such as cancel_action/cancel_job_id.
     *
     * @return array{prompt_id:string,images:array<int,array{filename:string,subfolder:string,type:string}>}
     */
    public static function runImages(
        string $base,
        array $workflow,
        int $timeoutSec,
        callable $sendStatus,
        string $queueLabel = 'Queueing ComfyUI workflow…',
        string $runningLabel = 'Running ComfyUI…',
        array $options = []
    ): array {
        $timeoutSec = max(30, min(3600, $timeoutSec));
        $sendStatus($queueLabel);

        $clientId = 'llc_' . bin2hex(random_bytes(12));
        // Best effort only. A failed WebSocket must never break generation; the
        // /history poll below remains the completion fallback.
        $ws = null;
        try {
            $ws = WebSocketClient::connect($base, $clientId, 3.0);
        } catch (\Throwable $e) {
            $ws = null;
        }

        $response = Client::json('POST', $base . '/prompt', ['prompt'=>$workflow, 'client_id'=>$clientId], 30);
        $promptId = (string)($response['prompt_id'] ?? '');
        if ($promptId === '') $promptId = (string)($response['number'] ?? '');
        if ($promptId === '') {
            $ws?->close();
            throw new \RuntimeException('ComfyUI: missing prompt_id in response');
        }

        $cancelMeta = [];
        $factory = $options['cancel_meta_factory'] ?? null;
        if (is_callable($factory)) {
            try {
                $made = $factory($promptId);
                if (is_array($made)) $cancelMeta = $made;
            } catch (\Throwable $e) {
                // Cancellation UI is optional; execution itself must continue.
            }
        }

        $emit = static function(string $title, ?float $progress = null, string $progressLabel = '') use ($sendStatus, &$cancelMeta): void {
            $meta = $cancelMeta;
            if ($progress !== null && is_finite($progress)) $meta['progress'] = max(0.0, min(1.0, $progress));
            if ($progressLabel !== '') $meta['progress_label'] = $progressLabel;
            $sendStatus($title, '', '', '', '', $meta);
        };

        // Replace the transient queueing label with a cancellable running activity
        // as soon as ComfyUI has assigned the prompt id.
        $emit($ws ? 'ComfyUI · Queued' : $runningLabel);

        $deadline = microtime(true) + (float)$timeoutSec;
        $lastFallbackStatusAt = microtime(true);
        $lastHistoryAt = 0.0;
        $lastLiveAt = 0.0;
        $lastUiEmitAt = 0.0;
        $lastEventSignature = '';
        $lastNodeId = '';
        $entry = null;

        try {
            while (microtime(true) < $deadline) {
                if (function_exists('connection_aborted') && \connection_aborted()) exit;

                // Drain a bounded number of WebSocket messages per pass so heavy
                // progress traffic cannot starve the /history completion poll.
                if ($ws && $ws->isOpen()) {
                    for ($i = 0; $i < 24; $i++) {
                        $message = $ws->readJson($i === 0 ? 0.12 : 0.0);
                        if (!is_array($message)) break;
                        $event = self::handleWsMessage($message, $workflow, $promptId, $lastNodeId);
                        if ($event === null) continue;
                        $lastLiveAt = microtime(true);
                        if (isset($event['node_id']) && (string)$event['node_id'] !== '') $lastNodeId = (string)$event['node_id'];
                        if (!empty($event['error'])) throw new \RuntimeException((string)$event['error']);
                        if (!empty($event['title'])) {
                            $eventTitle = (string)$event['title'];
                            $eventProgress = isset($event['progress']) ? (float)$event['progress'] : null;
                            $eventProgressLabel = (string)($event['progress_label'] ?? '');
                            $signature = $eventTitle . "\0" . ($eventProgress === null ? '' : number_format($eventProgress, 5, '.', '')) . "\0" . $eventProgressLabel;
                            $nowEmit = microtime(true);
                            $isProgressEvent = $eventProgress !== null;
                            if ($signature !== $lastEventSignature && (!$isProgressEvent || $nowEmit - $lastUiEmitAt >= 0.08 || $eventProgress >= 0.9999)) {
                                $emit($eventTitle, $eventProgress, $eventProgressLabel);
                                $lastEventSignature = $signature;
                                $lastUiEmitAt = $nowEmit;
                            }
                        }
                    }
                }

                $now = microtime(true);
                if ($now - $lastHistoryAt >= 0.75) {
                    $lastHistoryAt = $now;
                    try {
                        $history = Client::json('GET', $base . '/history/' . rawurlencode($promptId), null, 20);
                        $candidate = self::historyEntry($history, $promptId);
                        if ($candidate) {
                            $historyError = self::historyError($candidate, $workflow);
                            if ($historyError !== null) throw new \RuntimeException($historyError);
                            if (isset($candidate['outputs']) && is_array($candidate['outputs']) && self::hasImages($candidate['outputs'])) {
                                $entry = $candidate;
                                break;
                            }
                        }
                    } catch (\RuntimeException $e) {
                        // Execution errors detected from history are terminal; HTTP
                        // polling failures are not. Distinguish by our prefix.
                        if (str_starts_with($e->getMessage(), 'ComfyUI execution ')) throw $e;
                    } catch (\Throwable $e) {
                        // Temporary history failure: keep listening/polling.
                    }
                }

                // If no useful WebSocket event has arrived for a while, keep the
                // old generic heartbeat so reverse proxies and users both know the
                // request is alive.
                if ($now - max($lastLiveAt, $lastFallbackStatusAt) > 2.5) {
                    $emit($lastNodeId !== '' ? ('ComfyUI · ' . self::nodeLabel($workflow, $lastNodeId)) : $runningLabel);
                    $lastFallbackStatusAt = $now;
                }

                usleep(80000);
            }
        } finally {
            $ws?->close();
        }

        if (!is_array($entry) || !isset($entry['outputs']) || !is_array($entry['outputs'])) {
            throw new \RuntimeException('ComfyUI: timeout waiting for outputs (' . $timeoutSec . 's)');
        }

        $images = self::collectImages($entry['outputs']);
        if (!$images) throw new \RuntimeException('ComfyUI: no images in outputs');
        return ['prompt_id'=>$promptId, 'images'=>$images];
    }

    /** @return array<string,mixed>|null */
    private static function handleWsMessage(array $message, array $workflow, string $promptId, string $lastNodeId): ?array
    {
        $type = (string)($message['type'] ?? '');
        $data = $message['data'] ?? null;
        if (!is_array($data)) return null;

        $eventPromptId = trim((string)($data['prompt_id'] ?? ''));
        if ($eventPromptId !== '' && $eventPromptId !== $promptId) return null;

        if ($type === 'execution_start') {
            return ['title'=>'ComfyUI · Workflow started'];
        }

        if ($type === 'executing') {
            $nodeId = trim((string)($data['node'] ?? ''));
            if ($nodeId === '') return null;
            return [
                'title'=>'ComfyUI · ' . self::nodeLabel($workflow, $nodeId),
                'node_id'=>$nodeId,
            ];
        }

        if ($type === 'progress') {
            $nodeId = trim((string)($data['node'] ?? $lastNodeId));
            $value = is_numeric($data['value'] ?? null) ? (float)$data['value'] : null;
            $max = is_numeric($data['max'] ?? null) ? (float)$data['max'] : null;
            $progress = ($value !== null && $max !== null && $max > 0) ? ($value / $max) : null;
            $label = ($value !== null && $max !== null)
                ? self::formatProgressNumber($value) . ' / ' . self::formatProgressNumber($max)
                : '';
            return [
                'title'=>'ComfyUI · ' . self::nodeLabel($workflow, $nodeId),
                'node_id'=>$nodeId,
                'progress'=>$progress,
                'progress_label'=>$label,
            ];
        }

        if ($type === 'progress_state') {
            $nodes = $data['nodes'] ?? null;
            if (!is_array($nodes)) return null;
            $selected = null;
            foreach ($nodes as $nodeId => $state) {
                if (!is_array($state) || (string)($state['state'] ?? '') !== 'running') continue;
                $selected = [(string)$nodeId, $state];
                break;
            }
            if ($selected === null) return null;
            [$rawNodeId, $state] = $selected;
            $nodeId = trim((string)($state['display_node_id'] ?? $state['real_node_id'] ?? $state['node_id'] ?? $rawNodeId));
            $displayId = trim((string)($state['display_node_id'] ?? $state['node_id'] ?? $rawNodeId));
            $value = is_numeric($state['value'] ?? null) ? (float)$state['value'] : null;
            $max = is_numeric($state['max'] ?? null) ? (float)$state['max'] : null;
            $progress = ($value !== null && $max !== null && $max > 1) ? ($value / $max) : null;
            $label = ($value !== null && $max !== null && $max > 1)
                ? self::formatProgressNumber($value) . ' / ' . self::formatProgressNumber($max)
                : '';
            $labelNode = $nodeId !== '' ? $nodeId : $displayId;
            return [
                'title'=>'ComfyUI · ' . self::nodeLabel($workflow, $labelNode),
                'node_id'=>$labelNode,
                'progress'=>$progress,
                'progress_label'=>$label,
            ];
        }

        if ($type === 'execution_cached') {
            $nodes = $data['nodes'] ?? null;
            $count = is_array($nodes) ? count($nodes) : 0;
            return ['title'=>$count > 0 ? ('ComfyUI · Using ' . $count . ' cached node' . ($count === 1 ? '' : 's')) : 'ComfyUI · Using cached nodes'];
        }

        if ($type === 'execution_error') {
            $nodeId = trim((string)($data['node_id'] ?? $lastNodeId));
            $node = self::nodeLabel($workflow, $nodeId);
            $messageText = trim((string)($data['exception_message'] ?? $data['exception_type'] ?? 'unknown execution error'));
            return ['error'=>'ComfyUI execution failed · ' . $node . ': ' . $messageText];
        }

        if ($type === 'execution_interrupted') {
            $nodeId = trim((string)($data['node_id'] ?? $lastNodeId));
            $suffix = $nodeId !== '' ? (' · ' . self::nodeLabel($workflow, $nodeId)) : '';
            return ['error'=>'ComfyUI execution cancelled' . $suffix];
        }

        if ($type === 'execution_success') {
            return ['title'=>'ComfyUI · Finalizing output'];
        }

        return null;
    }

    private static function nodeLabel(array $workflow, string $nodeId): string
    {
        $nodeId = trim($nodeId);
        if ($nodeId === '') return 'Running';
        $node = $workflow[$nodeId] ?? null;
        if (!is_array($node) && str_contains($nodeId, ':')) {
            // Dynamic/subgraph execution ids may add suffixes. Try progressively
            // shorter prefixes against the original workflow ids.
            $parts = explode(':', $nodeId);
            while (count($parts) > 1 && !is_array($node)) {
                array_pop($parts);
                $candidate = implode(':', $parts);
                $node = $workflow[$candidate] ?? null;
                if (is_array($node)) $nodeId = $candidate;
            }
        }
        if (!is_array($node)) return 'Node ' . $nodeId;
        $meta = $node['_meta'] ?? null;
        $title = is_array($meta) ? trim((string)($meta['title'] ?? '')) : '';
        if ($title !== '') return $title;
        $class = trim((string)($node['class_type'] ?? ''));
        return $class !== '' ? $class : ('Node ' . $nodeId);
    }

    private static function formatProgressNumber(float $value): string
    {
        if (abs($value - round($value)) < 0.000001) return (string)(int)round($value);
        return rtrim(rtrim(number_format($value, 2, '.', ''), '0'), '.');
    }

    /** @return array<string,mixed>|null */
    private static function historyEntry(array $history, string $promptId): ?array
    {
        if (isset($history[$promptId]) && is_array($history[$promptId])) return $history[$promptId];
        if (isset($history['outputs']) && is_array($history)) return $history;
        $first = reset($history);
        return is_array($first) && isset($first['outputs']) ? $first : null;
    }

    private static function historyError(array $entry, array $workflow): ?string
    {
        $status = $entry['status'] ?? null;
        if (!is_array($status)) return null;
        $statusStr = strtolower(trim((string)($status['status_str'] ?? '')));
        $messages = $status['messages'] ?? null;
        if (is_array($messages)) {
            foreach ($messages as $message) {
                if (!is_array($message) || count($message) < 2) continue;
                $type = (string)($message[0] ?? '');
                $data = is_array($message[1] ?? null) ? $message[1] : [];
                if ($type === 'execution_error') {
                    $nodeId = trim((string)($data['node_id'] ?? ''));
                    $reason = trim((string)($data['exception_message'] ?? $data['exception_type'] ?? 'unknown execution error'));
                    return 'ComfyUI execution failed · ' . self::nodeLabel($workflow, $nodeId) . ': ' . $reason;
                }
                if ($type === 'execution_interrupted') {
                    return 'ComfyUI execution cancelled';
                }
            }
        }
        if (in_array($statusStr, ['error','failed'], true)) return 'ComfyUI execution failed';
        if (in_array($statusStr, ['cancelled','canceled','interrupted'], true)) return 'ComfyUI execution cancelled';
        return null;
    }

    private static function hasImages(array $outputs): bool
    {
        foreach ($outputs as $nodeOut) {
            if (is_array($nodeOut) && isset($nodeOut['images']) && is_array($nodeOut['images']) && count($nodeOut['images']) > 0) return true;
        }
        return false;
    }

    private static function collectImages(array $outputs): array
    {
        $images = [];
        foreach ($outputs as $nodeOut) {
            if (!is_array($nodeOut)) continue;
            $arr = $nodeOut['images'] ?? null;
            if (!is_array($arr)) continue;
            foreach ($arr as $image) {
                if (!is_array($image)) continue;
                $filename = (string)($image['filename'] ?? '');
                if ($filename === '') continue;
                $images[] = [
                    'filename'=>$filename,
                    'subfolder'=>(string)($image['subfolder'] ?? ''),
                    'type'=>(string)($image['type'] ?? 'output'),
                ];
            }
        }
        return $images;
    }
}
