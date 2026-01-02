# frozen_string_literal: true

module EagerEye
  module Detectors
    class CustomMethodQuery < Base
      QUERY_METHODS = %i[where find_by find_by! exists? find first last take pluck ids count sum average minimum
                         maximum].freeze
      ARRAY_METHODS = %i[first last take].freeze
      ITERATION_METHODS = %i[each map select find_all reject collect detect find_index flat_map].freeze

      def self.detector_name
        :custom_method_query
      end

      def detect(ast, file_path)
        return [] unless ast

        @issues = []
        @file_path = file_path

        find_iteration_blocks(ast) do |block_body, block_var, collection|
          is_array_collection = collection_is_array?(collection)
          check_block_for_query_methods(block_body, block_var, is_array_collection)
        end

        @issues
      end

      private

      def find_iteration_blocks(node, &block)
        return unless node.is_a?(Parser::AST::Node)

        if iteration_block?(node)
          block_var = extract_block_variable(node)
          block_body = node.children[2]
          yield(block_body, block_var, node.children[0]) if block_var && block_body
        end
        node.children.each { |child| find_iteration_blocks(child, &block) }
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
        return false if is_array_collection && ARRAY_METHODS.include?(method_name) &&
                        receiver_is_only_block_var?(node.children[0], block_var)

        receiver_chain_starts_with?(node.children[0], block_var)
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

      def collection_is_array?(node)
        return false unless node.is_a?(Parser::AST::Node)

        case node.type
        when :array then true
        when :send then %i[map select collect flat_map to_a uniq compact].include?(node.children[1])
        else false
        end
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
