# Changelog

## 9.0.0

### Breaking changes

- Require Ruby 3.3 or later and activerecord-sort 8.1 or later, below 9.
- Remove `StandardAPI::AccessControlList`. Each model's Policy declares what
  a create or update may write (`writable`, `association ..., writable:`)
  and sets or checks per record (`assign`, `filter`). `include StandardAPI`
  includes `StandardAPI::Controller` alone, and an
  `include StandardAPI::AccessControlList` raises `NameError`: delete it.
  Files in `app/controllers/acl` and `ACL` modules nested in controllers are
  no longer loaded or included, so their methods, ie. a `filter`, aren't
  used. `filter_model_params` is a private method of `StandardAPI::Controller`,
  and `create_resource` writes the new record with it.
- Remove the `<model>_params` fallback, ie. a controller's `photo_params`
  listing what `#create` and `#update` permit. It isn't used: what can be
  written is what the model's Policy makes `writable`. A controller can still
  override `model_params`.
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
- `#create` and `#update` render the associations written through nested
  attributes only where the model's Policy declares them.
- Remove `ApplicationHelper#excludes`. It isn't used, so it hides nothing;
  leave what it hid out of each model's Policy instead.
- Remove ACL `orders`. What can be ordered by is what the model's Policy
  declares `orderable`, ie. `attributes :id, :name, orderable: true`; ordering
  by anything else is rejected with a 400. An association declared
  `orderable` can be ordered by what its model's own Policy makes orderable.
  A controller's `<model>_orders` method, ie. `photo_orders`, isn't used.
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
  object or `null`, and an array column an array, without saying so.
  `Controller#model_attributes` is removed, and a `<model>_attributes`
  controller method isn't used.
- Remove ACL `nested`. What a create or update may write through nested
  attributes is the associations the model's Policy declares `writable`, ie.
  `association :photos, writable: true`, or `writable :photos` without
  rendering them. What's written of the associated records is up to their
  own model's Policy, or the one `writable: { policy: }` gives. An
  association that renders with `policy:` has to say which Policy writes it
  with `writable: { policy: }`, or raises `ArgumentError`.
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
- `StandardAPI::TestCase`'s create and update tests expect the params they
  send only in what the model's Policy makes `writable` on that action and
  doesn't `assign`. `create_attributes` and `update_attributes` are no longer
  the same method: each gives what its action could have written, and
  `update_attributes(record, was)` takes the record as it was before the
  update. `orders`, `required_orders` and `where_permitted?` ask the
  controller of a request the test made, making a GET for one if need be,
  so a Policy that reads the session or request gets one.

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
`includes` methods and move what they permitted into the Policy. For anything it permitted under a polymorphic
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
what they permitted `orderable` in the Policy instead. An association they permitted by name is declared
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

ACL `nested` has been replaced by the associations each model's Policy
declares `writable`. Delete it, and make what it listed `writable` in the
Policy instead: with `writable:` on an association it declares, or with
`writable` on its own for one it doesn't render:

    # Before, in PropertyACL
    def nested
      [ :photos, :landlord ]
    end

    # After
    class PropertyPolicy < StandardAPI::Policy
      association :photos, writable: true
      writable :landlord
    end

An association that renders with a `policy:` also says which Policy writes
it, ie. `association :landlord, policy: LandlordNamePolicy, writable: { policy:
LandlordPolicy }` for its own model's.

An ACL `filter` that only sets attributes on the server can be replaced with
`assign` in the Policy:

    # Before, in CommentACL
    def filter(comment, comment_params, id: nil, allow_id: nil)
      filter_model_params(comment, comment_params, id: id, allow_id: allow_id).tap do |whitelist|
        whitelist[:author_id] = current_user.id unless comment.persisted?
      end
    end

    # After
    class CommentPolicy < StandardAPI::Policy
      assign :author_id, on: :create, with: -> { current_user.id }
    end

