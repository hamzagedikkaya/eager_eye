# frozen_string_literal: true

require_relative "concerns/non_ar_source_detector"

module EagerEye
  module Detectors
    class PluckToArray < Base
      include Concerns::NonArSourceDetector

      SMALL_COLLECTIONS = %w[tags settings options categories roles permissions statuses types priorities].freeze

      def self.detector_name
        :pluck_to_array
      end

      def detect(ast, file_path)
        @issues = []
        @file_path = file_path
        reset_tracking_variables

        return @issues unless ast

        collect_all_info(ast)
        check_ast(ast)

        @issues
      end

      private

      def reset_tracking_variables
        @pluck_variables = {}
        @map_id_variables = {}
        @critical_pluck_variables = {}
        @small_collection_variables = {}
        @variable_usages = Hash.new(0)
        @to_sql_variables = {}
      end

      def collect_all_info(node)
        return unless node.is_a?(Parser::AST::Node)

        collect_assignments(node)
        collect_variable_usage(node)
        collect_to_sql_usage(node)

        node.children.each { |child| collect_all_info(child) }
      end

      def check_ast(node)
        return unless node.is_a?(Parser::AST::Node)

        check_where_calls(node)
        node.children.each { |child| check_ast(child) }
      end

      def collect_assignments(node)
        return unless node.type == :lvasgn

        var_name = node.children[0]
        value = node.children[1]

        return if non_db_source?(value)

        track_variable_type(var_name, value, node.loc.line)
      end

      def track_variable_type(var_name, value, line)
        @critical_pluck_variables[var_name] = line if all_pluck_call?(value)
        @small_collection_variables[var_name] = line if small_collection_pluck?(value)
        @pluck_variables[var_name] = line if pluck_call?(value)
        @map_id_variables[var_name] = line if map_id_call?(value)
      end

      def collect_variable_usage(node)
        return unless node.is_a?(Parser::AST::Node) && node.type == :lvar

        @variable_usages[node.children[0]] += 1
      end

      def collect_to_sql_usage(node)
        return unless node.is_a?(Parser::AST::Node) && node.type == :send && node.children[1] == :to_sql

        find_variables_in_chain(node).each { |var_name| @to_sql_variables[var_name] = true }
      end

      def find_variables_in_chain(node)
        return [] unless node.is_a?(Parser::AST::Node)
        return [node.children[0]] if node.type == :lvar

        node.children.flat_map { |child| find_variables_in_chain(child) }
      end

      def check_where_calls(node)
        return unless where_call?(node) && ar_receiver?(node)

        process_where_call(node)
      end

      def process_where_call(node)
        if critical_pluck?(node) then add_critical_issue(node)
        elsif small_collection?(node) then add_info_issue(node)
        elsif regular_pluck?(node) then check_regular_pluck(node)
        end
      end

      def check_regular_pluck(node)
        var_name = find_pluck_var_in_where(node)
        return if var_name && (multi_use_variable?(var_name) || @to_sql_variables[var_name])

        add_issue(node, var_name)
      end

      def where_call?(node) = node.type == :send && node.children[1] == :where

      def pluck_call?(node)
        node.is_a?(Parser::AST::Node) && node.type == :send && %i[pluck ids].include?(node.children[1])
      end

      def all_pluck_call?(node)
        pluck_call?(node) && node.children[0].is_a?(Parser::AST::Node) &&
          node.children[0].type == :send && node.children[0].children[1] == :all
      end

      def small_collection_pluck?(node)
        return false unless pluck_call?(node)

        receiver = node.children[0]
        receiver.is_a?(Parser::AST::Node) && receiver.type == :send &&
          SMALL_COLLECTIONS.any? { |c| receiver.children[1].to_s.include?(c) }
      end

      def map_id_call?(node)
        node.is_a?(Parser::AST::Node) && node.type == :send && %i[map collect].include?(node.children[1]) &&
          node.children[2..].any? { |arg| symbol_to_proc_id?(arg) }
      end

      def symbol_to_proc_id?(node)
        node.is_a?(Parser::AST::Node) && node.type == :block_pass &&
          node.children[0]&.type == :sym && %i[id to_i].include?(node.children[0].children[0])
      end

      def regular_pluck?(node) = node.children[2..].any? { |arg| pluck_var_in_hash?(arg) }
      def critical_pluck?(node) = node.children[2..].any? { |arg| critical_pluck_in_hash?(arg) }
      def small_collection?(node) = node.children[2..].any? { |arg| small_collection_in_hash?(arg) }

      def pluck_var_in_hash?(node) = hash_with_value?(node) { |v| pluck_value?(v) }
      def critical_pluck_in_hash?(node) = hash_with_value?(node) { |v| critical_value?(v) }
      def small_collection_in_hash?(node) = hash_with_value?(node) { |v| small_collection_value?(v) }

      def hash_with_value?(node, &block)
        return false unless node.is_a?(Parser::AST::Node) && node.type == :hash

        node.children.any? { |pair| pair.type == :pair && block.call(pair.children[1]) }
      end

      def pluck_value?(val)
        val.type == :lvar && (@pluck_variables.key?(val.children[0]) || @map_id_variables.key?(val.children[0]))
      end

      def critical_value?(val)
        val.type == :lvar ? @critical_pluck_variables.key?(val.children[0]) : all_pluck_call?(val)
      end

      def small_collection_value?(val)
        val.type == :lvar && @small_collection_variables.key?(val.children[0])
      end

      def find_pluck_var_in_where(node)
        node.children[2..].each do |arg|
          next unless arg.is_a?(Parser::AST::Node) && arg.type == :hash

          var = find_pluck_var_in_hash(arg)
          return var if var
        end
        nil
      end

      def find_pluck_var_in_hash(hash_node)
        hash_node.children.each do |pair|
          next unless pair.type == :pair && pair.children[1].type == :lvar

          var_name = pair.children[1].children[0]
          return var_name if @pluck_variables.key?(var_name) || @map_id_variables.key?(var_name)
        end
        nil
      end

      def multi_use_variable?(var_name) = @variable_usages[var_name] > 1
      def map_variable?(var_name) = @map_id_variables.key?(var_name)

      def add_issue(node, var_name = nil)
        message, suggestion = issue_content(var_name)
        @issues << create_issue(file_path: @file_path, line_number: node.loc.line,
                                message: message, suggestion: suggestion, severity: :warning)
      end

      def issue_content(var_name)
        if var_name && map_variable?(var_name)
          ["Using ID array from `.map(&:id)` in `where` causes two queries",
           "If source is ActiveRecord, use `.select(:id)` subquery instead"]
        else
          ["Using plucked array in `where` causes two queries and memory overhead",
           "Use `.select(:id)` subquery instead: `Model.where(col: OtherModel.select(:id))`"]
        end
      end

      def add_critical_issue(node)
        @issues << create_issue(file_path: @file_path, line_number: node.loc.line,
                                message: "Using `.all.pluck(:id)` loads entire table into memory - highly inefficient",
                                suggestion: "Use `.select(:id)` subquery: `Model.where(col: OtherModel.select(:id))`",
                                severity: :error)
      end

      def add_info_issue(node)
        @issues << create_issue(
          file_path: @file_path, line_number: node.loc.line,
          message: "Small collection pluck may be acceptable for few records",
          suggestion: "Consider `.select(:id)` for consistency, but pluck is fine for small collections",
          severity: :info
        )
      end
    end
  end
end
