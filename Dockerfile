# TryPost wrapper for Railway. The official image runs nginx, php-fpm, Reverb (websockets), Horizon (queues) and the scheduler under
# supervisord, listens on 80, expects the deployer to run `passport:keys`, hand-write a base64 APP_KEY, create the first user and
# rebuild the browser bundle with the public domain. Railway's healthcheck and edge dial the injected PORT and mount volumes owned by
# root, so this wrapper moves nginx onto $PORT, Reverb onto an internal port, derives the settings from variables at boot, keeps the
# Passport keys on the storage volume, rewrites the baked websocket address in the browser bundle to the public domain, creates the
# first user and an API key from ADMIN_EMAIL / ADMIN_PASSWORD, and only then starts the web server.
# Literals a deployer should never have to type are baked in here as ENV.
# upstream: trypostit/trypost
FROM ghcr.io/trypostit/trypost:2.1.0@sha256:de002279037d8c86eec16f2caad9ed8bb02ac259a25b0abfc43f3d18738777e6

# Reverb moves off 8080 (Railway injects PORT=8080 and nginx must own it); nginx.conf is upstream's with PORT and the key route added
RUN sed -i 's/--port=8080/--port=6001/' /etc/supervisor/conf.d/supervisord.conf
COPY nginx.conf /railway-nginx.conf.tmpl
COPY --chmod=0755 boot.sh /railway-boot.sh
COPY --chmod=0644 bootstrap.php /railway-bootstrap.php

ENV APP_ENV=production \
    APP_DEBUG=false \
    SELF_HOSTED=true \
    TRYPOST_TARGET=production \
    DB_CONNECTION=pgsql \
    DB_PORT=5432 \
    REDIS_PORT=6379 \
    QUEUE_CONNECTION=redis \
    CACHE_STORE=redis \
    SESSION_DRIVER=database \
    SESSION_SECURE_COOKIE=true \
    BROADCAST_CONNECTION=reverb \
    REVERB_APP_ID=trypost \
    REVERB_APP_KEY=trypost-reverb-key \
    REVERB_HOST=127.0.0.1 \
    REVERB_PORT=6001 \
    REVERB_SCHEME=http \
    REVERB_SERVER_PORT=6001 \
    PASSPORT_PRIVATE_KEY=file:///var/www/html/storage/oauth-private.key \
    PASSPORT_PUBLIC_KEY=file:///var/www/html/storage/oauth-public.key \
    FILESYSTEM_DISK=public \
    MAIL_MAILER=log \
    LOG_CHANNEL=stderr \
    LOG_LEVEL=info \
    NIGHTWATCH_ENABLED=false \
    TELESCOPE_ENABLED=false \
    POSTHOG_ENABLED=false

VOLUME ["/var/www/html/storage"]
EXPOSE 8080
ENTRYPOINT ["/railway-boot.sh"]
