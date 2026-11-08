# Changelog

All notable changes to this module are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

## [1.2.0] - 2026-11-08

### Added

- Receiver types beyond email: `webhook_receivers` (with optional `aad_auth`
  for secure webhooks), `sms_receivers`, `azure_app_push_receivers`,
  `logic_app_receivers` (the usual route to Microsoft Teams) and
  `arm_role_receivers`. All default to `{}`, so existing action groups plan
  unchanged. `use_common_alert_schema` defaults to `true` where the receiver
  supports it, matching `email_receivers`.
- Validation for the new receivers: https-only webhook and Logic App URLs,
  UUID `role_id` and `aad_auth.object_id`, Logic App workflow resource IDs,
  non-empty SMS fields, valid app push addresses.
- Plan-time check that receiver names are unique across all receiver types,
  ignoring case, as Azure requires.

### Changed

- The "alerts need a receiver" precondition now counts receivers of every
  type, so an alert routed only to a webhook or SMS is accepted.

## [1.1.0] - 2026-11-05

See the [v1.1.0 release](https://github.com/moveeeax/terraform-azurerm-monitor/releases/tag/v1.1.0).

## [1.0.0]

Initial release (`v0.1.0` points at the same commit).

[Unreleased]: https://github.com/moveeeax/terraform-azurerm-monitor/compare/v1.2.0...HEAD
[1.2.0]: https://github.com/moveeeax/terraform-azurerm-monitor/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/moveeeax/terraform-azurerm-monitor/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/moveeeax/terraform-azurerm-monitor/releases/tag/v1.0.0
