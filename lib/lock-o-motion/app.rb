module LockOMotion
  class App

    GEM_LOTION  = ".lotion.rb"
    USER_LOTION =  "lotion.rb"

    def self.setup(app, &block)
      new(app).send :setup, &block
    end

    def initialize(app)
      @app = app
    end

    def require(path, internal = false)
      Kernel.require path, internal
    end

    def ignore_require(path)
      @ignored_requires << path
    end

    def dependency(call, path, internal = false)
      call = "BUNDLER" if call.match(/\bbundler\b/)
      if call == __FILE__
        call = internal ? "GEM_LOTION" : "USER_LOTION"
      end

      ($: + LockOMotion.gem_paths).each do |load_path|
        if File.exists?(absolute_path = "#{load_path}/#{path}.bundle") ||
           File.exists?(absolute_path = "#{load_path}/#{path}.rb")
          if absolute_path.match(/\.rb$/)
            register_dependency call, absolute_path
            $:.unshift load_path unless $:.include?(load_path)
          else
            puts "   Warning #{call}\n           requires #{absolute_path}".red
          end
          return
        end
      end

      if path.match(/^\//) && File.exists?(path)
        register_dependency call, path
      else
        puts "   Warning Could not resolve dependency \"#{path}\"".red
      end
    end

  private

    def register_dependency(call, absolute_path)
      ((@dependencies[call] ||= []) << absolute_path).uniq!
    end

    def setup(&block)
      @files = []
      @dependencies = {}
      @ignored_requires = []

      Thread.current[:lotion_app] = self
      Kernel.instance_eval &hook
      Object.class_eval &hook

      Bundler.require :lotion
      require "colorize", true
      yield self if block_given?

      Kernel.instance_eval &unhook
      Object.class_eval &unhook
      Thread.current[:lotion_app] = nil

      bundler = @dependencies.delete("BUNDLER") || []
      gem_lotion = @dependencies.delete("GEM_LOTION") || []
      user_lotion = @dependencies.delete("USER_LOTION") || []

      gem_lotion.each do |file|
        default_files.each do |default_file|
          (@dependencies[default_file] ||= []) << file
        end
      end
      (bundler + user_lotion).each do |file|
        @dependencies[file] ||= []
        @dependencies[file] = default_files + @dependencies[file]
      end

      @files = (default_files + gem_lotion.sort + bundler.sort + (@dependencies.keys + @dependencies.values).flatten.sort + user_lotion.sort + @app.files).uniq
      @files << File.expand_path(USER_LOTION) if File.exists?(USER_LOTION)

      @app.files = @files
      @app.files_dependencies @dependencies
      write_lotion
    end

    def hook
      @hook ||= proc do
        def require_with_catch(path, internal = false)
          return if LockOMotion.skip?(path)
          if mock_path = LockOMotion.mock_path(path)
            path = mock_path
            internal = false
          end
          if caller[0].match(/^(.*\.rb)\b/)
            Thread.current[:lotion_app].dependency $1, path, internal
          end
          begin
            require_without_catch path
          rescue LoadError
            if gem_path = LockOMotion.gem_paths.detect{|x| File.exists? "#{x}/#{path}"}
              $:.unshift gem_path
              require_without_catch path
            end
          end
        end
        alias :require_without_catch :require
        alias :require :require_with_catch
      end
    end

    def unhook
      @unhook ||= proc do
        alias :require :require_without_catch
        undef :require_with_catch
        undef :require_without_catch
      end
    end

    def default_files
      @default_files ||= [
        File.expand_path("../../motion/core_ext.rb", __FILE__),
        File.expand_path("../../motion/lotion.rb", __FILE__),
        File.expand_path(GEM_LOTION)
      ]
    end

    def write_lotion
      FileUtils.rm GEM_LOTION if File.exists?(GEM_LOTION)
      File.open(GEM_LOTION, "w") do |file|
        file << <<-RUBY_CODE.gsub("          ", "")
          module Lotion
            FILES = #{pretty_inspect @files, 2}
            DEPENDENCIES = #{pretty_inspect @dependencies, 2}
            IGNORED_REQUIRES = #{pretty_inspect @ignored_requires, 2}
            USER_MOCKS = #{pretty_inspect USER_MOCKS, 2}
            GEM_MOCKS = #{pretty_inspect GEM_MOCKS, 2}
            LOAD_PATHS = #{pretty_inspect $:, 2}
            GEM_PATHS = #{pretty_inspect LockOMotion.gem_paths, 2}
            REQUIRED = #{pretty_inspect $", 2}
          end
        RUBY_CODE
      end
    end

    def pretty_inspect(object, indent = 0)
      if object.is_a?(Array)
        entries = object.collect{|x| "  #{pretty_inspect x, indent + 2}"}
        return "[]" if entries.empty?
        entries.each_with_index{|x, i| entries[i] = "#{x}," if i < entries.size - 1}
        ["[", entries, "]"].flatten.join "\n" + (" " * indent)
      elsif object.is_a?(Hash)
        entries = object.collect{|k, v| "  #{k.inspect} => #{pretty_inspect v, indent + 2}"}
        return "{}" if entries.empty?
        entries.each_with_index{|x, i| entries[i] = "#{x}," if i < entries.size - 1}
        ["{", entries, "}"].flatten.join "\n" + (" " * indent)
      else
        object.inspect
      end
    end

  end
end