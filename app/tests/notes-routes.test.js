import { describe, it, expect, beforeEach, vi } from 'vitest';
import request from 'supertest';
import jwt from 'jsonwebtoken';

vi.mock('../src/lib/db.js', () => ({
  query: vi.fn(),
  withTransaction: vi.fn(),
  pool: { end: vi.fn() },
}));

const { query } = await import('../src/lib/db.js');
const { buildApp } = await import('../src/server.js');

const tokenFor = (userId) =>
  jwt.sign({ sub: userId, email: 'u@govnotes.local' }, process.env.JWT_SIGNING_KEY, {
    algorithm: 'HS256',
    issuer: 'govnotes',
    expiresIn: 60,
  });

describe('notes routes', () => {
  beforeEach(() => {
    query.mockReset();
  });

  it('requires auth', async () => {
    const app = buildApp();
    const res = await request(app).get('/notes');
    expect(res.status).toBe(401);
  });

  it('lists notes for the authenticated user', async () => {
    query.mockResolvedValueOnce({
      rows: [
        {
          id: 'n1',
          title: 't',
          body: 'b',
          created_at: '2026-04-01T00:00:00Z',
          updated_at: '2026-04-02T00:00:00Z',
        },
      ],
    });
    const app = buildApp();
    const res = await request(app)
      .get('/notes')
      .set('Authorization', `Bearer ${tokenFor('user-1')}`);
    expect(res.status).toBe(200);
    expect(res.body.items).toHaveLength(1);
    expect(query.mock.calls[0][1]).toEqual(['user-1']);
  });

  it('rejects an invalid create payload', async () => {
    const app = buildApp();
    const res = await request(app)
      .post('/notes')
      .set('Authorization', `Bearer ${tokenFor('user-1')}`)
      .send({ title: '' });
    expect(res.status).toBe(400);
  });
});
