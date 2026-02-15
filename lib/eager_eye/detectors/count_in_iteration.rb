# frozen_string_literal: true

module EagerEye
  module Detectors
    class CountInIteration < Base
      COUNT_METHODS = %i[count].freeze
      ITERATION_METHODS = %i[each map select find_all reject collect each_with_index each_with_object flat_map
                             find_each find_in_batches in_batches].freeze

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
          association_call_on_block_var?(node.children[0], block_var)
      end

      def association_call_on_block_var?(node, block_var)
        return false unless node.is_a?(Parser::AST::Node) && node.type == :send

        receiver = node.children[0]
        return false unless receiver.is_a?(Parser::AST::Node)

        return true if receiver.type == :lvar && receiver.children[0] == block_var

        receiver.type == :send && chain_starts_with_block_var?(receiver, block_var)
      end

      def chain_starts_with_block_var?(node, block_var)
        return false unless node.is_a?(Parser::AST::Node)

        case node.type
        when :lvar then node.children[0] == block_var
        when :send then chain_starts_with_block_var?(node.children[0], block_var)
        else false
        end
      end

      def extract_block_variable(block_node)
        args_node = block_node.children[1]
        return nil unless args_node&.type == :args

        first_arg = args_node.children[0]
        first_arg&.type == :arg ? first_arg.children[0] : nil
      end

      def add_issue(node)
        receiver_chain = reconstruct_chain(node.children[0])

        @issues << create_issue(
          file_path: @file_path,
          line_number: node.loc.line,
          message: "`.count` called on `#{receiver_chain}` inside iteration always executes a COUNT query",
          suggestion: "Use `.size` instead (uses loaded collection) or add `counter_cache: true`"
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
