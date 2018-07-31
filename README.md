# StandardAPI

StandardAPI makes it easy to expost a [REST](https://en.wikipedia.org/wiki/Representational_state_transfer)
interface to your Rails models.

# Installation

    gem install standardapi

In your Gemfile:

    gem 'standardapi', require: 'standard_api'

In `config/application.rb:

    require_relative 'boot'

    require 'rails/all'
    require 'standard_api/middleware/query_encoding'

    # Require the gems listed in Gemfile, including any gems
    # you've limited to :test, :development, or :production.
    Bundler.require(*Rails.groups)

    module Tester
      class Application < Rails::Application
        # Initialize configuration defaults for originally generated Rails version.
        config.load_defaults 5.2

        # Settings in config/environments/* take precedence over those specified here.
        # Application configuration can go into files in config/initializers
        # -- all .rb files in that directory are automatically loaded after loading
        # the framework and any gems in your application.
        config.middleware.insert_after Rack::MethodOverride, StandardAPI::Middleware::QueryEncoding
      end
    end

# Usage

StandardAPI is a module that can be included into any controller to expose a API
for. Alternatly, it can be included into `ApplicationController`, giving all
inherited controllers an exposed API.

    class ApplicationController < ActiveController::Base
        include StandardAPI::Controller

    end

By default any paramaters passed to update and create are whitelisted with by
the method named after the model the controller represents. For example, the
following will only allow the `caption` attribute of the `Photo` model to be
updated.

    class PhotosController < ApplicationController
      include StandardAPI
      
      def photo_params
        [:caption]
      end
    end

If greater control of the allowed paramaters is required, the `model_params`
method can be overridden. It simply returns a set of `StrongParameters`.

    class PhotosController < ApplicationController
      include StandardAPI
      
      def model_params
        if @photo.author == current_user
          [:caption]
        else
          [:comment]
        end
      end
    end

Similarly, the ordering and includes (including of relationships in the reponse)
is whitelisted as well.

Full Example:

    class PhotosController < ApplicationController
      including StandardAPI

      # Allowed paramaters
      def photo_params
        [:caption]
      end

      # Allowed orderings
      def photo_orders
        [:id, :created_at, :updated_at]
      end

      # Allowed includes
      def photo_includes
        { author: [:photos] }
      end

    end

Note how includes can also support nested includes. So in this case when
including the author, the photos that the author took can also be included.

# Interface Specification

# Testing

##

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
        def current_mask
            { id: 1 }
        end

    end
