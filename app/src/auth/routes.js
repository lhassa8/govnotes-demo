import { Router } from 'express';
import bcrypt from 'bcrypt';
import { z } from 'zod';
import { query } from '../lib/db.js';
import { badRequest, unauthorized } from '../lib/errors.js';
import { signAccessToken } from './jwt.js';

const loginSchema = z.object({
  email: z.string().email(),
  password: z.string().min(8).max(200),
});

export const authRouter = Router();

authRouter.post('/login', async (req, res, next) => {
  try {
    const parsed = loginSchema.safeParse(req.body);
    if (!parsed.success) {
      throw badRequest('invalid credentials payload');
    }

    const { email, password } = parsed.data;
    const { rows } = await query(
      'SELECT id, email, display_name, password_hash FROM users WHERE email = $1',
      [email.toLowerCase()],
    );
    const user = rows[0];
    if (!user) {
      throw unauthorized('invalid credentials');
    }

    const ok = await bcrypt.compare(password, user.password_hash);
    if (!ok) {
      throw unauthorized('invalid credentials');
    }

    const token = signAccessToken(user);
    res.json({
      accessToken: token,
      user: { id: user.id, email: user.email, displayName: user.display_name },
    });
  } catch (err) {
    next(err);
  }
});

authRouter.post('/logout', (_req, res) => {
  // Tokens are stateless; the client discards the access token. A real
  // revocation flow would write to a denylist table keyed by jti.
  res.status(204).send();
});
