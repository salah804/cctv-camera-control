<?php
header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store');
mysqli_report(MYSQLI_REPORT_ERROR | MYSQLI_REPORT_STRICT);
require_once __DIR__ . '/db_connection.php';

function respond($success, $message, $status = 200) {
    http_response_code($status);
    echo json_encode(['success' => $success, 'message' => $message], JSON_UNESCAPED_UNICODE);
    exit;
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    header('Allow: POST');
    respond(false, 'Method not allowed.', 405);
}

$username = $_POST['username'] ?? '';
$password = $_POST['password'] ?? '';
$email = $_POST['email'] ?? '';
$mobile = $_POST['mobile'] ?? '';

if (!is_string($username) || !is_string($password) ||
    !is_string($email) || !is_string($mobile)) {
    respond(false, 'Invalid registration data.', 400);
}
$username = trim($username);
$email = trim($email);
$mobile = trim($mobile);
if ($username === '' || $password === '' || $email === '' || $mobile === '') {
    respond(false, 'All fields are required.', 400);
}
if (!preg_match('/\A[\p{L}\p{N}_.-]{3,50}\z/u', $username)) {
    respond(false, 'Username must contain 3-50 valid characters.', 400);
}
if (strlen($email) > 255 || !filter_var($email, FILTER_VALIDATE_EMAIL)) {
    respond(false, 'Please enter a valid email address.', 400);
}
if (!preg_match('/^\+?[0-9]{7,14}$/', $mobile)) {
    respond(false, 'Please enter a valid mobile number.', 400);
}
if (strlen($password) < 8 || strlen($password) > 72) {
    respond(false, 'Password must be 8-72 bytes long.', 400);
}

try {
    $conn->set_charset('utf8mb4');
    $check = $conn->prepare(
        'SELECT id, username, email FROM users
         WHERE username = ? OR email = ? LIMIT 1'
    );
    $check->bind_param('ss', $username, $email);
    $check->execute();
    $existingUser = $check->get_result()->fetch_assoc();
    $check->close();
    if ($existingUser) {
        respond(false, 'Username or email already exists.', 409);
    }
    $hashedPassword = password_hash($password, PASSWORD_DEFAULT);
    $insert = $conn->prepare(
        'INSERT INTO users (username, password, email, mobile, image)
         VALUES (?, ?, ?, ?, NULL)'
    );
    $insert->bind_param('ssss', $username, $hashedPassword, $email, $mobile);
    $insert->execute();
    $insert->close();
    respond(true, 'Account created successfully!');
} catch (mysqli_sql_exception $e) {
    if ((int)$e->getCode() === 1062) {
        respond(false, 'Username or email already exists.', 409);
    }
    error_log('Registration database error: ' . $e->getMessage());
    respond(false, 'Registration unavailable. Please try again.', 500);
} catch (Throwable $e) {
    error_log('Registration error: ' . $e->getMessage());
    respond(false, 'An unexpected error occurred.', 500);
}
