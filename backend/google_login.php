<?php

declare(strict_types=1);

header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store');

function sendJson(bool $success, string $message, int $status = 200, array $extra = []): void
{
    http_response_code($status);
    echo json_encode(array_merge([
        'success' => $success,
        'message' => $message,
    ], $extra), JSON_UNESCAPED_UNICODE);
    exit;
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    header('Allow: POST');
    sendJson(false, 'Use POST to sign in.', 405);
}

$idToken = $_POST['id_token'] ?? null;
if (!is_string($idToken) || $idToken === '' || strlen($idToken) > 8192) {
    sendJson(false, 'Missing or invalid Google ID token.', 400);
}

$vendorAutoload = __DIR__ . '/vendor/autoload.php';
if (!is_file($vendorAutoload)) {
    sendJson(false, 'Google login is not installed on the server.', 503);
}

require_once $vendorAutoload;
mysqli_report(MYSQLI_REPORT_ERROR | MYSQLI_REPORT_STRICT);
require_once __DIR__ . '/db_connection.php';

// This is the WEB application OAuth Client ID, not a client secret.
$webClientId = '628625399302-8orvhe3gidkdvfs7kt4lc8h5g0994qa2.apps.googleusercontent.com';

$transactionStarted = false;

try {
    if (!isset($conn) || !($conn instanceof mysqli)) {
        throw new RuntimeException('MySQL connection unavailable.');
    }

    // This checks Google's signature, expiration, issuer and the audience
    // (which must match the Web Client ID above).
    $googleClient = new Google_Client(['client_id' => $webClientId]);
    $payload = $googleClient->verifyIdToken($idToken);

    if (!is_array($payload)) {
        sendJson(false, 'Google token verification failed.', 401);
    }

    $googleId = (string) ($payload['sub'] ?? '');
    $email = trim((string) ($payload['email'] ?? ''));
    $displayName = trim((string) ($payload['name'] ?? ''));
    $verifiedEmail = filter_var(
        $payload['email_verified'] ?? false,
        FILTER_VALIDATE_BOOLEAN
    );

    if ($googleId === '' || !$verifiedEmail ||
        !filter_var($email, FILTER_VALIDATE_EMAIL) || strlen($email) > 255) {
        sendJson(false, 'The Google account email is not verified.', 403);
    }

    if (strlen($displayName) > 120) {
        $displayName = '';
    }

    $conn->set_charset('utf8mb4');
    $conn->query("SET time_zone = '+00:00'");
    $conn->begin_transaction();
    $transactionStarted = true;

    $provider = 'google';

    // Lookup by Google's permanent subject ID, NEVER email alone.
    $stmt = $conn->prepare(
        'SELECT u.id, u.username, u.email, u.full_name
         FROM user_social_accounts AS s
         INNER JOIN users AS u ON u.id = s.user_id
         WHERE s.provider = ? AND s.provider_user_id = ?
         LIMIT 1 FOR UPDATE'
    );
    $stmt->bind_param('ss', $provider, $googleId);
    $stmt->execute();
    $user = $stmt->get_result()->fetch_assoc();
    $stmt->close();

    if (!$user) {
        // Existing password accounts MUST be explicitly linked later.
        // Matching email is not sufficient proof of account ownership.
        $stmt = $conn->prepare('SELECT id FROM users WHERE email = ? LIMIT 1');
        $stmt->bind_param('s', $email);
        $stmt->execute();
        $emailExists = $stmt->get_result()->fetch_assoc();
        $stmt->close();

        if ($emailExists) {
            $conn->rollback();
            $transactionStarted = false;
            sendJson(
                false,
                'An account already uses this email. Sign in with your password; Google account linking is not available yet.',
                409
            );
        }

        $username = 'google_' . bin2hex(random_bytes(8));
        $stmt = $conn->prepare(
            'INSERT INTO users (username, email, mobile, password, image, full_name)
             VALUES (?, ?, NULL, NULL, NULL, ?)'
        );
        $stmt->bind_param('sss', $username, $email, $displayName);
        $stmt->execute();
        $userId = (int) $conn->insert_id;
        $stmt->close();

        $stmt = $conn->prepare(
            'INSERT INTO user_social_accounts (user_id, provider, provider_user_id)
             VALUES (?, ?, ?)'
        );
        $stmt->bind_param('iss', $userId, $provider, $googleId);
        $stmt->execute();
        $stmt->close();

        $user = [
            'id' => $userId,
            'username' => $username,
            'email' => $email,
            'full_name' => $displayName,
        ];
    }

    // Create an opaque session token; only its SHA-256 hash goes into MySQL.
    $sessionToken = bin2hex(random_bytes(32));
    $sessionHash = hash('sha256', $sessionToken);
    $expiresAt = gmdate('Y-m-d H:i:s', time() + 7 * 24 * 60 * 60);
    $userId = (int) $user['id'];

    $stmt = $conn->prepare(
        'INSERT INTO user_sessions (user_id, token_hash, expires_at)
         VALUES (?, ?, ?)'
    );
    $stmt->bind_param('iss', $userId, $sessionHash, $expiresAt);
    $stmt->execute();
    $stmt->close();

    $conn->commit();
    $transactionStarted = false;

    sendJson(true, 'Google sign-in successful.', 200, [
        'user' => [
            'id' => $userId,
            'username' => (string) $user['username'],
            'email' => (string) $user['email'],
            'full_name' => (string) ($user['full_name'] ?? ''),
        ],
        'session_token' => $sessionToken,
        'expires_at' => $expiresAt . ' UTC',
    ]);
} catch (Throwable $e) {
    if ($transactionStarted && isset($conn) && $conn instanceof mysqli) {
        try {
            $conn->rollback();
        } catch (Throwable $ignored) {
        }
    }
    error_log('Google login failed: ' . $e->getMessage());
    sendJson(false, 'Google sign-in is temporarily unavailable.', 500);
}
