# trypost-railway

Wrapper image for [TryPost](https://github.com/trypostit/trypost) (self-hosted social media scheduler, AGPL-3.0) on Railway.

It runs the official `ghcr.io/trypostit/trypost` image, pinned by digest, with nginx moved onto Railway's injected `PORT`, Reverb
(websockets) moved to an internal port, `APP_KEY` derived from a generated secret, Passport keys generated once onto the storage volume,
the baked websocket address in the browser bundle rewritten to the public domain, migrations retried, the owner account created from
`ADMIN_EMAIL` / `ADMIN_PASSWORD`, public registration left closed, and an API key minted once and served behind that login at
`/bootstrap/api-key`.

Needs Postgres and Redis alongside it; the Railway template wires both. Licence of this wrapper: MIT. TryPost itself is AGPL-3.0.
