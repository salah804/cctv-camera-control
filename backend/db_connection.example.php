<?php
// EXAMPLE ONLY. Copy your existing, WORKING db_connection.php from
// HelioHost to deploy. Never put database passwords in GitHub.
// Your production config lives outside the public document root.
// This example expects a private file returning an associative array.

$configFile = dirname(__DIR__, 2) . '/private/cctv_config.php';
if (!is_file($configFile)) {
    throw new RuntimeException('Private database configuration unavailable.');
}
$config = require $configFile;
if (!is_array($config)) {
    throw new RuntimeException('Private database configuration must return an array.');
}
$conn = new mysqli(
    $config['host'],
    $config['user'],
    $config['password'],
    $config['database']
);
$conn->set_charset('utf8mb4');