Any other ACL `filter` can move into the Policy as a `filter`. It's given the
params already permitted and assigned, and changes them in place rather than
returning them; `record` is the record being written and `on:` replaces
checking `record.persisted?`:

    # Before, in ChartACL
    def filter(chart, chart_params, id: nil, allow_id: nil)
      filter_model_params(chart, chart_params, id: id, allow_id: allow_id).tap do |whitelist|
        if (chart.global? || whitelist[:global]) && !admin?
          raise StandardAPI::UnpermittedParameters.new([{ chart: ['global'] }])
        end
        whitelist.delete(:roles) if chart.persisted? && !admin?
      end
    end

    # After
    class ChartPolicy < StandardAPI::Policy
      filter do |params|
        if (record&.global? || params[:global]) && !admin?
          raise StandardAPI::UnpermittedParameters.new([{ chart: ['global'] }])
        end
      end
      filter(on: :update) { |params| params.delete(:roles) if !admin? }
    end

`StandardAPI::AccessControlList` has been removed, so once every ACL method
has moved into the Policy, delete `include StandardAPI::AccessControlList`,
`app/controllers/acl` and the controllers' nested `ACL` modules. Nothing loads
or includes them anymore, so a `filter` left in one isn't run, and any other
helper method an ACL module defined is no longer on the controller: move it
out of `app/controllers/acl`, which StandardAPI has the autoloader ignore, and
include it into the controller yourself, ie. as a concern:

    # Before, in app/controllers/acl/photo_acl.rb
    module PhotoACL
      def photo_owner?(photo) = photo.account_id == current_account.id
    end

    # After, in app/controllers/concerns/photo_owner.rb
    module PhotoOwner
      def photo_owner?(photo) = photo.account_id == current_account.id
    end

    class ApplicationController < ActionController::Base
      include StandardAPI::Controller
      include PhotoOwner
    end

A controller's `<model>_params` method, ie. `photo_params`, isn't used either;
make what it permitted `writable` in the model's Policy.

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
  `writable`, `writable_associations`, `writable_policy`,
  `assigned_attributes`, `assigned_attribute_names`, `filter_params`,
  `value`, `hidden?` and `errors`.
  `application/_record` and custom partials are built on it.
- A controller can nest a subclass of `StandardAPI::Policy`
  (`PhotosController::Policy`), found by `StandardAPI::Policies`
  (`StandardAPI::Controller` includes it), to declare its model's attribute definitions. Like strong parameters only
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
  `assign :author_id, on: :create, with: -> { current_user.id }` sets an
  attribute on a create or update, or both without `on:`, in place of what
  the params send, writable or not; `with:` is a Symbol or Proc run on the
  Policy for the record being written. It applies to nested records too, and
  `schema/write.json` leaves it out. A name the model can't set, or an
  `attr_readonly` one not `on: :create`, raises `ArgumentError`.
  `filter { |params| ... }`, or `filter :method`, adjusts or rejects the
  permitted params of a create or update, or only one with `on:`, after the
  assigns, in place of an ACL `filter`. Filters run on the Policy for the
  record being written, in declaration order, inherited ones first, and for
  nested records with their own Policy or `writable: { policy: }`'s;
  `record_policy(record).filter_params(params)` runs them.
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
- Each resource serves three JSON Schemas (2020-12), built from its Policy,
  each drawn only with the actions it describes:
  - `schema/read.json`: a record as `#show` and `#index` render it, with the
    `include` param checked against the Policies. A column that
    allows NULL, and a singular association unless its presence is
    validated, allow `null`; decimals are strings, binary is hex, and an
    enum lists its names.
  - `schema/write.json`: the params `#create` and `#update` accept, with only
    the attributes and associations the Policy makes `writable`, and their
    validations. `required` is for a create. A
    `read_only` definition is `readOnly`; an auto populated column isn't, and
    isn't `required`.
  - `schema/query.json`: the `where`, `order` and `include` the Policies
    declare, following
    associations through `$defs`, plus `limit`, `offset`, `distinct` and `group_by`, and the
    params no Policy checks yet, marked as such.

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
