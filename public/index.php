<?php

declare(strict_types=1);

require __DIR__ . '/../vendor/autoload.php';

use App\Palindrome;

const MAX_TEXT_LENGTH = 10000;

/**
 * Единая точка ответа: JSON + корректный HTTP-статус.
 */
function respond(array $data, int $status = 200): never
{
    http_response_code($status);
    header('Content-Type: application/json; charset=utf-8');
    echo json_encode($data, JSON_UNESCAPED_UNICODE);
    exit;
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    respond(['error' => 'Use POST with a JSON body: {"text": "..."}'], 405);
}

// JSON-тело; при пустом теле допускаем ?text=... для ручной проверки из браузера
$payload = json_decode((string) file_get_contents('php://input'), true) ?: $_GET;
$text = $payload['text'] ?? null;

if (!is_string($text)) {
    respond(['error' => 'Field "text" (string) is required'], 400);
}
if (!mb_check_encoding($text, 'UTF-8')) {
    respond(['error' => 'Text must be valid UTF-8'], 400);
}
if (mb_strlen($text) > MAX_TEXT_LENGTH) {
    respond(['error' => sprintf('Text is too long, max %d characters', MAX_TEXT_LENGTH)], 413);
}

$strict = filter_var($payload['strict'] ?? false, FILTER_VALIDATE_BOOLEAN);

respond([
    'text' => $text,
    'isPalindrome' => Palindrome::isPalindrome($text, $strict),
    'mode' => $strict ? 'strict' : 'normalized',
]);
