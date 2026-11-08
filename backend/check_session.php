
<?php

// CCTV Camera Control - Session Verification API

header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store');

function sendResponse($status, $success, $message, $extra = [])
{
    http_response_code($status);

    echo json_encode(
        array_merge([
            'success' => $success,
            'message' => $message
        ], $extra),
        JSON_UNESCAPED_UNICODE
    );

    exit;
}

// Accept only GET requests.
if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
    header('Allow: GET');
    sendResponse(405, false, 'Method not allowed.');
}

// Read the session token from the Authorization header.
$authorization = $_SERVER['HTTP_AUTHORIZATION'] ?? '';

if ($authorization === '' && function_exists('getallheaders')) {
    foreach (getallheaders() as $name => $value) {
        if (strtolower($name) === 'authorization') {
            $authorization = $value;
            break;
        }
    }
}

// Our session token is 64 hexadecimal characters.
if (
    !preg_match(
        '/^Bearer\s+([a-f0-9]{64})$/i',
        trim($authorization),
        $matches
    )
) {
    sendResponse(
        401,
        false,
        'Missing or invalid session token.'
    );
}

$tokenHash = hash('sha256', $matches[1]);

try {
    mysqli_report(
        MYSQLI_REPORT_ERROR | MYSQLI_REPORT_STRICT
    );

    require_once __DIR__ . '/db_connection.php';

    if (!isset($conn) || !($conn instanceof mysqli)) {
        throw new RuntimeException('Database unavailable.');
    }

    $conn->set_charset('utf8mb4');

    $stmt = $conn->prepare(
        "SELECT
            u.id,
            u.username,
            u.email,
            u.full_name,
            s.expires_at
         FROM user_sessions AS s
         INNER JOIN users AS u ON u.id = s.user_id
         WHERE s.token_hash = ?
           AND s.expires_at > UTC_TIMESTAMP()
         LIMIT 1"
    );

    $stmt->bind_param('s', $tokenHash);
    $stmt->execute();

    $user = $stmt->get_result()->fetch_assoc();
    $stmt->close();

    if (!$user) {
        sendResponse(
            401,
            false,
            'Session expired or invalid.'
        );
    }

    sendResponse(
        200,
        true,
        'Session is valid.',
        [
            'user' => [
                'id' => (int) $user['id'],
                'username' => $user['username'],
                'email' => $user['email'],
                'full_name' => $user['full_name']
            ],
            'expires_at' => $user['expires_at']
        ]
    );

} catch (Throwable $e) {
    error_log('Session check error: ' . $e->getMessage());

    sendResponse(
        500,
        false,
        'Unable to verify session.'
    );
}
