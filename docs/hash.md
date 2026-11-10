# Checksums and hashes

| Function | Result |
|---|---|
| `Crc32(s)` | the CRC-32 checksum (as used by Zip, PNG, gzip) as a Long; `Hex(Crc32(s))` gives the usual 8 hex digits |
| `Md5(s [, raw])` | MD5, 32 hex digits |
| `Sha1(s [, raw])` | SHA-1, 40 hex digits |
| `Sha256(s [, raw])` | SHA-256, 64 hex digits |
| `HmacSha1(key, s [, raw])` | HMAC with SHA-1 |
| `HmacSha256(key, s [, raw])` | HMAC with SHA-256 |

Hex digits are lowercase. With `raw` = True the digest comes back as its bytes (16, 20 or 32
characters) instead, for feeding into `Base64Encode` or another hash. Strings hold bytes, so any
data can be hashed: read a file in Binary mode into a String and hash that.

```basic
Print Sha256("abc")
' ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad

' check a download
data = web.Get(url)
If Sha256(data) <> expected Then MsgBox "The file is damaged", vbCritical

' sign an API request (e.g. a webhook or an S3-style signature)
sig = Base64Encode(HmacSha256(secret, payload, True))
web.SetHeader "X-Signature", sig
```

Which to use: `Crc32` to notice accidental damage (fast, not secure); `Sha256` to identify or check
data; `HmacSha256` to prove a message came from someone who knows the key. MD5 and SHA-1 are
there for formats and services that still ask for them; don't use them for new security uses.

All of them are written in portable C inside Boing BASIC, so they work without AmiSSL.

## Tests

`tests/lib/hashtest.bas` (in `make test`, VM and native): the published test vectors (RFC 1321
for MD5, FIPS 180 for SHA-1 and SHA-256 including the one-million-"a" messages, RFC 2202 and RFC
4231 for HMAC with long keys), block-boundary lengths 55–65, raw digests, binary input. On the
AmigaOS 4 guest: identical output in the VM and native.
