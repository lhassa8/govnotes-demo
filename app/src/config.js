const required = (name) => {
  const value = process.env[name];
  if (!value) {
    throw new Error(`Missing required env var: ${name}`);
  }
  return value;
};

const optional = (name, fallback) => process.env[name] ?? fallback;

export const config = {
  env: optional('NODE_ENV', 'development'),
  port: Number(optional('PORT', '3000')),
  logLevel: optional('LOG_LEVEL', 'info'),
  databaseUrl: required('DATABASE_URL'),
  jwt: {
    signingKey: required('JWT_SIGNING_KEY'),
    accessTtlSeconds: Number(optional('JWT_ACCESS_TTL', '900')),
    issuer: 'govnotes',
  },
  uploads: {
    bucket: optional('USER_UPLOADS_BUCKET', ''),
    region: optional('AWS_REGION', 'us-east-1'),
  },
};
