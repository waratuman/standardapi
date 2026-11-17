# Changelog

## 9.0.0

### Breaking changes

- Require Ruby 3.3 or later and activerecord-sort 8.1 or later, below 9.
- Remove `Controller#excludes_for(klass)`, `Controller#excludes` and ACL
  `excludes`. What's rendered is up to the model's Policy, which can hide an
  attribute or association per record and pick the Policy included records
  render with. An ACL
  `excludes` method isn't used. `StandardAPI::Excludes`, `resolve_excludes`,
  `sub_excludes`, `apply_excludes` and `reject_excluded_errors` are removed: a
  custom partial asks `record_policy(record, local_assigns[:policy])` what it
  renders, and passes `policy:` rather than `excludes:` to nested records. An
  include that resolves to a plain value is rendered whole.
- Remove ACL `includes`. What can be included is what the model's Policy
  declares with `association` and `associations`, an association or a method;
  anything else is rejected with a 400, and what's included of an included
  record is checked against its own Policy, or the association's `policy:`.
  Under a polymorphic association or a method, what's included of it is
  checked against the Policies of the models the association's `types:` name.
  An ACL `includes` method
  raises `StandardAPI::InvalidConfiguration`.
- `#create` and `#update` render the associations written through nested
  attributes only where the model's Policy declares them.
- Remove `ApplicationHelper#excludes`. It isn't used, so it hides nothing;
  leave what it hid out of each model's Policy instead.
- Remove ACL `orders`. What can be ordered by is what the model's Policy
  declares `orderable`, ie. `attributes :id, :name, orderable: true`; ordering
  by anything else is rejected with a 400. An association declared
  `orderable` can be ordered by what its model's own Policy makes orderable.
  An ACL `orders` method raises `StandardAPI::InvalidConfiguration` at boot,
  as does a controller's `<model>_orders` method, ie. `photo_orders`, when
  ordering that model.
- Ordering through a polymorphic association is rejected with a 400; there is
  no single Policy to check it against.
- Orders ActiveRecord::Sort can't order by, ie. through more than one
  association, are rejected with a 400 rather than failing with a 500.
- Remove `Controller#model_orders`. Declare what can be ordered by in the
  model's Policy and use `orders_for(model)` instead. A controller that still
  overrides `model_orders` raises `StandardAPI::InvalidConfiguration`.
- Remove `StandardAPI::Orders.sanitize`. `StandardAPI::Orders` is included in
  `StandardAPI::Controller`; use `sanitize_orders` instead.
- Remove `Controller#model_includes`. Declare what can be included in the
  model's Policy instead. A controller that still overrides `model_includes`
  raises `StandardAPI::InvalidConfiguration`.
- Remove `StandardAPI::Includes.sanitize` and `.normalize`.
  `StandardAPI::Includes` is included in `StandardAPI::Controller`; use
  `sanitize_includes` and `normalize_includes` instead.
- An include's `order`, ie. `include[photos][order][id]=desc`, is checked
  against what the included model's Policy makes orderable, like the `order`
  param. Anything else, and any order under a polymorphic association, is
  rejected with a 400; before, any column could be ordered by.
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

- Replace `json_schema.json` with `schema/read.json`, `schema/write.json` and
  `schema/query.json` (see Added). `schema/read.json` describes records as
  rendered, with includes, as `json_schema.json` did; `schema/write.json` lists
  only the attributes the ACL permits, where `json_schema.json` listed every
  attribute and marked the rest `readOnly`. `include[only]` and
  `include[except]` have no equivalent, and `:json_schema` in a route's `only`
  or `except` raises Rails' `ArgumentError` for an unknown action.

### Upgrading from 8.x

