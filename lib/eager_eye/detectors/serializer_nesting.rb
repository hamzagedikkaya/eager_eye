# frozen_string_literal: true

require_relative "concerns/class_inspector"

module EagerEye
  module Detectors
    class SerializerNesting < Base
      include Concerns::ClassInspector

      SERIALIZER_PATTERNS = %w[ActiveModel::Serializer ActiveModelSerializers::Model Blueprinter::Base Alba::Resource].freeze
      ATTRIBUTE_METHODS = %i[attribute field attributes].freeze
      OBJECT_REFS = %i[object record resource].freeze

      def self.detector_name
        :serializer_nesting
      end

      def detect(ast, file_path, association_names = Set.new, method_queries = {}, serializer_usage = nil, # rubocop:disable Metrics/ParameterLists
                 all_columns = Set.new)
        return [] unless ast

        @dynamic_associations = association_names
        @method_queries = method_queries
        @serializer_usage = serializer_usage
        @all_columns = all_columns
        issues = []
        traverse_ast(ast) do |node|
          next unless node.type == :class && serializer_class?(node)

          find_nested_associations(node, file_path, issues)
        end
        issues
      end

      private

      def serializer_class?(node)
        class_name = extract_class_name(node)
        return false unless class_name

        class_name.end_with?("Serializer", "Blueprint", "Resource") ||
          inherits_from_serializer?(node) || includes_serializer_module?(node)
      end

      def inherits_from_serializer?(class_node)
        parent_node = class_node.children[1]
        return false unless parent_node

        parent_name = const_to_string(parent_node)
        SERIALIZER_PATTERNS.any? { |p| parent_name&.include?(p.split("::").last) }
      end

      def includes_serializer_module?(class_node)
        body = class_node.children[2]
        return false unless body

        traverse_ast(body) do |node|
          return true if node.type == :send && node.children[1] == :include && alba_resource?(node)
        end
        false
      end

      def alba_resource?(include_node)
        arg = include_node.children[2]
        arg && const_to_string(arg)&.include?("Alba")
      end

      def find_nested_associations(class_node, file_path, issues)
        body = class_node.children[2]
        return unless body

        serializer = extract_class_name(class_node)
        walk_with_view(body, nil) do |attr_block, view|
          find_association_in_block(attr_block.children[2], file_path, issues, serializer, view)
        end
      end

      # Walk the class body, tracking the enclosing Blueprinter `view :name do ...
      # end` so each attribute block is tagged with the view it belongs to (nil =
      # a base/default field rendered by every view). Yields attribute blocks.
      def walk_with_view(node, view, &block) # rubocop:disable Metrics/CyclomaticComplexity,Metrics/PerceivedComplexity
        return unless node.is_a?(Parser::AST::Node)

        if view_block?(node)
          inner_view = node.children[0].children[2]&.children&.first
          node.children[2..].each { |c| walk_with_view(c, inner_view, &block) }
          return
        end

        yield(node, view) if attribute_block?(node) && node.children[2]

        node.children.each { |c| walk_with_view(c, view, &block) }
      end

      def view_block?(node)
        node.type == :block && node.children[0]&.type == :send &&
          node.children[0].children[1] == :view &&
          node.children[0].children[2]&.type == :sym
      end

      def attribute_block?(node)
        node.type == :block && node.children[0]&.type == :send &&
          ATTRIBUTE_METHODS.include?(node.children[0].children[1])
      end

      def find_association_in_block(block_body, file_path, issues, serializer, view)
        storage_lines = collect_active_storage_lines(block_body)

        traverse_ast(block_body) do |node|
          next unless node.type == :send
          next if storage_lines.include?(node.loc.line)

          receiver = node.children[0]
          method_name = node.children[1]
          next unless object_reference?(receiver)
          next if suppressed?(serializer, view, method_name)

          if likely_association?(method_name)
            issues << create_issue(
              file_path: file_path,
              line_number: node.loc.line,
              message: "Nested association `#{receiver_name(receiver)}.#{method_name}` in serializer attribute",
              suggestion: "Eager load :#{method_name} in controller or use association serializer"
            )
          elsif model_query_method?(method_name)
            issues << create_issue(
              file_path: file_path,
              line_number: node.loc.line,
              message: "Model method `#{receiver_name(receiver)}.#{method_name}` contains a query in serializer",
              suggestion: "This method executes a query per serialized object. Preload or cache the data."
            )
          end
        end
      end

      # Stay silent when the access is provably safe:
      #   * the name is a plain DB column (not a declared association anywhere), or
      #   * the render-site index shows that everywhere this serializer/view is
      #     rendered the association is eager-loaded or only single records are
      #     passed (so there is no collection to multiply into an N+1).
      def suppressed?(serializer, view, method_name)
        return true if column_not_association?(method_name)
        return false unless @serializer_usage&.known_serializer?(serializer)

        @serializer_usage.safe_access?(serializer, view, method_name)
      end

      def column_not_association?(method_name)
        @all_columns&.include?(method_name) && !@dynamic_associations&.include?(method_name)
      end

      def object_reference?(node)
        return false unless node

        case node.type
        when :send then node.children[0].nil? && OBJECT_REFS.include?(node.children[1])
        when :lvar then true
        else false
        end
      end

      def receiver_name(node)
        case node.type
        when :send then node.children[1].to_s
        when :lvar then node.children[0].to_s
        else "object"
        end
      end

      def model_query_method?(method_name)
        @method_queries&.any? { |_model, methods| methods.include?(method_name) }
      end
    end
  end
end
