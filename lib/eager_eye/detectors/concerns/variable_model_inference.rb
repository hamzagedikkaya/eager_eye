# frozen_string_literal: true

module EagerEye
  module Detectors
    module Concerns
      # Tracks the inferred model class behind a local/instance variable, by
      # walking AST value-nodes down to a `:const` (e.g. `User.where(...)` →
      # `"User"`). Recurses into argument lists of relation-wrapper methods
      # (pagy, paginate, ...) so that `pagy(User.includes(...))` is still
      # recognized as a User-relation.
      module VariableModelInference
        # Methods whose first positional argument is the underlying relation
        # (Pagy/Kaminari/etc.). Walking into those args lets us see through
        # the wrapper to the source query.
        RELATION_WRAPPERS = %i[pagy paginate page kaminari with_pagy].freeze

        # LHS names in `@pagy, items = pagy(query)`-style assignments that
        # should not inherit the relation's model — they hold pagination
        # metadata, not records.
        PAGINATION_META_NAMES = %i[pagy paginator meta page_info pagination].freeze

        private

        def infer_model_from_value(node, depth = 0) # rubocop:disable Metrics/CyclomaticComplexity
          return nil if depth > 10 || !node.is_a?(Parser::AST::Node)

          case node.type
          when :const then node.children[1].to_s
          when :send  then infer_model_from_send(node, depth)
          when :lvar, :ivar then variable_model_for(node)
          when :if    then infer_model_from_branches(node, depth)
          when :begin then infer_model_from_first(node.children, depth)
          end
        end

        def infer_model_from_send(node, depth)
          method = node.children[1]
          if RELATION_WRAPPERS.include?(method) && node.children[2]
            from_arg = infer_model_from_value(node.children[2], depth + 1)
            return from_arg if from_arg
          end
          infer_model_from_value(node.children[0], depth + 1)
        end

        def infer_model_from_branches(node, depth)
          infer_model_from_value(node.children[1], depth + 1) ||
            infer_model_from_value(node.children[2], depth + 1)
        end

        def infer_model_from_first(children, depth)
          children.each do |child|
            result = infer_model_from_value(child, depth + 1)
            return result if result
          end
          nil
        end

        def variable_model_for(node)
          @variable_models&.[]([node.type == :ivar ? :ivar : :lvar, node.children[0]])
        end
      end
    end
  end
end
