# StandardAPI

StandardAPI makes it easy to expose a query interface for your Rails models

# Installation

    gem install standardapi

In your Gemfile

    gem 'standardapi', require: 'standard_api'

StandardAPI is a module you can include into any controllers you want to have
API access to, or in the ApplicationController, giving all inherited controller
access.

    class ApplicationController < ActiveController::Base
        include StandardAPI

    end

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
