# Changelog

## 9.0.0

### Breaking changes

- Replace `Controller#excludes_for(klass)` with per-record ACL
  `excludes(record)` rules.
- Renamed ACL methods are private. Calling them publicly (e.g.
  `controller.photo_attributes`) no longer works, and they are no longer
  routable actions.
- An ACL module may only define `attributes`, `orders`, `includes`,
  `excludes`, `nested` and `filter`. Any other method raises at boot.

### Added

- ACL excludes can remove attributes and nested associations from serialized
  responses.
- Exclude-aware serialization helpers for custom model partials.
- An ACL can be nested in its controller as an `ACL` module
  (`PhotosController::ACL`), as an alternative to `app/controllers/acl`.
  Controllers are loaded at boot and after each reload to find them.

### Deprecated

- Zero-arity ACL `excludes` methods. Accept the record argument instead.
