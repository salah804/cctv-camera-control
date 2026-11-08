<?php
// Shared authentication helper for private profile endpoints.
// Session tokens are 32 random bytes encoded as 64 hex characters.

function currentProfileUser(mysqli $conn): array
{
    $header = $_SERVER['HTTP_AUTHORIZATION']
        ?? $_SERVER['REDIRECT_HTTP_AUTHORIZATION']
        ?? '';

    if ($header === '' && function_exists('getallheaders')) {
        foreach (getallheaders() as $name => $value) {
            if (strcasecmp($name, 'Authorization') === 0) {
                $header = $value;
                break;
            }
        }
    }

    if (!preg_match('/^Bearer ([a-fA-F0-9]{64})$/', trim($header), $matches)) {
        http_response_code(401);
        header('Content-Type: application/json; charset=utf-8');
        echo json_encode(['success' => false, 'message' => 'Please sign in again.']);
        exit;
    }

    $tokenHash = hash('sha256', $matches[1]);
    $stmt = $conn->prepare(
        'SELECT u.id, u.username
         FROM user_sessions s
         JOIN users u ON u.id = s.user_id
         WHERE s.token_hash = ?
           AND s.expires_at > UTC_TIMESTAMP()
         LIMIT 1'
    );
    $stmt->bind_param('s', $tokenHash);
    $stmt->execute();
    $user = $stmt->get_result()->fetch_assoc();
    $stmt->close();

    if (!$user) {
        http_response_code(401);
        header('Content-Type: application/json; charset=utf-8');
        echo json_encode(['success' => false, 'message' => 'Session expired or invalid.']);
        exit;
    }

    return $user;
}
