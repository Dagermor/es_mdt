# Changelog

## es_mdt 2.0.0 (2026-11-17)

**One resource.** es_departments 1.9.1, es_doj 1.1.0 and es_mdt 1.11.3 are now one resource, named es_mdt.

- Old export names keep working: `exports.es_departments:*` and `exports.es_doj:*` are answered by es_mdt. The manifest also `provide`s both names.
- All tables, data, jobs, permissions, aces (`es_departments.admin`, `es_doj.admin`) and commands are unchanged.
- On first start es_mdt takes over the old resources' migration records and one-time setup marks.
- No `provide 'es_departments'`/`'es_doj'` in the manifest: FiveM would report those names as running, and whip_core would keep the jobs with them. es_mdt takes over the department jobs by itself on its first start.
- The WHIP permission `es_departments.manage` is now `es_mdt.departments.manage` (whip_core wants the resource's prefix).
- One NUI page: each part runs in its own frame, and NUI callbacks are prefixed per part (`dept_*`, `doj_*`).

**Jail bridge: any jail script.**

- `Config.Jail.provider = 'auto' | 'es_jail' | 'custom' | 'none' | '<resource>'`.
- `Config.Jail.custom` reaches a jail script through its exports with no code.
- For jail scripts: `exports.es_mdt:RegisterJailProvider`, `ReportJailRelease` and `ReportJailEscape`, plus events.
- With no jail script, sentences are recorded in `es_mdt_jail_sentences`, counted down in the MDT and shown in the Jail tab. `es_mdt:jail:sent` fires.
- The court's sentences go through the same bridge.

**Test tools.** The test tools are now behind `EsSuite.DevTools` in `shared/suite.lua`, off by default: `/dojtest`, `/ftotest` and MDT → Admin → Test data.

**es_jail 1.1.1:** depends on es_mdt and finds the departments inside it.

## Before 2.0.0 (separate resources)

- **es_mdt 1.11.3:** whip_evidence timeline entries and correct custody times.
- **es_mdt 1.11.2:** whip_evidence page calls fixed ("Unknown call"), and per-event timeline logs.
- **es_mdt 1.11.1:** whip_evidence photo ids; es_evidence parts hidden when it is off.
- **es_mdt 1.11.0:** optional whip_evidence bridge.
- **es_departments 1.9.1:** Health page colors.
- **es_departments 1.9.0:** `evidence_upload` and `evidence_case_close` permissions.
- **es_doj 1.1.0:** attorneys and the bar, fees, bail, appeals, and petitions.
