# frozen_string_literal: true

module EagerEye
  module Detectors
    class CustomMethodQuery < Base
      QUERY_METHODS = %i[where find_by find_by! exists? find first last take pluck ids count sum average minimum
                         maximum].freeze
      SAFE_QUERY_METHODS = %i[first last take count sum find size length].freeze
      SAFE_TRANSFORM_METHODS = %i[keys values split [] params sort pluck ids to_s to_a to_i chars bytes].freeze
      ITERATION_METHODS = %i[each map select find_all reject collect detect find_index flat_map].freeze

      def self.detector_name
        :custom_method_query
      end

      def detect(ast, file_path)
        return [] unless ast

        @issues = []
        @file_path = file_path

        find_iteration_blocks(ast) do |block_body, block_var, collection, definitions|
          is_array_collection = collection_is_array?(collection, definitions)
          check_block_for_query_methods(block_body, block_var, is_array_collection)
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

        receiver_chain_starts_with?(node.children[0], block_var)
      end

      def skip_array_method?(node, block_var, is_array_collection)
        return true if receiver_ends_with_safe_transform_method?(node.children[0])

        SAFE_QUERY_METHODS.include?(node.children[1]) &&
          is_array_collection && receiver_is_only_block_var?(node.children[0], block_var)
      end

      def receiver_is_only_block_var?(node, block_var)
        node.is_a?(Parser::AST::Node) && node.type == :lvar && node.children[0] == block_var
      end

      def receiver_chain_starts_with?(node, block_var)
        return false unless node.is_a?(Parser::AST::Node)

        case node.type
        when :lvar then node.children[0] == block_var
        when :send then receiver_chain_starts_with?(node.children[0], block_var)
        else false
        end
      end

      def extract_block_variable(block_node)
        args_node = block_node.children[1]
        return nil unless args_node&.type == :args

        first_arg = args_node.children[0]
        first_arg&.type == :arg ? first_arg.children[0] : nil
      end

      def collection_is_array?(node, definitions = {})
        return false unless node.is_a?(Parser::AST::Node)
        return true if %i[array hash].include?(node.type)
        return check_lvar_collection?(node, definitions) if node.type == :lvar
        return check_send_collection?(node, definitions) if node.type == :send

        false
      end

      def check_lvar_collection?(node, definitions)
        return false unless definitions

        definition = definitions[node.children[0]]
        definition ? collection_is_array?(definition, definitions) : false
      end

      def check_send_collection?(node, definitions)
        method_name = node.children[1]
        return true if %i[map select collect flat_map uniq compact].include?(method_name)
        return true if SAFE_TRANSFORM_METHODS.include?(method_name)

        collection_is_array?(node.children[0], definitions)
      end

      def receiver_ends_with_safe_transform_method?(node)
        return false unless node.is_a?(Parser::AST::Node) && node.type == :send

        SAFE_TRANSFORM_METHODS.include?(node.children[1])
      end

      def add_issue(node)
        method_name = node.children[1]
        association_chain = reconstruct_chain(node.children[0])

        @issues << create_issue(
          file_path: @file_path,
          line_number: node.loc.line,
          message: "Query method `.#{method_name}` called on `#{association_chain}` inside iteration",
          suggestion: "This query executes on each iteration. Consider preloading data or restructuring the query."
        )
      end

      def reconstruct_chain(node)
        return "" unless node.is_a?(Parser::AST::Node)

        case node.type
        when :lvar then node.children[0].to_s
        when :send
          receiver_str = reconstruct_chain(node.children[0])
          receiver_str.empty? ? node.children[1].to_s : "#{receiver_str}.#{node.children[1]}"
        else ""
        end
      end
    end
  end
end
