# StandardAPI

StandardAPI makes it easy to expose a [REST](https://en.wikipedia.org/wiki/Representational_state_transfer)
interface to your Rails models. It provides filtering, ordering, pagination,
includes (preloading), calculations, and access control out of the box with
minimal configuration.

- [Installation](#installation)
- [Quick Start](#quick-start)
- [Controllers](#controllers)
  - [Including StandardAPI](#including-standardapi)
  - [Whitelisting Attributes](#whitelisting-attributes)
  - [Whitelisting Orders](#whitelisting-orders)
  - [Limits and Pagination](#limits-and-pagination)
  - [Masks (Row-Level Filtering)](#masks-row-level-filtering)
- [Access Control List (ACL)](#access-control-list-acl)
- [Schemas](#schemas)
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

Include `StandardAPI` in a controller, define the allowed attributes and
orders, and give each model a Schema for what it renders and can include:

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
      
      # Allowed paramaters
      # By default any paramaters passed to update and create are whitelisted by
      # the method named after the model the controller represents. For example,
      # the following will only allow the `caption` attribute of the `Photo`
      # model to be set on update or create.
      def photo_params
        [:caption]
      end
      
      # Allowed orderings
      # The ordering is whitelisted as well, you will mostly likely want to
      # ensure indexes have been created on these columns. In this example the
      # response can be ordered by any permutation of `id`, `created_at`, and
      # `updated_at`.
      #
      # An association can be listed by name, ie. `:account`, to allow
      # ordering by the columns the associated model's orders permit
      # (`account_orders`). Only names can be listed here; a Hash, ie.
      # `{ account: [:name] }`, raises.
      def photo_orders
        [:id, :created_at, :updated_at]
      end
    end

What can be included (relationships in the response) is declared in the
model's Schema, with `association` and `associations` (see
[Associations](#associations)).

##### Access Control List

For greater control of the allowed paramaters and nesting of paramaters
`StandardAPI::AccessControlList` is available. To use it include it in your base
controller:

    class ApplicationController
        include StandardAPI::Control
        include StandardAPI::AccessControlList
    end

Then create an ACL file for each model you want in `app/controllers/acl`.

Taking the above example we would remove the `photo_*` methods and create the
following files:

`app/controllers/acl/photo_acl.rb`:

    module PhotoACL
      # Allowed attributes
      #
      # Accepts an optional record so the permitted list can vary per record
      # (e.g. based on ownership or state). The record is `nil` when there is no
      # record in context — most notably when rendering `schema.json` /
      # `schema/write.json` — so always guard against `nil` (or default it).
      def attributes(record = nil)
        [ :caption ]
      end
      
      # Allowed saving / creating nested attributes
      def nested
        [ :camera ]
      end
      
      # Allowed orders
      def orders
        [ :id, :created_at, :updated_at ]
      end
      
      # Allowed filters in the `where` param
      #
      # A column, or a column with "*", permits any operator on it, or the
      # operators it permits can be listed (aliases such as `greater_than` for
      # `gt` are permitted with them). An association is permitted by name,
      # and what is filtered on it is checked against the associated model's
      # wheres (for a polymorphic association, those of its `as` class).
      # Permitting an association also permits its `_ids`. A `filter_on`
      # filter is permitted by name. Without a `wheres` method nothing can be
      # filtered on.
      def wheres
        [ :id, :caption, { created_at: [:gt, :lt] }, :author ]
      end
    end

All of these methods are optional and will be included in ApplicationController
for StandardAPI to determine allowed attributes, nested attributes, orders and
filters. What can be included is declared in each model's Schema (see
[Associations](#associations)).

An ACL can instead be nested in the model's controller as an `ACL` module:

    class PhotosController < ApplicationController
      module ACL
        def attributes(record = nil)
          [ :caption ]
        end

        def orders
          [ :id, :created_at, :updated_at ]
        end
      end
    end

It is included in ApplicationController the same way as an
`app/controllers/acl` file, under the model's name (`photo_attributes`,
`photo_orders`, ...), so it is never included in its own controller and its
`orders` don't override the controller's own.
Controllers are loaded at boot (and after each reload) so their ACLs are found
before the first request.

The `nested` function tells StandardAPI what relations on `Photo` are allowed to
be set with the API and will determine what attributes are allowed by looking
for a `camera_acl` file.

An ACL decides what can be written, filtered and ordered. What's shown, and
what can be included, is up to the model's Schema (see [Schemas](#schemas)).

##### Custom partials

**Schemas are enforced in `application/_record` only.** If you have written a
custom partial for a model (`app/views/photos/_photo.json.jbuilder`),
StandardAPI cannot filter attributes that partial serializes itself — your
partial has to ask the record's schema what it renders:

    schema = record_schema(photo, local_assigns[:schema])

    json.set! :caption, photo.caption if schema.attribute?(:caption)

    # pass on the Schema the records of an association render with
    if includes[:account] && schema.include?(:account)
      json.partial! 'application/record', record: photo.account,
        includes: includes[:account], schema: schema.association_schema(:account)
    end

`record_schema(record, schema)` gives a `StandardAPI::Schema::Record`: what the
record renders with its model's Schema, or with `schema` in its place, the one
the association that included it gives, which the parent partial passes down as
the `schema` local.

- `attributes` are the definitions of what it renders, and `attribute?(name)`
  tells if one does.
- `include?(name)` tells if an include, an association or a method, renders.
- `includes(includes)` gives the includes of the `includes` local it renders,
  as `name, sub_include, sub_schema`: what to include of them, and the Schema to
  render them with. `application/_record` loops over it, as it does
  `attributes`:

      schema.includes(includes).each do |name, sub_include, sub_schema|
        json.set! name do
          json.partial! 'application/record', record: photo.send(name),
            includes: sub_include, schema: sub_schema
        end
      end

- `association_schema(name)` gives the Schema to pass on to an association's
  records, or `nil` for their own.
- `value(name)` is the value to render for an attribute (see `value:`).
- `hidden?(name)` tells if it hides an attribute or association of the model.
- `errors` are the record's validation errors, less those on what it hides.

`application/_record` is built on it, and
`test/standard_api/test_app/views/photos/_photo.json.jbuilder` is a complete
worked example of a custom partial.

Fragment caching is disabled automatically for any response a Schema that
varies by requester or a `mask_for` row mask could affect, since cache keys are
built from record timestamps and cannot distinguish one requester from another.

##### Schemas

A model's controller can declare how its attributes are described by nesting a
subclass of `StandardAPI::Schema`, like an `ACL`. `StandardAPI::Controller`
finds them, and every model it renders needs one:

    class PhotosController < ApplicationController
      class Schema < StandardAPI::Schema
        attributes :id, :format, :created_at                 # use these as they are
        attribute :caption, comment: 'Shown under the photo' # use one and change it
        attribute :thumbnail_url, :string                    # add one
        attribute :location, if: :admin?                     # hide one, per request

        associations :account, :properties                   # render these when included
      end
    end

Like strong parameters, a Schema is explicit: only the attributes and
associations it declares are rendered or described, so a column or association
added later stays hidden until it's listed. Types, defaults and validations of
a declared attribute still come from the model.

`remove` takes back a declaration, such as one inherited from a parent Schema.

Every model that's rendered or described needs a Schema, including one only
rendered as an include, or `StandardAPI::MissingSchema` is raised, so nothing is
exposed that no one chose to. A model with no controller of its own declares
its Schema by name, `ToolCallSchema` for `ToolCall`:

    class ToolCallSchema < StandardAPI::Schema
      attributes :id, :name, :arguments
    end

A custom partial that doesn't use `record_schema` isn't checked.

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

Declarations are inherited, so `class Schema < BaseSchema` works, and a Schema's
private methods stay on the Schema rather than the controller.

The Schema runs on one instance per model for the length of a request. A method
it doesn't define goes to its `controller`, private ones and ACL methods
included, so `params` and `admin?` just work. The Schema's own methods win, so
`attributes`, `model` and `schemas` are its own; call `controller.model` for the
controller's. Don't call `record_schema` from a condition, as
they call back into the Schema.

Every controller describes and renders a Photo with the same Schema, including
as an include of a property, so two controllers of one model with a Schema
raise `StandardAPI::InvalidConfiguration`, as does a nested `Schema` that isn't
a `StandardAPI::Schema`.

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
record of the model. For `record_schema(Photo)` and the JSON Schemas, `record` is
`nil`, so decide what that means: `if: -> { record&.public? }` hides the attribute
from them, while `unless: -> { record&.private? }` shows it. Hidden and
undeclared attributes aren't rendered or named in validation errors, and
fragments that include the model of a Schema that could vary by requester
aren't cached.

Hiding an attribute controls what the API shows, not what it permits: its ACL
still decides whether it can be written, and filtered or ordered by, which can
reveal its value.

###### Associations

What a request may include is what the Schema declares with `association` or
`associations`, an association or a method rendered as an include. Including
anything else is rejected with a 400. What's included of an included record is
checked against what its own Schema declares, or the `schema` the association
gives in its place, at every level below it:

    class PhotoSchema < StandardAPI::Schema
      associations :author, :camera        # include[author][photos] if AuthorSchema declares photos
    end

An association only renders when the `include` param asks for it, on `#create`
and `#update` too.

Declarations are checked for the model, with a `nil` record: `if` and `unless`
don't stop an association from being asked for, only from rendering, and one
declared in an `attributes_for` block can be asked for when it's declared for
the key a `nil` record gives.

Under a polymorphic association or a method there's no single model to check
what's included of it against. It's checked against the `schema` the
association gives, if it gives a Schema class, or else its `includes`:

    association :subject, includes: [:landlord, { photos: [:camera] }]

`if` and `unless` hide an association per record, as they do an attribute:

    association :comments, unless: -> { record&.locked? }

The included records render with their own model's Schema, found from the
association (or, for a polymorphic one, from each record's class), unless
`schema` gives one to render them with in its place:

    class NameSchema < StandardAPI::Schema
      attributes :id, :name
    end

    association :account, schema: NameSchema
    association :subject, schema: NameSchema                     # any model with an id and name
    association :owner, schema: -> { NameSchema if redacted?(record) }

It decides everything about the included records, their associations and
values too: `NameSchema` declares no associations, so nothing can be included
through `account`. Given a method name or Proc, it runs like a condition, on
the record including them, and returns a Schema, or `nil` to render them with
their own.

**It replaces their own Schema, so nothing their own Schema hides is hidden
unless it declares so too.** To start from what their own Schema renders, and
hide more, inherit from it:

    class AccountWithoutEmailSchema < AccountSchema
      remove :email
    end

The Schema is passed to the included records' partial as the `schema` local,
and `record_schema(record, local_assigns[:schema])` renders with it, so a custom
partial that calls it does too.

`varies_by_requester?` is true for a Schema with `if`, `unless`, `value` or
`attributes_for`, or an association whose `schema` is a method name, a Proc, or
a Schema that varies. Override it when a Schema doesn't vary, so fragments can
be cached.

A Schema's definitions come only from its declarations. Defining `schemas` on
a Schema raises `StandardAPI::InvalidConfiguration`, because an override could
render what `hidden_attributes` doesn't exclude. For a value that differs by
record, key it with `attributes_for`:

    attributes_for(-> { record&.title }) { |title| attribute :caption, comment: title }

`record_schema(Photo).attributes` returns the result, and `schema.json` and the
JSON Schemas (see [Schema Discovery](#schema-discovery)) are built from it.
Records are rendered from it too: `application/_record` renders the attributes
in `record_schema(record).attributes`. `record_schema` is available in
controllers and views, so other code (an MCP tool describing your models, for
instance) can read the same definitions without rendering a schema view and
parsing it back.

Before the Schema sees them, there is one definition per entry in
`model.attribute_names`, or, given a record, in `record.attribute_names`: the
attributes its query selected. A record loaded with `select(:id)` has only
`id`, and one loaded with `select('*, 1 AS rank')` also has `rank`, with a
`nil` type since the model doesn't have it. Records of a model with the same
attributes share their definitions before the Schema sees them.

    record_schema(Property).attributes.find { |s| s[:name] == 'name' }
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
| `read_only`      | Not in the ACL's `attributes`, or readonly on the model (`attr_readonly`)                                   |
| `required`       | NOT NULL and writable on create (permitted by the ACL, not auto populated), or validated for presence or acceptance without `allow_nil`. An `attr_readonly` attribute can be set on create, so it can be both `read_only` and `required` |
| `validations`    | `[{ kind: :length, options: { maximum: 12 } }, ...]`                                                        |

An attribute the model declares without a column (`attribute :nickname,
:string` in the model) has `nil` for `default`, `null`, `comment` and
`auto_populated`. The ACL's `attributes` is called without a record
(`attributes(nil)`), so `read_only` is the answer for the model as a whole.

A Schema `attribute` adding one the model doesn't have starts from
`StandardAPI::Schema::Builder::DEFAULTS`: `null` and `read_only` are `true`,
`auto_populated` is `false`.

For an STI subclass, ie. `Pdf < Document`, without an ACL or Schema of its
own, the base class's `attributes` and Schema are used
(`document_attributes`, `DocumentSchema`), as they are for `orders` and
`wheres`.

`schema.json` lists the same attributes as `record_schema(model).attributes`, with the same
`readonly`. A column's `type` still comes from its SQL type unless
a Schema declares another, so it reports `datetime` for date and time columns,
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
(2020-12) built from its ACL and Schema, so a client (an MCP tool, for
instance) can learn what it may send and what it will get back:

```
GET /records/schema/read.json   a record as #show and #index render it
GET /records/schema/write.json  params #create and #update accept
GET /records/schema/query.json  params #index and #calculate accept
```

Each route is only drawn with the actions it describes: `read_schema` with
`show` or `index`, `write_schema` with `create` or `update`, and
`query_schema` with `index` or `calculate`. Attributes are described from
their definitions in `record_schema(model).attributes` (see [Schemas](#schemas)), so only
what the model's Schema declares is described, with the `record` its
conditions see being `nil`.

- **`schema/read.json`** describes every definition as rendered (decimals as
  strings, binary columns as hex), and the associations in the `include`
  param, which is checked against the Schemas as on `#index`. A
  singular association allows `null` unless its presence is validated.
  Columns and includes are `required`; other attributes aren't, since a
  partial `select` can leave them out. When a Schema condition could hide
  something from a record, what it hides is still
  described and nothing is `required`. A model with a custom partial is
  described as any object.
- **`schema/write.json`** describes `{ "record": { ... } }` with only the
  attributes the ACL's `attributes(nil)` permit, with their validations, and
  the associations its `nested` permits (by attributes, `_ids` and foreign
  key). One the ACL permits but the Schema doesn't declare is `{}`.
  `required` lists the definitions' `required`, for a create; an update may
  send any of the properties. A `read_only` definition is `readOnly`: an
  `attr_readonly` attribute, which can be set on create but not changed, or
  one the Schema declares read only. A model with an ACL `filter` is
  described as any object.
- **`schema/query.json`** describes `where` and `order` as the ACL's `wheres`
  and `orders` permit them, and `include` as the Schemas declare it, following
  associations into the associated models' ACLs and Schemas through `$defs`, plus `limit`, `offset`,
  `distinct` and `group_by`. Columns to `group_by` and associations to `join`
  aren't listed by name, as not all of them need be exposed. An include's `where` and
  `order` are those the included model's ACL permits. A column permitted with
  any operator lists the operators that apply to its type. An include's `when`
  lists the attributes of the model it's on that its ACL `wheres` permit an
  `eq` on. It also describes the params no ACL checks yet, as they're used,
  with a description ending "Not checked by the ACL.": `distinct_on`, `join`,
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
`record_schema`. Called on a controller handling a request, they give what the
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

        # Allowed params
        def photo_params
          [:id, :file, :caption]
        end
  
        # Allowed orderings
        def photo_orders
          [:id, :created_at, :updated_at, :caption]
        end

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


