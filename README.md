# StandardAPI

StandardAPI makes it easy to expose a [REST](https://en.wikipedia.org/wiki/Representational_state_transfer)
interface to your Rails models.

# Installation

    gem install standardapi

In your `Gemfile`:

    gem 'standardapi', require: 'standard_api'

Optionally in `config/application.rb`:

    module MyApplication
      class Application < Rails::Application
        # Initialize configuration defaults for originally generated Rails version.
        config.load_defaults 6.0

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
      
      # Allowed sortings
      # The sorting is whitelisted as well, you will mostly likely want to
      # ensure indexes have been created on these columns. In this example the
      # response can be sorted by any permutation of `id`, `created_at`, and
      # `updated_at`.
      def photo_sorts
        [:id, :created_at, :updated_at]
      end
      
      # Allowed includes
      # Similarly, the includes (including of relationships in the reponse) are
      # whitelisted. Note how includes can also support nested includes. In this
      # case when including the author, the photos that the author took can also
      # be included.
      def photo_includes
        { author: [:photos] }
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
      def attributes
        [ :caption ]
      end
      
      # Allowed saving / creating nested attributes
      def nested
        [ :camera ]
      end
      
      # Allowed sorts
      def sorts
        [ :id, :created_at, :updated_at ]
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
for StandardAPI to determine allowed attributes, nested attributes, sorts and
includes.

`includes` now returns a shallow Array, StandardAPI can how determine including
an `author` and the author's `photos` is allowed by looking at what includes are
allowed on photo and author.

The `nested` function tells StandardAPI what relations on `Photo` are allowed to
be set with the API and will determine what attributes are allowed by looking
for a `camera_acl` file.

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

All resource end points can be filtered, sorted, limited, offset, and have includes. All options are passed via query string in a nested URI encoded format.

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
    sort: {
        created_at: 'desc'
    }
}
// should be
'limit=5&offset=0&where%5Bregion_ids%5D%5Bcontains%5D=20106&include%5Bproperty%5D%5Baddresses%5D=true&include%5Bphotos%5D=true&sort%5Bcreated_at%5D=desc'
```
### Include Options
Preload some relationships and have it delivered with each record in the resource.

### Where Options
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
  
        # Allowed sortings
        def photo_sorts
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
| `/models?sort[id]=asc` | `{ "sort": { "id": "asc" } }` | `SELECT * FROM models ORDER BY models.id ASC` | `[{ id: 1 }, { id: 2 }]` |
| `/models?sort[id]=desc` | `{ "sort": { "id": "desc" } }` | `SELECT * FROM models ORDER BY models.id DESC` | `[{ id: 2 }, { id: 1 }]` |
| `/models?sort[id][asc]=nulls_first` | `{ "sort": { "id": { "asc": "nulls_first" } } }` | `SELECT * FROM models ORDER BY models.id ASC NULLS FIRST` | `[{ id: null }, { id: 1 }]` |
| `/models?sort[id][asc]=nulls_last` | `{ "sort": { "id": { "asc": "nulls_last" } } }` | `SELECT * FROM models ORDER BY models.id ASC NULLS FIRST` | `[{ id: 1 }, { id: null }]` |
| `/models?where[id]=1` | `{ where: { id: 1 } }` | `SELECT * FROM models WHERE id = 1` | `[{ id: 1 }]` |
| `/models?where[id][]=1&where[id][]=2` | `{ where: { id: [1,2] } }` | `SELECT * FROM models WHERE id IN (1, 2)` | `[{ id: 1 }, { id: 2 }]` |



