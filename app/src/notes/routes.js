import { Router } from 'express';
import { z } from 'zod';
import { query } from '../lib/db.js';
import { badRequest, notFound } from '../lib/errors.js';
import { requireAuth } from '../auth/middleware.js';

const createSchema = z.object({
  title: z.string().min(1).max(200),
  body: z.string().max(64_000),
});

const updateSchema = z.object({
  title: z.string().min(1).max(200).optional(),
  body: z.string().max(64_000).optional(),
});

const toDto = (row) => ({
  id: row.id,
  title: row.title,
  body: row.body,
  createdAt: row.created_at,
  updatedAt: row.updated_at,
});

export const notesRouter = Router();

notesRouter.use(requireAuth);

notesRouter.get('/', async (req, res, next) => {
  try {
    const { rows } = await query(
      'SELECT id, title, body, created_at, updated_at FROM notes WHERE owner_id = $1 ORDER BY updated_at DESC LIMIT 100',
      [req.user.id],
    );
    res.json({ items: rows.map(toDto) });
  } catch (err) {
    next(err);
  }
});

notesRouter.post('/', async (req, res, next) => {
  try {
    const parsed = createSchema.safeParse(req.body);
    if (!parsed.success) {
      throw badRequest('invalid note payload');
    }
    const { title, body } = parsed.data;
    const { rows } = await query(
      `INSERT INTO notes (owner_id, title, body)
       VALUES ($1, $2, $3)
       RETURNING id, title, body, created_at, updated_at`,
      [req.user.id, title, body],
    );
    res.status(201).json(toDto(rows[0]));
  } catch (err) {
    next(err);
  }
});

notesRouter.get('/:id', async (req, res, next) => {
  try {
    const { rows } = await query(
      'SELECT id, title, body, created_at, updated_at FROM notes WHERE id = $1 AND owner_id = $2',
      [req.params.id, req.user.id],
    );
    if (!rows[0]) {
      throw notFound('note not found');
    }
    res.json(toDto(rows[0]));
  } catch (err) {
    next(err);
  }
});

notesRouter.patch('/:id', async (req, res, next) => {
  try {
    const parsed = updateSchema.safeParse(req.body);
    if (!parsed.success || Object.keys(parsed.data).length === 0) {
      throw badRequest('invalid note payload');
    }
    const fields = [];
    const values = [];
    let idx = 1;
    for (const [k, v] of Object.entries(parsed.data)) {
      fields.push(`${k} = $${idx++}`);
      values.push(v);
    }
    values.push(req.params.id, req.user.id);
    const { rows } = await query(
      `UPDATE notes SET ${fields.join(', ')}, updated_at = NOW()
       WHERE id = $${idx++} AND owner_id = $${idx}
       RETURNING id, title, body, created_at, updated_at`,
      values,
    );
    if (!rows[0]) {
      throw notFound('note not found');
    }
    res.json(toDto(rows[0]));
  } catch (err) {
    next(err);
  }
});

notesRouter.delete('/:id', async (req, res, next) => {
  try {
    const result = await query(
      'DELETE FROM notes WHERE id = $1 AND owner_id = $2',
      [req.params.id, req.user.id],
    );
    if (result.rowCount === 0) {
      throw notFound('note not found');
    }
    res.status(204).send();
  } catch (err) {
    next(err);
  }
});

notesRouter.post('/:id/attachments', async (req, res, next) => {
  try {
    const { rows } = await query(
      'SELECT id FROM notes WHERE id = $1 AND owner_id = $2',
      [req.params.id, req.user.id],
    );
    if (!rows[0]) {
      throw notFound('note not found');
    }
    // Stub presigned URL — wired up for real once we integrate the
    // AWS SDK client in the commercial codebase.
    res.json({
      uploadUrl: 'https://stub.govnotes.local/uploads/' + req.params.id,
      expiresIn: 900,
    });
  } catch (err) {
    next(err);
  }
});
