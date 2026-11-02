# Changelog

## 9.0.0

### Breaking changes

- Require Ruby 3.3 or later and activerecord-sort 8.1 or later, below 9.
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
- `json_schema.json` is removed; use `write_schema.json`. It lists only the
  attributes the ACL permits (rather than every attribute, marking the rest
  `readOnly`) and the ACL's nested associations. `json_schema.json`'s
  `include` param, with `only` and `except`, has no equivalent there: use
  `read_schema.json?include=...` for the shape of a response.
  `:json_schema` in the `only` or `except` of `standard_resources` or
  `standard_resource` now raises Rails' `ArgumentError` for an unknown
  action.
- An include's `order`, ie. `include[photos][order][id]=desc`, is checked
  against the included model's ACL `orders`, like the `order` param. Orders
  it doesn't permit, and any under a polymorphic association, are rejected
  with a 400; before, any column could be ordered by.
- The `where` param is checked against a new ACL `wheres` method, which lists
  what can be filtered on. Without one, nothing can: every `where` is
  rejected with a 400 until the model's ACL defines `wheres`, including for
  filters through associations.
  - A column permits any operator, or the operators it lists, ie.
    `{ photo_id: [:eq, :in] }`; an operator's aliases, ie. `gt` and
    `greater_than`, are permitted together. A bare value counts as `eq` and
    an Array as `in`.
  - An association is permitted by name, and what is filtered on it is
    checked against the associated model's ACL `wheres`; for a polymorphic
    association, those of its `as` class. Permitting an association also
    permits its `_ids`.
  - A `filter_on` filter is permitted by name.
  - Operators listed on an association raise
    `StandardAPI::InvalidConfiguration`. An operator activerecord-filter
    doesn't support is left to it, and raises its own error.
  - An STI subclass falls back to its base class's ACL `wheres`.
- An include's `where`, ie. `include[photos][where][id]=1`, is checked
  against the included model's ACL `wheres`, and rejected with a 400 under a
  polymorphic association.
- `StandardAPI::TestCase`'s `#index.json params[:where]` and
  `#calculate.json params[:where]` tests skip for a model whose ACL `wheres`
  don't permit filtering on `id`.

### Added

- ACL excludes can remove attributes and nested associations from serialized
  responses.
- Exclude-aware serialization helpers for custom model partials.
- An ACL can be nested in its controller as an `ACL` module
  (`PhotosController::ACL`), as an alternative to `app/controllers/acl`.
  Controllers are loaded at boot and after each reload to find them. Two ACLs
  that would define the same method, ie. nested in two controllers of one
  model, raise `StandardAPI::InvalidConfiguration`.
- An ACL can define `schemas(default_schema)` to adjust its model's attribute
  definitions: it receives the definitions StandardAPI builds and returns the
  ones to use. `schemas_for(Model)` returns the result, for use without
  rendering a view, and `write_schema.json`, `read_schema.json` and
  `query_schema.json` are built from it. Each definition has one `type`, the
  attribute's ActiveModel type, and a `comment`, which the JSON Schemas render
  as `description`.
- `read_schema.json` and `query_schema.json`: JSON Schemas of a rendered
  record, and of the params `#index` and `#calculate` accept. `where`, `order`,
  `include` and an include's `when` are limited to what the ACL permits;
  params the ACL doesn't check yet are described as used and marked "Not
  checked by the ACL." Each schema's route is only drawn with the actions it
  describes. `read_schema.json` leaves out what `ApplicationHelper#excludes`
  excludes.
- `write_schema_for(model)`, `read_schema_for(model, includes)` and
  `query_schema_for(model, ref: nil)` build those schemas in-process. With
  `ref:`, `query_schema_for` leaves the where, order and include of other
  models to the caller instead of building them into `$defs`.

### Changed

- The ACL `attributes` and `schemas` lookups fall back to the base class's
  ACL for an STI subclass, as `orders`, `includes` and `wheres` do. An STI
  subclass without an ACL of its own can now be created and updated with the
  attributes its base class's ACL permits, where before it permitted none,
  and `write_schema.json` and `schema.json` describe it the same way.
- `write_schema.json` and `read_schema.json` describe every attribute in
  `model.attribute_names`,
  including those declared without a column, and types each by its ActiveModel
  type rather than its column's SQL type. An `attribute` declaration that
  casts a column differently is described by its cast, and a type with no JSON
  Schema mapping gets an empty schema.

### Deprecated

- Zero-arity ACL `excludes` methods. Accept the record argument instead.

### Fixed

- `write_schema.json` includes `false` column defaults, and no longer sets a
  `null` default on enums without one. An array column's `readOnly`,
  `default` and `description` describe the array rather than its items.
- `read_only` is true for an `attr_readonly` attribute even when the ACL's
  `attributes` permit it, since Rails won't change it after create. `required`
  is about create, so a NOT NULL `attr_readonly` attribute is both: it must be
  sent on create and can't be changed after.
- `write_schema.json` doesn't mark an auto populated column `readOnly`: the
  database only fills it in when a create doesn't give one, so whether it can
  be written is up to the ACL. It still isn't `required`.
- `write_schema.json` is valid JSON Schema for `format` and `inclusion`
  validations. A `format` Regexp was rendered in Ruby's syntax, ie.
  `(?-mix:\d{3})`, which isn't an ECMA 262 pattern; it is now rendered as its
  source, and left out when JavaScript wouldn't read it the same way (flags,
  `\A`, `\z`, inline flag groups). An `inclusion` Range was rendered as a
  String `enum`; a numeric Range is now `minimum` and `maximum`, and other
  Ranges and Procs are left out.
- `read_schema.json` describes the records StandardAPI renders: a column that
  allows NULL, an attribute without a column, and a singular association that
  is included unless its presence is validated (ie. a required `belongs_to`),
  allow `null`; a decimal is a String, as a BigDecimal renders; and an enum
  lists its names. In `write_schema.json` a decimal is a number or a String.
- The turbostreamer `schema.json` reports `readonly` like the jbuilder one when
  a model has no ACL `attributes`, instead of always `true`.

### Security

- An include's `when`, ie. `include[photos][when][active]=true`, which renders
  the include only for the records matching it, called `record.send` with
  each of its keys, so a GET could call any method on the records it
  rendered: `include[photos][when][destroy]=1` destroyed them. Its keys must
  now be attributes of the model, permitted like a `where` with `eq` by its
  ACL `wheres`, and are read with `read_attribute`; anything else is rejected
  with a 400.
- The `group_by` param was passed to `group` as a String, which Rails uses
  as raw SQL, so a client could append SQL to the `GROUP BY` of `index`,
  `calculate` and the other actions, ie.
  `group_by=id HAVING (SELECT ...) = 'a'`, and read any data the database
  user can from whether records came back. It now only accepts column names
  of the model, passed to `group` as columns, and rejects anything else with
  a 400.
