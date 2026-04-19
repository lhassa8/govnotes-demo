// Tests do not connect to a real database. We set enough env to let
// config.js parse and we stub the db module per-test.
process.env.NODE_ENV = 'test';
process.env.DATABASE_URL = 'postgres://test:test@localhost:5432/test';
process.env.JWT_SIGNING_KEY = 'test-signing-key-do-not-use-anywhere-else';
process.env.LOG_LEVEL = 'silent';
