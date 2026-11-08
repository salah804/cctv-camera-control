<?php

// =============================================
// CCTV CAMERA CONTROL - PASSWORD RESET PAGE
// Validates an emailed, single-use reset token.
// =============================================

header('Content-Type: text/html; charset=utf-8');
header('Cache-Control: no-store, no-cache, must-revalidate');
header('Pragma: no-cache');
header('Referrer-Policy: no-referrer');
header('X-Content-Type-Options: nosniff');
header('X-Frame-Options: DENY');
header(
    "Content-Security-Policy: default-src 'none'; " .
    "style-src 'unsafe-inline'; form-action 'self'; " .
    "base-uri 'none'; frame-ancestors 'none'"
);

// =============================================
// ESCAPE HTML OUTPUT
// =============================================

function escapeHtml(string $value): string
{
    return htmlspecialchars(
        $value,
        ENT_QUOTES | ENT_SUBSTITUTE,
        'UTF-8'
    );
}

// =============================================
// ACCEPT GET AND POST ONLY
// =============================================

$requestMethod = $_SERVER['REQUEST_METHOD'] ?? 'GET';

if ($requestMethod !== 'GET' && $requestMethod !== 'POST') {
    header('Allow: GET, POST');
    http_response_code(405);
    exit('Method not allowed.');
}

// =============================================
// READ RESET TOKEN
// =============================================

// The emailed token is 32 random bytes,
// encoded as 64 hexadecimal characters.

$submittedToken = $requestMethod === 'POST'
    ? ($_POST['token'] ?? null)
    : ($_GET['token'] ?? null);

$tokenValidFormat = is_string($submittedToken)
    && preg_match(
        '/\A[a-f0-9]{64}\z/D',
        $submittedToken
    ) === 1;

$errorMessage = '';
$successMessage = '';
$showForm = false;
$transactionOpen = false;
$dbConnection = null;

// =============================================
// VERIFY TOKEN AND PROCESS RESET
// =============================================

