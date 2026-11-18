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
  An ACL `includes` method is no longer renamed, so it overrides
  `Controller#includes`: delete it.
- `#create` and `#update` render the associations written through nested
  attributes only where the model's Policy declares them.
- Remove `ApplicationHelper#excludes`. It isn't used, so it hides nothing;
  leave what it hid out of each model's Policy instead.
- Remove ACL `orders`. What can be ordered by is what the model's Policy
  declares `orderable`, ie. `attributes :id, :name, orderable: true`; ordering
  by anything else is rejected with a 400. An association declared
  `orderable` can be ordered by what its model's own Policy makes orderable.
  A controller's `<model>_orders` method, ie. `photo_orders`, isn't used. An
  ACL `orders` method is no longer renamed, so it overrides
  `Controller#orders`: delete it.
- Ordering through a polymorphic association is rejected with a 400; there is
  no single Policy to check it against.
- Orders ActiveRecord::Sort can't order by, ie. through more than one
  association, are rejected with a 400 rather than failing with a 500.
- Remove `Controller#model_orders`. Declare what can be ordered by in the
  model's Policy and use `record_policy(model).orderable` instead. An
  override of `model_orders` isn't used.
- Remove `Controller#required_orders`. Declare them in the model's Policy with
  `required_orders :id`; they're orderable without being declared `orderable`.
  An override of `required_orders` isn't used.
- Remove ACL `attributes`. What a create or update may set is what the
  model's Policy declares `writable`, ie. `attributes :name, writable: true`,
  decided for the record being created or updated. A json column takes an
  object or `null`, and an array column an array, without saying so. An ACL
  `attributes` method is no longer renamed, so it isn't used: delete it.
  `Controller#model_attributes` is removed, and a `<model>_attributes`
  controller method isn't used.
- `read_only` is true for an attribute the Policy doesn't make `writable`.
  Before, a model without ACL `attributes` had every attribute not
  `attr_readonly` described as writable, though none could be written.
- Remove `StandardAPI::Orders.sanitize`. `StandardAPI::Orders` is included in
  `StandardAPI::Controller`; use `sanitize_orders` instead. It takes a
  `Policy::Record`, ie. `sanitize_orders(orders, record_policy(model))`, in
  place of a permit list and a model.
- Remove `Controller#model_includes`. Declare what can be included in the
  model's Policy instead. An override of `model_includes` isn't used.
- Remove `StandardAPI::Includes.sanitize` and `.normalize`.
  `StandardAPI::Includes` is included in `StandardAPI::Controller`; use
  `sanitize_includes` and `normalize_includes` instead.
- An include's `order`, ie. `include[photos][order][id]=desc`, is checked
  against what the included model's Policy makes orderable, like the `order`
  param. Anything else, and any order under a polymorphic association, is
  rejected with a 400; before, any column could be ordered by.
- The `where` param is checked against what the model's Policy declares
  `filterable`. Nothing else can be filtered on: every `where` is rejected
  with a 400 until the Policy makes it filterable, including for filters
  through associations.
  - A column permits any operator, or the operators it lists, ie.
    `attribute :photo_id, filterable: [:eq, :in]`; an operator's aliases, ie.
    `gt` and `greater_than`, are permitted together. A bare value counts as
    `eq` and an Array as `in`.
  - An association declared `filterable` is checked against what the
    associated model's Policy makes filterable; for a polymorphic
    association, the Policy of its `as` class. It also permits its `_ids`.
  - A `filter_on` filter, a has_and_belongs_to_many join table, or anything
    else that isn't rendered is permitted with `filterable :name`.
  - An operator activerecord-filter doesn't support is left to it, and
    raises its own error.
- An include's `where`, ie. `include[photos][where][id]=1`, is checked
  against what the included model's Policy makes filterable, and rejected
  with a 400 under a polymorphic association.
- `StandardAPI::TestCase`'s `#index.json params[:where]` and
  `#calculate.json params[:where]` tests skip for a model whose Policy
  doesn't make `id` filterable.

- Replace `json_schema.json` with `schema/read.json`, `schema/write.json` and
  `schema/query.json` (see Added). `schema/read.json` describes records as
  rendered, with includes, as `json_schema.json` did; `schema/write.json` lists
  only the attributes the Policy makes writable, where `json_schema.json` listed every
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
declares, which decide both what can be included and what renders. Delete ACL
`includes` methods and move what they permitted into the Policy: one left in
place overrides `Controller#includes`, so the `include` param is ignored. For anything it permitted under a polymorphic
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
by what each model's Policy declares `orderable`. Delete them, and declare
what they permitted `orderable` in the Policy instead: an ACL `orders` left in
place overrides `Controller#orders`, so every index sorts by its list and
ignores the `order` param. An association they permitted by name is declared
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

A controller's `required_orders` method has moved to the model's Policy, so
it applies wherever that model is the one listed:

    # Before, in PhotosController
    def required_orders
      [ :id ]
    end

    # After
    class PhotoPolicy < StandardAPI::Policy
      required_orders :id
    end

