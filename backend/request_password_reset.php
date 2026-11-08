
<?php

// ==========================================
// CCTV CAMERA CONTROL
// REQUEST PASSWORD RESET
// ==========================================

use PHPMailer\PHPMailer\PHPMailer;

header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store');
header('X-Content-Type-Options: nosniff');

const GENERIC_MESSAGE =
    'If an account exists for this email, '
    . 'you will receive password recovery instructions.';

// ==========================================
// RESPONSE
// ==========================================

function respond(
    int $status,
    bool $success,
    string $message
): void {
    http_response_code($status);

    echo json_encode([
        'success' => $success,
        'message' => $message
    ], JSON_UNESCAPED_UNICODE);

    exit;
}

// ==========================================
// POST ONLY
// ==========================================

if (($_SERVER['REQUEST_METHOD'] ?? '') !== 'POST') {
    header('Allow: POST');

    respond(
        405,
        false,
        'Use POST to request password recovery.'
    );
}

// ==========================================
// VALIDATE EMAIL
// ==========================================

$accountEmail = $_POST['email'] ?? null;

if (
    !is_string($accountEmail) ||
    strlen($accountEmail) > 254
) {
    respond(400, false, 'Invalid email address.');
}

$accountEmail = trim($accountEmail);

if (!filter_var($accountEmail, FILTER_VALIDATE_EMAIL)) {
    respond(400, false, 'Invalid email address.');
}

// ==========================================
// PROCESS PASSWORD RESET REQUEST
// ==========================================

