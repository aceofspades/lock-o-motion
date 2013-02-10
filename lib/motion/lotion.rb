module Lotion
  extend self

  def require(path)
    return if required.include? path
    required << path

    if absolute_path = resolve(path)
      unless (IGNORED_REQUIRES + REQUIRED).include?(absolute_path)
        puts "   Warning Add the following with Lotion.setup block: app.require \"#{path}\"".yellow
      end
    else
      raise LoadError, "cannot load such file -- #{path}"
    end
  end

  def warn(*args)
    message = begin
      if args.size == 1
        args.first
      else
        object, method, caller = *args
        "Called #{object}.#{method} from #{resolve caller[0]}"
      end
    end
    puts "   Warning #{message}".yellow
  end

private

  def required
    @required ||= []
  end

  def resolve(path)
    if path.match /^\//
      path
    else
      (LOAD_PATHS + GEM_PATHS).each do |load_path|
        if File.exists?(absolute_path = "#{load_path}/#{path}.rb") ||
           File.exists?(absolute_path = "#{load_path}/#{path}.bundle")
          return (absolute_path if absolute_path.match(/\.rb$/))
        end
      end
      nil
    end
  end

end