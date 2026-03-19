# frozen_string_literal: true

module EagerEye
  module Detectors
    class ScopeChainNPlusOne < Base
      ITERATION_METHODS = %i[each map select find_all reject collect detect find_index flat_map
                             find_each find_in_batches in_batches array!].freeze

      def self.detector_name
        :scope_chain_n_plus_one
      end

      def detect(ast, file_path, scope_maps = {})
        return [] unless ast

        @issues = []
        @file_path = file_path
        @all_scopes = scope_maps.each_value.reduce(Set.new, :merge)
        return [] if @all_scopes.empty?

        find_iteration_blocks(ast)
        @issues
      end

      private

      def find_iteration_blocks(node)
        return unless node.is_a?(Parser::AST::Node)

        if iteration_block?(node)
          block_var = extract_block_variable(node)
          check_block(node.children[2], block_var) if block_var
        end

        node.children.each { |child| find_iteration_blocks(child) }
      end

      def iteration_block?(node)
        node.type == :block && node.children[0]&.type == :send &&
          ITERATION_METHODS.include?(node.children[0].children[1])
      end

      def check_block(node, block_var)
        return unless node.is_a?(Parser::AST::Node)

        add_issue(node) if scope_chain_on_association?(node, block_var)
        node.children.each { |child| check_block(child, block_var) }
      end

      def scope_chain_on_association?(node, block_var)
        return false unless node.type == :send

        method_name = node.children[1]
        return false unless @all_scopes.include?(method_name)

        receiver = node.children[0]
        receiver_chain_starts_with?(receiver, block_var) && chain_depth(receiver, block_var) >= 1
      end

      def chain_depth(node, block_var)
        return 0 unless node.is_a?(Parser::AST::Node)
        return 0 if node.type == :lvar && node.children[0] == block_var

        node.type == :send ? 1 + chain_depth(node.children[0], block_var) : 0
      end

      def add_issue(node)
        chain = reconstruct_chain(node.children[0])
        @issues << create_issue(
          file_path: @file_path,
          line_number: node.loc.line,
          message: "Scope `.#{node.children[1]}` called on `#{chain}` inside iteration",
          suggestion: "Each scope call executes a new query. Consider preloading or using a joined query."
        )
      end
    end
  end
end
