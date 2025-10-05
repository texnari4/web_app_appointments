// Register Services routes on an existing Express app
import type { Express, Request, Response } from 'express';
import * as store from './services';

export function registerServiceRoutes(app: Express) {
  // List all services + groups
  app.get('/public/api/services', async (_req: Request, res: Response) => {
    try {
      const data = await store.listAll();
      res.json(data);
    } catch (e: any) {
      res.status(500).json({ error: 'Failed to read services' });
    }
  });

  // Groups CRUD
  app.post('/public/api/service-groups', async (req: Request, res: Response) => {
    try {
      const g = await store.createGroup({ name: req.body?.name, isActive: req.body?.isActive });
      res.status(201).json(g);
    } catch (e: any) {
      res.status(400).json({ error: e?.message || 'Failed to create group' });
    }
  });

  app.put('/public/api/service-groups/:id', async (req: Request, res: Response) => {
    try {
      const g = await store.updateGroup(req.params.id, req.body || {});
      res.json(g);
    } catch (e: any) {
      res.status(404).json({ error: e?.message || 'Failed to update group' });
    }
  });

  app.delete('/public/api/service-groups/:id', async (req: Request, res: Response) => {
    try {
      await store.deleteGroup(req.params.id);
      res.status(204).end();
    } catch (e: any) {
      res.status(404).json({ error: e?.message || 'Failed to delete group' });
    }
  });

  // Items CRUD
  app.post('/public/api/services', async (req: Request, res: Response) => {
    try {
      const s = await store.createService(req.body || {});
      res.status(201).json(s);
    } catch (e: any) {
      res.status(400).json({ error: e?.message || 'Failed to create service' });
    }
  });

  app.put('/public/api/services/:id', async (req: Request, res: Response) => {
    try {
      const s = await store.updateService(req.params.id, req.body || {});
      res.json(s);
    } catch (e: any) {
      res.status(404).json({ error: e?.message || 'Failed to update service' });
    }
  });

  app.delete('/public/api/services/:id', async (req: Request, res: Response) => {
    try {
      await store.deleteService(req.params.id);
      res.status(204).end();
    } catch (e: any) {
      res.status(404).json({ error: e?.message || 'Failed to delete service' });
    }
  });
}
