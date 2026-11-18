# Post-deployment project follow-ups

This is an editorial and engineering backlog for the projects featured on tylerbaum.dev.
**Do not hold up the personal-site deployment for these items.** Recheck project HEADs
and the corresponding audits before distributing implementation handoffs.

## Black / White

- [ ] Expand the now-corrected compiler-pipeline illustration with an audited
  semantic-tooling / protected-gate exhibit. The compile path does not
  automatically run canonical formatting today.
- [ ] Develop or capture a genuine exhibit for the byte-identical binary whose
  weakened contract is refused by the Protected Change Gate.
- [ ] Prepare a safely publishable Uncheatable Boss demonstration with provenance,
  the finite verification scope, live-agent versus seeded-invalid distinction, and
  native replacement / replay evidence.
- [ ] Address the stored-evidence checking weakness: `white verify --check` can
  accept a forged status change from disproven/unresolved to accepted. The Protected
  Change Gate performs fresh verification; do not conflate the two paths.
- [ ] Make the experimental semantic interface handle effects / ownership failures
  correctly rather than reporting an internal Core error, and avoid falsely marking
  obligations removed when head analysis is incomplete.
- [ ] Integrate the planned canonical format → lint → compile workflow, when ready;
  do not describe this as current functionality.

Source: 2026-11-17 Black portfolio audit and approved Black project copy.

## Brigid

- [ ] Fix the description-list grouping false positive for valid `<dl><div>...`
  constructs, then adjust the portfolio's site-source code excerpt to remove the
  workaround explanation. The portfolio's primary rejection exhibit now uses a
  genuinely invalid `<ul><div>` nesting example.
- [ ] Fix HXML text content escaping (audit D1).
- [ ] Guard raw script/style content boundaries or clearly and safely constrain
  the API contract (D2).
- [ ] Prevent HTML/HXML comment breakout and invalid XML comments (D3).
- [ ] Validate custom HTML/HXML element names at the appropriate boundary (D4).
- [ ] Resolve HXML ByteString/Text empty-tag disagreement (D5).
- [ ] Correct `hx-history-elt` serialization and other attribute/selector bugs
  (D6–D10); confirm which are reproducible.
- [ ] Clarify URL scheme policy and the limits of raw escape hatches (D11).
- [ ] Improve independent spec validation for the document generator (D12).
- [ ] Repair the Blaze benchmark converter (`id_`), capture a reproducible
  environment, compare equivalent output, and rerun the three renderers (D13).
- [ ] Update stale README TODOs, add CI and consider release packaging.

Source: 2026-11-17 Brigid portfolio audit at `e0f4d45`.

## Paranoia Engine / Lockdown

- [ ] Back up or push the unmerged Phase 10 consequence work and experimental
  branches; audit reports these only in local worktrees (D-2).
- [ ] Reconcile engine product name (Paranoia Engine), playable demo (Lockdown),
  and historic `lockdown-*` code namespaces across documentation.
- [ ] Fix or bound unchecked authoritative `i64` arithmetic before claiming
  that every step operation is checked (D-3).
- [ ] Keep verification language precise: bounded scenarios are not formal proofs;
  document nonblocking unresolved geometric reachability (D-4).
- [ ] Strengthen independent authority for the code-writing agent and gate/checker
  changes; the gameplay author's controlled tool interface alone is not an OS
  sandbox (D-5/D-9).
- [ ] Perform and record a human-paced stage rehearsal, investigate frame hitches,
  and capture a reviewed video if it will be published (D-6/D-7).
- [ ] Reconcile and publish README coverage through Phase 09/10; correct tool
  counts, audio descriptions and historical naming (D-8).
- [ ] Audit generated asset and model usage rights before publishing bundles or
  screenshots, and sanitize local usernames and paths from logs (D-10/D-13).
- [ ] If publishing experimental Material Reality, ensure it is based on the
  corrected Phase 10 line rather than the buggy Material Reality v1 HEAD (D-1);
  label uncalibrated physics and unsupported scope.
- [ ] Consider a counterfactual/cause exhibit and a model-evaluation display that
  preserves negative findings (selected policy not best on final split, and no
  improvement in raw regret).

Source: 2026-11-17 Paranoia portfolio audit of `spike/material-reality`
(`2287d04`), `main` (`5968001`) and unpushed `phase-10-consequence`
(`926f5c2`), statuses as reported at that time.
