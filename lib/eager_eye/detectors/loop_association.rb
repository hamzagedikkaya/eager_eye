# frozen_string_literal: true

module EagerEye
  module Detectors
    class LoopAssociation < Base
      ITERATION_METHODS = %i[each map collect select find find_all reject filter filter_map flat_map
                             find_each find_in_batches in_batches].freeze
      PRELOAD_METHODS = %i[includes preload eager_load].freeze
      SINGLE_RECORD_METHODS = %i[find find_by find_by! first first! last last! take take! second third fourth fifth
                                 forty_two sole find_sole_by].freeze
      ASSOCIATION_NAMES = Set.new(%w[
        author user owner creator admin member customer client post article comment category tag
        parent company organization project task item order product account profile setting image
        avatar photo attachment document authors users owners creators admins members customers
        clients posts articles comments categories tags children companies organizations projects
        tasks items orders products accounts profiles settings images avatars photos attachments
        documents
      ]).freeze
      EXCLUDED_METHODS = %i[
        id to_s to_h to_a to_json to_xml inspect class object_id nil? blank? present? empty?
        any? none? size count length save save! update update! destroy destroy! delete delete!
        valid? invalid? errors new? persisted? changed? frozen? name title body content text
        description value key type status state created_at updated_at deleted_at origin
        priority level kind label code reason amount price quantity url path email phone
        address notes memo data metadata position rank score rating enabled disabled active
        published draft archived locked visible hidden
      ].freeze

      def self.detector_name
        :loop_association
      end

      def detect(ast, file_path, association_preloads = {}, association_names = Set.new)
        return [] unless ast

        issues = []
        @association_preloads = association_preloads
        @dynamic_associations = association_names
        build_variable_maps(ast)

        traverse_ast(ast) do |node|
          next unless iteration_block?(node)

          block_var = extract_block_variable(node)
          next unless block_var

          block_body = node.children[2]
          next unless block_body

          collection_node = node.children[0]
          next if single_record_iteration?(collection_node)

          included = extract_included_associations(collection_node)
          included.merge(extract_variable_preloads(collection_node))
          included.merge(get_association_preloads(infer_model_name_from_collection(collection_node)))

          find_association_calls(block_body, block_var, file_path, issues, included)
        end

        issues
      end

      private

      def get_association_preloads(model_name)
        preloaded = Set.new
        @association_preloads&.each do |key, assocs|
          preloaded.merge(assocs) if key.start_with?("#{model_name}#")
        end
        preloaded
      end

      def infer_model_name_from_collection(node)
        return nil unless node&.type == :send

        receiver = node.children[0]
        receiver.children[1].to_s if receiver&.type == :const
      end

      def iteration_block?(node)
        node.type == :block && node.children[0]&.type == :send &&
          ITERATION_METHODS.include?(node.children[0].children[1])
      end

      def extract_included_associations(collection_node)
        included = Set.new
        return included unless collection_node&.type == :send

        current = collection_node
        while current&.type == :send
          extract_includes_from_method(current, included) if PRELOAD_METHODS.include?(current.children[1])
          current = current.children[0]
        end
        included
      end

      def build_variable_maps(ast)
        @variable_preloads = {}
        @single_record_variables = Set.new

        traverse_ast(ast) { |node| process_variable_assignment(node) }
      end

      def process_variable_assignment(node)
        return unless %i[lvasgn ivasgn].include?(node.type)

        var_type = node.type == :lvasgn ? :lvar : :ivar
        var_name = node.children[0]
        value_node = node.children[1]
        return unless value_node

        key = [var_type, var_name]
        preloaded = extract_included_associations(value_node)
        @variable_preloads[key] = preloaded unless preloaded.empty?
        @single_record_variables.add(key) if single_record_query?(value_node)
      end

      def extract_variable_preloads(node)
        key = variable_key_for_node(node)
        (key && @variable_preloads&.[](key)) || Set.new
      end

      def variable_key_for_node(node)
        case node&.type
        when :lvar then [:lvar, node.children[0]]
        when :ivar then [:ivar, node.children[0]]
        when :send then variable_key_for_node(node.children[0])
        end
      end

      def single_record_query?(node)
        last_send = find_last_send_method(node)
        last_send && SINGLE_RECORD_METHODS.include?(last_send)
      end

      def find_last_send_method(node)
        current = node
        while current&.type == :send
          return current.children[1] if SINGLE_RECORD_METHODS.include?(current.children[1])

          current = current.children[0]
        end
        nil
      end

      def single_record_iteration?(node)
        return false unless node&.type == :send && (receiver = node.children[0])

        key = variable_key_for_node(receiver)
        (key && @single_record_variables&.include?(key)) || single_record_query?(receiver)
      end

      def extract_includes_from_method(method_node, included_set)
        included_set.merge(extract_symbols_from_args(extract_method_args(method_node)))
      end

      def find_association_calls(node, block_var, file_path, issues, included_associations = Set.new)
        reported = Set.new
        traverse_ast(node) do |child|
          next unless reportable_association_call?(child, block_var, reported, included_associations)

          method = child.children[1]
          issues << create_issue(
            file_path: file_path,
            line_number: child.loc.line,
            message: "Potential N+1 query: `#{block_var}.#{method}` called inside loop",
            suggestion: "Use `includes(:#{method})` before iterating"
          )
        end
      end

      def reportable_association_call?(node, block_var, reported, included)
        return false unless node.type == :send

        receiver = node.children[0]
        method = node.children[1]
        return false unless receiver&.type == :lvar && receiver.children[0] == block_var
        return false if excluded_method?(method, included)

        reported.add?("#{node.loc.line}:#{method}")
      end

      def excluded_method?(method, included)
        EXCLUDED_METHODS.include?(method) ||
          !known_association?(method) ||
          included.include?(method)
      end

      def known_association?(method)
        ASSOCIATION_NAMES.include?(method.to_s) || @dynamic_associations.include?(method)
      end
    end
  end
end
