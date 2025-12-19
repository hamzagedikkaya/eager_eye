# frozen_string_literal: true

module EagerEye
  module Detectors
    class CallbackQuery < Base
      CALLBACK_METHODS = %i[
        before_validation after_validation
        before_save after_save around_save
        before_create after_create around_create
        before_update after_update around_update
        before_destroy after_destroy around_destroy
        after_commit after_rollback
        after_create_commit after_update_commit after_destroy_commit
        after_save_commit
      ].freeze

      QUERY_INDICATORS = %i[
        where find find_by find_by! first last take
        exists? any? none? many? one?
        count sum average minimum maximum
        pluck ids select
        update update_all update! update_attribute update_column update_columns
        destroy destroy_all destroy! delete delete_all
        create create! save save! insert insert_all insert! upsert upsert_all
        increment! decrement! toggle!
        reload
      ].freeze

      ITERATION_METHODS = %i[each map select find_all reject collect].freeze

      def self.detector_name
        :callback_query
      end

      def detect(ast, file_path)
        @issues = []
        @file_path = file_path
        @callback_methods = {}

        return @issues unless ast

        find_callback_definitions(ast)
        check_callback_methods(ast)

        @issues
      end

      private

      def find_callback_definitions(node)
        return unless node.is_a?(Parser::AST::Node)

        extract_callback_method_name(node) if callback_definition?(node)

        node.children.each do |child|
          find_callback_definitions(child)
        end
      end

      def callback_definition?(node)
        return false unless node.type == :send
        return false unless node.children[0].nil?

        method_name = node.children[1]
        CALLBACK_METHODS.include?(method_name)
      end

      def extract_callback_method_name(node)
        node.children[2..].each do |arg|
          next unless arg.is_a?(Parser::AST::Node) && arg.type == :sym

          method_name = arg.children[0]
          callback_type = node.children[1]
          @callback_methods[method_name] = callback_type
        end
      end

      def check_callback_methods(node)
        return unless node.is_a?(Parser::AST::Node)

        if method_definition?(node)
          method_name = node.children[0]
          if @callback_methods.key?(method_name)
            callback_type = @callback_methods[method_name]
            check_method_body_for_queries(node, method_name, callback_type)
          end
        end

        node.children.each do |child|
          check_callback_methods(child)
        end
      end

      def method_definition?(node)
        node.type == :def
      end

      def check_method_body_for_queries(method_node, method_name, callback_type)
        method_body = method_node.children[2]
        return unless method_body

        find_iterations_with_queries(method_body, method_name, callback_type)
      end

      def find_iterations_with_queries(node, method_name, callback_type)
        return unless node.is_a?(Parser::AST::Node)

        if iteration_block?(node)
          add_iteration_issue(node, method_name, callback_type)
          find_query_calls_in_block(node, method_name, callback_type)
        end

        node.children.each do |child|
          find_iterations_with_queries(child, method_name, callback_type)
        end
      end

      def find_query_calls_in_block(node, method_name, callback_type)
        return unless node.is_a?(Parser::AST::Node)

        add_query_issue(node, method_name, callback_type) if query_call?(node)

        node.children.each do |child|
          find_query_calls_in_block(child, method_name, callback_type)
        end
      end

      def query_call?(node)
        return false unless node.type == :send

        method = node.children[1]
        QUERY_INDICATORS.include?(method)
      end

      def iteration_block?(node)
        return false unless node.type == :block

        send_node = node.children[0]
        return false unless send_node&.type == :send

        method_name = send_node.children[1]
        ITERATION_METHODS.include?(method_name)
      end

      def add_query_issue(node, method_name, callback_type)
        query_method = node.children[1]

        @issues << create_issue(
          file_path: @file_path,
          line_number: node.loc.line,
          message: "Query method `.#{query_method}` found in `#{callback_type}` callback `:#{method_name}`",
          severity: :warning,
          suggestion: "Callbacks run on every save/create/update. Consider moving to a background job"
        )
      end

      def add_iteration_issue(node, method_name, callback_type)
        @issues << create_issue(
          file_path: @file_path,
          line_number: node.loc.line,
          message: "Iteration found in `#{callback_type}` callback `:#{method_name}` - potential N+1",
          severity: :error,
          suggestion: "Avoid iterations in callbacks. Use background jobs for bulk operations"
        )
      end
    end
  end
end
