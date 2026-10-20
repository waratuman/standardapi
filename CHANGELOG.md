# Changelog

## 9.0.0

### Breaking changes

- Require Ruby 3.3 or later and activerecord-sort 8.0.1 or later.
- Replace `Controller#excludes_for(klass)` with per-record ACL
  `excludes(record)` rules.
- Ordering through an association listed by name in ACL `orders`, ie.
  `:property`, is checked against the associated model's ACL `orders`. Orders
  it doesn't permit, including any through an association whose model's ACL
  has no `orders`, are rejected with a 400.
- ACL `orders` list only the names of columns and associations that can be
  ordered by. A Hash in ACL `orders`, ie. `{ property: [:name] }`, raises
  `StandardAPI::InvalidConfiguration`. List the association by name and permit
  its columns in the associated model's ACL `orders` instead.
- Ordering through a polymorphic association is rejected with a 400; there is
  no single ACL to check it against.
- Orders ActiveRecord::Sort can't order by, ie. through more than one
  association, are rejected with a 400 rather than failing with a 500.
- Remove `Controller#model_orders`. Define the model's ACL `orders` and use
  `orders_for(model)` instead. A controller that still overrides
  `model_orders` raises `StandardAPI::InvalidConfiguration`.
- Remove `StandardAPI::Orders.sanitize`. `StandardAPI::Orders` is included in
  `StandardAPI::Controller`; use `sanitize_orders` instead.

### Added

- ACL excludes can remove attributes and nested associations from serialized
  responses.
- Exclude-aware serialization helpers for custom model partials.
- An ACL can be nested in its controller as an `ACL` module
  (`PhotosController::ACL`), as an alternative to `app/controllers/acl`.
  Controllers are loaded at boot and after each reload to find them. Two ACLs
  that would define the same method, ie. nested in two controllers of one
  model, raise `StandardAPI::InvalidConfiguration`.

### Deprecated

- Zero-arity ACL `excludes` methods. Accept the record argument instead.
