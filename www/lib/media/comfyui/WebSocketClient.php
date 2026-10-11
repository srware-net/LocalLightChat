<?php
declare(strict_types=1);

namespace LLC\Media\ComfyUI;

/**
 * Small dependency-free WebSocket client used only for ComfyUI execution events.
 * Binary preview frames are intentionally ignored; image previews can be added later
 * without changing Runner's event model.
 */
final class WebSocketClient
{
    /** @var resource|null */
    private $stream;
    private string $buffer = '';
    private string $fragment = '';
    private ?int $fragmentOpcode = null;

    private function __construct($stream)
    {
        $this->stream = $stream;
        stream_set_blocking($this->stream, false);
    }

    public static function connect(string $base, string $clientId, float $timeoutSec = 3.0): ?self
    {
        $parts = parse_url($base);
        if (!is_array($parts)) return null;
        $scheme = strtolower((string)($parts['scheme'] ?? 'http'));
        $host = (string)($parts['host'] ?? '');
        if ($host === '') return null;
        $secure = $scheme === 'https' || $scheme === 'wss';
        $port = (int)($parts['port'] ?? ($secure ? 443 : 80));
        $transport = $secure ? 'ssl' : 'tcp';
        $path = rtrim((string)($parts['path'] ?? ''), '/') . '/ws?clientId=' . rawurlencode($clientId);
        if ($path === '') $path = '/ws?clientId=' . rawurlencode($clientId);

        $contextOptions = [];
        if ($secure) {
            $contextOptions['ssl'] = [
                'SNI_enabled' => true,
                'peer_name' => $host,
                'verify_peer' => true,
                'verify_peer_name' => true,
            ];
        }
        $context = stream_context_create($contextOptions);
        $errno = 0;
        $errstr = '';
        $stream = @stream_socket_client(
            $transport . '://' . $host . ':' . $port,
            $errno,
            $errstr,
            max(0.5, $timeoutSec),
            STREAM_CLIENT_CONNECT,
            $context
        );
        if (!is_resource($stream)) return null;

        stream_set_timeout($stream, max(1, (int)ceil($timeoutSec)));
        $key = base64_encode(random_bytes(16));
        $hostHeader = $host;
        $defaultPort = $secure ? 443 : 80;
        if ($port !== $defaultPort) $hostHeader .= ':' . $port;
        $headers = [
            'GET ' . $path . ' HTTP/1.1',
            'Host: ' . $hostHeader,
            'Upgrade: websocket',
            'Connection: Upgrade',
            'Sec-WebSocket-Key: ' . $key,
            'Sec-WebSocket-Version: 13',
            'User-Agent: PrivateWebChat-ComfyUI/1.0',
        ];
        if (isset($parts['user'])) {
            $user = rawurldecode((string)$parts['user']);
            $pass = rawurldecode((string)($parts['pass'] ?? ''));
            $headers[] = 'Authorization: Basic ' . base64_encode($user . ':' . $pass);
        }
        $request = implode("\r\n", $headers) . "\r\n\r\n";
        if (@fwrite($stream, $request) === false) {
            @fclose($stream);
            return null;
        }

        $response = '';
        $deadline = microtime(true) + max(0.5, $timeoutSec);
        while (!str_contains($response, "\r\n\r\n") && microtime(true) < $deadline) {
            $chunk = @fread($stream, 4096);
            if (is_string($chunk) && $chunk !== '') {
                $response .= $chunk;
                if (strlen($response) > 32768) break;
                continue;
            }
            usleep(10000);
        }
        $headEnd = strpos($response, "\r\n\r\n");
        if ($headEnd === false) {
            @fclose($stream);
            return null;
        }
        $head = substr($response, 0, $headEnd + 4);
        if (!preg_match('~^HTTP/\d(?:\.\d)?\s+101\b~i', $head)) {
            @fclose($stream);
            return null;
        }
        if (!preg_match('~^Sec-WebSocket-Accept:\s*(.+)$~mi', $head, $m)) {
            @fclose($stream);
            return null;
        }
        $expected = base64_encode(sha1($key . '258EAFA5-E914-47DA-95CA-C5AB0DC85B11', true));
        if (trim((string)$m[1]) !== $expected) {
            @fclose($stream);
            return null;
        }

        $client = new self($stream);
        $tail = substr($response, $headEnd + 4);
        if ($tail !== '') $client->buffer .= $tail;
        return $client;
    }

    public function isOpen(): bool
    {
        return is_resource($this->stream) && !feof($this->stream);
    }

