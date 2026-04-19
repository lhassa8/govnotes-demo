import { Router } from 'express';
import { query } from '../lib/db.js';
import { notFound } from '../lib/errors.js';
import { requireAuth } from '../auth/middleware.js';

export const usersRouter = Router();

usersRouter.get('/me', requireAuth, async (req, res, next) => {
  try {
    const { rows } = await query(
      'SELECT id, email, display_name, created_at FROM users WHERE id = $1',
      [req.user.id],
    );
    const user = rows[0];
    if (!user) {
      throw notFound('user not found');
    }
    res.json({
      id: user.id,
      email: user.email,
      displayName: user.display_name,
      createdAt: user.created_at,
    });
  } catch (err) {
    next(err);
  }
});
