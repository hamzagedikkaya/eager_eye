# frozen_string_literal: true

require_relative "source_parser"

module EagerEye
  class Analyzer
    DETECTOR_CLASSES = {
      loop_association: Detectors::LoopAssociation,
      serializer_nesting: Detectors::SerializerNesting,
      missing_counter_cache: Detectors::MissingCounterCache,
      custom_method_query: Detectors::CustomMethodQuery,
      count_in_iteration: Detectors::CountInIteration,
      callback_query: Detectors::CallbackQuery,
      pluck_to_array: Detectors::PluckToArray,
      delegation_n_plus_one: Detectors::DelegationNPlusOne,
      decorator_n_plus_one: Detectors::DecoratorNPlusOne,
      scope_chain_n_plus_one: Detectors::ScopeChainNPlusOne,
      validation_n_plus_one: Detectors::ValidationNPlusOne
    }.freeze

    DETECTOR_EXTRA_ARGS = {
      Detectors::LoopAssociation => %i[association_preloads association_names method_queries associations_by_model
                                       all_columns],
      Detectors::SerializerNesting => %i[association_names method_queries serializer_usage all_columns],
      Detectors::MissingCounterCache => %i[association_names],
      Detectors::DecoratorNPlusOne => %i[association_names method_queries],
      Detectors::CustomMethodQuery => %i[method_queries associations_by_model all_columns],
      Detectors::DelegationNPlusOne => %i[delegation_maps],
      Detectors::ScopeChainNPlusOne => %i[scope_maps],
      Detectors::ValidationNPlusOne => %i[uniqueness_models]
    }.freeze

    attr_reader :paths, :issues, :association_preloads, :association_names, :method_queries, :delegation_maps,
                :scope_maps, :uniqueness_models, :associations_by_model, :all_columns, :columns_by_model,
                :serializer_usage, :skipped_files

    def initialize(paths: nil)
      @paths = Array(paths || EagerEye.configuration.app_path)
      @issues = []
      @association_preloads = {}
      @association_names = Set.new
      @associations_by_model = {}
      @method_queries = {}
      @delegation_maps = {}
      @scope_maps = {}
      @uniqueness_models = Set.new
      @all_columns = Set.new
      @columns_by_model = {}
      @serializer_usage = SerializerUsageParser.new
      @skipped_files = {}
    end

    def run
      @issues = []
      @skipped_files = {}
      collect_schema
      collect_model_metadata
      collect_serializer_usage
      ruby_files.each { |file_path| analyze_file(file_path) }
      @issues
    end

    private

    def collect_schema
      schema = SchemaParser.new
      return unless schema.parse_from_path(@paths[0])

      @all_columns = schema.all_columns
      @columns_by_model = schema.columns_by_model
    end

    # Pre-pass over every analyzed file to learn how serializers are rendered
    # (eager-loaded associations, single-record vs collection). The detector uses
    # this to stay silent on associations preloaded at all render sites.
    def collect_serializer_usage
      ruby_files.each do |file_path|
        ast = parse_source(File.read(file_path), file_path)
        @serializer_usage.parse_file(ast) if ast
      rescue Errno::ENOENT, Errno::EACCES
        next
      end
    end

    def collect_model_metadata
      model_files.each do |file_path|
        ast = parse_source(File.read(file_path), file_path)
        next unless ast

        model_name = extract_model_name(file_path)

        assoc_parser = AssociationParser.new
        assoc_parser.parse_model(ast, model_name)
        @association_preloads.merge!(assoc_parser.preloaded_associations)
        @association_names.merge(assoc_parser.association_names)
        assoc_parser.associations_by_model.each do |m, set|
          (@associations_by_model[m] ||= Set.new).merge(set)
        end

        deleg_parser = DelegationParser.new
        deleg_parser.parse_model(ast, model_name)
        @delegation_maps.merge!(deleg_parser.delegation_maps)

        scope_parser = ScopeParser.new
        scope_parser.parse_model(ast, model_name)
        @scope_maps.merge!(scope_parser.scope_maps)

        validation_parser = ValidationParser.new
        validation_parser.parse_model(ast, model_name)
        @uniqueness_models.merge(validation_parser.uniqueness_models)

        method_query_parser = MethodQueryParser.new
        method_query_parser.parse_model(ast, model_name)
        @method_queries.merge!(method_query_parser.method_queries)
      rescue Errno::ENOENT, Errno::EACCES
        next
      end
    end

    def model_files
      Dir.glob(File.join(@paths[0], "models", "**", "*.rb"))
    end

    def extract_model_name(file_path)
      name = File.basename(file_path, ".rb")
      name.respond_to?(:camelize) ? name.camelize : name.split("_").map(&:capitalize).join
    end

    def ruby_files
      paths.flat_map { |path| resolve_path(path) }.reject { |file| excluded?(file) }
    end

    def resolve_path(path)
      return [path] if File.file?(path)
      return Dir.glob(File.join(path, "**", "*.{rb,jbuilder}")) if File.directory?(path)

      Dir.glob(path)
    end

    def excluded?(file_path)
      EagerEye.configuration.excluded_paths.any? do |pattern|
        File.fnmatch?(pattern, file_path, File::FNM_PATHNAME)
      end
    end

    def analyze_file(file_path)
      source = File.read(file_path)
      ast = parse_source(source, file_path)
      return unless ast

      comment_parser = CommentParser.new(source)
      min_severity = EagerEye.configuration.min_severity

      enabled_detectors.each do |detector|
        file_issues = detector.detect(*detector_args(detector, ast, file_path))
        @issues.concat(file_issues.select do |issue|
          !comment_parser.disabled_at?(issue.line_number, issue.detector) &&
            issue.meets_minimum_severity?(min_severity)
        end)
      end
    rescue Errno::ENOENT, Errno::EACCES => e
      warn "EagerEye: Could not read file #{file_path}: #{e.message}"
    end

    # A file the parser cannot handle (syntax error, binary literal whose
    # escapes are invalid UTF-8, ...) is skipped from analysis entirely. Each
    # such file is recorded in #skipped_files and warned about exactly once,
    # even though every file is parsed by multiple passes.
    def parse_source(source, file_path)
      SourceParser.parse(source, file_path)
    rescue Parser::SyntaxError, Parser::UnknownEncodingInMagicComment, EncodingError => e
      register_unparseable(file_path, e.message)
      nil
    end

    def register_unparseable(file_path, message)
      return if @skipped_files.key?(file_path)

      @skipped_files[file_path] = message
      warn "EagerEye: Skipped unparseable file #{file_path}: #{message}"
    end

    def detector_args(detector, ast, file_path)
      extra = DETECTOR_EXTRA_ARGS.find { |klass, _| detector.is_a?(klass) }&.last || []
      [ast, file_path, *extra.map { |name| instance_variable_get(:"@#{name}") }]
    end

    def enabled_detectors
      @enabled_detectors ||= EagerEye.configuration.enabled_detectors.filter_map do |name|
        DETECTOR_CLASSES[name]&.new
      end
    end
  end
end
