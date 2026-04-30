# frozen_string_literal: true

require_relative "concerns/variable_model_inference"

module EagerEye
  module Detectors
    class LoopAssociation < Base # rubocop:disable Metrics/ClassLength
      include Concerns::VariableModelInference

      ITERATION_METHODS = %i[each map collect select find find_all reject filter filter_map flat_map
                             each_with_index each_with_object reduce inject
                             find_each find_in_batches in_batches array!].freeze
      PRELOAD_METHODS = %i[includes preload eager_load].freeze
      SINGLE_RECORD_METHODS = %i[find find_by find_by! first first! last last! take take! second third fourth fifth
                                 forty_two sole find_sole_by].freeze
      # Terminal methods on an association that do NOT trigger a SELECT for
      # loading the association — they translate directly to UPDATE/DELETE SQL
      # against the association's foreign key.
      NON_LOADING_TERMINAL_METHODS = %i[update_all delete_all destroy_all touch_all
                                        increment_counter decrement_counter].freeze
      ASSOCIATION_NAMES = Set.new(%w[
        author user owner creator admin member customer client post article comment category
        parent company organization project task item order product account profile
        avatar photo authors users owners creators admins members customers
        clients posts articles comments categories children companies organizations projects
        tasks items orders products accounts profiles avatars photos
      ]).freeze
      EXCLUDED_METHODS = %i[
        id to_s to_h to_a to_json to_xml inspect class object_id nil? blank? present? empty?
        any? none? size count length save save! update update! destroy destroy! delete delete!
        valid? invalid? errors new? persisted? changed? frozen? name title body content text
        description value key type status state created_at updated_at deleted_at origin
        priority level kind label code reason amount price quantity url path email phone
        address notes memo data metadata position rank score rating enabled disabled active
        published draft archived locked visible hidden tag image attachment document setting
      ].freeze

      def self.detector_name
        :loop_association
      end

      def detect(ast, file_path, association_preloads = {}, association_names = Set.new, # rubocop:disable Metrics/ParameterLists
                 method_queries = {}, associations_by_model = {})
        return [] unless ast

        issues = []
        @association_preloads = association_preloads
        @dynamic_associations = association_names
        @method_queries = method_queries
        @associations_by_model = associations_by_model
        build_variable_maps(ast)

        traverse_ast(ast) do |node|
          next unless iteration_block?(node)

          block_var = extract_iteration_variable(node)
          next unless block_var

          block_body = node.children[2]
          next unless block_body

          collection_node = node.children[0]
          next if single_record_iteration?(collection_node)

          included = collect_included_associations(collection_node)
          model_name = infer_model_from_value(collection_node)
          skip_nodes = collect_non_loading_skip_set(block_body)

          find_association_calls(block_body, block_var, file_path, issues, included, model_name, skip_nodes)
        end

        issues
      end

      private

      def collect_included_associations(collection_node)
        included = extract_included_associations_deep(collection_node)
        included.merge(extract_variable_preloads(collection_node))
        included.merge(get_association_preloads(infer_model_from_value(collection_node)))
        included
      end

      def get_association_preloads(model_name)
        preloaded = Set.new
        return preloaded unless model_name

        @association_preloads&.each do |key, assocs|
          preloaded.merge(assocs) if key.start_with?("#{model_name}#")
        end
        preloaded
      end

      def iteration_block?(node)
        node.type == :block && node.children[0]&.type == :send &&
          ITERATION_METHODS.include?(node.children[0].children[1])
      end

      # Extract :includes/:preload/:eager_load arguments from a value node,
      # walking BOTH the receiver chain and any method arguments. The arg
      # recursion is what lets us see through wrappers like pagy(query, ...).
      def extract_included_associations_deep(value_node, depth = 0)
        included = Set.new
        return included if depth > 10 || !value_node.is_a?(Parser::AST::Node)

        current = walk_send_chain_for_preloads(value_node, included, depth)
        merge_preloads_from_non_send(current, included, depth)
        included
      end

      def walk_send_chain_for_preloads(node, included, depth)
        current = node
        while current.is_a?(Parser::AST::Node) && current.type == :send
          extract_includes_from_method(current, included) if PRELOAD_METHODS.include?(current.children[1])
          current.children[2..].each do |arg|
            included.merge(extract_included_associations_deep(arg, depth + 1))
          end
          current = current.children[0]
        end
        current
      end

      def merge_preloads_from_non_send(node, included, depth)
        case node&.type
        when :if          then merge_branch_preloads(node, included, depth)
        when :begin       then node.children.each do |c|
          included.merge(extract_included_associations_deep(c, depth + 1))
        end
        when :lvar, :ivar then merge_variable_preloads(node, included)
        end
      end

      def merge_branch_preloads(node, included, depth)
        included.merge(extract_included_associations_deep(node.children[1], depth + 1))
        included.merge(extract_included_associations_deep(node.children[2], depth + 1))
      end

      def merge_variable_preloads(node, included)
        key = [node.type == :ivar ? :ivar : :lvar, node.children[0]]
        included.merge(@variable_preloads[key]) if @variable_preloads&.key?(key)
      end

      def build_variable_maps(ast)
        @variable_preloads = {}
        @variable_models = {}
        @single_record_variables = Set.new

        traverse_ast(ast) { |node| process_variable_assignment(node) }
      end

      def process_variable_assignment(node)
        case node.type
        when :lvasgn, :ivasgn then process_simple_assignment(node)
        when :masgn then process_multi_assignment(node)
        end
      end

      def process_simple_assignment(node)
        var_type = node.type == :lvasgn ? :lvar : :ivar
        var_name = node.children[0]
        value_node = node.children[1]
        return unless value_node && var_name

        record_variable(var_type, var_name, value_node)
      end

      def process_multi_assignment(node)
        mlhs, rhs = node.children
        return unless mlhs && rhs

        # mlhs.children is a list of lvasgn/ivasgn (LHS targets). RHS is
        # typically a method call like `pagy(query)` returning [meta, records],
        # or an array literal. We can't statically know which target gets which
        # slot, so apply preloads/model to every LHS — except names that look
        # like pagination metadata.
        mlhs.children.each { |target| record_multi_target(target, rhs) }
      end

      def record_multi_target(target, rhs)
        return unless %i[lvasgn ivasgn].include?(target&.type)

        name = target.children[0]
        return if PAGINATION_META_NAMES.include?(name)

        var_type = target.type == :lvasgn ? :lvar : :ivar
        record_variable(var_type, name, rhs)
      end

      def record_variable(var_type, var_name, value_node)
        key = [var_type, var_name]

        preloaded = extract_included_associations_deep(value_node)
        @variable_preloads[key] = preloaded unless preloaded.empty?

        model = infer_model_from_value(value_node)
        @variable_models[key] = model if model

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

      # Pre-scan: when an inner send like `block_var.assoc` is the receiver of a
      # NON_LOADING_TERMINAL_METHODS call (e.g. `.update_all`), the assoc access
      # does not trigger a SELECT. Track those receiver nodes so we don't flag them.
      def collect_non_loading_skip_set(block_body)
        skip = Set.new
        traverse_ast(block_body) do |node|
          next unless node.type == :send && NON_LOADING_TERMINAL_METHODS.include?(node.children[1])

          receiver = node.children[0]
          collect_chain_node_ids(receiver, skip)
        end
        skip
      end

      def collect_chain_node_ids(node, set)
        return unless node.is_a?(Parser::AST::Node) && node.type == :send

        set.add(node.object_id)
        collect_chain_node_ids(node.children[0], set)
      end

      def find_association_calls(node, block_var, file_path, issues, included_associations, model_name, skip_nodes) # rubocop:disable Metrics/ParameterLists
        reported = Set.new
        traverse_ast(node) do |child|
          next if skip_nodes.include?(child.object_id)

          if reportable_association_call?(child, block_var, reported, included_associations, model_name)
            method = child.children[1]
            issues << create_issue(
              file_path: file_path,
              line_number: child.loc.line,
              message: "Potential N+1 query: `#{block_var}.#{method}` called inside loop",
              suggestion: "Use `includes(:#{method})` before iterating"
            )
          elsif reportable_method_query_call?(child, block_var, reported, model_name)
            method = child.children[1]
            issues << create_issue(
              file_path: file_path,
              line_number: child.loc.line,
              message: "Potential N+1 query: `#{block_var}.#{method}` calls a query method defined in the model",
              suggestion: "Preload the data or restructure to avoid per-record queries"
            )
          end
        end
      end

      def reportable_association_call?(node, block_var, reported, included, model_name)
        return false unless node.type == :send

        receiver = node.children[0]
        method = node.children[1]
        return false unless receiver&.type == :lvar && receiver.children[0] == block_var
        return false if excluded_method?(method, included, model_name)

        reported.add?("#{node.loc.line}:#{method}")
      end

      def excluded_method?(method, included, model_name)
        EXCLUDED_METHODS.include?(method) ||
          included.include?(method) ||
          !known_association?(method, model_name)
      end

      # When we know the iteration variable's model AND have parsed that model's
      # associations, trust that map exclusively — methods not in it are columns
      # or scalar accessors, not associations. Otherwise fall back to heuristics
      # (hardcoded common names + globally collected association names).
      def known_association?(method, model_name)
        if model_name && @associations_by_model&.key?(model_name)
          return @associations_by_model[model_name].include?(method)
        end

        ASSOCIATION_NAMES.include?(method.to_s) || @dynamic_associations.include?(method)
      end

      def reportable_method_query_call?(node, block_var, reported, model_name)
        return false unless block_var_send?(node, block_var)
        return false if EXCLUDED_METHODS.include?(node.children[1])
        return false unless method_known_to_query?(node.children[1], model_name)

        reported.add?("#{node.loc.line}:#{node.children[1]}")
      end

      # When the receiver model is known, only consider methods defined as a
      # query on THAT model — not any model in the project. Without a known
      # model, fall back to the global "any model has this method" heuristic.
      def method_known_to_query?(method, model_name)
        return false unless @method_queries

        if model_name
          @method_queries[model_name]&.include?(method) || false
        else
          @method_queries.any? { |_, ms| ms.include?(method) }
        end
      end

      def block_var_send?(node, block_var)
        node.type == :send && node.children[0]&.type == :lvar && node.children[0].children[0] == block_var
      end
    end
  end
end