`Controller#excludes_for(klass)` and ACL `excludes` have been replaced by the
model's Policy, which renders only what it declares and can hide an attribute
or association per record. An ACL `excludes` method isn't used, so move what
it hid into the Policy:

    # Before, in PhotoACL
    def excludes(photo)
      { caption: !photo.public?, camera: photo.anonymous?, account: [:email] }
    end

    # After
    class PhotoPolicy < StandardAPI::Policy
      attribute :caption, if: -> { record&.public? }
      association :camera, unless: -> { record&.anonymous? }
      association :account, policy: AccountWithoutEmailPolicy
    end

A custom partial asks `record_policy(record, local_assigns[:policy])` what it
renders, instead of applying `resolve_excludes` (see Custom partials in the
README), and passes `policy:` to nested records instead of `excludes:`.
`Controller#excludes(record)` is now `record_policy(record).hidden?(name)`.

`ApplicationHelper#excludes` is no longer used, and nothing checks for it, so
**what it hid renders if the model's Policy declares it**. This matters most for
what it usually hid, credentials like `password_digest`: check that no Policy
declares them, ie. by listing every column. Remove it, and leave what it hid
out of each model's Policy, which renders only what it declares:

    # Before, in ApplicationHelper
    def excludes
      { user: [:password_digest] }
    end

    # After: UserPolicy doesn't declare password_digest
    class UserPolicy < StandardAPI::Policy
      attributes :id, :name, :email
    end

ACL `includes` has been replaced by the associations each model's Policy
declares, which decide both what can be included and what renders. An ACL
`includes` method raises `StandardAPI::InvalidConfiguration` at boot. Move what
it permitted into the Policy. For anything it permitted under a polymorphic
association or a method, list the models it can be in that association's
`types`, and declare what can be included of them in their Policies:

    # Before, in PhotoACL
    def includes
      { author: true, camera: true, subject: [:landlord] }
    end

    # After: subject is polymorphic, and PropertyPolicy declares landlord
    class PhotoPolicy < StandardAPI::Policy
      associations :author, :camera
      association :subject, types: [Property]
    end

ACL `orders`, and a controller's `<model>_orders` methods, have been replaced
by what each model's Policy declares `orderable`, and raise
`StandardAPI::InvalidConfiguration`. Declare what they permitted `orderable`
in the Policy instead. An association they permitted by name is declared
`orderable` too, and its columns made orderable in its own model's Policy:

    # Before, in PhotoACL
    def orders
      [ :id, :created_at, :account ]
    end

    # After: AccountPolicy makes what can be ordered by of an account orderable
    class PhotoPolicy < StandardAPI::Policy
      attributes :id, :created_at, orderable: true
      association :account, orderable: true
    end

`json_schema.json` has been replaced by `schema/read.json`, `schema/write.json`
and `schema/query.json` (see Schema Discovery in the README). For the shape
of a record, with includes, use `schema/read.json`; for what a create or update
accepts, `schema/write.json`, which lists only the attributes the ACL permits. `include[only]` and `include[except]` have no equivalent. A route
that names `:json_schema` in `only` or `except` raises `ArgumentError`, so
name `:read_schema`, `:write_schema` or `:query_schema` instead.

### Added

- `record_policy(record_or_model, policy)` gives a `StandardAPI::Policy::Record`,
  what a record renders: `attributes`, `attribute?`, `includes`, `include?`,
  `association_policy`, `value`, `hidden?` and `errors`.
  `application/_record` and custom partials are built on it.
- An ACL can be nested in its controller as an `ACL` module
  (`PhotosController::ACL`), as an alternative to `app/controllers/acl`.
  Controllers are loaded at boot and after each reload to find them. Two ACLs
  that would define the same method, ie. nested in two controllers of one
  model, raise `StandardAPI::InvalidConfiguration`.
