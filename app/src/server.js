import express from 'express';
import helmet from 'helmet';
import rateLimit from 'express-rate-limit';
import pinoHttp from 'pino-http';

import { config } from './config.js';
import { logger } from './lib/logger.js';
import { errorHandler, notFound } from './lib/errors.js';
import { authRouter } from './auth/routes.js';
import { notesRouter } from './notes/routes.js';
import { usersRouter } from './users/routes.js';

export const buildApp = () => {
  const app = express();

  app.disable('x-powered-by');
  app.set('trust proxy', 1);

  app.use(helmet());
  app.use(express.json({ limit: '1mb' }));
  app.use(pinoHttp({ logger }));

  const authLimiter = rateLimit({
    windowMs: 15 * 60 * 1000,
    limit: 20,
    standardHeaders: 'draft-7',
    legacyHeaders: false,
  });

  app.get('/health', (_req, res) => res.json({ status: 'ok' }));

  app.use('/auth', authLimiter, authRouter);
  app.use('/notes', notesRouter);
  app.use('/users', usersRouter);

  app.use((_req, _res, next) => next(notFound('route not found')));
  app.use(errorHandler(logger));

  return app;
};

if (import.meta.url === `file://${process.argv[1]}`) {
  const app = buildApp();
  app.listen(config.port, () => {
    logger.info({ port: config.port }, 'govnotes app listening');
  });
}
