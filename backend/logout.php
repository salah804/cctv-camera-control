<?php
// CCTV Camera Control - revoke an existing PHP session.
// The raw session token is never stored in MySQL.

header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store');

function logoutReply($status, $success, $message) {
    http_response_code($status);
    echo json_encode([
        'success' => $success,
        'message' => $message
    ], JSON_UNESCAPED_UNICODE);
    exit;
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    header('Allow: POST');
    logoutReply(405, false, 'Use POST to log out.');
}

$authorization = $_SERVER['HTTP_AUTHORIZATION']
    ?? $_SERVER['REDIRECT_HTTP_AUTHORIZATION']
    ?? '';

if ($authorization === '' && function_exists('getallheaders')) {
    foreach (getallheaders() as $name => $value) {
        if (strcasecmp($name, 'Authorization') === 0) {
            $authorization = $value;
            break;
        }
    }
}

if (!preg_match('/^Bearer\s+([a-f0-9]{64})$/i', trim($authorization), $matches)) {
    logoutReply(401, false, 'Missing or invalid session token.');
}

$tokenHash = hash('sha256', $matches[1]);

try {
    mysqli_report(MYSQLI_REPORT_ERROR | MYSQLI_REPORT_STRICT);
    require_once __DIR__ . '/db_connection.php';

    if (!isset($conn) || !($conn instanceof mysqli)) {
        throw new RuntimeException('Database unavailable.');
    }

    $stmt = $conn->prepare('DELETE FROM user_sessions WHERE token_hash = ?');
    $stmt->bind_param('s', $tokenHash);
    $stmt->execute();
    $deleted = $stmt->affected_rows;
    $stmt->close();

    if ($deleted < 1) {
        logoutReply(401, false, 'Session already invalid or revoked.');
    }

    logoutReply(200, true, 'Signed out successfully.');
} catch (Throwable $e) {
    error_log('Logout failed: ' . $e->getMessage());
    logoutReply(500, false, 'Could not revoke session.');
}