if (!$tokenValidFormat) {

    http_response_code(400);

    $errorMessage =
        'This password-reset link is invalid or missing.';

} else {

    // Only the SHA-256 hash is stored
    // in our database.

    $resetTokenHash = hash(
        'sha256',
        $submittedToken
    );

    try {

        mysqli_report(
            MYSQLI_REPORT_ERROR | MYSQLI_REPORT_STRICT
        );

        // db_connection.php may define
        // $username = 'root'.
        //
        // We avoid that variable entirely.

        require_once __DIR__ . '/db_connection.php';
		// This page displays an HTML password reset form.
           header('Content-Type: text/html; charset=utf-8');
		

        if (
            !isset($conn) ||
            !($conn instanceof mysqli)
        ) {
            throw new RuntimeException(
                'Database connection unavailable'
            );
        }

        $dbConnection = $conn;
        $dbConnection->set_charset('utf8mb4');

        // =====================================
        // GET: VERIFY RECOVERY LINK
        // =====================================

        if ($requestMethod === 'GET') {

            $stmt = $dbConnection->prepare(
                'SELECT id
                 FROM password_reset_tokens
                 WHERE token_hash = ?
                   AND used_at IS NULL
                   AND expires_at > UTC_TIMESTAMP()
                 LIMIT 1'
            );

            $stmt->bind_param(
                's',
                $resetTokenHash
            );

            $stmt->execute();

            $tokenRow = $stmt
                ->get_result()
                ->fetch_assoc();

            $stmt->close();

            if ($tokenRow) {

                $showForm = true;

            } else {

                http_response_code(400);

                $errorMessage =
                    'This reset link is expired, already used, '
                    . 'or invalid. Please request a new link '
                    . 'in the app.';
            }

        } else {

            // =================================
            // POST: READ NEW PASSWORD
            // =================================

            $newPassword =
                $_POST['new_password'] ?? null;

            $confirmPassword =
                $_POST['confirm_password'] ?? null;

            $validationError = '';

            // =================================
            // VALIDATE PASSWORD
            // =================================

            if (
                !is_string($newPassword) ||
                !is_string($confirmPassword)
            ) {

                $validationError =
                    'Please fill in both password fields.';

            } elseif (strlen($newPassword) < 8) {

                $validationError =
                    'Your new password must be at least '
                    . '8 characters long.';

            } elseif (strlen($newPassword) > 72) {

                $validationError =
                    'Your new password must be at most '
                    . '72 UTF-8 bytes.';

            } elseif (
                !hash_equals(
                    $newPassword,
                    $confirmPassword
                )
            ) {

                $validationError =
                    'The passwords do not match.';
            }

            // =================================
            // START DATABASE TRANSACTION
            // =================================

            $dbConnection->begin_transaction();
            $transactionOpen = true;

            // Lock the token record to prevent
            // two requests from consuming it.

            $stmt = $dbConnection->prepare(
                'SELECT id, user_id
                 FROM password_reset_tokens
                 WHERE token_hash = ?
                   AND used_at IS NULL
                   AND expires_at > UTC_TIMESTAMP()
                 LIMIT 1 FOR UPDATE'
            );

            $stmt->bind_param(
                's',
                $resetTokenHash
            );

            $stmt->execute();

            $tokenRow = $stmt
                ->get_result()
                ->fetch_assoc();

            $stmt->close();

            // =================================
            // EXPIRED OR INVALID TOKEN
            // =================================

            if (!$tokenRow) {

                $dbConnection->rollback();
                $transactionOpen = false;

                http_response_code(400);

                $errorMessage =
                    'This reset link is expired, already used, '
                    . 'or invalid. Please request a new link '
                    . 'in the app.';

            } elseif ($validationError !== '') {

                // =================================
                // PASSWORD VALIDATION FAILED
                // =================================

                $dbConnection->rollback();
                $transactionOpen = false;

                $errorMessage = $validationError;
                $showForm = true;

            } else {

                // =================================
                // GET VERIFIED ACCOUNT ID
                // =================================

                $accountUserId =
                    (int) $tokenRow['user_id'];

                // =================================
                // HASH NEW PASSWORD
                // =================================

                $newPasswordHash = password_hash(
                    $newPassword,
                    PASSWORD_DEFAULT
                );

                // =================================
                // UPDATE USER PASSWORD
                // =================================

                $updateUser = $dbConnection->prepare(
                    'UPDATE users
                     SET password = ?
                     WHERE id = ?'
                );

                $updateUser->bind_param(
                    'si',
                    $newPasswordHash,
                    $accountUserId
                );

                $updateUser->execute();

                $updatedUsers =
                    $updateUser->affected_rows;

                $updateUser->close();

                if ($updatedUsers !== 1) {

                    throw new RuntimeException(
                        'Reset target user not found'
                    );
                }

                // =================================
                // INVALIDATE ALL RECOVERY TOKENS
                // =================================

                $invalidateTokens = $dbConnection->prepare(
                    'UPDATE password_reset_tokens
                     SET used_at = UTC_TIMESTAMP()
                     WHERE user_id = ?
                       AND used_at IS NULL'
                );

                $invalidateTokens->bind_param(
                    'i',
                    $accountUserId
                );

                $invalidateTokens->execute();
                $invalidateTokens->close();

                // =================================
                // REVOKE EXISTING APP SESSIONS
                // =================================

                $revokeSessions = $dbConnection->prepare(
                    'DELETE FROM user_sessions
                     WHERE user_id = ?'
                );

                $revokeSessions->bind_param(
                    'i',
                    $accountUserId
                );

                $revokeSessions->execute();
                $revokeSessions->close();

                // =================================
                // COMMIT ALL CHANGES
                // =================================

                $dbConnection->commit();
                $transactionOpen = false;

                $successMessage =
                    'Your password has been reset. '
                    . 'Return to the CCTV Camera Control '
                    . 'app and sign in with your new password.';
            }
        }

    } catch (Throwable $exception) {

        if (
            $transactionOpen &&
            $dbConnection instanceof mysqli
        ) {

            try {
                $dbConnection->rollback();
            } catch (Throwable $ignored) {
                // Connection may already be closed.
            }
        }

        // Never log actual reset tokens
        // or submitted passwords.

        error_log(
            'CCTV password reset failed: '
            . $exception->getMessage()
        );

        http_response_code(500);
        $showForm = false;

        $errorMessage =
            'Unable to process your request right now. '
            . 'Please try again later.';
    }
}
?>

<!DOCTYPE html>
<html lang="en">

