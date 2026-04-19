import { describe, it, expect, vi } from 'vitest';
import { HttpError, badRequest, errorHandler } from '../src/lib/errors.js';

describe('errorHandler', () => {
  it('renders an HttpError as JSON', () => {
    const res = {
      status: vi.fn().mockReturnThis(),
      json: vi.fn(),
    };
    const logger = { error: vi.fn() };
    errorHandler(logger)(badRequest('nope'), {}, res, () => {});
    expect(res.status).toHaveBeenCalledWith(400);
    expect(res.json).toHaveBeenCalledWith({
      error: { code: 'bad_request', message: 'nope' },
    });
  });

  it('renders an unknown error as a 500', () => {
    const res = {
      status: vi.fn().mockReturnThis(),
      json: vi.fn(),
    };
    const logger = { error: vi.fn() };
    errorHandler(logger)(new Error('boom'), {}, res, () => {});
    expect(res.status).toHaveBeenCalledWith(500);
    expect(logger.error).toHaveBeenCalled();
  });

  it('HttpError keeps its status and code', () => {
    const err = new HttpError(418, 'teapot', 'short and stout');
    expect(err.status).toBe(418);
    expect(err.code).toBe('teapot');
  });
});
