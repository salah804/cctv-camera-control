<?php
header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store');
mysqli_report(MYSQLI_REPORT_ERROR | MYSQLI_REPORT_STRICT);
require_once __DIR__ . '/db_connection.php';
require_once __DIR__ . '/profile_auth.php';

function respond($success, $message, $status = 200) {
    http_response_code($status);
    echo json_encode(['success' => $success, 'message' => $message], JSON_UNESCAPED_UNICODE);
    exit;
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    header('Allow: POST');
    respond(false, 'Method not allowed.', 405);
}
$action = $_POST['action'] ?? 'update_details';
if (!is_string($action)) respond(false, 'Invalid action.', 400);

try {
    $conn->set_charset('utf8mb4');
    $authenticatedUser = currentProfileUser($conn);
    $userId = (int)$authenticatedUser['id'];

    if ($action === 'upload_image') {
        if (!isset($_FILES['image']) || !is_array($_FILES['image']) ||
            $_FILES['image']['error'] !== UPLOAD_ERR_OK) {
            respond(false, 'No valid image uploaded.', 400);
        }
        $file = $_FILES['image'];
        $maxSize = 2 * 1024 * 1024;
        if (!isset($file['size'], $file['tmp_name']) ||
            !is_int($file['size']) || !is_string($file['tmp_name']) ||
            $file['size'] <= 0 || $file['size'] > $maxSize ||
            !is_uploaded_file($file['tmp_name'])) {
            respond(false, 'Invalid uploaded image.', 400);
        }
        $mime = (new finfo(FILEINFO_MIME_TYPE))->file($file['tmp_name']);
        if (!in_array($mime, ['image/jpeg', 'image/png', 'image/webp'], true)) {
            respond(false, 'Use JPG, PNG, or WebP.', 400);
        }
        $imageInfo = @getimagesize($file['tmp_name']);
        if ($imageInfo === false || $imageInfo[0] <= 0 ||
            $imageInfo[1] <= 0 || $imageInfo[0] > 5000 ||
            $imageInfo[1] > 5000) {
            respond(false, 'Invalid image file.', 400);
        }
        $imageData = file_get_contents($file['tmp_name']);
        if ($imageData === false) respond(false, 'Unable to read image.', 400);
        $stmt = $conn->prepare('UPDATE users SET image = ? WHERE id = ?');
        $blob = null;
        $stmt->bind_param('bi', $blob, $userId);
        $stmt->send_long_data(0, $imageData);
        $stmt->execute();
        $stmt->close();
        respond(true, 'Profile picture updated successfully.');
    }

    if ($action === 'remove_image') {
        $stmt = $conn->prepare('UPDATE users SET image = NULL WHERE id = ?');
        $stmt->bind_param('i', $userId);
        $stmt->execute();
        $stmt->close();
        respond(true, 'Profile picture removed.');
    }

    if ($action !== 'update_details') {
        respond(false, 'Unsupported action.', 400);
    }
    foreach (['full_name', 'email', 'mobile', 'company', 'job_title', 'location', 'bio'] as $field) {
        if (!isset($_POST[$field]) || !is_string($_POST[$field])) {
            respond(false, 'Missing or invalid field: ' . $field, 400);
        }
    }

    $fullName = trim($_POST['full_name']);
    $email = trim($_POST['email']);
    $mobile = trim($_POST['mobile']);
    $company = trim($_POST['company']);
    $jobTitle = trim($_POST['job_title']);
    $location = trim($_POST['location']);
    $bio = trim($_POST['bio']);

    if (strlen($email) > 255 || !filter_var($email, FILTER_VALIDATE_EMAIL)) {
        respond(false, 'Invalid email address.', 400);
    }
    if (strlen($fullName) > 480 || strlen($company) > 480 ||
        strlen($jobTitle) > 400 || strlen($location) > 480 ||
        strlen($bio) > 4000) {
        respond(false, 'One or more fields are too long.', 400);
    }
    if ($mobile !== '' && !preg_match('/^\+?[0-9]{7,14}$/', $mobile)) {
        respond(false, 'Invalid mobile number.', 400);
    }

    $stmt = $conn->prepare(
        "UPDATE users SET full_name = ?, email = ?, mobile = NULLIF(?, ''),
         company = ?, job_title = ?, location = ?, bio = ? WHERE id = ?"
    );
    $stmt->bind_param('sssssssi', $fullName, $email, $mobile, $company,
        $jobTitle, $location, $bio, $userId);
    $stmt->execute();
    $stmt->close();
    respond(true, 'Profile updated successfully.');
} catch (mysqli_sql_exception $e) {
    if ((int)$e->getCode() === 1062) respond(false, 'Email is already in use.', 409);
    error_log('Profile SQL error: ' . $e->getMessage());
    respond(false, 'Database update failed.', 500);
} catch (Throwable $e) {
    error_log('Profile error: ' . $e->getMessage());
    respond(false, 'Unable to update profile.', 500);
}
