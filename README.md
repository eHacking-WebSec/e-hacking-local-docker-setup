# README

To use the local ehacking docker setup, the domains from the `.env` file must point to the local system (`127.0.0.1`). The `/etc/hosts` file can be used for this under Linux. In addition, the browser must trust the certificate used under `certificates`.

You can then start the local setup using `docker compose up -d`.

Hint: check the config before starting using `docker compose config`.
