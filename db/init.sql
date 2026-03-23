-- Create separate database for n8n internal state
SELECT 'CREATE DATABASE n8n' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'n8n')\gexec

-- Placeholder for app schema
SELECT 1;
