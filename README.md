# Admin Panel Inline v4

Self-contained admin panel with inline CSS and JS (no separate styles.css/admin.js).
Place the `public/admin/index.html` into your project's `public/admin/` so that it's served at `/admin/`.

## Features
- Tabs: Masters, Services (read-only list for now).
- Masters: list, create (name, phone, avatar URL, isActive). Instant refresh without page reload.
- Uses endpoints:
  - GET  /public/api/masters
  - POST /public/api/masters
  - GET  /public/api/services

## Deploy notes
- No external CSS/JS requests (prevents 404/MIME issues).
- Works with CORS disabled if served under the same host.
- Expects your server to statically serve `/public/admin/index.html` at `/admin/` or `/public/admin/`.

