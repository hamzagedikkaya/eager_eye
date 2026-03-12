# frozen_string_literal: true

module EagerEye
  module Detectors
    class ValidationNPlusOne < Base
      ITERATION_METHODS = %i[each map select find_all reject collect detect find_index flat_map
                             find_each find_in_batches in_batches].freeze
      CREATE_METHODS = %i[create create!].freeze
      SAVE_METHODS = %i[save save!].freeze

      def self.detector_name
        :validation_n_plus_one
      end

      def detect(ast, file_path, uniqueness_models = Set.new)
        return [] unless ast

        @issues = []
        @file_path = file_path
        @uniqueness_models = uniqueness_models
        return [] if @uniqueness_models.empty?

        find_iteration_blocks(ast)
        @issues
      end

      private

      def find_iteration_blocks(node)
        return unless node.is_a?(Parser::AST::Node)

        if iteration_block?(node)
          block_body = node.children[2]
          check_block(block_body) if block_body
        end

        node.children.each { |child| find_iteration_blocks(child) }
      end

      def iteration_block?(node)
        node.type == :block && node.children[0]&.type == :send &&
          ITERATION_METHODS.include?(node.children[0].children[1])
      end

      def check_block(block_body)
        new_model_vars = {}
        collect_model_new_assignments(block_body, new_model_vars)
        scan_for_issues(block_body, new_model_vars)
      end

      def collect_model_new_assignments(node, vars)
        return unless node.is_a?(Parser::AST::Node)

        if node.type == :lvasgn && model_new_call?(node.children[1])
          model_name = const_name(node.children[1].children[0])
          vars[node.children[0]] = model_name
        end

        node.children.each { |child| collect_model_new_assignments(child, vars) }
      end

      def scan_for_issues(node, new_model_vars)
        return unless node.is_a?(Parser::AST::Node)

        if node.type == :send
          check_create_call(node)
          check_save_call(node, new_model_vars)
        end

        node.children.each { |child| scan_for_issues(child, new_model_vars) }
      end

      def check_create_call(node)
        return unless CREATE_METHODS.include?(node.children[1])

        receiver = node.children[0]
        return unless receiver&.type == :const

        model_name = const_name(receiver)
        add_issue(node, model_name, node.children[1]) if @uniqueness_models.include?(model_name)
      end

      def check_save_call(node, new_model_vars)
        return unless SAVE_METHODS.include?(node.children[1])

        receiver = node.children[0]
        return unless receiver&.type == :lvar

        model_name = new_model_vars[receiver.children[0]]
        add_issue(node, model_name, node.children[1]) if model_name
      end

      def model_new_call?(node)
        return false unless node.is_a?(Parser::AST::Node) && node.type == :send

        node.children[1] == :new && node.children[0]&.type == :const &&
          @uniqueness_models.include?(const_name(node.children[0]))
      end

      def const_name(node)
        return "" unless node.is_a?(Parser::AST::Node) && node.type == :const

        parent = node.children[0]
        name = node.children[1].to_s
        parent ? "#{const_name(parent)}::#{name}" : name
      end

      def add_issue(node, model_name, method_name)
        @issues << create_issue(
          file_path: @file_path,
          line_number: node.loc.line,
          message: "`#{model_name}.#{method_name}` inside iteration — uniqueness validation causes SELECT per record",
          suggestion: "Use `insert_all` with unique index constraints, or batch-validate before saving."
        )
      end
    end
  end
end
