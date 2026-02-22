# frozen_string_literal: true

module EagerEye
  module Detectors
    class DecoratorNPlusOne < Base
      DECORATOR_PATTERNS = %w[Draper::Decorator SimpleDelegator Delegator].freeze
      OBJECT_REFS = %i[object __getobj__ source model].freeze
      ACTIVE_STORAGE_METHODS = %i[attached? attach attachment attachments blob blobs purge purge_later variant
                                  preview].freeze
      HAS_MANY_ASSOCIATIONS = %w[
        authors users owners creators admins members customers clients
        posts articles comments categories tags children companies organizations
        projects tasks items orders products accounts profiles settings
        images avatars photos attachments documents
      ].freeze

      def self.detector_name
        :decorator_n_plus_one
      end

      def detect(ast, file_path)
        return [] unless ast

        issues = []

        traverse_ast(ast) do |node|
          next unless decorator_class?(node)

          find_association_accesses(node, file_path, issues)
        end

        issues
      end

      private

      def decorator_class?(node)
        return false unless node.type == :class

        class_name = extract_class_name(node)
        return false unless class_name

        decorator_name_pattern?(class_name) || inherits_from_decorator?(node)
      end

      def decorator_name_pattern?(class_name)
        class_name.end_with?("Decorator", "Presenter", "ViewObject")
      end

      def extract_class_name(class_node)
        name_node = class_node.children[0]
        name_node.children[1].to_s if name_node&.type == :const
      end

      def inherits_from_decorator?(class_node)
        parent_node = class_node.children[1]
        return false unless parent_node

        parent_name = const_to_string(parent_node)
        DECORATOR_PATTERNS.any? { |p| parent_name&.include?(p.split("::").last) }
      end

      def const_to_string(node)
        return nil unless node&.type == :const

        parts = []
        current = node
        while current&.type == :const
          parts.unshift(current.children[1].to_s)
          current = current.children[0]
        end
        parts.join("::")
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
          next unless association_access?(node, storage_lines)

          receiver = node.children[0]
          method_name = node.children[1]
          issues << create_decorator_issue(file_path, node.loc.line, receiver, method_name)
        end
      end

      def association_access?(node, storage_lines)
        return false unless node.type == :send
        return false if storage_lines.include?(node.loc.line)

        object_reference?(node.children[0]) && likely_association?(node.children[1])
      end

      def collect_active_storage_lines(body)
        lines = Set.new
        traverse_ast(body) do |node|
          next unless node.type == :send && ACTIVE_STORAGE_METHODS.include?(node.children[1])

          lines << node.loc.line
        end
        lines
      end

      def object_reference?(node)
        return false unless node&.type == :send

        node.children[0].nil? && OBJECT_REFS.include?(node.children[1])
      end

      def likely_association?(method_name)
        HAS_MANY_ASSOCIATIONS.include?(method_name.to_s)
      end

      def create_decorator_issue(file_path, line, receiver, method_name)
        ref = receiver.children[1]
        create_issue(
          file_path: file_path,
          line_number: line,
          message: "N+1 in decorator: `#{ref}.#{method_name}` loads association on each decorated object",
          suggestion: "Eager load :#{method_name} in the controller before decorating the collection"
        )
      end
    end
  end
end
