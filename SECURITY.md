# Security Policy

## Supported versions

Security fixes are applied to the latest commit on the default branch. Older commits, forks, and independently deployed contract instances are not supported unless the Molpha team states otherwise.

Smart contracts are immutable once deployed. A source-level fix may require a new deployment and an explicit migration by integrators.

## Reporting a vulnerability

Do not open a public issue, discussion, or pull request for a suspected vulnerability.

Report it through GitHub's [private vulnerability reporting](https://github.com/Molpha/molpha-evm-verifier/security/advisories/new). If private reporting is unavailable, contact a Molpha maintainer through an established private channel and ask for a secure reporting path before sharing technical details.

Include as much of the following as possible:

- The affected commit, contract, and function
- A clear description of the vulnerability and its impact
- Preconditions and a minimal proof of concept or reproduction steps
- Whether deployed contracts or funds may be at risk
- Any suggested mitigation
- How you would like to be credited, or whether you prefer anonymity

Do not include private keys, seed phrases, production credentials, or other third-party secrets in a report.

## Response process

The maintainers aim to acknowledge a report within three business days. We will validate the issue, determine severity and affected deployments, coordinate remediation, and agree on a disclosure timeline with the reporter. Complex issues may require more time, but we will provide status updates while remediation is in progress.

Please allow a reasonable remediation window before public disclosure. We may ask the reporter to retest a patch or deployment before an advisory is published.

## Research guidelines

Good-faith research must:

- Avoid accessing, modifying, or destroying data that is not yours
- Avoid privacy violations, denial of service, social engineering, and automated abuse
- Use local chains, forks, or test deployments whenever possible
- Stop testing and report immediately if real funds or production systems may be affected
- Comply with applicable law

The project does not promise a bug bounty or payment. Recognition and any reward are determined case by case.
