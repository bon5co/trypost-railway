#!/bin/sh
# TryPost on Railway: derive settings, prepare the storage volume, migrate, create the first user and API key, then start supervisord.
set -e
cd /var/www/html

# Railway ignores OCI whiteouts, so the dev-time package manifest that upstream deleted in a later layer comes back and
# names laravel/pail, which production does not install: drop both caches and let Laravel rebuild them from vendor/
rm -f bootstrap/cache/packages.php bootstrap/cache/services.php

need() { eval "v=\${$1:-}"; [ -n "$v" ] || { echo "[railway-boot] $1 is required" >&2; exit 1; }; }
for n in APP_URL APP_SECRET DB_HOST DB_USERNAME DB_PASSWORD DB_DATABASE REDIS_HOST REDIS_PASSWORD REVERB_APP_SECRET ADMIN_EMAIL ADMIN_PASSWORD; do need "$n"; done

PORT="${PORT:-8080}"
DOMAIN="${APP_URL#https://}"; DOMAIN="${DOMAIN%%/*}"

# A stable APP_KEY from a generated secret: the same value on every redeploy, so sessions and encrypted columns survive
if [ -z "${APP_KEY:-}" ]; then
  APP_KEY="base64:$(printf %s "$APP_SECRET" | openssl dgst -sha256 -binary | openssl base64 -A)"
  export APP_KEY
fi

# The volume mounts root-owned and empty over upstream's storage skeleton
mkdir -p storage/app/public storage/app/private storage/framework/cache/data storage/framework/sessions storage/framework/views \
  storage/framework/testing storage/logs storage/bootstrap bootstrap/cache
chmod 0755 storage/bootstrap

# Passport signs API tokens with this pair: made once, kept on the volume
if [ ! -s storage/oauth-private.key ] || [ ! -s storage/oauth-public.key ]; then
  echo "[railway-boot] generating Passport keys"
  rm -f storage/oauth-private.key storage/oauth-public.key
  php artisan passport:keys --force --no-interaction
fi
chown www-data:www-data storage/oauth-private.key storage/oauth-public.key
chmod 0600 storage/oauth-private.key storage/oauth-public.key  # league/oauth2-server rejects any other mode, public key included

# nginx on the injected PORT, with the key route; the htpasswd is the admin login
sed "s/__PORT__/$PORT/g" /railway-nginx.conf.tmpl > /etc/nginx/http.d/default.conf
printf '%s:%s\n' "$ADMIN_EMAIL" "$(openssl passwd -apr1 "$ADMIN_PASSWORD")" > /etc/nginx/railway.htpasswd
chmod 0644 /etc/nginx/railway.htpasswd

# The browser bundle was built for localhost:8080 over ws; point it at the public domain over wss on 443
JS=$(grep -l 'wsHost:`localhost`,wsPort:`8080`' public/build/assets/*.js 2>/dev/null || true)
if [ -n "$JS" ]; then
  for f in $JS; do
    sed -i "s/wsHost:\`localhost\`,wsPort:\`8080\`,wssPort:\`8080\`,forceTLS:!1/wsHost:\`$DOMAIN\`,wsPort:\`443\`,wssPort:\`443\`,forceTLS:!0/g" "$f"
  done
  echo "[railway-boot] websocket address set to $DOMAIN"
elif ! grep -q "wsHost:\`$DOMAIN\`" public/build/assets/*.js 2>/dev/null; then
  echo "[railway-boot] websocket address not found in the browser bundle" >&2
  exit 1
fi

# Postgres is a separate service that may still be starting; the generate project also starts three copies of this app at once,
# which race the same migration, so retry
n=0
until pg_isready -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USERNAME" -d "$DB_DATABASE" >/dev/null 2>&1; do
  n=$((n+1)); [ "$n" -le 90 ] || { echo "[railway-boot] postgres not reachable" >&2; exit 1; }; sleep 2
done
n=0
until php artisan migrate --force --no-interaction; do
  n=$((n+1)); [ "$n" -le 8 ] || { echo "[railway-boot] migrate failed" >&2; exit 1; }
  echo "[railway-boot] migrate failed, retry $n"; sleep 6
done
php artisan changelog:sync || true
php artisan db:seed --class='Database\Seeders\PassportSeeder' --force
php /railway-bootstrap.php
[ -L public/storage ] || php artisan storage:link --force || true

php artisan config:cache
php artisan route:cache
php artisan view:cache
php artisan event:cache

chown -R www-data:www-data storage bootstrap/cache
# the key file stays root-owned and readable by nginx's workers only through the basic-auth route
chown root:root storage/bootstrap storage/bootstrap/api-key.txt 2>/dev/null || true
echo "[railway-boot] ready, starting supervisord"
exec /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf
