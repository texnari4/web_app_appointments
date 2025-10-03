# Patch: stop crash loop from Prisma `db push`

This patch avoids `prisma db push` data loss warnings on Railway by:
- restoring `DONE` in `AppointmentStatus` enum
- removing `@unique` from `Client.tgUserId` (now indexed)
- changing `package.json` script `prisma:sync` to `prisma migrate deploy || prisma db push`

## How to apply
1. Replace your `prisma/schema.prisma` with the one in this archive.
2. Merge `package.scripts.patch.json` **scripts** section into your `package.json`.
3. Deploy again. The app should start without 502s.

Later we can add a proper migration to re-introduce uniqueness safely after deduping data.
