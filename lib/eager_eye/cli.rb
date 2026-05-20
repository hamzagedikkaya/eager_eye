# frozen_string_literal: true

require "optparse"

module EagerEye
  class CLI
    attr_reader :argv, :options

    def initialize(argv = ARGV)
      @argv = argv
      @options = default_options
    end

    def run
      parse_options!
      return 0 if options[:help] || options[:version]

      issues = analyze
      issues = apply_baseline(issues) if options[:baseline]

      if options[:suggest_fixes]
        fixer = AutoFixer.new(issues)
        fixer.suggest
        return 0
      end

      if options[:fix]
        fixer = AutoFixer.new(issues, interactive: !options[:force])
        fixer.run
        return 0
      end

      output_report(issues)
      exit_code(issues)
    end

    private

    def default_options
      {
        paths: [],
        format: :console,
        exclude: [],
        only: [],
        min_severity: nil,
        fail_on_issues: true,
        colorize: $stdout.tty?,
        help: false,
        version: false,
        suggest_fixes: false,
        fix: false,
        force: false,
        baseline: nil
      }
    end

    def parse_options!
      parser.parse!(argv)
      options[:paths] = argv.empty? ? [EagerEye.configuration.app_path] : argv
    rescue OptionParser::InvalidOption => e
      warn "Error: #{e.message}"
      warn parser
      exit 1
    end

    def parser
      @parser ||= OptionParser.new do |opts|
        opts.banner = "Usage: eager_eye [options] [paths...]"
        opts.separator ""
        opts.separator "Options:"

        add_output_options(opts)
        add_filter_options(opts)
        add_behavior_options(opts)
        add_info_options(opts)
        add_fix_options(opts)
      end
    end

    def add_output_options(opts)
      opts.on("-f", "--format FORMAT", %i[console json], "Output format (console, json)") do |format|
        options[:format] = format
      end

      opts.on("--no-color", "Disable colored output") do
        options[:colorize] = false
      end
    end

    def add_filter_options(opts)
      opts.on("-e", "--exclude PATTERN", "Exclude files matching pattern") do |pattern|
        options[:exclude] << pattern
      end

      opts.on("-o", "--only DETECTORS", "Run only specified detectors (comma-separated)") do |detectors|
        options[:only] = detectors.split(",").map(&:strip).map(&:to_sym)
      end

      opts.on("-s", "--min-severity LEVEL", %i[info warning error],
              "Minimum severity to report (info, warning, error)") do |level|
        options[:min_severity] = level
      end
    end

    def add_behavior_options(opts)
      opts.on("--no-fail", "Exit with 0 even if issues found") do
        options[:fail_on_issues] = false
      end

      opts.on("--baseline FILE",
              "Compare against a previous JSON report; only show issues NOT in baseline") do |path|
        options[:baseline] = path
      end
    end

    def add_info_options(opts)
      opts.on("-v", "--version", "Show version") do
        puts "EagerEye #{EagerEye::VERSION}"
        options[:version] = true
      end

      opts.on("-h", "--help", "Show this help message") do
        puts opts
        options[:help] = true
      end
    end

    def add_fix_options(opts)
      opts.separator ""
      opts.separator "Auto-fix options (experimental):"

      opts.on("--suggest-fixes", "Show auto-fix suggestions") do
        options[:suggest_fixes] = true
      end

      opts.on("--fix", "Apply auto-fixes interactively") do
        options[:fix] = true
      end

      opts.on("--force", "Apply fixes without confirmation (use with --fix)") do
        options[:force] = true
      end
    end

    def analyze
      configure_from_options!
      Analyzer.new(paths: options[:paths]).run
    end

    def configure_from_options!
      EagerEye.configure do |config|
        config.excluded_paths += options[:exclude]
        config.enabled_detectors = options[:only] unless options[:only].empty?
        config.min_severity = options[:min_severity] if options[:min_severity]
      end
    end

    def output_report(issues)
      reporter = create_reporter(issues)
      puts reporter.report
    end

    def create_reporter(issues)
      case options[:format]
      when :json
        Reporters::Json.new(issues, pretty: true)
      else
        Reporters::Console.new(issues, colorize: options[:colorize])
      end
    end

    def exit_code(issues)
      options[:fail_on_issues] && issues.any? ? 1 : 0
    end

    def apply_baseline(issues)
      Baseline.filter(issues, options[:baseline])
    rescue Baseline::InvalidBaselineError => e
      warn "Error: #{e.message}"
      exit 1
    end
  end
end
