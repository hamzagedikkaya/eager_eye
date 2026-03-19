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

      ITERATION_METHODS = %i[each map select find_all reject collect
                             find_each find_in_batches in_batches array!].freeze
      AR_BATCH_METHODS = %i[find_each find_in_batches in_batches].freeze
      NON_AR_NAMESPACES = %w[Sidekiq Redis ActionCable ActionMailer Kafka].freeze
      TRANSACTIONAL_CALLBACKS = %i[before_validation before_save before_create before_update before_destroy
                                   around_save around_create around_update around_destroy].freeze

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
        node.children.each { |child| find_callback_definitions(child) }
      end

      def callback_definition?(node)
        node.type == :send && node.children[0].nil? && CALLBACK_METHODS.include?(node.children[1])
      end

      def extract_callback_method_name(node)
        node.children[2..].each do |arg|
          next unless arg.is_a?(Parser::AST::Node) && arg.type == :sym

          @callback_methods[arg.children[0]] = node.children[1]
        end
      end

      def check_callback_methods(node)
        return unless node.is_a?(Parser::AST::Node)

        if node.type == :def && @callback_methods.key?(node.children[0])
          body = node.children[2]
          find_iterations_with_queries(body, node.children[0], @callback_methods[node.children[0]]) if body
        end

        node.children.each { |child| check_callback_methods(child) }
      end

      def find_iterations_with_queries(node, method_name, callback_type)
        return unless node.is_a?(Parser::AST::Node)

        if iteration_block?(node)
          block_var = extract_block_variable(node)
          collection = node.children[0].children[0]
          if block_var && !non_ar_collection?(collection) && contains_ar_query_on_variable?(node, block_var)
            add_iteration_issue(node, method_name, callback_type)
            find_query_calls_in_block(node, method_name, callback_type, block_var)
          end
        end

        node.children.each { |child| find_iterations_with_queries(child, method_name, callback_type) }
      end

      def find_query_calls_in_block(node, method_name, callback_type, block_var)
        return unless node.is_a?(Parser::AST::Node)

        if query_call?(node) && receiver_chain_starts_with?(node.children[0], block_var)
          add_query_issue(node, method_name, callback_type)
        end

        node.children.each { |child| find_query_calls_in_block(child, method_name, callback_type, block_var) }
      end

      def query_call?(node)
        node.type == :send && QUERY_INDICATORS.include?(node.children[1])
      end

      def iteration_block?(node)
        return false unless node.type == :block && node.children[0]&.type == :send

        method_name = node.children[0].children[1]
        return false unless ITERATION_METHODS.include?(method_name)
        return true if AR_BATCH_METHODS.include?(method_name)

        !static_collection?(node.children[0].children[0])
      end

      def static_collection?(node)
        return true unless node.is_a?(Parser::AST::Node)

        %i[array const irange erange].include?(node.type)
      end

      def add_query_issue(node, method_name, callback_type)
        suggestion = if transactional_callback?(callback_type)
                       "Callbacks run on every save/create/update. Move the query outside the iteration or preload data"
                     else
                       "Callbacks run on every save/create/update. Consider moving to a background job"
                     end

        @issues << create_issue(
          file_path: @file_path,
          line_number: node.loc.line,
          message: "Query method `.#{node.children[1]}` found in `#{callback_type}` callback `:#{method_name}`",
          severity: :warning,
          suggestion: suggestion
        )
      end

      def add_iteration_issue(node, method_name, callback_type)
        suggestion = if transactional_callback?(callback_type)
                       "Avoid DB queries in before_*/around_* callbacks. Preload data outside the iteration instead"
                     else
                       "Avoid iterations in callbacks. Use background jobs for bulk operations"
                     end

        @issues << create_issue(
          file_path: @file_path,
          line_number: node.loc.line,
          message: "Iteration found in `#{callback_type}` callback `:#{method_name}` - potential N+1",
          severity: :error,
          suggestion: suggestion
        )
      end

      def transactional_callback?(callback_type)
        TRANSACTIONAL_CALLBACKS.include?(callback_type)
      end

      def non_ar_collection?(node)
        ns = root_namespace(node)
        ns && NON_AR_NAMESPACES.include?(ns)
      end

      def root_namespace(node)
        return nil unless node.is_a?(Parser::AST::Node)

        case node.type
        when :const then node.children[0].nil? ? node.children[1].to_s : root_namespace(node.children[0])
        when :send, :block then root_namespace(node.children[0])
        end
      end

      def contains_ar_query_on_variable?(node, block_var)
        return false unless node.is_a?(Parser::AST::Node)
        return true if query_call?(node) && receiver_chain_starts_with?(node.children[0], block_var)

        node.children.any? { |child| contains_ar_query_on_variable?(child, block_var) }
      end
    end
  end
end
