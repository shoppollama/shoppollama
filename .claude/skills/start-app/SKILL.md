---
name: start-app
description: Start the Shoppollama Phoenix app locally on http://localhost:4000. Use when the user runs /start-app or asks to start/run/boot the app/server in this repo.
---

# Start Shoppollama locally

Bring up the local Phoenix LiveView server on port 4000. The app depends on a running Ollama instance on port 11434.

## Steps

1. **Check port 4000 isn't already in use.** Run `lsof -i :4000`. If something is listening, tell the user and stop — don't kill it.

2. **Verify Ollama is running.** Run `curl -sS -o /dev/null -w "%{http_code}\n" http://localhost:11434/api/tags`. If it returns anything other than `200`, tell the user to run `ollama serve` in another terminal and stop.

3. **Start Phoenix in the background.** From the repo root, launch:
   ```
   MIX_ENV=dev mix phx.server
   ```
   Use the Bash tool with `run_in_background: true` so logs stream to a file you can tail.

4. **Wait for readiness.** Poll `http://localhost:4000` with an `until` loop until it returns a response, e.g.:
   ```
   until curl -sS -o /dev/null http://localhost:4000 2>/dev/null; do sleep 1; done
   ```
   Use Bash `run_in_background: true` so you get a single completion notification.

5. **Confirm to the user.** Once ready, report the URL `http://localhost:4000` and the background task ID so they can read logs or stop it later.

## Notes

- If `mix setup` has never been run (no `_build` or `deps` dirs), run `mix setup` first to fetch deps and migrate the DB.
- The DB file is `shoppollama_dev.db` (SQLite) at the repo root. Don't delete it.
- Stripe env vars (`STRIPE_SECRET_KEY`, `STRIPE_PUBLISHABLE_KEY`) are optional for booting; payment features won't work without them but the app starts fine.
