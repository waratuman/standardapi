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
  - [Whitelisting Includes](#whitelisting-includes)
  - [Limits and Pagination](#limits-and-pagination)
  - [Masks (Row-Level Filtering)](#masks-row-level-filtering)
  - [Excluding Attributes from Responses](#excluding-attributes-from-responses)
- [Access Control List (ACL)](#access-control-list-acl)
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

Include `StandardAPI` in a controller and define the allowed attributes,
orders, and includes:

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
      
      # Allowed includes
      # Similarly, the includes (including of relationships in the reponse) are
      # whitelisted. Includes nested in a relationship are permitted by the
      # related model's includes. In this case when including the author, the
      # photos that the author took can also be included if the author model's
      # includes permit `:photos`. Permitting the nested includes here, ie.
      # `{ author: [:photos] }`, raises, except for a polymorphic association.
      def photo_includes
        [:author]
      end
    end

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
      # `json_schema.json` — so always guard against `nil` (or default it).
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
      
      # Allowed includes
      def includes
        [ :author ]
      end
    end

`app/controllers/acl/author_acl.rb`:

    module AuthorACL
      def includes
        [ :photos ]
      end
    end

All of these methods are optional and will be included in ApplicationController
for StandardAPI to determine allowed attributes, nested attributes, orders and
includes.

An ACL can instead be nested in the model's controller as an `ACL` module:

    class PhotosController < ApplicationController
      module ACL
        def attributes(record = nil)
          [ :caption ]
        end

        def orders
          [ :id, :created_at, :updated_at ]
        end

        def includes
          [ :author ]
        end
      end
    end

It is included in ApplicationController the same way as an
`app/controllers/acl` file, under the model's name (`photo_attributes`,
`photo_orders`, ...), so it is never included in its own controller and its
`includes`, `orders` and `excludes` don't override the controller's own.
Controllers are loaded at boot (and after each reload) so their ACLs are found
before the first request.

`includes` now returns a shallow Array, StandardAPI can how determine including
an `author` and the author's `photos` is allowed by looking at what includes are
allowed on photo and author.

The `nested` function tells StandardAPI what relations on `Photo` are allowed to
be set with the API and will determine what attributes are allowed by looking
for a `camera_acl` file.

##### Excludes and custom partials

An ACL may also define `excludes(record)`, returning the attributes and
relations to strip from the response for that record:

    module PhotoACL
      def excludes(record)
        {
          # hide an attribute
          caption: !record.public?,
          # drop a whole relation
          camera: record.anonymous?,
          # or reach into one
          account: [ :email ]
        }
      end
    end

Only `true` excludes a key. `false`, `nil` and empty collections exclude
nothing, so predicates can be assigned directly as above.

**Excludes are enforced in `application/_record` only.** If you have written a
custom partial for a model (`app/views/photos/_photo.json.jbuilder`),
StandardAPI cannot filter attributes that partial serializes itself — your
partial has to apply the excludes. Two helpers are provided:

    excluded = resolve_excludes(photo, local_assigns[:excludes])

    json.set! :caption, photo.caption unless excluded[:caption] == true

    # forward the sub-tree when nesting another record
    if includes[:account] && excluded[:account] != true
      json.partial! 'application/record', record: photo.account,
        includes: includes[:account], excludes: sub_excludes(excluded, :account)
    end

`resolve_excludes` merges the record's own ACL excludes with whatever the
parent partial passed down; `sub_excludes` returns the sub-tree to forward for
a given key. `test/standard_api/test_app/views/photos/_photo.json.jbuilder` is
a complete worked example.

Fragment caching is disabled automatically for any response an exclude rule or
a `mask_for` row mask could affect, since cache keys are built from record
timestamps and cannot distinguish one requester from another.

##### Schemas

An ACL may also define `schemas(default_schema)` to adjust how its model's
attributes are described. It receives the definitions StandardAPI builds for
the model and returns the definitions to use, so it can change, drop or add
attributes:

    module PhotoACL
      def schemas(default_schema)
        default_schema.map do |schema|
          schema[:name] == 'caption' ? schema.merge(comment: 'Shown under the photo') : schema
        end
      end
    end

Like the other ACL methods it is included in ApplicationController under the
model's name (`photo_schemas`). `schemas_for(Photo)` returns the result, and
`json_schema.json` is built from it. `schemas_for` is available in controllers
and views, so other code (an MCP tool describing your models, for instance) can
read the same definitions without rendering a schema view and parsing it back.

Before the ACL sees them, there is one definition per entry in
`model.attribute_names`:

    schemas_for(Property).find { |s| s[:name] == 'name' }
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
| `array`          | Whether the column is an array. `type` is then the type of its elements. `json_schema.json` puts `readOnly`, `default` and `description` on the array and the type and validations on its `items` |
| `comment`        | The column comment. `json_schema.json` renders it as `description`                                          |
| `auto_populated` | Whether the database fills it in. `nil` when the adapter can't tell                                         |
| `read_only`      | Not in the ACL's `attributes`, or, with no ACL `attributes`, readonly on the model                          |
| `required`       | NOT NULL and writable (not read only, not auto populated), or validated for presence or acceptance without `allow_nil` |
| `validations`    | `[{ kind: :length, options: { maximum: 12 } }, ...]`                                                        |

An attribute declared without a column (`attribute :nickname, :string`) has
`nil` for `default`, `null`, `comment` and `auto_populated`. The ACL's
`attributes` is called without a record (`attributes(nil)`), so `read_only` is
the answer for the model as a whole.

A definition the ACL's `schemas` adds must have every key above:
`json_schema.json` reads them all (use `[]` for no `validations`).

For an STI subclass, ie. `Pdf < Document`, without an ACL of its own, the base
class's `attributes` and `schemas` are used (`document_attributes`,
`document_schemas`), as they are for `orders`, `includes` and `wheres`.

`schema.json` is not built from `schemas_for`, and the ACL's `schemas` doesn't
affect it: its `type` still comes from the column's SQL type, so it reports
`datetime` for date and time columns, `hash` for JSON and `decimal` for floats.

##### Upgrading from 8.x

`Controller#excludes_for(klass)` has been replaced by `excludes(record)`, so
that ACL rules can vary by record. Move exclusion logic into the model's ACL
and accept the record:

    # Before
    excludes_for(Photo)

    # After, in PhotoACL
    def excludes(photo)
      { caption: !photo.public? }
    end

Zero-arity ACL `excludes` methods still work temporarily, but emit a
deprecation warning and should be updated to accept the record.

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

        # Allowed includes
        # You can include the author and the authors photos in the JSON response
        def photo_includes
          { :author => [:photos] }
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


