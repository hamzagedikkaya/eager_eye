# frozen_string_literal: true

module EagerEye
  module Detectors
    class CustomMethodQuery < Base
      QUERY_METHODS = %i[where find_by find_by! exists? find first last take pluck ids count sum average minimum
                         maximum].freeze
      SAFE_QUERY_METHODS = %i[first last take count sum find size length ids].freeze
      SAFE_TRANSFORM_METHODS = %i[keys values split [] params sort pluck ids to_s to_a to_i chars bytes].freeze
      ARRAY_COLUMN_SUFFIXES = %w[_ids _tags _types _codes _names _values _arr].freeze
      ITERATION_METHODS = %i[each map select find_all reject collect detect find_index flat_map
                             find_each find_in_batches in_batches].freeze

      def self.detector_name
        :custom_method_query
      end

      def detect(ast, file_path)
        return [] unless ast

        @issues = []
        @file_path = file_path

        find_iteration_blocks(ast) do |block_body, block_var, collection, definitions|
          check_block_for_query_methods(block_body, block_var, collection_is_array?(collection, definitions))
        end

        @issues
      end

      private

      def find_iteration_blocks(node, definitions = {}, &block)
        return unless node.is_a?(Parser::AST::Node)

        definitions[node.children[0]] = node.children[1] if node.type == :lvasgn

        if iteration_block?(node)
          block_var = extract_block_variable(node)
          block_body = node.children[2]
          yield(block_body, block_var, node.children[0], definitions) if block_var && block_body
        end
        node.children.each { |child| find_iteration_blocks(child, definitions, &block) }
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