<head>

    <meta charset="UTF-8">

    <meta
        name="viewport"
        content="width=device-width, initial-scale=1"
    >

    <title>
        Reset Password | CCTV Camera Control
    </title>

    <style>

        * {
            box-sizing: border-box;
        }

        body {
            margin: 0;
            min-height: 100vh;
            display: grid;
            place-items: center;
            padding: 24px;
            background: radial-gradient(
                circle at 80% 10%,
                #102b3a 0%,
                #080d18 45%
            );
            color: #eef8ff;
            font-family:
                system-ui,
                -apple-system,
                'Segoe UI',
                sans-serif;
        }

        .card {
            width: 100%;
            max-width: 460px;
            padding: 32px;
            background: #111c2d;
            border: 1px solid #26364b;
            border-radius: 22px;
            box-shadow: 0 24px 80px #0007;
        }

        .icon {
            display: grid;
            place-items: center;
            width: 64px;
            height: 64px;
            border-radius: 18px;
            background: #142f43;
            color: #50d5f5;
            font-size: 28px;
            margin-bottom: 22px;
        }

        h1 {
            font-size: 26px;
            margin: 0 0 12px;
        }

        .description,
        .hint {
            color: #94a3b8;
            line-height: 1.6;
        }

        .description {
            margin: 0 0 26px;
            font-size: 14px;
        }

        label {
            display: block;
            margin: 18px 0 8px;
            font-weight: 650;
            font-size: 13px;
        }

        input {
            width: 100%;
            padding: 15px;
            border-radius: 12px;
            border: 1px solid #26364b;
            background: #080d18;
            color: #fff;
            font: inherit;
        }

        input:focus {
            outline: 2px solid #50d5f5;
            outline-offset: 1px;
        }

        button {
            display: block;
            width: 100%;
            margin-top: 24px;
            padding: 15px;
            background: #50d5f5;
            color: #080d18;
            font: inherit;
            font-weight: 750;
            border: 0;
            border-radius: 12px;
            cursor: pointer;
        }

        button:hover {
            background: #8ce7ff;
        }

        .message {
            padding: 14px;
            border-radius: 12px;
            line-height: 1.5;
        }

        .error {
            background: #441d29;
            border: 1px solid #913b50;
        }

        .success {
            background: #133d35;
            border: 1px solid #247d69;
        }

        .hint {
            font-size: 12px;
            margin: 10px 0 0;
        }

        footer {
            text-align: center;
            color: #94a3b8;
            margin-top: 28px;
            font-size: 11px;
            letter-spacing: 1px;
        }

    </style>

</head>

<body>

    <main class="card">

        <div class="icon" aria-hidden="true">
            &#128274;
        </div>

        <h1>Reset Your Password</h1>

        <p class="description">
            Create a new password for your CCTV Camera
            Control account. Your recovery link works
            only once and expires after 30 minutes.
        </p>

        <?php if ($successMessage !== ''): ?>

            <div class="message success" role="status">
                <?php echo escapeHtml($successMessage); ?>
            </div>

        <?php else: ?>

            <?php if ($errorMessage !== ''): ?>

                <div class="message error" role="alert">
                    <?php echo escapeHtml($errorMessage); ?>
                </div>

            <?php endif; ?>

            <?php if ($showForm): ?>

                
<form
    method="post"
    action="/reset_password.php"
    autocomplete="off"
>


                    <input
                        type="hidden"
                        name="token"
                        value="<?php echo escapeHtml($submittedToken); ?>"
                    >

                    <label for="new_password">
                        New Password
                    </label>

                    <input
                        id="new_password"
                        name="new_password"
                        type="password"
                        minlength="8"
                        required
                        autocomplete="new-password"
                    >

                    <p class="hint">
                        At least 8 characters,
                        maximum 72 UTF-8 bytes.
                    </p>

                    <label for="confirm_password">
                        Confirm New Password
                    </label>

                    <input
                        id="confirm_password"
                        name="confirm_password"
                        type="password"
                        minlength="8"
                        required
                        autocomplete="new-password"
                    >

                    <button type="submit">
                        Reset Password
                    </button>

                </form>

            <?php endif; ?>

        <?php endif; ?>

        <footer>
            CCTV CAMERA CONTROL
        </footer>

    </main>

</body>
</html>
