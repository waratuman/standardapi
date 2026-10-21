# Changelog

## 9.0.0

### Breaking changes

- Require Ruby 3.3 or later and activerecord-sort 8.1.0 or later.
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
- Includes through an association listed by name in ACL `includes`, ie.
  `:landlord`, are checked against the associated model's ACL `includes`.
  Includes it doesn't permit are rejected with a 400. This also loosens
  includes: listing an association by name permits everything its ACL
  `includes` permit, at every level below it.
- Permitting an association's includes in ACL `includes`, ie.
  `{ landlord: [:photos] }`, raises `StandardAPI::InvalidConfiguration`. List
  the association by name and permit its includes in the associated model's
  ACL `includes` instead. A polymorphic association's includes, or those of a
  method rendered as an include, can still be permitted this way.
- Remove `Controller#model_includes`. Define the model's ACL `includes` and use
  `includes_for(model)` instead. A controller that still overrides
  `model_includes` raises `StandardAPI::InvalidConfiguration`.
- Remove `StandardAPI::Includes.sanitize` and `.normalize`.
  `StandardAPI::Includes` is included in `StandardAPI::Controller`; use
  `sanitize_includes` and `normalize_includes` instead.
- An include's `order`, ie. `include[photos][order][id]=desc`, is checked
  against the included model's ACL `orders`, like the `order` param. Orders
  it doesn't permit, and any under a polymorphic association, are rejected
  with a 400; before, any column could be ordered by.

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

### Security

- The `group_by` param was passed to `group` as a String, which Rails uses
  as raw SQL, so a client could append SQL to the `GROUP BY` of `index`,
  `calculate` and the other actions, ie.
  `group_by=id HAVING (SELECT ...) = 'a'`, and read any data the database
  user can from whether records came back. It now only accepts column names
  of the model, passed to `group` as columns, and rejects anything else with
  a 400.
