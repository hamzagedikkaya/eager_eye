# frozen_string_literal: true

module EagerEye
  class FixerRegistry
    FIXERS = {
      count_in_iteration: Fixers::CountToSize,
      pluck_to_array: Fixers::PluckToSelect
    }.freeze

    def self.fixer_for(issue, source_code)
      fixer_class = FIXERS[issue.detector]
      return nil unless fixer_class

      fixer_class.new(issue, source_code)
    end

    def self.fixable?(issue, source_code)
      fixer = fixer_for(issue, source_code)
      fixer&.fixable? || false
    end
  end
end