- A controller can nest a subclass of `StandardAPI::Policy`
  (`PhotosController::Policy`), found by `StandardAPI::Policies`, the sibling
  of `StandardAPI::AccessControlList` (`include StandardAPI` includes both),
  to declare its model's attribute definitions. Like strong parameters only
  declared attributes are used. `attributes` declares them, `attribute` can
  also change or add one, `remove` drops one, and
  `attributes_for`
  declares those only known at runtime, once a request per key. `if` and `unless` hide an attribute
  per record, or per requester: hidden attributes join the record's excludes,
  and a Policy that could vary by requester turns off fragment caching for its
  model. Two Policies of one model raise `StandardAPI::InvalidConfiguration`.
  Rendering or describing a model with no Policy raises
  `StandardAPI::MissingPolicy`; a model with no controller declares one by name,
  `ToolCallPolicy` for `ToolCall`.
  A Policy declares the associations an include may render with `association`
  and `associations`; one it doesn't declare isn't rendered or described.
  `if` and `unless` hide one per record, and the included records render
  with `policy:` in place of their own model's Policy; to keep what that
  hides, it inherits from it.
  `orderable: true` on an attribute or association, ie. `attributes :id,
  :name, orderable: true`, lets a request order by it, and `orderable: false`
  takes back an inherited one. `attributes` and `associations` take the same
  options as `attribute` and `association`.
  `attribute ..., value:` renders a computed value in place of the record's;
  `serialize_attribute` reads values with `attribute_value(record, name)`.
  `record_policy(record_or_model).attributes` returns the result, for use
  without rendering a view, and the JSON Schemas, `schema.json` and
  `application/_record` are built from it: a record renders the attributes in
  `record_policy(record).attributes`, one per entry in
  `record.attribute_names`, so an attribute a Policy removes isn't rendered and
  one it adds is read from the record. Each definition has one `type`, the
  attribute's ActiveModel type, and a `comment`, which the JSON Schemas
  render as `description`.
- Each resource serves three JSON Schemas (2020-12), built from its ACL and
  Policy, each drawn only with the actions it describes:
  - `schema/read.json`: a record as `#show` and `#index` render it, with the
    `include` param checked against the Policies. A column that
    allows NULL, and a singular association unless its presence is
    validated, allow `null`; decimals are strings, binary is hex, and an
    enum lists its names.
  - `schema/write.json`: the params `#create` and `#update` accept, with only
    the attributes the ACL's `attributes` permit, their validations, and the
    associations its `nested` permits. `required` is for a create. A
    `read_only` definition is `readOnly`; an auto populated column isn't, and
    isn't `required`.
  - `schema/query.json`: the `where` and `order` the ACL's `wheres` and
    `orders` permit, and the `include` the Policies declare, following
    associations through `$defs`, plus `limit`, `offset`, `distinct` and `group_by`, and the
    params no ACL checks yet, marked as such.

  Validations are valid JSON Schema: a `format` Regexp is its source, left out
  when JavaScript wouldn't read it the same way, and a numeric `inclusion`
  Range is `minimum` and `maximum`. A validation that doesn't always run
  (`if`, `unless`, `on`) or allows blank, and an option given as a Symbol or
  a Proc, is left out. `read_schema_for`, `write_schema_for` and
  `query_schema_for` build them, and are public like `record_policy`.

### Changed

- The ACL `attributes` and Policy lookups fall back to the base
  class's for an STI subclass, as `orders` and `wheres` do. An STI
  subclass without an ACL of its own can now be created and updated with the
  attributes its base class's ACL permits, where before it permitted none,
  and the JSON Schemas and `schema.json` describe it the same way.
- `schema.json` lists only what the model's Policy declares, and `readonly` is
  the definition's `read_only`, so it's true for an `attr_readonly` attribute
  even when the ACL permits it. A column's `type` still comes from its SQL type
  unless the Policy declares another.

### Fixed

- `read_only` is true for an `attr_readonly` attribute even when the ACL's
  `attributes` permit it, since Rails won't change it after create. `required`
  is about create, so a NOT NULL `attr_readonly` attribute is both: it must be
  sent on create and can't be changed after.
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
