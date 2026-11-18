# Progress: corpus release assets (task A1)

## Done

1. `tools/release-corpus.sh` builds the corpus archives and `SHA256SUMS`.
2. `tools/test-release-corpus.sh` tests the script. The CI job "Scripts" runs it.
3. The job `corpus-assets` in `.github/workflows/release-please.yml` attaches the kit, the corpus archives, `SHA256SUMS` and an attestation. actionlint v1.7.12 passes.
4. `README.md` lists the files of a corpus release and the verification steps.

## Next

1. The operator checks the first corpus release after the merge (the question below).

## Blocked

Nothing. No release, tag or `workflow_dispatch` run was made. The job is not measured on GitHub.

## Question for the operator

After the merge, the first `corpus-v*` release runs the new job `corpus-assets`.
Please check that release and answer this question:

> Does the release `corpus-vX.Y.Z` have the files `agent-signals-corpus-X.Y.Z.tar.gz`,
> `agent-signals-corpus-X.Y.Z.zip`, `SHA256SUMS`, `agent-signals-kit.tar.gz`,
> `agent-signals-kit.zip` and `agent-signals-kit.sha256`, and do
> `sha256sum -c SHA256SUMS` and
> `gh attestation verify agent-signals-corpus-X.Y.Z.tar.gz --repo xSAVIKx/agent-signals`
> both pass?

If the job fails, read the log of the job "Corpus release assets". The kit
files are uploaded before the attestation step, so a failed attestation does
not stop the kit download.
