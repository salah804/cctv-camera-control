
<?php

// ==========================================
// CCTV CAMERA CONTROL
// REGULAR LOGIN API
// SERVER-SIDE SESSION AUTHENTICATION
// ==========================================

header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store');
header('X-Content-Type-Options: nosniff');

// ==========================================
// JSON RESPONSE
// ==========================================

function sendResponse(
    int $status,
    bool $success,
    string $message,
    array $extra = []
): void {

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

// ==========================================
// REQUIRE POST
// ==========================================

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {

    header('Allow: POST');

    sendResponse(
        405,
        false,
        'Use POST to log in.'
    );
}

// ==========================================
// READ INPUT
// ==========================================

// Important: Use $accountUsername because
// db_connection.php may use $username
// for the MySQL login credentials.

$accountUsername = $_POST['username'] ?? null;
$accountPassword = $_POST['password'] ?? null;

if (
    !is_string($accountUsername) ||
    !is_string($accountPassword)
) {
    sendResponse(
        400,
        false,
        'Invalid login information.'
    );
}

$accountUsername = trim($accountUsername);

if (
    $accountUsername === '' ||
    $accountPassword === '' ||
    strlen($accountUsername) > 255 ||
    strlen($accountPassword) > 1024
) {
    sendResponse(
        400,
        false,
        'Invalid login information.'
    );
}

// ==========================================
// CONNECT TO DATABASE
// ==========================================

try {

    mysqli_report(
        MYSQLI_REPORT_ERROR |
        MYSQLI_REPORT_STRICT
    );

    require_once __DIR__ . '/db_connection.php';

    if (
        !isset($conn) ||
        !($conn instanceof mysqli)
    ) {
        throw new RuntimeException(
            'Database connection unavailable.'
        );
    }

    $conn->set_charset('utf8mb4');

    // ======================================
    // FIND ACCOUNT
    // ======================================

    $stmt = $conn->prepare(
        'SELECT id, username, password
         FROM users
         WHERE username = ?
         LIMIT 1'
    );

    $stmt->bind_param(
        's',
        $accountUsername
    );

    $stmt->execute();

    $user = $stmt
        ->get_result()
        ->fetch_assoc();

    $stmt->close();

    // ======================================
    // VERIFY PASSWORD
    // ======================================

    $validPassword = false;

    if (
        $user &&
        is_string($user['password']) &&
        $user['password'] !== ''
    ) {

        $storedPassword = $user['password'];

        $passwordInfo = password_get_info(
            $storedPassword
        );

        $isHashed =
            ($passwordInfo['algoName'] ?? 'unknown')
            !== 'unknown';

        if ($isHashed) {

            $validPassword = password_verify(
                $accountPassword,
                $storedPassword
            );

        } else {

            // Temporary compatibility with
            // legacy plaintext passwords.
            // Migrate old accounts before
            // production deployment.

            $validPassword = hash_equals(
                $storedPassword,
                $accountPassword
            );
        }
    }

    if (!$validPassword) {

        sendResponse(
            401,
            false,
            'Invalid username or password.'
        );
    }

    // ======================================
    // CREATE SECURE SESSION TOKEN
    // ======================================

    $userId = (int) $user['id'];

    // 32 cryptographically random bytes,
    // represented by 64 hex characters.

    $sessionToken = bin2hex(
        random_bytes(32)
    );

    // Only the hash is stored in MySQL.

    $tokenHash = hash(
        'sha256',
        $sessionToken
    );

    // Session expires after 30 days.
    // All timestamps are UTC.

    $createdAt = gmdate(
        'Y-m-d H:i:s'
    );

    $expiresAt = gmdate(
        'Y-m-d H:i:s',
        time() + (30 * 24 * 60 * 60)
    );

    // ======================================
    // SAVE SESSION IN DATABASE
    // ======================================

    $sessionStmt = $conn->prepare(
        'INSERT INTO user_sessions
         (user_id, token_hash, expires_at, created_at)
         VALUES (?, ?, ?, ?)'
    );

    $sessionStmt->bind_param(
        'isss',
        $userId,
        $tokenHash,
        $expiresAt,
        $createdAt
    );

    $sessionStmt->execute();
    $sessionStmt->close();

    // ======================================
    // LOGIN SUCCESS
    // ======================================

    sendResponse(
        200,
        true,
        'Login successful.',
        [
            'user' => [
                'username' => $user['username']
            ],
            'session_token' => $sessionToken,
            'expires_at' => $expiresAt
        ]
    );

} catch (Throwable $e) {

    // Never expose tokens, passwords,
    // or database credentials to the app.

    error_log(
        'CCTV regular login failed: ' .
        $e->getMessage()
    );

    sendResponse(
        500,
        false,
        'Unable to log in. Please try again.'
    );
}
