import { describe, it, expect } from 'vitest';
import jwt from 'jsonwebtoken';
import { requireAuth } from '../src/auth/middleware.js';

const mkReq = (headers = {}) => ({ headers });

const runMiddleware = (req) =>
  new Promise((resolve) => {
    requireAuth(req, {}, (err) => resolve({ err, req }));
  });

describe('requireAuth', () => {
  it('rejects when no authorization header is present', async () => {
    const { err } = await runMiddleware(mkReq());
    expect(err).toBeDefined();
    expect(err.status).toBe(401);
  });

  it('rejects when the scheme is not Bearer', async () => {
    const { err } = await runMiddleware(mkReq({ authorization: 'Basic abc' }));
    expect(err).toBeDefined();
    expect(err.status).toBe(401);
  });

  it('rejects an invalid token', async () => {
    const { err } = await runMiddleware(mkReq({ authorization: 'Bearer not-a-real-token' }));
    expect(err).toBeDefined();
    expect(err.status).toBe(401);
  });

  it('attaches req.user for a valid token', async () => {
    const token = jwt.sign(
      { sub: 'user-123', email: 'alice@govnotes.local' },
      process.env.JWT_SIGNING_KEY,
      { algorithm: 'HS256', issuer: 'govnotes', expiresIn: 60 },
    );
    const { err, req } = await runMiddleware(mkReq({ authorization: `Bearer ${token}` }));
    expect(err).toBeUndefined();
    expect(req.user).toEqual({ id: 'user-123', email: 'alice@govnotes.local' });
  });
});
