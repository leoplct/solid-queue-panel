# Security policy

## Reporting a vulnerability

Please report security issues privately through
[GitHub's advisory form](https://github.com/leoplct/solid-queue-panel/security/advisories/new),
not as a public issue.

Include what an attacker can do, the version you found it on, and the smallest
reproduction you have. You can expect a first reply within a week, and an
advisory with a fixed release once the problem is confirmed and understood.

## Supported versions

Until 1.0, fixes go to the latest release only.

## What the panel exposes

The panel reads and writes the tables Solid Queue owns, and shows Active Job
payloads. Anybody who reaches it can, unless it is configured otherwise, see
what your jobs were enqueued with and discard, retry or pause them. Two things
follow, and both are configuration rather than defects:

- **Reaching the panel is the whole boundary.** Leaving `username` and
  `password` blank, with no `authenticate_with` block and no route constraint,
  leaves it open to anyone who can load the URL.
- **A shared password identifies nobody.** The built-in form authenticates the
  panel, not a person. Where individual accountability is required, mount the
  panel behind your application's own authentication and set `config.audit_actor`.

See [Sensitive payloads and the audit trail](README.md#sensitive-payloads-and-the-audit-trail)
for filtering payloads, hiding them entirely, and where the audit trail goes.
