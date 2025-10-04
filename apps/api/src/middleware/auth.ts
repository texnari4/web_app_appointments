import type { Request, Response, NextFunction } from 'express';

export function requireRole(...roles: Array<'client'|'master'|'admin'>) {
  return (req: Request, res: Response, next: NextFunction) => {
    const auth = (req as any).auth as { role: 'client' | 'master' | 'admin' };
    if (!auth || !roles.includes(auth.role)) {
      return res.status(403).json({ error: 'Forbidden' });
    }
    next();
  };
}
