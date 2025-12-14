# frozen_string_literal: true

module EagerEye
  module Detectors
    class SerializerNesting < Base
      # Serializer base classes to detect
      SERIALIZER_PATTERNS = [
        "ActiveModel::Serializer",
        "ActiveModelSerializers::Model",
        "Blueprinter::Base",
        "Alba::Resource"
      ].freeze

      # Method names that define attributes in serializers
      ATTRIBUTE_METHODS = %i[attribute field attributes].freeze

      # Object reference names in serializers
      OBJECT_REFS = %i[object record resource].freeze

      # Common association names (same as LoopAssociation)
      ASSOCIATION_NAMES = %w[
        author user owner creator admin member customer client
        post article comment category tag parent company organization
        project task item order product account profile setting
        image avatar photo attachment document
        authors users owners creators admins members customers clients
        posts articles comments categories tags children companies organizations
        projects tasks items orders products accounts profiles settings
        images avatars photos attachments documents
      ].freeze

      def self.detector_name
        :serializer_nesting
      end

      def detect(ast, file_path)
        return [] unless ast

        issues = []

        traverse_ast(ast) do |node|
          next unless serializer_class?(node)

          find_nested_associations(node, file_path, issues)
        end

        issues
      end

      private

      def serializer_class?(node)
        return false unless node.type == :class

        # Check class name ends with Serializer, Blueprint, or Resource
        class_name = extract_class_name(node)
        return false unless class_name

        class_name.end_with?("Serializer", "Blueprint", "Resource") ||
          inherits_from_serializer?(node) ||
          includes_serializer_module?(node)
      end

      def extract_class_name(class_node)
        name_node = class_node.children[0]
        return nil unless name_node
        return nil unless name_node.type == :const

        name_node.children[1].to_s
      end

      def inherits_from_serializer?(class_node)
        parent_node = class_node.children[1]
        return false unless parent_node

        parent_name = const_to_string(parent_node)
        SERIALIZER_PATTERNS.any? { |pattern| parent_name&.include?(pattern.split("::").last) }
      end

      def includes_serializer_module?(class_node)
        body = class_node.children[2]
        return false unless body

        traverse_ast(body) do |node|
          next unless node.type == :send

          method = node.children[1]
          return true if method == :include && alba_resource?(node)
        end

        false
      end

      def alba_resource?(include_node)
        arg = include_node.children[2]
        return false unless arg

        const_to_string(arg)&.include?("Alba")
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

      def find_nested_associations(class_node, file_path, issues)
        body = class_node.children[2]
        return unless body

        traverse_ast(body) do |node|
          next unless attribute_block?(node)

          block_body = node.children[2]
          next unless block_body

          find_association_in_block(block_body, node, file_path, issues)
        end
      end

      def attribute_block?(node)
        return false unless node.type == :block

        send_node = node.children[0]
        return false unless send_node&.type == :send

        method_name = send_node.children[1]
        ATTRIBUTE_METHODS.include?(method_name)
      end

      def find_association_in_block(block_body, _block_node, file_path, issues)
        traverse_ast(block_body) do |node|
          next unless node.type == :send

          receiver = node.children[0]
          method_name = node.children[1]

          next unless object_reference?(receiver)
          next unless likely_association?(method_name)

          issues << create_issue(
            file_path: file_path,
            line_number: node.loc.line,
            message: "Nested association `#{receiver_name(receiver)}.#{method_name}` in serializer attribute",
            suggestion: "Eager load :#{method_name} in controller or use association serializer"
          )
        end
      end

      def object_reference?(node)
        return false unless node

        case node.type
        when :send
          # object.something or record.something
          receiver = node.children[0]
          method = node.children[1]

          receiver.nil? && OBJECT_REFS.include?(method)
        when :lvar
          # Block variable like |post|
          true
        else
          false
        end
      end

      def receiver_name(node)
        case node.type
        when :send
          node.children[1].to_s
        when :lvar
          node.children[0].to_s
        else
          "object"
        end
      end

      def likely_association?(method_name)
        ASSOCIATION_NAMES.include?(method_name.to_s)
      end
    end
  end
end
