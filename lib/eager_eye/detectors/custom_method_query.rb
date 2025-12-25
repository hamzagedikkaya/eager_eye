# frozen_string_literal: true

module EagerEye
  module Detectors
    class CustomMethodQuery < Base
      QUERY_METHODS = %i[
        where
        find_by
        find_by!
        exists?
        find
        first
        last
        take
        pluck
        ids
        count
        sum
        average
        minimum
        maximum
      ].freeze

      # Array-only methods that should not be flagged when collection is clearly an array
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
          block_body = extract_block_body(node)
          collection = extract_collection(node)
          yield(block_body, block_var, collection) if block_var && block_body
        end

        node.children.each do |child|
          find_iteration_blocks(child, &block)
        end
      end

      def iteration_block?(node)
        return false unless node.type == :block

        send_node = node.children[0]
        return false unless send_node&.type == :send

        method_name = send_node.children[1]
        ITERATION_METHODS.include?(method_name)
      end

      def check_block_for_query_methods(node, block_var, is_array_collection = false) # rubocop:disable Style/OptionalBooleanParameter
        return unless node.is_a?(Parser::AST::Node)

        add_issue(node) if query_chain_on_association?(node, block_var, is_array_collection)

        node.children.each do |child|
          check_block_for_query_methods(child, block_var, is_array_collection)
        end
      end

      def query_chain_on_association?(node, block_var, is_array_collection = false) # rubocop:disable Style/OptionalBooleanParameter
        return false unless node.type == :send

        method_name = node.children[1]
        return false unless QUERY_METHODS.include?(method_name)

        # Skip array-only methods when collection is clearly an array (.map result)
        # AND the receiver is only the block variable (not chained)
        if is_array_collection && ARRAY_METHODS.include?(method_name) &&
           receiver_is_only_block_var?(node.children[0], block_var)
          return false
        end

        receiver = node.children[0]
        receiver_chain_starts_with?(receiver, block_var)
      end

      def receiver_is_only_block_var?(node, block_var)
        # Returns true only if receiver is EXACTLY the block variable, not a chain
        node.is_a?(Parser::AST::Node) &&
          node.type == :lvar &&
          node.children[0] == block_var
      end

      def receiver_chain_starts_with?(node, block_var)
        return false unless node.is_a?(Parser::AST::Node)

        case node.type
        when :lvar
          node.children[0] == block_var
        when :send
          receiver_chain_starts_with?(node.children[0], block_var)
        else
          false
        end
      end

      def extract_block_variable(block_node)
        args_node = block_node.children[1]
        return nil unless args_node&.type == :args

        first_arg = args_node.children[0]
        return nil unless first_arg&.type == :arg

        first_arg.children[0]
      end

      def extract_block_body(block_node)
        block_node.children[2]
      end

      def extract_collection(block_node)
        # Extract the collection being iterated on
        # For: collection.each { |item| ... }
        # Returns: the send node representing the collection method call
        block_node.children[0]
      end

      def collection_is_array?(collection_node)
        return false unless collection_node.is_a?(Parser::AST::Node)

        case collection_node.type
        when :array
          # Literal array: [1, 2, 3].each { |item| ... }
          true
        when :send
          # Only consider these methods as definitely returning arrays when iterating
          method_name = collection_node.children[1]
          # map, select, collect, etc. on anything return arrays for iteration
          %i[map select collect flat_map to_a uniq compact].include?(method_name)
        else
          # Block variable itself won't tell us if it's an array
          false
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
        when :lvar
          node.children[0].to_s
        when :send
          receiver_str = reconstruct_chain(node.children[0])
          method = node.children[1]
          receiver_str.empty? ? method.to_s : "#{receiver_str}.#{method}"
        else
          ""
        end
      end
    end
  end
end
