-- Dev/test-only seed user. NOT for production use.
-- Credentials: test@tervisehull.ee / DevPassword123!
-- Hash generated with: htpasswd -bnBC 10 "" 'DevPassword123!'
INSERT INTO users (email, password_hash)
VALUES ('test@tervisehull.ee', '$2y$10$s6nGETqT4tTj1l/XSj/Uh.gIWnOQ4IiYICtI6T1g9uHg5ke1NOq8y');
