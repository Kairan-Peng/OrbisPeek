# Security policy

Quicklook is in early development. There is no stable support or backport schedule yet; security fixes target the current development version. Do not treat development or locally signed packages as notarized releases.

## Reporting a vulnerability

If the repository's Security tab offers **Report a vulnerability**, use that private reporting form. This is conditional: the project does not currently advertise a dedicated private email address or guarantee that GitHub private reporting is enabled.

If no private form is available, open an issue asking a maintainer to arrange a private reporting channel. Include only a broad description, such as “potential local file access issue”; withhold exploit steps, affected private documents, personal paths and credentials until a private channel is agreed. Do not use a public issue for sensitive details. We do not promise a response-time SLA.

Once a private channel is available, useful evidence includes the app version/build, macOS version, installation method, affected component, impact, reproduction steps and a synthetic minimal sample. Maintainers will assess the report, coordinate a fix and discuss disclosure with the reporter.

## Scope and boundaries

Relevant issues include sandbox or directory-authorization bypasses, unexpected script execution or network requests from document content, escaping local-resource boundaries, and unsafe handling of malformed or large files. Rendering differences or a conflicting Quick Look provider can be reported through the ordinary bug template.

Documents are untrusted input. The renderer limits document reads, disables document-provided scripts and restricts local images. Optional directory access is read-only and can be revoked in the host. These are intended boundaries, not a guarantee that every input or platform has been audited. See [local resource documentation](docs/local-image-access.md) for details.

Never attach developer certificates, private keys, Apple credentials or unreviewed diagnostic exports to a report. Build and release workflows must keep credentials outside the repository and require explicit notarization configuration.
