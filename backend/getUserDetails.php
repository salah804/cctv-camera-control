<?php
header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store');
mysqli_report(MYSQLI_REPORT_ERROR | MYSQLI_REPORT_STRICT);
require_once __DIR__ . '/db_connection.php';
require_once __DIR__ . '/profile_auth.php';

function respond($success, $message, $data = null, $status = 200) {
    http_response_code($status);
    $result = ['success' => $success, 'message' => $message];
    if ($data !== null) $result['data'] = $data;
    echo json_encode($result, JSON_UNESCAPED_UNICODE);
    exit;
}

if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
    header('Allow: GET');
    respond(false, 'Method not allowed.', null, 405);
}
try {
    $conn->set_charset('utf8mb4');
    $authenticatedUser = currentProfileUser($conn);
    $userId = (int)$authenticatedUser['id'];
    $stmt = $conn->prepare(
        'SELECT id, username, email, mobile, full_name,
                company, job_title, location, bio, image
         FROM users WHERE id = ? LIMIT 1'
    );
    $stmt->bind_param('i', $userId);
    $stmt->execute();
    $user = $stmt->get_result()->fetch_assoc();
    $stmt->close();
    if (!$user) respond(false, 'User not found.', null, 404);
    $data = [
        'id' => (int)$user['id'],
        'username' => $user['username'],
        'email' => $user['email'],
        'mobile' => $user['mobile'] ?? '',
        'full_name' => $user['full_name'] ?? '',
        'company' => $user['company'] ?? '',
        'job_title' => $user['job_title'] ?? '',
        'location' => $user['location'] ?? '',
        'bio' => $user['bio'] ?? '',
        'image' => !empty($user['image']) ? base64_encode($user['image']) : null,
    ];
    respond(true, 'Profile loaded successfully.', $data);
} catch (Throwable $e) {
    error_log('Profile fetch error: ' . $e->getMessage());
    respond(false, 'Unable to load profile.', null, 500);
}
