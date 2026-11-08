
# CCTV Camera Control — PHP Backend

PHP/MySQL API used by the Flutter CCTV Camera Control app. Production endpoint: `https://salahayash.helioho.st/cctv-api/`.

## Backend source included

The following files were recovered from user-supplied code or previously reviewed endpoint versions: `register.php`, `google_login.php`, `logout.php`, `getUserDetails.php`, `update_profile.php`, `profile_auth.php`, `reset_password.php`. They were not re-tested against production in this exported copy.

**Complete the repository using your known-working copies** of `login.php`, `check_session.php`, `change_password.php`, and `request_password_reset.php` from HelioHost Plesk before describing the repo as a complete backend. The source for those exact deployed versions was not available in this conversation. Do not generate replacements or overwrite the live files just to make the GitHub repo complete.

The actual `db_connection.php` is deliberately excluded from Git and must remain available when deployed. `db_connection.example.php` documents one safe pattern; it does NOT necessarily match the format of your existing private configuration file, and must NOT replace your working file.

## Production structure

- `httpdocs/cctv-api/` — copy the PHP API files here
- `private/cctv_config.php` — private MySQL credentials (outside document root)
- `private/cctv_mail_config.php` — private SMTP password (outside document root)
- `httpdocs/cctv-api/vendor/` — Composer dependencies (excluded from Git)

Run `composer install --no-dev --optimize-autoloader` on a compatible machine / server as appropriate. Preserve the working `.htaccess` Authorization header forwarding rule.

## Safety

- The app has authenticated profiles; all profile operations must use an active `Bearer` token and derive user identity from the session in MySQL.
- Never commit `.env`, camera RTSP credentials, Google client secrets, Gmail app passwords, MySQL dumps with user data, or production private PHP config.
- The public Google OAuth **client ID** embedded in `google_login.php` is not an OAuth client secret.
- Keep the website's separate IQRA project files untouched.
