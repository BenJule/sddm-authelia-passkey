## Description

<!-- What does this PR change and why? Keep the scope focused. -->

## Type of change

- [ ] Bug fix
- [ ] New feature
- [ ] Refactoring with no intended functional change
- [ ] Theme / UX
- [ ] Packaging / release
- [ ] Build / CI
- [ ] Documentation
- [ ] Security hardening

## Testing

<!-- Describe exactly what was tested and where. -->

- [ ] Broker tests: `cd src/broker && go test ./...`
- [ ] KWallet service tests: `cd src/kwallet-secretd && go test ./...`
- [ ] Go vet clean
- [ ] ShellCheck clean for changed shell scripts
- [ ] PAM hardening/build checks pass
- [ ] Package build + lintian pass if packaged files changed
- [ ] Native Theme tests / visual regression pass if theme code changed
- [ ] Lab VM regression completed if authentication, PAM or theme integration changed
- [ ] Normal password login was verified before smartphone/passkey login where PAM behaviour changed

## Security and trust boundaries

Does this change touch authentication, identity mapping, approval markers, KWallet, PAM, provider handling or recovery behaviour?

- [ ] No security/trust-boundary change
- [ ] Yes, and the affected boundary is explained below

<!-- If yes, reference docs/security.md and docs/threat-model.md and explain why the password fallback invariant remains safe. -->

## Checklist

- [ ] One logical change per PR
- [ ] New behaviour has tests
- [ ] Documentation is updated where behaviour or configuration changed
- [ ] No secrets, tokens, credentials or private keys are included
- [ ] PAM changes preserve the invariant that missing/failed approval falls through to the normal password path
- [ ] Security-relevant changes update the threat model when a trust boundary changes
