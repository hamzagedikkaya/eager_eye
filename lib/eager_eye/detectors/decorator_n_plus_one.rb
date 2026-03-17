# frozen_string_literal: true

require_relative "concerns/class_inspector"

module EagerEye
  module Detectors
    class DecoratorNPlusOne < Base
      include Concerns::ClassInspector

      DECORATOR_PATTERNS = %w[Draper::Decorator SimpleDelegator Delegator].freeze
      OBJECT_REFS = %i[object __getobj__ source model].freeze

      def self.detector_name
        :decorator_n_plus_one
      end

      def detect(ast, file_path, association_names = Set.new, method_queries = {})
        return [] unless ast

        @dynamic_associations = association_names
        @method_queries = method_queries
        issues = []
        traverse_ast(ast) do |node|
          next unless node.type == :class && decorator_class?(node)

          find_association_accesses(node, file_path, issues)
        end
        issues
      end

      private

      def decorator_class?(node)
        class_name = extract_class_name(node)
        return false unless class_name

        class_name.end_with?("Decorator", "Presenter", "ViewObject") || inherits_from_decorator?(node)
      end

      def inherits_from_decorator?(class_node)
        parent_node = class_node.children[1]
        return false unless parent_node

        parent_name = const_to_string(parent_node)
        DECORATOR_PATTERNS.any? { |p| parent_name&.include?(p.split("::").last) }
      end

      def find_association_accesses(class_node, file_path, issues)
        body = class_node.children[2]
        return unless body

        traverse_ast(body) do |node|
          next unless node.type == :def

          find_associations_in_method(node.children[2], file_path, issues)
        end
      end

      def find_associations_in_method(method_body, file_path, issues)
        return unless method_body

        storage_lines = collect_active_storage_lines(method_body)
        traverse_ast(method_body) do |node|
          next unless node.type == :send
          next if storage_lines.include?(node.loc.line)

          receiver = node.children[0]
          method_name = node.children[1]
          next unless object_reference?(receiver)

          ref = receiver.children[1]
          if likely_association?(method_name)
            issues << create_issue(
              file_path: file_path,
              line_number: node.loc.line,
              message: "N+1 in decorator: `#{ref}.#{method_name}` loads association on each decorated object",
              suggestion: "Eager load :#{method_name} in the controller before decorating the collection"
            )
          elsif model_query_method?(method_name)
            issues << create_issue(
              file_path: file_path,
              line_number: node.loc.line,
              message: "N+1 in decorator: `#{ref}.#{method_name}` calls a query method defined in the model",
              suggestion: "Preload the data in the controller before decorating the collection"
            )
          end
        end
      end

      def object_reference?(node)
        node&.type == :send && node.children[0].nil? && OBJECT_REFS.include?(node.children[1])
      end

      def model_query_method?(method_name)
        @method_queries&.any? { |_model, methods| methods.include?(method_name) }
      end
    end
  end
end
