# frozen_string_literal: true

module EagerEye
  class AutoFixer
    def initialize(issues, interactive: true)
      @issues = issues
      @interactive = interactive
      @files_cache = {}
    end

    def run
      fixes = collect_fixes
      return puts "No auto-fixable issues found." if fixes.empty?

      @interactive ? apply_interactively(fixes) : apply_all(fixes)
    end

    def suggest
      fixes = collect_fixes
      return puts "No auto-fixable issues found." if fixes.empty?

      fixes.group_by { |f| f[:file] }.each do |file, file_fixes|
        puts "\n#{file}:"
        file_fixes.each do |fix|
          puts "  Line #{fix[:line]}:"
          puts "    - #{fix[:original]}"
          puts "    + #{fix[:fixed]}"
        end
      end
    end

    private

    def collect_fixes
      @issues.filter_map do |issue|
        fixer = FixerRegistry.fixer_for(issue, read_file(issue.file_path))
        fixer&.fixable? ? fixer.diff : nil
      end
    end

    def read_file(path)
      @files_cache[path] ||= File.read(path)
    end

    def apply_interactively(fixes)
      fixes.each do |fix|
        puts "\n#{fix[:file]}:#{fix[:line]}"
        puts "  - #{fix[:original]}"
        puts "  + #{fix[:fixed]}"
        print "Apply this fix? [y/n/q] "

        response = $stdin.gets&.chomp&.downcase
        case response
        when "y"
          apply_fix(fix)
          puts "  Applied"
        when "q"
          puts "Aborted."
          break
        else
          puts "  Skipped"
        end
      end
    end

    def apply_all(fixes)
      fixes.group_by { |f| f[:file] }.each do |file, file_fixes|
        lines = File.readlines(file)

        file_fixes.sort_by { |f| -f[:line] }.each do |fix|
          lines[fix[:line] - 1] = "#{fix[:fixed]}\n"
        end

        File.write(file, lines.join)
        puts "Fixed #{file_fixes.size} issue(s) in #{file}"
      end
    end

    def apply_fix(fix)
      lines = File.readlines(fix[:file])
      lines[fix[:line] - 1] = "#{fix[:fixed]}\n"
      File.write(fix[:file], lines.join)
    end
  end
end
