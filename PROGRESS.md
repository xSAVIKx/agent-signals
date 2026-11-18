# Progress: corpus release assets (task A1)

## Done

1. `tools/release-corpus.sh` builds the corpus archives and `SHA256SUMS`.
2. `tools/test-release-corpus.sh` tests the script. The CI job "Scripts" runs it.
3. The job `corpus-assets` in `.github/workflows/release-please.yml` attaches the kit, the corpus archives, `SHA256SUMS` and an attestation. actionlint v1.7.12 passes.

## Next

1. Document the assets and the verification.

## Blocked

Nothing.
