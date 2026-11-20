<?php
// First boot: the owner account from ADMIN_EMAIL / ADMIN_PASSWORD, and an API key for it written to storage/bootstrap/api-key.txt
// (served only behind that same login by nginx). Idempotent: an existing user or key file is left alone.
require '/var/www/html/vendor/autoload.php';
$app = require '/var/www/html/bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();

$email = (string) getenv('ADMIN_EMAIL');
$password = (string) getenv('ADMIN_PASSWORD');
if ($email === '' || strlen($password) < 16) {
    fwrite(STDERR, "[bootstrap] ADMIN_EMAIL and an ADMIN_PASSWORD of at least 16 characters are required\n");
    exit(1);
}

$user = App\Models\User::query()->where('email', $email)->first();
if (! $user && ! App\Models\User::query()->exists()) {
    try {
        $user = App\Actions\User\CreateUser::execute([
            'name' => 'Administrator',
            'email' => $email,
            'password' => $password,
            'email_verified_at' => now(),
        ]);
        echo "[bootstrap] created owner $email\n";
    } catch (Throwable $e) {
        // another copy of this boot won the race
        $user = App\Models\User::query()->where('email', $email)->first();
        if (! $user) { throw $e; }
    }
}
if (! $user) {
    echo "[bootstrap] a different account already owns this install, no key minted\n";
    exit(0);
}

$file = '/var/www/html/storage/bootstrap/api-key.txt';
if (is_file($file) && filesize($file) > 0) {
    exit(0);
}
$workspace = $user->refresh()->currentWorkspace;
if (! $workspace) {
    fwrite(STDERR, "[bootstrap] owner has no workspace\n");
    exit(1);
}
$created = App\Actions\ApiKey\IssueApiKey::execute($user, $workspace, ['name' => 'railway-bootstrap']);
file_put_contents($file, $created['plain_token'] . "\n");
chmod($file, 0644);
echo "[bootstrap] API key written\n";
