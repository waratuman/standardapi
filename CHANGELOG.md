# Changelog

## 9.0.0

### Breaking changes

- Replace `Controller#excludes_for(klass)` with per-record ACL
  `excludes(record)` rules.

### Added

- ACL excludes can remove attributes and nested associations from serialized
  responses.
- Exclude-aware serialization helpers for custom model partials.
- An ACL can be nested in its controller as an `ACL` module
  (`PhotosController::ACL`), as an alternative to `app/controllers/acl`.
  Controllers are loaded at boot and after each reload to find them.
- `schemas_for(model)` returns the attribute definitions that
  `json_schema.json` is built from, for use without rendering a view. Each has
  one `type`, the attribute's ActiveModel type.

### Changed

- `json_schema.json` describes every attribute in `model.attribute_names`,
  including those declared without a column, and types each by its ActiveModel
  type rather than its column's SQL type. An `attribute` declaration that
  casts a column differently is described by its cast, and a type with no JSON
  Schema mapping gets an empty schema.

### Deprecated

- Zero-arity ACL `excludes` methods. Accept the record argument instead.

### Fixed

- `json_schema.json` includes `false` column defaults, and no longer sets a
  `null` default on enums without one.
- The turbostreamer `schema.json` reports `readonly` like the jbuilder one when
  a model has no ACL `attributes`, instead of always `true`.
