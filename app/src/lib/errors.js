export class HttpError extends Error {
  constructor(status, code, message) {
    super(message);
    this.status = status;
    this.code = code;
  }
}

export const badRequest = (message, code = 'bad_request') =>
  new HttpError(400, code, message);

export const unauthorized = (message = 'unauthorized') =>
  new HttpError(401, 'unauthorized', message);

export const forbidden = (message = 'forbidden') =>
  new HttpError(403, 'forbidden', message);

export const notFound = (message = 'not found') =>
  new HttpError(404, 'not_found', message);

export const errorHandler = (logger) => (err, _req, res, _next) => {
  if (err instanceof HttpError) {
    res.status(err.status).json({ error: { code: err.code, message: err.message } });
    return;
  }
  logger.error({ err }, 'unhandled error');
  res.status(500).json({ error: { code: 'internal', message: 'internal server error' } });
};
