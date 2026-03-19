# frozen_string_literal: true

module EagerEye
  module Detectors
    class CountInIteration < Base
      COUNT_METHODS = %i[count].freeze
      ITERATION_METHODS = %i[each map select find_all reject collect each_with_index each_with_object flat_map
                             find_each find_in_batches in_batches array!].freeze
      ARRAY_METHOD_SUFFIXES = %w[_ids _tags _types _codes _names _values].freeze

      def self.detector_name
        :count_in_iteration
      end

      def detect(ast, file_path)
        @issues = []
        @file_path = file_path
        return @issues unless ast

        find_iteration_blocks(ast) do |block_body, block_var|
          check_for_count_calls(block_body, block_var)
        end

        @issues
      end

      private

      def find_iteration_blocks(node, &block)
        return unless node.is_a?(Parser::AST::Node)

        if iteration_block?(node)
          block_var = extract_block_variable(node)
          block_body = node.children[2]
          yield(block_body, block_var) if block_var && block_body
        end

        node.children.each { |child| find_iteration_blocks(child, &block) }
      end

      def iteration_block?(node)
        node.type == :block && node.children[0]&.type == :send &&
          ITERATION_METHODS.include?(node.children[0].children[1])
      end

      def check_for_count_calls(node, block_var)
        return unless node.is_a?(Parser::AST::Node)

        add_issue(node) if count_on_association?(node, block_var)
        node.children.each { |child| check_for_count_calls(child, block_var) }
      end

      def count_on_association?(node, block_var)
        node.type == :send && COUNT_METHODS.include?(node.children[1]) &&
          !array_returning_method?(node.children[0]) &&
          association_call_on_block_var?(node.children[0], block_var)
      end

      def array_returning_method?(node)
        return false unless node.is_a?(Parser::AST::Node) && node.type == :send

        ARRAY_METHOD_SUFFIXES.any? { |suffix| node.children[1].to_s.end_with?(suffix) }
      end

      def association_call_on_block_var?(node, block_var)
        node.is_a?(Parser::AST::Node) && node.type == :send &&
          receiver_chain_starts_with?(node.children[0], block_var)
      end

      def add_issue(node)
        chain = reconstruct_chain(node.children[0])
        @issues << create_issue(
          file_path: @file_path,
          line_number: node.loc.line,
          message: "`.count` called on `#{chain}` inside iteration always executes a COUNT query",
          suggestion: "Use `.size` instead (uses loaded collection) or add `counter_cache: true`"
        )
      end
    end
  end
end
