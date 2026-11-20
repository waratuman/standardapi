# StandardAPI

StandardAPI makes it easy to expose a [REST](https://en.wikipedia.org/wiki/Representational_state_transfer)
interface to your Rails models. It provides filtering, ordering, pagination,
includes (preloading), calculations, and access control out of the box with
minimal configuration.

- [Installation](#installation)
- [Quick Start](#quick-start)
- [Controllers](#controllers)
  - [Including StandardAPI](#including-standardapi)
- [Limits and Pagination](#limits-and-pagination)
  - [Masks (Row-Level Filtering)](#masks-row-level-filtering)
- [Policies](#policies)
- [Routes](#routes)
- [API Usage](#api-usage)
  - [Filtering (where)](#filtering-where)
  - [Ordering](#ordering)
  - [Includes](#includes)
  - [Pagination](#pagination)
  - [Calculations](#calculations)
  - [Relationship Management](#relationship-management)
  - [Schema Discovery](#schema-discovery)
- [Query Encoding Middleware](#query-encoding-middleware)
- [Views and Customization](#views-and-customization)
- [Testing](#testing)

# Installation

    gem install standardapi

In your `Gemfile`:

    gem 'standardapi', require: 'standard_api'

# Quick Start

Include `StandardAPI` in a controller, define the allowed attributes, and give
each model a Policy for what it renders, can include and can be ordered by:

        # QueryEncoding middleware intercepts and parses the query string
        # as MessagePack if the `Query-Encoding` header is set to `application/msgpack`
        # which allows GET request with types as opposed to all values being interpeted
        # as strings
        config.middleware.insert_after Rack::MethodOverride, StandardAPI::Middleware::QueryEncoding
      end
    end

# Implementation

StandardAPI is a module that can be included into any controller to expose a API
for. Alternatly, it can be included into `ApplicationController`, giving all
inherited controllers an exposed API.

    class PhotosController < ApplicationController
      include StandardAPI
    end

What's shown, what can be written, included (relationships in the response),
ordered by and filtered on is up to the model's Policy (see
[Policies](#policies)). A create or update may only set what the Policy makes
`writable`, and its `assign` and `filter` set or check params per record (see
[Writes](#writes)).

##### Custom partials

**Policies are enforced in `application/_record` only.** If you have written a
custom partial for a model (`app/views/photos/_photo.json.jbuilder`),
StandardAPI cannot filter attributes that partial serializes itself — your
partial has to ask the record's policy what it renders:

    policy = record_policy(photo, local_assigns[:policy])

    json.set! :caption, photo.caption if policy.attribute?(:caption)

    # pass on the Policy the records of an association render with
    if includes[:account] && policy.include?(:account)
      json.partial! 'application/record', record: photo.account,
        includes: includes[:account], policy: policy.association_policy(:account)
    end

`record_policy(record, policy)` gives a `StandardAPI::Policy::Record`: what the
record renders with its model's Policy, or with `policy` in its place, the one
the association that included it gives, which the parent partial passes down as
the `policy` local.

- `attributes` are the definitions of what it renders, and `attribute?(name)`
  tells if one does.
- `include?(name)` tells if an include, an association or a method, renders.
- `includes(includes)` gives the includes of the `includes` local it renders,
  as `name, sub_include, sub_policy`: what to include of them, and the Policy to
  render them with. `application/_record` loops over it, as it does
  `attributes`:

      policy.includes(includes).each do |name, sub_include, sub_policy|
        json.set! name do
          json.partial! 'application/record', record: photo.send(name),
            includes: sub_include, policy: sub_policy
        end
      end

- `association_policy(name)` gives the Policy to pass on to an association's
  records, or `nil` for their own.
- `orderable` names what a request may order by (see [Orders](#orders)),
  decided for the model whatever the record.
- `required_orders` names what every request is ordered by after its own
  orders, decided for the model too.
- `writable` is what a create or update of the record may set, as strong
  parameters permit it (see [Writes](#writes)); a model is a create.
- `value(name)` is the value to render for an attribute (see `value:`).
- `hidden?(name)` tells if it hides an attribute or association of the model,
  or an attribute the Policy adds.
- `errors` are the record's validation errors, less those on what it hides.

`application/_record` is built on it, and
`test/standard_api/test_app/views/photos/_photo.json.jbuilder` is a complete
worked example of a custom partial.

Fragment caching is disabled automatically for any response a Policy that
varies by requester or a `mask_for` row mask could affect, since cache keys are
built from record timestamps and cannot distinguish one requester from another.

##### Policies

A model's controller can declare how its attributes are described by nesting a
subclass of `StandardAPI::Policy`. `StandardAPI::Controller`
finds them, and every model it renders needs one:

    class PhotosController < ApplicationController
      class Policy < StandardAPI::Policy
        attributes :id, :created_at, orderable: true         # use these, and order by them
        attribute :format                                    # use one as it is
attribute :caption, comment: 'Shown under the photo' # use one and change it
        attribute :thumbnail_url, :string                    # add one
        attribute :location, if: :admin?                     # hide one, per request

        associations :account, :properties                   # render these when included
      end
    end

Like strong parameters, a Policy is explicit: only the attributes and
associations it declares are rendered or described, so a column or association
added later stays hidden until it's listed. Types, defaults and validations of
a declared attribute still come from the model.

`remove` takes back a declaration, such as one inherited from a parent Policy.

Every model that's rendered or described needs a Policy, including one only
rendered as an include, or `StandardAPI::MissingPolicy` is raised, so nothing is
exposed that no one chose to. A model with no controller of its own declares
its Policy by name, `ToolCallPolicy` for `ToolCall`:

    class ToolCallPolicy < StandardAPI::Policy
      attributes :id, :name, :arguments
    end

A custom partial that doesn't use `record_policy` isn't checked.

`attribute` takes any key of the definition below. With a type it adds an
attribute the model doesn't have, read from the record by name
(`record.thumbnail_url`), and read only unless it says otherwise. Without a
type, naming an attribute the model doesn't have raises, as does an unknown
option. A real attribute a query didn't select stays out of that record's
definitions, whatever is declared for it.

`value` renders something else in place of the record's value. It takes a
method name or Proc that runs on the instance like a condition, reading the
record from `record`:

    attribute :email, value: -> { record.email if admin? }
    attribute :issues, :json, value: :visible_issues

It changes what's rendered, not the definition, so the type still comes from
the model or the declaration. `serialize_attribute` reads values with
`attribute_value(record, name)`; an override of it should too. A custom partial
renders its own values, so isn't changed.

Declarations are inherited, so `class Policy < BasePolicy` works, and a Policy's
private methods stay on the Policy rather than the controller.

The Policy runs on one instance per model for the length of a request. A method
it doesn't define goes to its `controller`, private ones
included, so `params` and `admin?` just work. The Policy's own methods win, so
`attributes`, `model` and `definitions` are its own; call `controller.model` for the
controller's. Don't call `record_policy` from a condition, as
they call back into the Policy.

Every controller describes and renders a Photo with the same Policy, including
as an include of a property, so two controllers of one model with a Policy
raise `StandardAPI::InvalidConfiguration`, as does a nested `Policy` that isn't
a `StandardAPI::Policy`.

`attributes_for` declares attributes only known at runtime. Its key is a method
name or Proc that reads `record` (`nil` for a model), and records with the same
key share the result. The block runs on the instance once a request per key, is
given the key, and declares with `attribute`, `attributes`, `association`,
`associations` and `remove`. `record` raises in the block, since its result is
shared between records:

    attributes_for :account_id do |account_id|
      Field.where(account_id: account_id).each do |field|
        attribute field.key, field.value_type, comment: field.name
      end
    end

    private

    def account_id
      record&.account_id || params[:account_id]
    end

`if` and `unless` take a method name or Proc that runs on the instance, once for
each record, takes no arguments and reads the record from `record`. A controller
method can't read `record`, so a named one is called without it; pass the record
to one that needs it: `unless: -> { hide?(record) }`. Don't memoize
something about `record` in an instance variable, as the instance serves every
record of the model. For `record_policy(Photo)` and the JSON Schemas, `record` is
`nil`, so decide what that means: `if: -> { record&.public? }` hides the attribute
from them, while `unless: -> { record&.private? }` shows it. Hidden and
undeclared attributes aren't rendered or named in validation errors, and
fragments that include the model of a Policy that could vary by requester
aren't cached.

Hiding an attribute controls what the API shows, not what it permits: it can
still be written if it's `writable` (see [Writes](#writes)), which can reveal
its value. It can't be ordered by or filtered on while it's hidden from the
model (see [Orders](#orders) and [Filters](#filters)).

###### Orders

What a request may order by, with the `order` param or an include's `order`,
is what the Policy declares `orderable`. Ordering by anything else is rejected
with a 400. You'll most likely want an index on each of them:

    class PhotoPolicy < StandardAPI::Policy
      attributes :id, :created_at, orderable: true
      attribute :caption, orderable: true
      association :account, orderable: true    # order[account][name] if AccountPolicy makes name orderable
    end

An association declared `orderable` can be ordered by what its model's own
Policy makes orderable, one association deep; a polymorphic one can't be
ordered by. `orderable: false` takes back one inherited from a parent Policy.

What's orderable is decided for the model, with a `nil` record, so an
attribute an `if` or `unless` hides from the model can't be ordered by. One
declared in an `attributes_for` block is orderable when it's declared for the
key a `nil` record gives.

`required_orders` orders every request by its names, in order, after what the
request orders by, unless it already orders by them, ie. so pages are stable.
They're orderable without being declared `orderable`. Without an `order`, the
controller's `default_orders` come first:

    class PhotoPolicy < StandardAPI::Policy
      attribute :created_at, orderable: true
      required_orders :id                      # order=created_at sorts by created_at, then id
    end

###### Filters

What a request may filter on, with the `where` param or an include's `where`
and `when`, is what the Policy declares `filterable`. Filtering on anything
else is rejected with a 400:

    class PhotoPolicy < StandardAPI::Policy
      attributes :id, :caption, filterable: true      # with any operator
      attribute :created_at, filterable: [:gt, :lt]   # with only these
      association :author, filterable: true           # where[author][name] if AuthorPolicy makes name filterable
      filterable :search, :photos_tags                # without rendering them
    end

`filterable: true` (or `"*"`) permits any operator, or `filterable:` lists the
operators it permits; an operator's aliases, ie. `greater_than` for `gt`, are
permitted with it. A bare value counts as `eq` and an Array as `in`.

An association declared `filterable` can be filtered on by what its model's
own Policy makes filterable; for a polymorphic one, the Policy of the class its
`as` names. It also permits filtering on its `_ids`. It can only be
`filterable: true`.

`filterable` on its own permits names without declaring them, so they're
neither rendered nor includable: a `filter_on` filter, a
has_and_belongs_to_many join table, or an association that shouldn't be
included. `operators:` limits the operators, and `if` and `unless` decide it
for the model, so they can read the controller or the request:

    filterable :tims, unless: -> { controller.class.model == Library }

Filtering on a column can reveal its values, ie. `where[salary][gt]=100000`, so
make only what a requester may see filterable. What's filterable is decided for
the model, with a `nil` record, so an attribute an `if` or `unless` hides from
the model can't be filtered on. `filterable: false` and `remove` take one back.

###### Writes

What a create or update may set is what the Policy declares `writable`.
Anything else in the params is dropped, as strong parameters drop it:

    class PhotoPolicy < StandardAPI::Policy
      attributes :caption, :metadata, writable: true    # metadata, a jsonb column, takes an object or null
      attribute :account_id, writable: { on: :create }  # can't be changed after
      attribute :tags, writable: [:name, { filter: {} }] # an array of objects
      writable :file                                    # without rendering it
    end

`writable: true` permits what the column's type takes: an array for an array
column, an object or `null` for a `json` or `jsonb` one, or else a single
value. A strong parameters permit, as an Array, takes its place. `on: :create`
or `on: :update` permits it only on one; a model, ie. for the schema, is a
create.

What's writable is decided for the record being created or updated, before
the params are assigned. An `if` or `unless` decides what renders, not what's
writable, so a hidden attribute can still be written; one declared in an
`attributes_for` block is writable when it's declared for the record's key.
`writable: false` and `remove` take one back.

`writable` on its own permits names without declaring them, so they aren't
rendered: a password, or an `attr_accessor`. It takes `on:`, and `permit:` for
a strong parameters permit.

`assign` sets an attribute on the server, ie. the author of a new record:

    class CommentPolicy < StandardAPI::Policy
      assign :author_id, on: :create, with: -> { current_user.id }
      assign :ip_address, with: :remote_ip   # a method of the Policy, or the controller

      private

      def remote_ip = request.remote_ip
    end

`with:` is a Symbol naming a method or a Proc, run on the Policy like a
condition, with `record` the record being created or updated. `on:` works as
for `writable`, a new record being a create. What it gives replaces anything
the params send, and the attribute needn't be `writable`; `schema/write.json`
doesn't list it. A nested record gets what its own Policy, or `writable: {
policy: }`'s, assigns. `remove` takes one back, and
`record_policy(record).assigned_attributes` gives what's set, as name =>
value. Assigning a name the model can't set, or an `attr_readonly` one
other than `on: :create`, raises `ArgumentError` when first used.

`filter` adjusts or rejects what a create or update sets, once it's been
permitted and assigned:

    class ChartPolicy < StandardAPI::Policy
      filter do |params|
        if (record&.global? || params[:global]) && !admin?
          raise StandardAPI::UnpermittedParameters.new([{ chart: ['global'] }])
        end
      end
      filter :limit_roles, on: :update   # a method of the Policy, given the params

      private

      def limit_roles(params) = params.delete(:roles) if !admin?
    end

A filter is a block, or a Symbol naming a method or a Proc, run on the Policy
like a condition, with `record` the record being created or updated. It's
given the permitted params, an `ActionController::Parameters`, after what's
`assign`ed is set, so it sees those values, and it may change them in place
or raise; `StandardAPI::UnpermittedParameters` responds with a 400. `on:`
works as for `assign`. Filters run in the order they're declared, inherited
ones first, and one declared in an `attributes_for` block runs for the
records of its key. A nested record runs its own Policy's, or `writable: {
policy: }`'s, filters. `record_policy(record).filter_params(params)` runs
them.

An association is written through nested attributes:

    class PropertyPolicy < StandardAPI::Policy
      association :photos, writable: true            # photos: [{ id: 1, caption: 'Lobby' }, { caption: 'Roof' }]
      association :landlord, writable: { on: :create }
      writable :accounts                             # without rendering them
    end

A create or update may then send the associated records' attributes, which
creates a record without an `id` and updates the one with it; only their
`id`s, as `[{ id: 1 }]` or `photo_ids`; or the foreign key, ie.
`landlord_id`. What can be set of an associated record is what its own model's
Policy makes writable. `on:` works as for an attribute;
`permit:` doesn't, as what an associated record takes is up to its Policy.

`writable: { policy: }` writes the associated records with another Policy
class in their own's place, ie. to narrow what can be set of them through
this association:

    class PropertyPolicy < StandardAPI::Policy
      association :photos, policy: PhotoSummaryPolicy, writable: { policy: PhotoCaptionPolicy }
      association :landlord, policy: LandlordNamePolicy, writable: { policy: LandlordPolicy }
    end

The `policy:` an association renders with doesn't decide what's written of
it, so an association declared with both `policy:` and `writable:` has to say
which Policy writes it, even when it's its own model's, or it raises
`ArgumentError`: when it's declared, or when it's first written if the two are
declared apart. As the associated records are written before they're loaded,
it's a class, not a Symbol or Proc.

A writable attribute's definition isn't `read_only`, unless it's only writable
on create or the model makes it `attr_readonly`, and it's `required` when its
column is NOT NULL and not auto populated, unless it's only writable on update.

###### Associations

What a request may include is what the Policy declares with `association` or
`associations`, an association or a method rendered as an include. Including
anything else is rejected with a 400. What's included of an included record is
checked against what its own Policy declares, or the `policy` the association
gives in its place, at every level below it:

    class PhotoPolicy < StandardAPI::Policy
      associations :author, :camera        # include[author][photos] if AuthorPolicy declares photos
    end

An association only renders when the `include` param asks for it. On
`#create` and `#update`, so do the associations written through nested
attributes (see [Writes](#writes)), where the Policy declares them.

Declarations are checked for the model, with a `nil` record: `if` and `unless`
don't stop an association from being asked for, only from rendering, and one
declared in an `attributes_for` block can be asked for when it's declared for
the key a `nil` record gives.

Under a polymorphic association or a method there's no single model to check
what's included of it against. It's checked against the `policy` the
association gives, if it gives a Policy class, or else the Policies of the
models its `types` name: each include is permitted if one of them declares it,
and checked below it against that model. A `where` or `order` under it is
rejected, and a `when` isn't checked, as its records can be of any type:

    association :subject, types: [Property, 'Account']   # include[subject][landlord] if PropertyPolicy or AccountPolicy declares it

Without `policy` or `types`, nothing can be included of it.

`if` and `unless` hide an association per record, as they do an attribute:

    association :comments, unless: -> { record&.locked? }

The included records render with their own model's Policy, found from the
association (or, for a polymorphic one, from each record's class), unless
`policy` gives one to render them with in its place:

    class NamePolicy < StandardAPI::Policy
      attributes :id, :name
    end

    association :account, policy: NamePolicy
    association :subject, policy: NamePolicy                     # any model with an id and name
    association :owner, policy: -> { NamePolicy if redacted?(record) }

It decides everything about the included records, their associations and
values too: `NamePolicy` declares no associations, so nothing can be included
through `account`. Given a method name or Proc, it runs like a condition, on
the record including them, and returns a Policy, or `nil` to render them with
their own.

The same goes for a method: a record it returns, or a relation or an Array of
records, renders as the records of an association do, with their own Policy or
the `policy` given. Plain JSON data it returns, nil, a String, Symbol, Numeric,
true, false, Date, Time or `ActiveSupport::Duration` (as its seconds), or a
Hash, an Array or a Set (as an Array) of them, is rendered whole.
Anything else raises `StandardAPI::MissingPolicy` rather than rendering it with
`as_json`, which would expose all of its instance variables: a model that
isn't an ActiveRecord can't have a Policy, not even one `policy` gives, and a
record in a Hash, or in an Array with anything but records, isn't rendered with
its Policy. Return a Hash of what to render instead. A response that includes a
method isn't cached.

**It replaces their own Policy, so nothing their own Policy hides is hidden
unless it declares so too.** To start from what their own Policy renders, and
hide more, inherit from it:

    class AccountWithoutEmailPolicy < AccountPolicy
      remove :email
    end

The Policy is passed to the included records' partial as the `policy` local,
and `record_policy(record, local_assigns[:policy])` renders with it, so a custom
partial that calls it does too.

`varies_by_requester?` is true for a Policy with `if`, `unless`, `value` or
`attributes_for`, or an association whose `policy` is a method name, a Proc, or
a Policy that varies. Override it when a Policy doesn't vary, so fragments can
be cached.

A Policy's definitions come only from its declarations. For a value that
differs by record, key it with `attributes_for`:

    attributes_for(-> { record&.title }) { |title| attribute :caption, comment: title }

`record_policy(Photo).attributes` returns the result, and `schema.json` and the
JSON Schemas (see [Schema Discovery](#schema-discovery)) are built from it.
Records are rendered from it too: `application/_record` renders the attributes
in `record_policy(record).attributes`. `record_policy` is available in
controllers and views, so other code (an MCP tool describing your models, for
instance) can read the same definitions without rendering a schema view and
parsing it back.

Before the Policy sees them, there is one definition per entry in
`model.attribute_names`, or, given a record, in `record.attribute_names`: the
attributes its query selected. A record loaded with `select(:id)` has only
`id`, and one loaded with `select('*, 1 AS rank')` also has `rank`, with a
`nil` type since the model doesn't have it. Records of a model with the same
attributes share their definitions before the Policy sees them.

    record_policy(Property).attributes.find { |s| s[:name] == 'name' }
    # => { name: 'name', type: 'string', enum: nil, default: nil,
    #      primary_key: false, null: true, array: false, comment: nil,
    #      auto_populated: false, read_only: false, required: true,
    #      validations: [{ kind: :presence, options: {} }] }

| Key              | Value                                                                                                       |
|------------------|-------------------------------------------------------------------------------------------------------------|
| `name`           | The attribute name                                                                                          |
| `type`           | The ActiveModel type, `type_for_attribute(name).type`, as a String (`string`, `text`, `integer`, `decimal`, `date`, `time`, `datetime`, `jsonb`, ...). `string` for an enum, `nil` for a type that doesn't name itself |
| `enum`           | The names an enum accepts, or `nil`                                                                         |
| `default`        | The column default cast to Ruby. For an enum, the name of the default                                       |
| `primary_key`    | Whether it is the primary key                                                                               |
| `null`           | Whether the column allows `NULL`                                                                            |
| `array`          | Whether the column is an array. `type` is then the type of its elements. The JSON Schemas put `readOnly`, `default` and `description` on the array and the type and validations on its `items` |
| `comment`        | The column comment. The JSON Schemas render it as `description`                                             |
| `auto_populated` | Whether the database fills it in (a serial id, a function default), so a create needn't set it. It doesn't make it `read_only` |
| `read_only`      | Not `writable` in the Policy, only writable on create, or readonly on the model (`attr_readonly`)           |
| `required`       | NOT NULL and writable on create (`writable` in the Policy, not auto populated), or validated for presence or acceptance without `allow_nil`. An `attr_readonly` attribute can be set on create, so it can be both `read_only` and `required` |
| `validations`    | `[{ kind: :length, options: { maximum: 12 } }, ...]`                                                        |

An attribute the model declares without a column (`attribute :nickname,
:string` in the model) has `nil` for `default`, `null`, `comment` and
`auto_populated`. They're decided for a `nil` record, so `read_only` is the
answer for the model as a whole.

A Policy `attribute` adding one the model doesn't have starts from
`StandardAPI::Policy::Builder::DEFAULTS`: `null` and `read_only` are `true`,
`auto_populated` is `false`.

For an STI subclass, ie. `Pdf < Document`, without a Policy of its own, the
base class's is used (`DocumentPolicy`).

`schema.json` lists the same attributes as `record_policy(model).attributes`, with the same
`readonly`. A column's `type` still comes from its SQL type unless
a Policy declares another, so it reports `datetime` for date and time columns,
`hash` for JSON and `decimal` for floats.

# API Usage
Resources can be queried via REST style end points
```
GET     /records/:id        fetch record
PATCH   /records/:id        update record
GET     /records/           fetch records
GET     /records/calculate  apply count and other functions on record(s)
POST    /records            create record
DELETE  /records            destroy record
```

All resource end points can be filtered, ordered, limited, offset, and have includes. All options are passed via query string in a nested URI encoded format.

```javascript
// Example
params = {
    limit: 5,
    offset: 0,
    where: {
        region_ids: {
            contains: newyork.id
        }
    },
    include: {
        property: {
            addresses: true
        },
        photos: true
    },
    order: {
        created_at: 'desc'
    }
}
// should be
'limit=5&offset=0&where%5Bregion_ids%5D%5Bcontains%5D=20106&include%5Bproperty%5D%5Baddresses%5D=true&include%5Bphotos%5D=true&order%5Bcreated_at%5D=desc'
```

## Pagination

Use `limit` and `offset` for pagination:

```
id: 5               WHERE properties.id = 5
id: [5, 10, 15]     WHERE properties.id IN (5, 10, 15)
id: {gt: 5}         WHERE properties.id > 5
id: {gte: 5}        WHERE properties.id >= 5
id: {lt: 5}         WHERE properties.id < 5
id: {lte: 5}        WHERE properties.id <= 5
address_id: nil     WHERE properties.address_id IS NULL
address_id: false   WHERE properties.address_id IS NULL..."
address_id: true    WHERE properties.address_id IS NOT NULL..."

// Array columns
tags: 'Skyscraper'                          WHERE properties.tags = {"Skyscraper"}
tags: ['Skyscraper', 'Brick']               WHERE properties.tags = '{"Skyscraper", "Brick"}'
tags: {overlaps: ['Skyscraper', 'Brick']}   WHERE properties.tags && '{"Skyscraper", "Brick"}'
tags: {contains: ['Skyscraper', 'Brick']}   WHERE accounts.tags @> '{"Skyscraper", "Brick"}'

// Geospatial
location: {within: 0106000020e6...}         WHERE ST_Within("listings"."location", ST_GeomFromEWKB(E'\\x0106000020e6...)

// On Relationships
property: {size: 10000}         JOIN properties WHERE properties.size = 10000"
```
## Calculations

The only change on calculate routes is the `selects` paramater contains the functions to apply. Currently just `minimum`, `maximum`, `average`, `sum`, and `count`.

```
{ count: '*' }                                          SELECT COUNT(*)
[{ count: '*' }]                                        SELECT COUNT(*)
[{ count: '*', maximum: :id, minimum: :id }]            SELECT COUNT(*), MAXIMUM(id), MINIMUM(id)
[{ maximum: :id }, { maximum: :count }]                 SELECT MAXIMUM(id), MAXIMUM(count)
```

## Schema Discovery

Each resource serves three [JSON Schemas](https://json-schema.org/draft/2020-12)
(2020-12) built from its Policy, so a client (an MCP tool, for
instance) can learn what it may send and what it will get back:

```
GET /records/schema/read.json   a record as #show and #index render it
GET /records/schema/write.json  params #create and #update accept
GET /records/schema/query.json  params #index and #calculate accept
```

Each route is only drawn with the actions it describes: `read_schema` with
`show` or `index`, `write_schema` with `create` or `update`, and
`query_schema` with `index` or `calculate`. Attributes are described from
their definitions in `record_policy(model).attributes` (see [Policies](#policies)), so only
what the model's Policy declares is described, with the `record` its
conditions see being `nil`.

- **`schema/read.json`** describes every definition as rendered (decimals as
  strings, binary columns as hex), and the associations in the `include`
  param, which is checked against the Policies as on `#index`. A
  singular association allows `null` unless its presence is validated.
  Columns and includes are `required`; other attributes aren't, since a
  partial `select` can leave them out. When a Policy condition could hide
  something from a record, what it hides is still
  described and nothing is `required`. A model with a custom partial is
  described as any object.
- **`schema/write.json`** describes `{ "record": { ... } }` with only the
  attributes the Policy makes `writable` for a create, with their
  validations, and the associations it makes `writable` (by
  attributes, `_ids` and foreign key). One that's writable but not declared,
  ie. with `writable :password`, is `{}`.
  `required` lists the definitions' `required`, for a create; an update may
  send any of the properties. A `read_only` definition is `readOnly`: an
  `attr_readonly` attribute, which can be set on create but not changed, or
  one the Policy declares read only.
- **`schema/query.json`** describes `where`, `order` and `include` as the
  Policies declare them, following associations into the associated models'
  Policies through `$defs`, plus `limit`, `offset`,
  `distinct` and `group_by`. Columns to `group_by` and associations to `join`
  aren't listed by name, as not all of them need be exposed. An include's `where` and
  `order` are what the included model's Policy makes filterable and
  orderable. A column permitted with
  any operator lists the operators that apply to its type. An include's `when`
  lists the attributes of the model it's on that its Policy makes filterable
  with `eq`. It also describes the params no Policy checks yet, as they're used,
  with a description ending "Not checked by the Policy.": `distinct_on`, `join`,
  `#calculate`'s `select`, and `distinct_on` within an include. `limit` is
  required unless there is a `default_limit`, or the query has a `select`
  (`#calculate`).

  It describes one form of each param, the canonical one. The server takes
  others that it doesn't list, so params using them work but don't validate:
  an operator's aliases (ie. `greater_than` or `gteq` for `gt` and `gte`), an
  order by a dotted key (`{ "property.name": "asc" }`) or by an association's
  name alone, an upper-case direction (`DESC`), and a single value where an
  array column takes an array.

The schemas are built by `read_schema_for(model, includes)`,
`write_schema_for(model)` and `query_schema_for(model)`, which are public like
`record_policy`. Called on a controller handling a request, they give what the
actions render, so a caller can validate params in-process before running an
action. `query_schema_for` builds the where, order and include of every model
reachable through a permitted association into `$defs`; given `ref:`, it
leaves other models to the caller:

    query_schema_for(Property, ref: ->(model, kind) {
      # kind is "Where", "Order" or "Include"; nil builds it into $defs
      { '$ref' => "myapp://schema/#{model.model_name.plural}#/$defs/#{model.name.gsub('::', '')}#{kind}" }
    })

A schema built with `ref:` also has the where, order and include of its own
model in `$defs`, as `PropertyWhere`, `PropertyOrder` and `PropertyInclude`,
so the schemas of the other models can refer to them.

# Testing

And example contoller and it's tests.

    class PhotosController < ApplicationController
        include StandardAPI

        # If you have actions you don't want include be sure to hide them,
        # otherwise if you include StandardAPI::TestCase and you don't have the
        # action setup, the test will fail.
        hide_action :destroy

# Mask for Photo. Provide this method if you want to mask some records
        # The mask is then applyed to all actions when querring ActiveRecord
        # Will only allow photos that have id one. For more on the syntax see
        # the activerecord-filter gem.
        def mask_for(table_name)
            { id: 1 }
        end

    end

# Usage

StandardAPI Resource Interface

| PATH | JSON | SQL | RESULT |
|------|------|-----|--------|
| `/models` | `{}` | `SELECT * FROM models` | `[{ id: 1 }, { id: 2 }]` |
| `/models?limit=1` | `{ "limit": 1 }` | `SELECT * FROM models LIMIT 1` | `[{ id: 1 }]` |
| `/models?offset=1` | `{ "offset": 1 }` | `SELECT * FROM models OFFSET 1` | `[{ id: 2 }]` |
| `/models?order[id]=asc` | `{ "order": { "id": "asc" } }` | `SELECT * FROM models ORDER BY models.id ASC` | `[{ id: 1 }, { id: 2 }]` |
| `/models?order[id]=desc` | `{ "order": { "id": "desc" } }` | `SELECT * FROM models ORDER BY models.id DESC` | `[{ id: 2 }, { id: 1 }]` |
| `/models?order[id][asc]=nulls_first` | `{ "order": { "id": { "asc": "nulls_first" } } }` | `SELECT * FROM models ORDER BY models.id ASC NULLS FIRST` | `[{ id: null }, { id: 1 }]` |
| `/models?order[id][asc]=nulls_last` | `{ "order": { "id": { "asc": "nulls_last" } } }` | `SELECT * FROM models ORDER BY models.id ASC NULLS FIRST` | `[{ id: 1 }, { id: null }]` |
| `/models?where[id]=1` | `{ where: { id: 1 } }` | `SELECT * FROM models WHERE id = 1` | `[{ id: 1 }]` |
| `/models?where[id][]=1&where[id][]=2` | `{ where: { id: [1,2] } }` | `SELECT * FROM models WHERE id IN (1, 2)` | `[{ id: 1 }, { id: 2 }]` |


