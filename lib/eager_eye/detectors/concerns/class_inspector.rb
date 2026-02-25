# frozen_string_literal: true

module EagerEye
  module Detectors
    module Concerns
      module ClassInspector
        HAS_MANY_ASSOCIATIONS = %w[
          authors users owners creators admins members customers clients
          posts articles comments categories tags children companies organizations
          projects tasks items orders products accounts profiles settings
          images avatars photos attachments documents
        ].freeze

        ACTIVE_STORAGE_METHODS = %i[
          attached? attach attachment attachments blob blobs purge purge_later variant preview
        ].freeze

        private

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

        def extract_class_name(class_node)
          name_node = class_node.children[0]
          name_node.children[1].to_s if name_node&.type == :const
        end

        def likely_association?(method_name)
          HAS_MANY_ASSOCIATIONS.include?(method_name.to_s)
        end

        def collect_active_storage_lines(body)
          lines = Set.new
          traverse_ast(body) do |node|
            lines << node.loc.line if node.type == :send && ACTIVE_STORAGE_METHODS.include?(node.children[1])
          end
          lines
        end
      end
    end
  end
end
