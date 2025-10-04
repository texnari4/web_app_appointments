# Web App Appointments – Next Version

This version builds upon the minimal skeleton by introducing a **Master** entity and corresponding REST API endpoints.

## Features Added

- **Master model** (`Master`): Allows adding service providers (e.g. stylists or manicurists) with `name`, `phone`, and optional `email` fields. A master can have many services.
- **Service model update**: Each `Service` can optionally belong to a master via `masterId`. The API includes the associated `Master` when fetching services.
- **Endpoints**
  - `GET /masters` – lists all masters with their services.
  - `POST /masters` – creates a new master with validation using Zod.
  - `GET /services` – lists services with related masters.
  - `POST /services` – creates a new service. Accepts an optional `masterId` to associate the service with a master.
- **Data seeding**: A simple seed script (`scripts/seed.ts`) populates the database with one master (Ирина) and two services (Маникюр and Педикюр).
- **Validation**: Requests are validated with **Zod** before reaching the database.
- **Logging**: `pino` and `pino-http` provide structured logging.

## Usage

Install dependencies and generate the Prisma client:

```bash
npm install
npx prisma generate
```

Apply migrations and seed the database (optional):

```bash
npm run prisma:sync
npm run seed
```

Start the development server:

```bash
npm run build
npm start
```

The server listens on `PORT` (default 8080) and exposes the routes documented above.

## Next Steps

Future iterations could introduce:

- Appointment scheduling linking clients, services, and masters.
- Authentication and role-based access control.
- Admin dashboard improvements.
- Additional validation and business logic.
