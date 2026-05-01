# frozen_string_literal: true

require_relative "concerns/variable_model_inference"

module EagerEye
  module Detectors
    class CustomMethodQuery < Base # rubocop:disable Metrics/ClassLength
      include Concerns::VariableModelInference

      QUERY_METHODS = %i[where find_by find_by! exists? find first last take pluck ids count sum average minimum
                         maximum].freeze
      SAFE_QUERY_METHODS = %i[first last take count sum find size length ids].freeze
      SAFE_TRANSFORM_METHODS = %i[keys values split [] params sort pluck ids to_s to_a to_i chars bytes].freeze
      ARRAY_COLUMN_SUFFIXES = %w[_ids _tags _types _codes _names _values _arr].freeze
      ITERATION_METHODS = %i[each map select find_all reject collect detect find_index flat_map
                             each_with_index each_with_object reduce inject
                             find_each find_in_batches in_batches array!].freeze

      def self.detector_name
        :custom_method_query
      end

      def detect(ast, file_path, method_queries = {}, associations_by_model = {})
        return [] unless ast

        @issues = []
        @file_path = file_path
        @method_queries = method_queries
        @associations_by_model = associations_by_model

        # Process each method def as its own scope so variable models from one
        # method don't bleed into another (e.g. `orders = Order.all` in #index
        # vs `orders = Foo.where(...).all` in #report — global tracking would
        # mis-attribute the iteration variable's class across scopes).
        process_scope(ast, {})

        @issues
      end

      private

      def process_scope(scope_node, definitions)
        @variable_models ||= {}
        scope_body = scope_body_for(scope_node)
        return unless scope_body

        find_iteration_blocks_in_scope(scope_body, definitions)

        process_nested_defs(scope_body, definitions)
      end

      def process_nested_defs(scope_body, definitions)
        nested_defs = []
        each_nested_def(scope_body) { |d| nested_defs << d }
        return if nested_defs.empty?

        call_sites_by_callee = collect_sibling_call_sites(nested_defs)

        nested_defs.each do |nested_def|
          with_scope_snapshot do
            seed_params_from_callers(nested_def, call_sites_by_callee)
            process_scope(nested_def, definitions.dup)
          end
        end
      end

      # See LoopAssociation#collect_sibling_call_sites for the rationale.
      def collect_sibling_call_sites(nested_defs)
        sibling_names = nested_defs.filter_map { |d| def_name(d) }.to_set
        result = Hash.new { |h, k| h[k] = [] }

        nested_defs.each do |def_node|
          def_body = scope_body_for(def_node)
          next unless def_body

          with_scope_snapshot do
            each_node_in_scope(def_body) do |node|
              record_definition(node, {})
              next unless self_send_to_sibling?(node, sibling_names)

              result[node.children[1]] << {
                args: node.children[2..],
                models: @variable_models.dup
              }
            end
          end
        end

        result
      end

      def self_send_to_sibling?(node, sibling_names)
        return false unless node.type == :send

        receiver = node.children[0]
        return false unless receiver.nil? || (receiver.is_a?(Parser::AST::Node) && receiver.type == :self)

        sibling_names.include?(node.children[1])
      end

      def def_name(def_node)
        case def_node.type
        when :def  then def_node.children[0]
        when :defs then def_node.children[1]
        end
      end

      def seed_params_from_callers(def_node, call_sites_by_callee)
        return unless def_node.type == :def

        call_sites = call_sites_by_callee[def_name(def_node)]
        return if call_sites.nil? || call_sites.empty?

        extract_param_names(def_node).each_with_index do |param_name, idx|
          model = first_arg_model(call_sites, idx)
          @variable_models[[:lvar, param_name]] = model if model
        end
      end

      def first_arg_model(call_sites, idx)
        call_sites.each do |site|
          arg = site[:args][idx]
          next unless arg

          saved = @variable_models
          @variable_models = site[:models]
          model = infer_model_from_value(arg)
          @variable_models = saved
          return model if model
        end
        nil
      end

      def extract_param_names(def_node)
        args_node = def_node.children[1]
        return [] unless args_node.is_a?(Parser::AST::Node) && args_node.type == :args

        args_node.children.filter_map do |arg|
          next unless arg.is_a?(Parser::AST::Node) && %i[arg optarg kwarg kwoptarg].include?(arg.type)

          arg.children[0]
        end
      end

      def scope_body_for(node)
        return node unless node.is_a?(Parser::AST::Node)

        case node.type
        when :def  then node.children[2]
        when :defs then node.children[3]
        else node
        end
      end

      def with_scope_snapshot
        saved_models = @variable_models.dup
        yield
      ensure
        @variable_models = saved_models
      end

      def each_node_in_scope(node, &block)
        return unless node.is_a?(Parser::AST::Node)

        yield node

        node.children.each do |child|
          next unless child.is_a?(Parser::AST::Node)
          next if %i[def defs].include?(child.type)

          each_node_in_scope(child, &block)
        end
      end

      def each_nested_def(node, &block)
        return unless node.is_a?(Parser::AST::Node)

        node.children.each do |child|
          next unless child.is_a?(Parser::AST::Node)

          if %i[def defs].include?(child.type)
            yield child
          else
            each_nested_def(child, &block)
          end
        end
      end

      def find_iteration_blocks_in_scope(scope_body, definitions)
        each_node_in_scope(scope_body) do |node|
          record_definition(node, definitions)
          next unless iteration_block?(node)

          block_var = extract_iteration_variable(node)
          block_body = node.children[2]
          next unless block_var && block_body

          model_name = infer_model_from_value(node.children[0])
          check_block_for_query_methods(block_body, block_var, collection_is_array?(node.children[0], definitions))
          check_block_for_model_query_methods(block_body, block_var, model_name)
        end
      end

      def record_definition(node, definitions)
        case node.type
        when :lvasgn then record_simple_definition(node, :lvar, definitions)
        when :ivasgn then record_simple_definition(node, :ivar, nil)
        when :masgn  then record_multi_definition(node, definitions)
        end
      end

      def record_simple_definition(node, var_type, definitions)
        name = node.children[0]
        value = node.children[1]
        return unless name && value

        definitions[name] = value if definitions
        model = infer_model_from_value(value)
        @variable_models[[var_type, name]] = model if model
      end

      def record_multi_definition(node, definitions)
        mlhs, rhs = node.children
        return unless mlhs && rhs

        model = infer_model_from_value(rhs)
        mlhs.children.each { |target| record_multi_target(target, rhs, model, definitions) }
      end

      def record_multi_target(target, rhs, model, definitions)
        return unless %i[lvasgn ivasgn].include?(target&.type)

        tname = target.children[0]
        return if PAGINATION_META_NAMES.include?(tname)

        var_type = target.type == :lvasgn ? :lvar : :ivar
        @variable_models[[var_type, tname]] = model if model
        definitions[tname] = rhs if target.type == :lvasgn
      end

      def iteration_block?(node)
        node.type == :block && node.children[0]&.type == :send &&
          ITERATION_METHODS.include?(node.children[0].children[1])
      end

      def check_block_for_query_methods(node, block_var, is_array_collection = false) # rubocop:disable Style/OptionalBooleanParameter
        return unless node.is_a?(Parser::AST::Node)

        add_issue(node) if query_chain_on_association?(node, block_var, is_array_collection)
        node.children.each { |child| check_block_for_query_methods(child, block_var, is_array_collection) }
      end

      def query_chain_on_association?(node, block_var, is_array_collection = false) # rubocop:disable Style/OptionalBooleanParameter
        return false unless node.type == :send

        method_name = node.children[1]
        return false unless QUERY_METHODS.include?(method_name)
        return false if skip_array_method?(node, block_var, is_array_collection)
        return false if receiver_is_query_chain?(node.children[0])

        receiver_chain_starts_with?(node.children[0], block_var)
      end

      def skip_array_method?(node, block_var, is_array_collection)
        return true if receiver_ends_with_safe_transform_method?(node.children[0])

        SAFE_QUERY_METHODS.include?(node.children[1]) &&
          is_array_collection && direct_block_var?(node.children[0], block_var)
      end

      def direct_block_var?(node, block_var)
        node.is_a?(Parser::AST::Node) && node.type == :lvar && node.children[0] == block_var
      end

      def collection_is_array?(node, definitions = {}, visited = Set.new)
        return false unless node.is_a?(Parser::AST::Node)
        return false unless visited.add?(node.object_id)

        return true if %i[array hash].include?(node.type)

        case node.type
        when :lvar
          defn = definitions[node.children[0]]
          defn && collection_is_array?(defn, definitions, visited)
        when :send then send_returns_array?(node, definitions, visited)
        else false
        end
      end

      def send_returns_array?(node, definitions, visited)
        method_name = node.children[1]
        return true if %i[map select collect flat_map uniq compact].include?(method_name)
        return true if SAFE_TRANSFORM_METHODS.include?(method_name)

        collection_is_array?(node.children[0], definitions, visited)
      end

      def receiver_ends_with_safe_transform_method?(node)
        return false unless node.is_a?(Parser::AST::Node) && node.type == :send

        method_name = node.children[1]
        SAFE_TRANSFORM_METHODS.include?(method_name) ||
          ARRAY_COLUMN_SUFFIXES.any? { |suffix| method_name.to_s.end_with?(suffix) }
      end

      def receiver_is_query_chain?(node)
        node.is_a?(Parser::AST::Node) && node.type == :send && QUERY_METHODS.include?(node.children[1])
      end

      def check_block_for_model_query_methods(node, block_var, model_name)
        return unless node.is_a?(Parser::AST::Node)

        if model_query_call?(node, block_var, model_name)
          method = node.children[1]
          @issues << create_issue(
            file_path: @file_path,
            line_number: node.loc.line,
            message: "Model method `.#{method}` contains a query and is called inside iteration",
            suggestion: "This method executes a query on each iteration. Preload data or move the query outside."
          )
        end
        node.children.each { |child| check_block_for_model_query_methods(child, block_var, model_name) }
      end

      def model_query_call?(node, block_var, model_name)
        return false unless block_var_immediate_send?(node, block_var)

        method = node.children[1]
        # If we know the receiver model AND the method is one of its
        # associations, treat it as an association access — not a query method.
        return false if association_on_model?(method, model_name)

        method_defined_as_query?(method, model_name)
      end

      def block_var_immediate_send?(node, block_var)
        node.type == :send &&
          (receiver = node.children[0])&.type == :lvar &&
          receiver.children[0] == block_var
      end

      def association_on_model?(method, model_name)
        model_name && @associations_by_model&.dig(model_name)&.include?(method)
      end

      def method_defined_as_query?(method, model_name)
        return false unless @method_queries

        if model_name
          @method_queries[model_name]&.include?(method) || false
        else
          @method_queries.any? { |_model, methods| methods.include?(method) }
        end
      end

      def add_issue(node)
        chain = reconstruct_chain(node.children[0])
        @issues << create_issue(
          file_path: @file_path,
          line_number: node.loc.line,
          message: "Query method `.#{node.children[1]}` called on `#{chain}` inside iteration",
          suggestion: "This query executes on each iteration. Consider preloading data or restructuring the query."
        )
      end
    end
  end
end
