# Changelog

## 9.0.0

### Breaking changes

- Replace `Controller#excludes_for(klass)` with per-record ACL
  `excludes(record)` rules.

### Added

- ACL `nested` declarations may use a Hash as well as an Array.
- ACL excludes can remove attributes and nested associations from serialized
  responses.
- Exclude-aware serialization helpers for custom model partials.

### Deprecated

- Zero-arity ACL `excludes` methods. Accept the record argument instead.
