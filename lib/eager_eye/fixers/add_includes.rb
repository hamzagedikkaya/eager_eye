# frozen_string_literal: true

module EagerEye
  module Fixers
    class AddIncludes < Base
      ITERATION_METHODS_RE = %w[
        each map collect select find_all reject filter filter_map
        flat_map find_each find_in_batches in_batches
      ].join("|")
      ITERATION_PATTERN = /\.(#{ITERATION_METHODS_RE})\b/

      def fixable?
        issue.detector == :loop_association &&
          !association_name.nil? &&
          !iteration_line_index.nil?
      end

      def diff
        return nil unless fixable?

        idx = iteration_line_index
        original_line = @source_lines[idx]
        fixed_line = insert_includes(original_line)
        return nil if original_line == fixed_line

        {
          file: issue.file_path,
          line: idx + 1,
          original: original_line.chomp,
          fixed: fixed_line.chomp
        }
      end

      protected

      def fixed_content
        raise NotImplementedError
      end

      private

      def association_name
        return nil unless issue.suggestion

        match = issue.suggestion.match(/includes\(:(\w+)\)/)
        match && match[1]
      end

      def iteration_line_index
        start = issue.line_number - 2
        start.downto([start - 10, 0].max) do |i|
          return i if @source_lines[i]&.match?(ITERATION_PATTERN)
        end
        nil
      end

      def insert_includes(line)
        line.sub(ITERATION_PATTERN, ".includes(:#{association_name})\\0")
      end
    end
  end
end
