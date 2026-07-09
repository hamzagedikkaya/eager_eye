# frozen_string_literal: true

require_relative "source_parser"

module EagerEye
  # Parses db/schema.rb to learn the real column names of each table. Columns are
  # the dominant false-positive source: when a receiver's model can't be inferred,
  # the name heuristics flag any method whose name collides with an association
  # name — but a DB column (`comsn_rate`, `vat_rate`, `service_fee_rate`) is never
  # an association. Knowing the column names lets the detectors disambiguate.
  #
  # Schema lookup walks up from the analyzed path so `eager_eye app/` still finds
  # `<root>/db/schema.rb`. Parsing is AST-based (a `create_table "x" do |t| ... end`
  # block whose body holds `t.<type> "col"` / `t.column "col"` / `t.references "y"`).
  class SchemaParser
    COLUMN_DEFINERS = %i[
      string text integer bigint float decimal boolean date datetime time timestamp
      binary json jsonb uuid inet cidr money hstore citext virtual primary_key column
    ].freeze
    REFERENCE_DEFINERS = %i[references belongs_to].freeze

    attr_reader :columns_by_table, :all_columns

    def initialize
      @columns_by_table = {}
      @all_columns = Set.new
    end

    # Returns true if a schema was found and parsed.
    def parse_from_path(start_path)
      schema = locate_schema(start_path)
      return false unless schema

      ast = parse(File.read(schema), schema)
      return false unless ast

      walk(ast)
      true
    rescue Errno::ENOENT, Errno::EACCES
      false
    end

    # Column names mapped onto the model a table name classifies to
    # ("eod_items" -> "EodItem"). Used for per-model column resolution.
    def columns_by_model
      @columns_by_model ||= @columns_by_table.transform_keys { |table| classify(table) }
    end

    private

    def locate_schema(start_path)
      dir = File.expand_path(File.directory?(start_path) ? start_path : File.dirname(start_path))
      12.times do
        candidate = File.join(dir, "db", "schema.rb")
        return candidate if File.file?(candidate)

        parent = File.dirname(dir)
        break if parent == dir

        dir = parent
      end
      nil
    end

    # An unparseable schema silently disables the column disambiguation that
    # filters most false positives, so the failure must not be swallowed.
    def parse(source, file_path)
      SourceParser.parse(source, file_path)
    rescue Parser::SyntaxError, Parser::UnknownEncodingInMagicComment, EncodingError => e
      warn "EagerEye: Could not parse schema #{file_path}: #{e.message} (schema-aware column checks disabled)"
      nil
    end

    def walk(node)
      return unless node.is_a?(Parser::AST::Node)

      capture_create_table(node) if create_table_block?(node)
      node.children.each { |child| walk(child) }
    end

    def create_table_block?(node)
      node.type == :block && node.children[0]&.type == :send &&
        node.children[0].children[1] == :create_table
    end

    def capture_create_table(block_node)
      table = string_arg(block_node.children[0])
      return unless table

      cols = (@columns_by_table[table] ||= Set.new)
      collect_columns(block_node.children[2], cols)
    end

    def collect_columns(body, cols)
      return unless body.is_a?(Parser::AST::Node)

      add_column_from_send(body, cols) if body.type == :send
      body.children.each { |child| collect_columns(child, cols) }
    end

    def add_column_from_send(node, cols)
      method = node.children[1]
      name = string_arg(node)
      return unless name

      if COLUMN_DEFINERS.include?(method)
        register(cols, name)
      elsif REFERENCE_DEFINERS.include?(method)
        register(cols, "#{name}_id")
      end
    end

    def register(cols, name)
      sym = name.to_sym
      cols << sym
      @all_columns << sym
    end

    def string_arg(node)
      return unless node.is_a?(Parser::AST::Node)

      node.children[2..]&.find { |a| a.is_a?(Parser::AST::Node) && a.type == :str }&.children&.first
    end

    def classify(table)
      base = table.to_s
      singular = base.respond_to?(:singularize) ? base.singularize : base.sub(/s\z/, "")
      singular.split("_").map(&:capitalize).join
    end
  end
end
