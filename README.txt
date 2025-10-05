Admin UI (extended) — drop-in bundle
====================================

What this is
------------
A frontend-only admin panel you can copy to your server's `/public/admin`.
It adds sections:
  • Мастера — add/edit/delete
  • Услуги — add/edit/delete
  • Клиенты — add/edit/delete
  • Записи — create/edit status/delete + list
  • Отчёты — quick summary by dates
  • Настройки — basic app settings

Assumed API endpoints (existing in your server):
  GET    /public/api/masters
  POST   /public/api/masters
  PUT    /public/api/masters/:id
  DELETE /public/api/masters/:id

  GET    /public/api/services
  POST   /public/api/services
  PUT    /public/api/services/:id
  DELETE /public/api/services/:id

  GET    /public/api/clients
  POST   /public/api/clients
  PUT    /public/api/clients/:id
  DELETE /public/api/clients/:id

  GET    /public/api/appointments?from=&to=&masterId=&clientId=&serviceId=
  POST   /public/api/appointments
  PUT    /public/api/appointments/:id
  DELETE /public/api/appointments/:id

  GET    /public/api/reports/summary?from=&to=
  GET    /public/api/settings
  PUT    /public/api/settings

Install
-------
1) Copy the folder `public/admin/` from this archive to your runtime image or volume
   so it is served at `https://<host>/admin/` (or `/public/admin/` if you mount it so).
2) Make sure your static server maps `/admin` to this folder and serves correct MIME types.
3) Open /admin/ in browser.

Notes
-----
• No build step is required — plain HTML/CSS/JS.
• If your admin is under `/admin/`, keep the `<link href="styles.css">` and
  `<script src="admin.js" type="module">` as is.
