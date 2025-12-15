# frozen_string_literal: true

module EagerEye
  module Fixers
    class Base
      attr_reader :issue, :source_lines

      def initialize(issue, source_code)
        @issue = issue
        @source_code = source_code
        @source_lines = source_code.lines
      end

      def fixable?
        false
      end

      def fix
        raise NotImplementedError
      end

      def diff
        return nil unless fixable?

        original_line = @source_lines[issue.line_number - 1]
        fixed_line = fixed_content
        return nil if original_line == fixed_line

        {
          file: issue.file_path,
          line: issue.line_number,
          original: original_line.chomp,
          fixed: fixed_line.chomp
        }
      end

      protected

      def fixed_content
        raise NotImplementedError
      end

      def line_content
        @source_lines[issue.line_number - 1]
      end
    end
  end
end
