# frozen_string_literal: true

module EagerEye
  module Detectors
    class LoopAssociation < Base
      ITERATION_METHODS = %i[each map collect select find find_all reject filter filter_map flat_map].freeze
      PRELOAD_METHODS = %i[includes preload eager_load].freeze
      # Methods that return a single record (not a collection)
      SINGLE_RECORD_METHODS = %i[find find_by find_by! first first! last last! take take! second third fourth fifth
                                 forty_two sole find_sole_by].freeze

      # Common association names (belongs_to = singular, has_many = plural)
      ASSOCIATION_NAMES = Set.new(%w[
        author user owner creator admin member customer client post article comment category tag
        parent company organization project task item order product account profile setting image
        avatar photo attachment document authors users owners creators admins members customers
        clients posts articles comments categories tags children companies organizations projects
        tasks items orders products accounts profiles settings images avatars photos attachments
        documents
      ]).freeze

      # Methods that should NOT be treated as associations
      EXCLUDED_METHODS = %i[
        id to_s to_h to_a to_json to_xml inspect class object_id nil? blank? present? empty?
        any? none? size count length save save! update update! destroy destroy! delete delete!
        valid? invalid? errors new? persisted? changed? frozen? name title body content text
        description value key type status state created_at updated_at deleted_at
      ].freeze

      def self.detector_name
        :loop_association
      end

      def detect(ast, file_path)
        return [] unless ast

        issues = []
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

          find_association_calls(block_body, block_var, file_path, issues, included)
        end

        issues
      end

      private

      def iteration_block?(node)
        return false unless node.type == :block

        send_node = node.children[0]
        return false unless send_node&.type == :send

        method_name = send_node.children[1]
        ITERATION_METHODS.include?(method_name)
      end

      def extract_block_variable(block_node)
        args_node = block_node.children[1]
        return nil unless args_node&.type == :args
        return nil if args_node.children.empty?

        first_arg = args_node.children[0]
        return nil unless first_arg&.type == :arg

        first_arg.children[0]
      end

      def extract_included_associations(collection_node)
        included = Set.new
        return included unless collection_node&.type == :send

        # Traverse through chained method calls to find includes/preload/eager_load
        current = collection_node
        while current&.type == :send
          method_name = current.children[1]
          extract_includes_from_method(current, included) if PRELOAD_METHODS.include?(method_name)

          current = current.children[0]
        end

        included
      end

      def build_variable_maps(ast)
        @variable_preloads = {}
        @single_record_variables = Set.new

        traverse_ast(ast) do |node|
          next unless %i[lvasgn ivasgn].include?(node.type)

          var_type = node.type == :lvasgn ? :lvar : :ivar
          var_name = node.children[0]
          value_node = node.children[1]
          next unless value_node

          key = [var_type, var_name]
          preloaded = extract_included_associations(value_node)
          @variable_preloads[key] = preloaded unless preloaded.empty?
          @single_record_variables.add(key) if single_record_query?(value_node)
        end
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
        current = node
        while current&.type == :send && !SINGLE_RECORD_METHODS.include?(current.children[1])
          current = current.children[0]
        end
        current&.type == :send && SINGLE_RECORD_METHODS.include?(current.children[1])
      end

      def single_record_iteration?(node)
        return false unless node&.type == :send && (receiver = node.children[0])

        key = variable_key_for_node(receiver)
        (key && @single_record_variables&.include?(key)) || single_record_query?(receiver)
      end

      def extract_includes_from_method(method_node, included_set)
        args = method_node.children[2..]
        args&.each do |arg|
          case arg&.type
          when :sym
            # includes(:product)
            included_set.add(arg.children[0])
          when :hash
            # includes(product: :manufacturer)
            extract_from_hash(arg, included_set)
          end
        end
      end

      def extract_from_hash(hash_node, included_set)
        hash_node.children.each do |pair|
          key = pair.children[0]
          included_set.add(key.children[0]) if key&.type == :sym
        end
      end

      def find_association_calls(node, block_var, file_path, issues, included_associations = Set.new)
        reported_associations = Set.new

        traverse_ast(node) do |child|
          next unless child.type == :send

          receiver = child.children[0]
          method_name = child.children[1]

          # Only detect direct calls on block variable (post.author, not post.author.name)
          next unless direct_call_on_block_var?(receiver, block_var)
          next unless likely_association?(method_name)

          # Skip if association is already included
          next if included_associations.include?(method_name)

          # Avoid duplicate reports for same association on same line
          report_key = "#{child.loc.line}:#{method_name}"
          next if reported_associations.include?(report_key)

          reported_associations << report_key

          issues << create_issue(
            file_path: file_path,
            line_number: child.loc.line,
            message: "Potential N+1 query: `#{block_var}.#{method_name}` called inside iteration",
            suggestion: "Consider using `includes(:#{method_name})` on the collection before iterating"
          )
        end
      end

      def direct_call_on_block_var?(receiver, block_var)
        return false unless receiver

        receiver.type == :lvar && receiver.children[0] == block_var
      end

      def likely_association?(method_name)
        return false if EXCLUDED_METHODS.include?(method_name)

        ASSOCIATION_NAMES.include?(method_name.to_s)
      end
    end
  end
end
