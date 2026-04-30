# frozen_string_literal: true

require_relative "concerns/variable_model_inference"

module EagerEye
  module Detectors
    class CustomMethodQuery < Base
      include Concerns::VariableModelInference

      QUERY_METHODS = %i[where find_by find_by! exists? find first last take pluck ids count sum average minimum
                         maximum].freeze
      SAFE_QUERY_METHODS = %i[first last take count sum find size length ids].freeze
      SAFE_TRANSFORM_METHODS = %i[keys values split [] params sort pluck ids to_s to_a to_i chars bytes].freeze
      ARRAY_COLUMN_SUFFIXES = %w[_ids _tags _types _codes _names _values _arr].freeze
      ITERATION_METHODS = %i[each map select find_all reject collect detect find_index flat_map
                             each_with_index each_with_object reduce inject
                             find_each find_in_batches in_batches array!].freeze

      def self.detector_name
        :custom_method_query
      end

      def detect(ast, file_path, method_queries = {}, associations_by_model = {})
        return [] unless ast

        @issues = []
        @file_path = file_path
        @method_queries = method_queries
        @associations_by_model = associations_by_model
        @variable_models = {}

        find_iteration_blocks(ast) do |block_body, block_var, collection, definitions|
          model_name = infer_model_from_value(collection)
          check_block_for_query_methods(block_body, block_var, collection_is_array?(collection, definitions))
          check_block_for_model_query_methods(block_body, block_var, model_name)
        end

        @issues
      end

      private

      def find_iteration_blocks(node, definitions = {}, &block)
        return unless node.is_a?(Parser::AST::Node)

        record_definition(node, definitions)

        if iteration_block?(node)
          block_var = extract_iteration_variable(node)
          block_body = node.children[2]
          yield(block_body, block_var, node.children[0], definitions) if block_var && block_body
        end
        node.children.each { |child| find_iteration_blocks(child, definitions, &block) }
      end

      def record_definition(node, definitions)
        case node.type
        when :lvasgn then record_simple_definition(node, :lvar, definitions)
        when :ivasgn then record_simple_definition(node, :ivar, nil)
        when :masgn  then record_multi_definition(node, definitions)
        end
      end

      def record_simple_definition(node, var_type, definitions)
        name = node.children[0]
        value = node.children[1]
        return unless name && value

        definitions[name] = value if definitions
        model = infer_model_from_value(value)
        @variable_models[[var_type, name]] = model if model
      end

      def record_multi_definition(node, definitions)
        mlhs, rhs = node.children
        return unless mlhs && rhs

        model = infer_model_from_value(rhs)
        mlhs.children.each { |target| record_multi_target(target, rhs, model, definitions) }
      end

      def record_multi_target(target, rhs, model, definitions)
        return unless %i[lvasgn ivasgn].include?(target&.type)

        tname = target.children[0]
        return if PAGINATION_META_NAMES.include?(tname)

        var_type = target.type == :lvasgn ? :lvar : :ivar
        @variable_models[[var_type, tname]] = model if model
        definitions[tname] = rhs if target.type == :lvasgn
      end

      def iteration_block?(node)
        node.type == :block && node.children[0]&.type == :send &&
          ITERATION_METHODS.include?(node.children[0].children[1])
      end

      def check_block_for_query_methods(node, block_var, is_array_collection = false) # rubocop:disable Style/OptionalBooleanParameter
        return unless node.is_a?(Parser::AST::Node)

        add_issue(node) if query_chain_on_association?(node, block_var, is_array_collection)
        node.children.each { |child| check_block_for_query_methods(child, block_var, is_array_collection) }
      end

      def query_chain_on_association?(node, block_var, is_array_collection = false) # rubocop:disable Style/OptionalBooleanParameter
        return false unless node.type == :send

        method_name = node.children[1]
        return false unless QUERY_METHODS.include?(method_name)
        return false if skip_array_method?(node, block_var, is_array_collection)
        return false if receiver_is_query_chain?(node.children[0])

        receiver_chain_starts_with?(node.children[0], block_var)
      end

      def skip_array_method?(node, block_var, is_array_collection)
        return true if receiver_ends_with_safe_transform_method?(node.children[0])

        SAFE_QUERY_METHODS.include?(node.children[1]) &&
          is_array_collection && direct_block_var?(node.children[0], block_var)
      end

      def direct_block_var?(node, block_var)
        node.is_a?(Parser::AST::Node) && node.type == :lvar && node.children[0] == block_var
      end

      def collection_is_array?(node, definitions = {}, visited = Set.new)
        return false unless node.is_a?(Parser::AST::Node)
        return false unless visited.add?(node.object_id)

        return true if %i[array hash].include?(node.type)

        case node.type
        when :lvar
          defn = definitions[node.children[0]]
          defn && collection_is_array?(defn, definitions, visited)
        when :send then send_returns_array?(node, definitions, visited)
        else false
        end
      end

      def send_returns_array?(node, definitions, visited)
        method_name = node.children[1]
        return true if %i[map select collect flat_map uniq compact].include?(method_name)
        return true if SAFE_TRANSFORM_METHODS.include?(method_name)

        collection_is_array?(node.children[0], definitions, visited)
      end

      def receiver_ends_with_safe_transform_method?(node)
        return false unless node.is_a?(Parser::AST::Node) && node.type == :send

        method_name = node.children[1]
        SAFE_TRANSFORM_METHODS.include?(method_name) ||
          ARRAY_COLUMN_SUFFIXES.any? { |suffix| method_name.to_s.end_with?(suffix) }
      end

      def receiver_is_query_chain?(node)
        node.is_a?(Parser::AST::Node) && node.type == :send && QUERY_METHODS.include?(node.children[1])
      end

      def check_block_for_model_query_methods(node, block_var, model_name)
        return unless node.is_a?(Parser::AST::Node)

        if model_query_call?(node, block_var, model_name)
          method = node.children[1]
          @issues << create_issue(
            file_path: @file_path,
            line_number: node.loc.line,
            message: "Model method `.#{method}` contains a query and is called inside iteration",
            suggestion: "This method executes a query on each iteration. Preload data or move the query outside."
          )
        end
        node.children.each { |child| check_block_for_model_query_methods(child, block_var, model_name) }
      end

      def model_query_call?(node, block_var, model_name)
        return false unless block_var_immediate_send?(node, block_var)

        method = node.children[1]
        # If we know the receiver model AND the method is one of its
        # associations, treat it as an association access — not a query method.
        return false if association_on_model?(method, model_name)

        method_defined_as_query?(method, model_name)
      end

      def block_var_immediate_send?(node, block_var)
        node.type == :send &&
          (receiver = node.children[0])&.type == :lvar &&
          receiver.children[0] == block_var
      end

      def association_on_model?(method, model_name)
        model_name && @associations_by_model&.dig(model_name)&.include?(method)
      end

      def method_defined_as_query?(method, model_name)
        return false unless @method_queries

        if model_name
          @method_queries[model_name]&.include?(method) || false
        else
          @method_queries.any? { |_model, methods| methods.include?(method) }
        end
      end

      def add_issue(node)
        chain = reconstruct_chain(node.children[0])
        @issues << create_issue(
          file_path: @file_path,
          line_number: node.loc.line,
          message: "Query method `.#{node.children[1]}` called on `#{chain}` inside iteration",
          suggestion: "This query executes on each iteration. Consider preloading data or restructuring the query."
        )
      end
    end
  end
end
