# Amarantos ACRT Discourse extension

This companion extension keeps `pastliferegression.in` independent while exposing a narrow SEO/editorial bridge and a separately gated administrator-authenticated service surface to the Amarantos WordPress certification module.

It provides badge `103` and `ACRT` group reconciliation, public activity snapshots, approved related-guide mappings, public editorial candidates, category privacy controls, and staff-safe dormancy actions. It never returns email addresses or private-message/report content.

## Installation

1. Back up the Discourse database and capture exports of badge 103 grants, ACPPL/ACRT membership, category permissions and relevant site settings.
2. Add `git clone https://github.com/venumurthy/amarantos-discourse-acrt.git amarantos-acrt` to the `cmd:` list under the `after_code` plugin hook in `/var/discourse/containers/app.yml`. Remove the old `cp -a /opt/amarantos-local-plugins/amarantos-acrt amarantos-acrt` line, then run `cd /var/discourse && ./launcher rebuild app`.
3. Enable `amarantos_synergy_enabled` only after installation validation. SEO can then use `amarantos_seo_bridge_enabled` and `amarantos_schema_enabled` while `amarantos_acrt_enabled` remains off.
4. Create an API key owned by a dedicated administrator and restrict it to the `amarantos_acrt` read/write scopes. Deliver it to WordPress through the approved secret channel.
5. If discourse-solved is installed, set its schema output to `never`; this plugin provides Q&A microdata only in category 11 while Discourse retains its standard discussion markup elsewhere.
6. Enable the plugin, call the health endpoint, and use labelled non-public test accounts before any migration or enforcement action.

All mutating routes require an administrator-authenticated API key. Certification routes remain unavailable unless `amarantos_acrt_enabled` is on; SEO/editorial routes remain unavailable unless `amarantos_seo_bridge_enabled` is on. Group migration, category permission changes, suspension and guide publication happen only through explicit requests. Reactivation only unsuspends; it intentionally does not restore badge 103, ACRT membership or email preferences.

## Service routes

- `GET /amarantos-acrt/v1/health.json`
- `GET /amarantos-acrt/v1/certification-state.json`
- `GET /amarantos-acrt/v1/users/:id/certification-state.json`
- `GET /amarantos-acrt/v1/users/:id/activity.json`
- `POST|DELETE /amarantos-acrt/v1/users/:id/certification.json`
- `POST /amarantos-acrt/v1/migrate-group.json`
- `PUT|DELETE /amarantos-acrt/v1/topics/:id/related-guide.json`
- `GET /amarantos-acrt/v1/dormancy-candidates.json`
- `POST|DELETE /amarantos-acrt/v1/users/:id/dormancy.json`
- `GET /amarantos-acrt/v1/editorial-candidates.json`
- `POST /amarantos-acrt/v1/configure-categories.json`

The single-user certification-state route returns the same public badge, group, suspension and approved profile fields as the paginated route, scoped to the requested Discourse ID. The Academy refresh uses this route and the matching single-user activity route after checking the authenticated Amarantos account's linked ID.

## Release

Version 1.2.4 lets linked forum staff accounts use the Academy's read-only certification-state refresh. Certification and dormancy changes to staff accounts remain blocked.

## Rollback

Disable the plugin first. Restore category permissions and group membership from the pre-change exports. Badge 103 remains the authoritative record; do not recreate membership from cached WordPress data. The related-guide custom fields may remain dormant or be cleared through the service before uninstalling.
