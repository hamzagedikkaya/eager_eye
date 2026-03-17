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

      def detect(ast, file_path, association_names = Set.new, method_queries = {})
        return [] unless ast

        @dynamic_associations = association_names
        @method_queries = method_queries
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

        traverse_ast(body) do |node|
          next unless attribute_block?(node) && node.children[2]

          find_association_in_block(node.children[2], file_path, issues)
        end
      end

      def attribute_block?(node)
        node.type == :block && node.children[0]&.type == :send &&
          ATTRIBUTE_METHODS.include?(node.children[0].children[1])
      end

      def find_association_in_block(block_body, file_path, issues)
        storage_lines = collect_active_storage_lines(block_body)

        traverse_ast(block_body) do |node|
          next unless node.type == :send
          next if storage_lines.include?(node.loc.line)

          receiver = node.children[0]
          method_name = node.children[1]
          next unless object_reference?(receiver)

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
