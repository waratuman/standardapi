# Changelog

## 9.0.0

### Breaking changes

- Replace `Controller#excludes_for(klass)` with per-record ACL
  `excludes(record)` rules.
- Ordering through an association listed by name in ACL `orders`, ie.
  `:property`, is checked against the associated model's ACL `orders`. Orders
  it doesn't permit, including any through an association whose model's ACL
  has no `orders`, are rejected with a 400.

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
- Permitting an association's columns in ACL `orders`, ie.
  `{ property: [:name] }`. List the association by name and permit its columns
  in the associated model's ACL `orders` instead.
- `Controller#model_orders`, including overriding it. Define the model's ACL
  `orders` and use `orders_for(model)` instead.
- `StandardAPI::Orders.sanitize`. `StandardAPI::Orders` is included in
  `StandardAPI::Controller`; use `sanitize_orders` instead.
