# frozen_string_literal: true

module EagerEye
  module Fixers
    class PluckToSelect < Base
      def fixable?
        issue.detector == :pluck_to_array && single_line_pattern?
      end

      protected

      def fixed_content
        line_content.gsub(/\.pluck\((:\w+)\)/, '.select(\1)')
      end

      private

      def single_line_pattern?
        line_content&.include?(".pluck(") && line_content.include?(".where(")
      end
    end
  end
end