    /**
     * Return the next JSON text message, or null when no text message arrived
     * before the timeout. Binary preview frames are consumed and discarded.
     */
    public function readJson(float $timeoutSec = 0.15): ?array
    {
        $deadline = microtime(true) + max(0.0, $timeoutSec);
        while ($this->isOpen()) {
            while (($frame = $this->extractFrame()) !== null) {
                [$opcode, $fin, $payload] = $frame;
                if ($opcode === 0x8) {
                    $this->close();
                    return null;
                }
                if ($opcode === 0x9) {
                    $this->sendControl(0xA, $payload);
                    continue;
                }
                if ($opcode === 0xA) continue;

                if ($opcode === 0x0 && $this->fragmentOpcode !== null) {
                    $this->fragment .= $payload;
                    if (!$fin) continue;
                    $opcode = $this->fragmentOpcode;
                    $payload = $this->fragment;
                    $this->fragmentOpcode = null;
                    $this->fragment = '';
                } elseif (($opcode === 0x1 || $opcode === 0x2) && !$fin) {
                    $this->fragmentOpcode = $opcode;
                    $this->fragment = $payload;
                    continue;
                }

                // We intentionally ignore binary preview frames for now.
                if ($opcode !== 0x1) continue;
                $decoded = json_decode($payload, true);
                if (is_array($decoded)) return $decoded;
            }

            $remaining = $deadline - microtime(true);
            if ($remaining <= 0) return null;
            $read = [$this->stream];
            $write = null;
            $except = null;
            $sec = (int)floor($remaining);
            $usec = (int)max(0, min(999999, round(($remaining - $sec) * 1000000)));
            $n = @stream_select($read, $write, $except, $sec, $usec);
            if ($n === false || $n === 0) return null;
            $chunk = @fread($this->stream, 65536);
            if ($chunk === false || $chunk === '') {
                if (feof($this->stream)) $this->close();
                return null;
            }
            $this->buffer .= $chunk;
        }
        return null;
    }

    public function close(): void
    {
        if (is_resource($this->stream)) @fclose($this->stream);
        $this->stream = null;
        $this->buffer = '';
        $this->fragment = '';
        $this->fragmentOpcode = null;
    }

    /** @return array{0:int,1:bool,2:string}|null */
    private function extractFrame(): ?array
    {
        $len = strlen($this->buffer);
        if ($len < 2) return null;
        $b1 = ord($this->buffer[0]);
        $b2 = ord($this->buffer[1]);
        $fin = ($b1 & 0x80) !== 0;
        $opcode = $b1 & 0x0F;
        $masked = ($b2 & 0x80) !== 0;
        $payloadLen = $b2 & 0x7F;
        $offset = 2;
        if ($payloadLen === 126) {
            if ($len < 4) return null;
            $payloadLen = unpack('n', substr($this->buffer, 2, 2))[1];
            $offset = 4;
        } elseif ($payloadLen === 127) {
            if ($len < 10) return null;
            $parts = unpack('Nhigh/Nlow', substr($this->buffer, 2, 8));
            if ((int)$parts['high'] !== 0) {
                // ComfyUI control/progress frames are tiny. Avoid absurd allocations.
                $this->close();
                return null;
            }
            $payloadLen = (int)$parts['low'];
            $offset = 10;
        }
        $mask = '';
        if ($masked) {
            if ($len < $offset + 4) return null;
            $mask = substr($this->buffer, $offset, 4);
            $offset += 4;
        }
        if ($payloadLen < 0 || $payloadLen > 16 * 1024 * 1024) {
            $this->close();
            return null;
        }
        if ($len < $offset + $payloadLen) return null;
        $payload = substr($this->buffer, $offset, $payloadLen);
        $this->buffer = substr($this->buffer, $offset + $payloadLen);
        if ($masked) {
            $unmasked = '';
            for ($i = 0; $i < $payloadLen; $i++) $unmasked .= $payload[$i] ^ $mask[$i % 4];
            $payload = $unmasked;
        }
        return [$opcode, $fin, $payload];
    }

    private function sendControl(int $opcode, string $payload = ''): void
    {
        if (!$this->isOpen()) return;
        $payload = substr($payload, 0, 125);
        $mask = random_bytes(4);
        $masked = '';
        for ($i = 0, $n = strlen($payload); $i < $n; $i++) $masked .= $payload[$i] ^ $mask[$i % 4];
        $frame = chr(0x80 | ($opcode & 0x0F)) . chr(0x80 | strlen($payload)) . $mask . $masked;
        @fwrite($this->stream, $frame);
    }
}
