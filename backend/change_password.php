<?php




declare(strict_types=1);

// ==========================================
// CCTV CAMERA CONTROL
// SECURE CHANGE PASSWORD API
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
    string $message
): void {

    http_response_code($status);

    echo json_encode([
        'success' => $success,
        'message' => $message,
    ], JSON_UNESCAPED_UNICODE);

    exit;
}

// ==========================================
// READ AUTHORIZATION TOKEN
// ==========================================

function bearerToken(): ?string {

    $authorization =
        $_SERVER['HTTP_AUTHORIZATION']
        ?? $_SERVER['REDIRECT_HTTP_AUTHORIZATION']
        ?? '';

    // Compatibility with PHP environments
    // that expose Authorization via headers.

    if (
        $authorization === '' &&
        function_exists('getallheaders')
    ) {

        foreach (getallheaders() as $name => $value) {

            if (strcasecmp($name, 'Authorization') === 0) {
                $authorization = $value;
                break;
            }
        }
    }

    // Our PHP login issues 32 random bytes
    // encoded as a 64-character hex token.

    if (
        !is_string($authorization) ||
        !preg_match(
            '/^Bearer\s+([a-f0-9]{64})$/i',
            trim($authorization),
            $matches
        )
    ) {
        return null;
    }

    return $matches[1];
}

// ==========================================
// REQUIRE POST
// ==========================================

if (
    ($_SERVER['REQUEST_METHOD'] ?? '') !== 'POST'
) {

    header('Allow: POST');

    sendResponse(
        405,
        false,
        'Use POST to change password.'
    );
}

// ==========================================
// REQUIRE AUTHENTICATION
// ==========================================

$sessionToken = bearerToken();

if ($sessionToken === null) {

    sendResponse(
        401,
        false,
        'Please sign in again.'
    );
}

// ==========================================
// VALIDATE REQUEST DATA
// ==========================================

// We intentionally DO NOT trust
// $_POST['username'].
//
// The user identity must come from the
// verified session in MySQL.

$currentPassword =
    $_POST['currentPassword'] ?? null;

$newPassword =
    $_POST['newPassword'] ?? null;

if (
    !is_string($currentPassword) ||
    !is_string($newPassword) ||
    $currentPassword === '' ||
    $newPassword === ''
) {

    sendResponse(
        400,
        false,
        'Please fill in all required fields.'
    );
}

if (strlen($currentPassword) > 1024) {

    sendResponse(
        400,
        false,
        'Invalid current password.'
    );
}

if (
    strlen($newPassword) < 8 ||
    strlen($newPassword) > 72
) {

    sendResponse(
        422,
        false,
        'New password must contain 8 to 72 bytes.'
    );
}

if (
    hash_equals(
        $currentPassword,
        $newPassword
    )
) {

    sendResponse(
        422,
        false,
        'New password must be different from current password.'
    );
}

// ==========================================
// DATABASE AND AUTHENTICATION
// ==========================================

$transactionStarted = false;

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
    // HASH THE SESSION TOKEN
    // ======================================

    // MySQL only stores SHA-256 hashes,
    // never the original session token.

    $sessionHash = hash(
        'sha256',
        $sessionToken
    );

    $nowUtc = gmdate(
        'Y-m-d H:i:s'
    );

    // ======================================
    // START TRANSACTION
    // ======================================

    $conn->begin_transaction();

    $transactionStarted = true;

    // ======================================
    // VERIFY SESSION IN MYSQL
    // ======================================

    $stmt = $conn->prepare(
        'SELECT
            s.id AS session_id,
            u.id AS user_id,
            u.password
         FROM user_sessions AS s
         INNER JOIN users AS u
             ON u.id = s.user_id
         WHERE s.token_hash = ?
           AND s.expires_at > ?
         LIMIT 1
         FOR UPDATE'
    );

    $stmt->bind_param(
        'ss',
        $sessionHash,
        $nowUtc
    );

    $stmt->execute();

    $account = $stmt
        ->get_result()
        ->fetch_assoc();

    $stmt->close();

    // ======================================
    // REJECT INVALID SESSION
    // ======================================

    if (!$account) {

        $conn->rollback();
        $transactionStarted = false;

        sendResponse(
            401,
            false,
            'Session expired or invalid. Please sign in again.'
        );
    }

    // ======================================
    // AUTHENTICATED ACCOUNT
    // ======================================

    $userId = (int) $account['user_id'];

    $currentSessionId =
        (int) $account['session_id'];

    $storedPassword =
        $account['password'];

    // IMPORTANT:
    //
    // $userId comes from the verified
    // session, NOT the submitted username.

    // ======================================
    // GOOGLE-ONLY ACCOUNT
    // ======================================

    if (
        !is_string($storedPassword) ||
        $storedPassword === ''
    ) {

        $conn->rollback();
        $transactionStarted = false;

        sendResponse(
            403,
            false,
            'This account does not have a local password.'
        );
    }

    // ======================================
    // CHECK PASSWORD STORAGE
    // ======================================

    $passwordInfo = password_get_info(
        $storedPassword
    );

    $isHashed =
        ($passwordInfo['algoName'] ?? 'unknown')
        !== 'unknown';

    // ======================================
    // VERIFY CURRENT PASSWORD
    // ======================================

    if ($isHashed) {

        $validPassword = password_verify(
            $currentPassword,
            $storedPassword
        );

    } else {

        // Temporary support for accounts
        // created before password hashing.
        //
        // Migrate legacy accounts and
        // remove this fallback before release.

        $validPassword = hash_equals(
            $storedPassword,
            $currentPassword
        );
    }

    if (!$validPassword) {

        $conn->rollback();
        $transactionStarted = false;

        sendResponse(
            401,
            false,
            'Invalid current password.'
        );
    }

    // ======================================
    // HASH THE NEW PASSWORD
    // ======================================

    $newPasswordHash = password_hash(
        $newPassword,
        PASSWORD_DEFAULT
    );

    // ======================================
    // UPDATE PASSWORD
    // ======================================

    $stmt = $conn->prepare(
        'UPDATE users
         SET password = ?
         WHERE id = ?'
    );

    $stmt->bind_param(
        'si',
        $newPasswordHash,
        $userId
    );

    $stmt->execute();
    $stmt->close();

    // ======================================
    // REVOKE OTHER SESSIONS
    // ======================================

    // Keep this device signed in,
    // but revoke sessions on other devices.

    $stmt = $conn->prepare(
        'DELETE FROM user_sessions
         WHERE user_id = ?
           AND id <> ?'
    );

    $stmt->bind_param(
        'ii',
        $userId,
        $currentSessionId
    );

    $stmt->execute();
    $stmt->close();

    // ======================================
    // COMMIT CHANGES
    // ======================================

    $conn->commit();

    $transactionStarted = false;

    // ======================================
    // SUCCESS
    // ======================================

    sendResponse(
        200,
        true,
        'Password changed successfully.'
    );

} catch (Throwable $e) {

    if (
        $transactionStarted &&
        isset($conn) &&
        $conn instanceof mysqli
    ) {

        try {
            $conn->rollback();
        } catch (Throwable $ignored) {
            // Preserve the original error.
        }
    }

    // Never expose database details
    // or credentials in API responses.

    error_log(
        'CCTV change password failed: ' .
        $e->getMessage()
    );

    sendResponse(
        500,
        false,
        'Unable to update password.'
    );
}
