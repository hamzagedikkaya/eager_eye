# frozen_string_literal: true

module EagerEye
  module Fixers
    class PluckToSelect < Base
      # This fixer only works for single-line pluck + where patterns
      # Two-line patterns are too complex to fix automatically

      def fixable?
        issue.detector == :pluck_to_array &&
          single_line_pattern?
      end

      protected

      def fixed_content
        # Model.where(col: OtherModel.pluck(:id)) -> Model.where(col: OtherModel.select(:id))
        line_content.gsub(/\.pluck\((:\w+)\)/, '.select(\1)')
      end

      private

      def single_line_pattern?
        return false unless line_content

        line_content.include?(".pluck(") && line_content.include?(".where(")
      end
    end
  end
end
