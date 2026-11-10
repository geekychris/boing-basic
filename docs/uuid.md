# CreateUUID: unique identifiers

`CreateUUID()` returns a new random UUID (version 4), as 36 characters in lower case:

```basic
Print CreateUUID()          ' 3f2b8c1e-9d4a-4e7b-a5c2-0d8e6f1b2a93
```

Use one when a record, file or message needs a name nobody else will pick: database keys that
must not collide between machines, temporary file names, session ids. The chance of two being
the same is negligible (122 random bits).

The form is `xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx`: hexadecimal digits, `4` marks the version and
`y` is one of 8, 9, a, b (RFC 4122).

Randomness comes from the system where it has a source (`/dev/urandom` on the host); on AmigaOS
the generator is seeded from the EClock, the time and memory addresses and stirred again from the
clock on every call. Good for identifiers; for keys and passwords use a cryptographic source.

Tested by `tests/libs/uuidtest.bas` (2000 UUIDs: format, version and variant digits, no
duplicates).