ACL `attributes` has been replaced by what each model's Policy declares
`writable`. Delete them, and declare what they permitted `writable` in the
Policy instead. List a json column once, rather than as both `:metadata` and
`{ metadata: {} }`; a strong parameters permit, as an Array, takes the place
of a shape the column's type doesn't give, and `on:` replaces checking
`record.new_record?`. What isn't rendered, ie. a password, is declared with
`writable` on its own:

    # Before, in UserACL
    def attributes(record = nil)
      keys = [ :name, :password, :metadata, { metadata: {} }, { roles: [] } ]
      keys << :email_address if record.nil? || record.new_record?
      keys
    end

    # After
    class UserPolicy < StandardAPI::Policy
      attributes :name, :metadata, :roles, writable: true   # roles is an array column
      attribute :email_address, writable: { on: :create }
      writable :password
    end

What else an ACL `attributes` decided per record is declared in an
`attributes_for` block, keyed on what it read of the record.

`json_schema.json` has been replaced by `schema/read.json`, `schema/write.json`
and `schema/query.json` (see Schema Discovery in the README). For the shape
of a record, with includes, use `schema/read.json`; for what a create or update
accepts, `schema/write.json`, which lists only the attributes the Policy makes writable. `include[only]` and `include[except]` have no equivalent. A route
that names `:json_schema` in `only` or `except` raises `ArgumentError`, so
name `:read_schema`, `:write_schema` or `:query_schema` instead.

### Added

- `record_policy(record_or_model, policy)` gives a `StandardAPI::Policy::Record`,
  what a record renders: `attributes`, `attribute?`, `includes`, `include?`,
  `association_policy`, `orderable`, `required_orders`, `filterable`,
  `writable`, `value`, `hidden?` and `errors`.
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
  takes back an inherited one. `filterable: true`, or the operators it
  permits, lets a request filter on it the same way, and `filterable :name`
  permits a name without declaring it, ie. a `filter_on` filter.
  `writable: true` on an attribute lets a create or update set it, as its
  column's type takes it, or as a strong parameters permit Array gives;
  `writable: { on: :create }` or `{ on: :update }` only on one, and
  `writable :password` without declaring it.
  `attributes` and `associations` take the same options as `attribute` and
  `association`.
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
    the attributes the Policy makes `writable`, their validations, and the
    associations the ACL's `nested` permits. `required` is for a create. A
    `read_only` definition is `readOnly`; an auto populated column isn't, and
    isn't `required`.
  - `schema/query.json`: the `where`, `order` and `include` the Policies
    declare, following
    associations through `$defs`, plus `limit`, `offset`, `distinct` and `group_by`, and the
    params no ACL checks yet, marked as such.

  Validations are valid JSON Schema: a `format` Regexp is its source, left out
  when JavaScript wouldn't read it the same way, and a numeric `inclusion`
  Range is `minimum` and `maximum`. A validation that doesn't always run
  (`if`, `unless`, `on`) or allows blank, and an option given as a Symbol or
  a Proc, is left out. `read_schema_for`, `write_schema_for` and
  `query_schema_for` build them, and are public like `record_policy`.

### Changed

- The Policy lookup falls back to the base class's for an STI subclass. An
  STI subclass without a Policy of its own can now be created and updated
  with what its base class's Policy makes `writable`, where before it
  permitted none, and the JSON Schemas and `schema.json` describe it the same
  way.
- `schema.json` lists only what the model's Policy declares, and `readonly` is
  the definition's `read_only`, so it's true for an `attr_readonly` attribute
  even when it's `writable`. A column's `type` still comes from its SQL type
  unless the Policy declares another.

### Fixed

- A controller with required orders sorts an index without an `order` by its
  `default_orders`, then the required orders; before, it ignored
  `default_orders`. They're no longer written into `params[:order]` either.
- `read_only` is true for an `attr_readonly` attribute even when the Policy
  makes it `writable`, since Rails won't change it after create. `required`
  is about create, so a NOT NULL `attr_readonly` attribute is both: it must be
  sent on create and can't be changed after.
- The turbostreamer `schema.json` reports `readonly` like the jbuilder one,
  instead of always `true`.

### Security

- An include's `when`, ie. `include[photos][when][active]=true`, which renders
  the include only for the records matching it, called `record.send` with
  each of its keys, so a GET could call any method on the records it
  rendered: `include[photos][when][destroy]=1` destroyed them. Its keys must
  now be attributes of the model its Policy makes filterable with `eq`, and
  are read with `read_attribute`; anything else is rejected
  with a 400.
- The `group_by` param was passed to `group` as a String, which Rails uses
  as raw SQL, so a client could append SQL to the `GROUP BY` of `index`,
  `calculate` and the other actions, ie.
  `group_by=id HAVING (SELECT ...) = 'a'`, and read any data the database
  user can from whether records came back. It now only accepts column names
  of the model, passed to `group` as columns, and rejects anything else with
  a 400.
