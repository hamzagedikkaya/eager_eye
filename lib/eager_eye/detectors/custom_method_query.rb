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

      ITERATION_METHODS = %i[each map select find_all reject collect detect find_index flat_map].freeze

      def self.detector_name
        :custom_method_query
      end

      def detect(ast, file_path)
        return [] unless ast

        @issues = []
        @file_path = file_path

        find_iteration_blocks(ast) do |block_body, block_var|
          check_block_for_query_methods(block_body, block_var)
        end

        @issues
      end

      private

      def find_iteration_blocks(node, &block)
        return unless node.is_a?(Parser::AST::Node)

        if iteration_block?(node)
          block_var = extract_block_variable(node)
          block_body = extract_block_body(node)
          yield(block_body, block_var) if block_var && block_body
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

      def check_block_for_query_methods(node, block_var)
        return unless node.is_a?(Parser::AST::Node)

        add_issue(node) if query_chain_on_association?(node, block_var)

        node.children.each do |child|
          check_block_for_query_methods(child, block_var)
        end
      end

      def query_chain_on_association?(node, block_var)
        return false unless node.type == :send

        method_name = node.children[1]
        return false unless QUERY_METHODS.include?(method_name)

        receiver = node.children[0]
        receiver_chain_starts_with?(receiver, block_var)
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

      def add_issue(node)
        method_name = node.children[1]
        association_chain = reconstruct_chain(node.children[0])

        @issues << create_issue(
          file_path: @file_path,
          line_number: node.loc.line,
          message: "Query method `.#{method_name}` called on `#{association_chain}` inside iteration",
          severity: :warning,
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
