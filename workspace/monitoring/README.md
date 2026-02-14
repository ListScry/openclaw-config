# Global keep-alive + session monitoring

This folder is global (not tied to any repo).

## Goal
Every 8 minutes:
- open each site in the OpenClaw browser profile
- perform a harmless click/navigation to keep the authenticated session alive
- detect if the session is logged out/expired
- alert Jon only when intervention is needed

## Files
- `sites.json`: list of sites and heuristics

## Notes / reality check
Some sites (especially payment portals protected by Cloudflare/reCAPTCHA) may expire sessions regardless of activity or may detect automation. In those cases we can:
- best-effort keep-alive (open + minimal navigation)
- but expect periodic re-login

## Next step
Fill in stable `keepAliveAction` selectors for each site after we capture a snapshot of each logged-in page.
