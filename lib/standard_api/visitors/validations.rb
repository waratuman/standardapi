module StandardAPI
  module Visitors

    class Validator < Arel::Visitors::Visitor

      def visit_ActiveRecord_Validations_AbsenceValidator(o, col)
        visit_validator(:absence, o.options)
      end

      def visit_ActiveRecord_Validations_AcceptanceValidator(o, col)
        visit_validator(:acceptance, o.options)
      end

      def visit_ActiveRecord_Validations_ComparisonValidator(o, col)
        visit_validator(:comparison, o.options)
      end

      def visit_ActiveRecord_Validations_ConfirmationValidator(o, col)
        visit_validator(:confirmation, o.options)
      end

      def visit_ActiveRecord_Validations_ExclusionValidator(o, col)
        visit_validator(:exclusion, o.options)
      end

      def visit_ActiveRecord_Validations_FormatValidator(o, col)
        visit_validator(:format, o.options)
      end

      def visit_ActiveRecord_Validations_InclusionValidator(o, col)
        visit_validator(:inclusion, o.options)
      end

      def visit_ActiveRecord_Validations_LengthValidator(o, col)
        visit_validator(:length, o.options)
      end

      def visit_ActiveRecord_Validations_NumericalityValidator(o, col)
        visit_validator(:numericality, o.options)
      end

      def visit_ActiveRecord_Validations_PresenceValidator(o, col)
        visit_validator(:presence, o.options)
      end

      def visit_ActiveRecord_Validations_WithValidator(o, col)
        visit_validator(:with, o.options)
      end

      def visit_ActiveModel_Validations_FormatValidator(o, col)
        visit_validator(:format, o.options)
      end
      
      def visit_ActiveModel_Validations_InclusionValidator(o, col)
        visit_validator(:inclusion, o.options)
      end

      private

      def visit_validator(name, options)
        { name => options.empty? ? true : options.as_json }
      end

      def visit(object, collector = nil)
        dispatch_method = dispatch[object.class]
        if collector
          send dispatch_method, object, collector
        else
          send dispatch_method, object
        end
      rescue NoMethodError => e
      end

    end

  end
end
