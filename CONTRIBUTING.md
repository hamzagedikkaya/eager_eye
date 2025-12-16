# Contributing to EagerEye

Thank you for your interest in contributing to EagerEye!

## Development Setup

```bash
git clone https://github.com/hamzagedikkaya/eager_eye.git
cd eager_eye
bin/setup
```

## Running Tests

```bash
bundle exec rspec
bundle exec rubocop
```

## Adding a New Detector

1. Create `lib/eager_eye/detectors/your_detector.rb`
2. Inherit from `EagerEye::Detectors::Base`
3. Implement `.detector_name` class method
4. Implement `#detect(ast, file_path)` instance method
5. Add to autoload in `lib/eager_eye.rb`
6. Add to default detectors in `configuration.rb`
7. Add to `DETECTOR_CLASSES` in `analyzer.rb`
8. Write tests in `spec/detectors/your_detector_spec.rb`
9. Update README with documentation

### Detector Template

```ruby
# frozen_string_literal: true

module EagerEye
  module Detectors
    class YourDetector < Base
      def self.detector_name
        :your_detector
      end

      def detect(ast, file_path)
        issues = []
        return issues unless ast

        traverse_ast(ast) do |node|
          # Your detection logic here
          if problematic_pattern?(node)
            issues << create_issue(
              file_path: file_path,
              line_number: node.loc.line,
              message: "Description of the issue",
              suggestion: "How to fix it"
            )
          end
        end

        issues
      end

      private

      def problematic_pattern?(node)
        # Return true if node matches the pattern you're detecting
        false
      end
    end
  end
end
```

## Code Style

- Follow RuboCop rules (run `bundle exec rubocop`)
- Maintain 90%+ test coverage
- Document public methods
- Keep methods small and focused

## Pull Request Process

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/my-feature`)
3. Write tests for your changes
4. Ensure all tests pass and RuboCop is clean
5. Commit your changes (`git commit -am 'Add my feature'`)
6. Push to the branch (`git push origin feature/my-feature`)
7. Open a Pull Request with a clear description

## Reporting Bugs

When reporting bugs, please include:

- Ruby version
- EagerEye version
- Minimal code example that reproduces the issue
- Expected behavior
- Actual behavior

## Feature Requests

Feature requests are welcome! Please open an issue describing:

- The problem you're trying to solve
- Your proposed solution
- Any alternatives you've considered