try {

    mysqli_report(
        MYSQLI_REPORT_ERROR | MYSQLI_REPORT_STRICT
    );

    // ======================================
    // LOAD DATABASE AND PHPMAILER
    // ======================================

    require_once __DIR__ . '/db_connection.php';
    require_once __DIR__ . '/vendor/autoload.php';

    // ======================================
    // LOAD PRIVATE GMAIL CONFIGURATION
    // ======================================

    $mailConfigPath = dirname(__DIR__, 2)
        . '/private/cctv_mail_config.php';

    if (!is_readable($mailConfigPath)) {
        throw new RuntimeException(
            'Private Gmail configuration not found.'
        );
    }

    $mailConfig = require $mailConfigPath;

    if (!is_array($mailConfig)) {
        throw new RuntimeException(
            'Private Gmail configuration must return an array.'
        );
    }

    // Verify required SMTP settings exist.
    foreach (
        [
            'smtp_host',
            'smtp_user',
            'smtp_pass',
            'smtp_port',
            'from_email',
            'from_name'
        ] as $key
    ) {

        if (
            !isset($mailConfig[$key]) ||
            trim((string) $mailConfig[$key]) === ''
        ) {
            throw new RuntimeException(
                'Gmail configuration setting missing: ' . $key
            );
        }
    }

    // ======================================
    // VERIFY DATABASE CONNECTION
    // ======================================

    if (
        !isset($conn) ||
        !($conn instanceof mysqli)
    ) {
        throw new RuntimeException(
            'Database unavailable.'
        );
    }

    $conn->set_charset('utf8mb4');

    // ======================================
    // RATE LIMITING
    // ======================================

    $now = gmdate('Y-m-d H:i:s');

    $cutoff = gmdate(
        'Y-m-d H:i:s',
        time() - 900
    );

    $ip = $_SERVER['REMOTE_ADDR'] ?? 'unknown';

    $ipHash = hash('sha256', $ip);

    $emailHash = hash(
        'sha256',
        strtolower($accountEmail)
    );

    // Maximum 10 requests per IP
    // within 15 minutes.

    $stmt = $conn->prepare(
        'SELECT COUNT(*) AS total
         FROM password_reset_requests
         WHERE ip_hash = ?
           AND created_at >= ?'
    );

    $stmt->bind_param(
        'ss',
        $ipHash,
        $cutoff
    );

    $stmt->execute();

    $ipCount = (int) $stmt
        ->get_result()
        ->fetch_assoc()['total'];

    $stmt->close();

    // Maximum 3 requests per email
    // within 15 minutes.

    $stmt = $conn->prepare(
        'SELECT COUNT(*) AS total
         FROM password_reset_requests
         WHERE email_hash = ?
           AND created_at >= ?'
    );

    $stmt->bind_param(
        'ss',
        $emailHash,
        $cutoff
    );

    $stmt->execute();

    $emailCount = (int) $stmt
        ->get_result()
        ->fetch_assoc()['total'];

    $stmt->close();

    if ($ipCount >= 10 || $emailCount >= 3) {
        respond(
            429,
            false,
            'Too many requests. Please try again later.'
        );
    }

    // ======================================
    // RECORD THE REQUEST
    // ======================================

    $stmt = $conn->prepare(
        'INSERT INTO password_reset_requests
         (ip_hash, email_hash, created_at)
         VALUES (?, ?, ?)'
    );

    $stmt->bind_param(
        'sss',
        $ipHash,
        $emailHash,
        $now
    );

    $stmt->execute();
    $stmt->close();

    // ======================================
    // FIND USER ACCOUNT
    // ======================================

    $stmt = $conn->prepare(
        'SELECT id, password
         FROM users
         WHERE email = ?
         LIMIT 1'
    );

    $stmt->bind_param(
        's',
        $accountEmail
    );

    $stmt->execute();

    $user = $stmt
        ->get_result()
        ->fetch_assoc();

    $stmt->close();

    // Never reveal whether the email exists.
    // Google-only accounts without a local
    // password should use Google recovery.

    if (
        !$user ||
        $user['password'] === null ||
        $user['password'] === ''
    ) {
        respond(
            202,
            true,
            GENERIC_MESSAGE
        );
    }

    $userId = (int) $user['id'];

    // ======================================
    // GENERATE SECURE RESET TOKEN
    // ======================================

    $rawToken = bin2hex(
        random_bytes(32)
    );

    $tokenHash = hash(
        'sha256',
        $rawToken
    );

    $expiresAt = gmdate(
        'Y-m-d H:i:s',
        time() + 1800
    );

    // Store only the token hash in MySQL.

    $stmt = $conn->prepare(
        'INSERT INTO password_reset_tokens
         (user_id, token_hash, expires_at, created_at)
         VALUES (?, ?, ?, ?)'
    );

    $stmt->bind_param(
        'isss',
        $userId,
        $tokenHash,
        $expiresAt,
        $now
    );

    $stmt->execute();

    $tokenRowId = $conn->insert_id;

    $stmt->close();

    // ======================================
    // PERMANENT HELIOHOST RESET URL
    // ======================================

    $resetBaseUrl =
        'https://salahayash.helioho.st/cctv-api/reset_password.php';

    if (
        !filter_var(
            $resetBaseUrl,
            FILTER_VALIDATE_URL
        ) ||
        parse_url(
            $resetBaseUrl,
            PHP_URL_SCHEME
        ) !== 'https'
    ) {
        throw new RuntimeException(
            'Secure reset URL is not configured.'
        );
    }

    $resetUrl = $resetBaseUrl
        . '?token='
        . rawurlencode($rawToken);

    // ======================================
    // SEND EMAIL USING PHPMAILER
    // ======================================

    $mail = new PHPMailer(true);

    $mail->isSMTP();

    $mail->Host =
        $mailConfig['smtp_host'];

    $mail->SMTPAuth = true;

    $mail->Username =
        $mailConfig['smtp_user'];

    $mail->Password =
        $mailConfig['smtp_pass'];

    // Gmail supports:
    // Port 465 with SMTPS
    // Port 587 with STARTTLS

    $smtpPort = (int) $mailConfig['smtp_port'];

    if (
        $smtpPort !== 465 &&
        $smtpPort !== 587
    ) {
        throw new RuntimeException(
            'Unsupported SMTP port in private config.'
        );
    }

    $mail->Port = $smtpPort;

    $mail->SMTPSecure =
        $smtpPort === 587
            ? PHPMailer::ENCRYPTION_STARTTLS
            : PHPMailer::ENCRYPTION_SMTPS;

    $mail->CharSet = 'UTF-8';

    // Never display SMTP credentials or
    // SMTP conversation in HTTP responses.
    $mail->SMTPDebug = 0;

    $mail->setFrom(
        $mailConfig['from_email'],
        $mailConfig['from_name']
    );

    $mail->addAddress(
        $accountEmail
    );

    $mail->isHTML(false);

    $mail->Subject =
        'CCTV Camera Control - Reset Your Password';

    $mail->Body =
        "Hello,\n\n"
        . "We received a request to reset your "
        . "CCTV Camera Control password.\n\n"
        . "Open the following link:\n\n"
        . $resetUrl . "\n\n"
        . "This link expires in 30 minutes "
        . "and can only be used once.\n\n"
        . "If you did not request this, "
        . "you can ignore this email.\n\n"
        . "CCTV Camera Control Team";

    // Send recovery email.
    $mail->send();

    respond(
        202,
        true,
        GENERIC_MESSAGE
    );

} catch (Throwable $e) {

    // ======================================
    // ERROR LOGGING
    // ======================================

    // Internal error details go to HelioHost
    // logs, never to the API response.

    error_log(
        'CCTV password reset request failed: '
        . $e->getMessage()
    );

    // ======================================
    // DELETE UNUSED RESET TOKEN
    // ======================================

    // If a token was created but email
    // delivery failed, delete that token.

    if (
        isset($conn, $tokenRowId) &&
        $conn instanceof mysqli
    ) {

        try {

            $cleanup = $conn->prepare(
                'DELETE FROM password_reset_tokens
                 WHERE id = ?'
            );

            $cleanup->bind_param(
                'i',
                $tokenRowId
            );

            $cleanup->execute();
            $cleanup->close();

        } catch (Throwable $ignored) {

            // Keep the public response generic.
        }
    }

    // Never disclose account existence
    // through email delivery errors.

    respond(
        202,
        true,
        GENERIC_MESSAGE
    );
}
