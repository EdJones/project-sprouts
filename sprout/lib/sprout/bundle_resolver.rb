# Taken from http://github.com/carlhuda/bundler
module Gem
  class Dependency
    def required_by
      @required_by ||= []
    end
  end
  class Specification
    def required_by
      @required_by ||= []
    end
  end
end

module Sprout

  class Index
    def self.from_installed_gems
      #Source::SystemGems.new.specs
      index = Index.new
      Gem::cache.each do |name, spec|
        index << spec
      end
      index
    end

    def self.from_cached_specs(path)
    #  index = Index.new
    #  Sprout::cache
    #  Dir["#{path}/*.gem"].each do |gemfile|
    #    spec = Gem::Format.from_file_by_path(gemfile).spec
    #    index << spec
    #  end

    #  index
    end

    def initialize
      @cache = {}
      @specs = Hash.new { |h,k| h[k] = [] }
    end

    def initialize_copy(o)
      super
      @cache = {}
      @specs = Hash.new { |h,k| h[k] = [] }
      merge!(o)
    end

    def empty?
      each { return false }
      true
    end

    def search(query)
      case query
      when Gem::Specification then search_by_spec(query)
      when String then @specs[query]
      else search_by_dependency(query)
      end
    end

    alias [] search

    def <<(spec)
      arr = @specs[spec.name]

      arr.delete_if do |s|
        s.version == spec.version && s.platform == spec.platform
      end

      arr << spec
      spec
    end

    def each(&blk)
      @specs.values.each do |specs|
        specs.each(&blk)
      end
    end

    def merge!(other)
      other.each do |spec|
        self << spec
      end
      self
    end

    def merge(other)
      dup.merge!(other)
    end

    def freeze
      @specs.each do |k,v|
        v.freeze
      end
      super
    end

    private

    def search_by_spec(spec)
      @specs[spec.name].select { |s| s.version == spec.version }
    end

    def search_by_dependency(dependency)
      @cache[dependency.hash] ||= begin
        specs = @specs[dependency.name]

        #wants_prerelease = dependency.requirement.prerelease?
        #only_prerelease  = specs.all? {|spec| spec.version.prerelease? }
        found = specs.select { |spec| dependency =~ spec }

        #unless wants_prerelease || only_prerelease
        #  found.reject! { |spec| spec.version.prerelease? }
        #end

        found.sort_by {|s| [s.version, s.platform.to_s == 'ruby' ? "\\0" : s.platform.to_s] }
      end

    end

  end

  class Resolver
    attr_reader :errors

    # Figures out the best possible configuration of gems that satisfies
    # the list of passed dependencies and any child dependencies without
    # causing any gem activation errors.
    #
    # ==== Parameters
    # *dependencies<Gem::Dependency>:: The list of dependencies to resolve
    #
    # ==== Returns
    # <GemBundle>,nil:: If the list of dependencies can be resolved, a
    #   collection of gemspecs is returned. Otherwise, nil is returned.
    def self.resolve(requirements, index, source_requirements = {})
      resolver = new(index, source_requirements)
      result = catch(:success) do
        resolver.resolve(requirements, {})
        output = resolver.errors.inject("") do |o, (conflict, (origin, requirement))|
          if origin
            o << "  Conflict on: #{conflict.inspect}:\\n"
            o << "    * #{conflict} (#{origin.version}) activated by #{origin.required_by.first}\\n"
            o << "    * #{requirement} required by #{requirement.required_by.first}\\n"
          else
            o << "  #{requirement} not found in any of the sources\\n"
            o << "      required by #{requirement.required_by.first}\\n"
          end
        o << "    All possible versions of origin requirements conflict."
        end
        raise VersionConflict, "No compatible versions could be found for required dependencies:\\n  #{output}"
        nil
      end
      if result
        # Order gems in order of dependencies. Every gem's dependency is at
        # a smaller index in the array.
        ordered = []
        result.values.each do |spec1|
          index = nil
          place = ordered.detect do |spec2|
            spec1.dependencies.any? { |d| d.name == spec2.name }
          end
          place ?
            ordered.insert(ordered.index(place), spec1) :
            ordered << spec1
        end
        ordered.reverse
      end
    end

    def self.resolve_libraries(library_names)
      index = Index.from_installed_gems
      lib_specs = library_names.map {|lib| Sprout.find_gem_spec "sprout-#{lib}-library" }
      resolved_specs = resolve lib_specs, index
      library_names_with_dependencies = []
      resolved_specs.each do |l|
        if l.name =~ /\Asprout-(.*)-library\Z/
          library_names_with_dependencies << $1
        end
      end
      library_names_with_dependencies
    end

    def initialize(index, source_requirements)
      @errors = {}
      @stack  = []
      @index  = index
      @source_requirements = source_requirements
    end

    def debug
      puts yield if defined?($debug) && $debug
    end

    def resolve(reqs, activated)
      # If the requirements are empty, then we are in a success state. Aka, all
      # gem dependencies have been resolved.
      throw :success, activated if reqs.empty?

      debug { STDIN.gets ; print "\\e[2J\\e[f" ; "==== Iterating ====\\n\\n" }

      # Sort dependencies so that the ones that are easiest to resolve are first.
      # Easiest to resolve is defined by:
      #   1) Is this gem already activated?
      #   2) Do the version requirements include prereleased gems?
      #   3) Sort by number of gems available in the source.
      reqs = reqs.sort_by do |a|
        [ activated[a.name] ? 0 : 1,
          #a.requirement.prerelease? ? 0 : 1,
          @errors[a.name]   ? 0 : 1,
          activated[a.name] ? 0 : search(a).size ]
      end

      debug { "Activated:\\n" + activated.values.map { |a| "  #{a.name} (#{a.version})" }.join("\\n") }
      debug { "Requirements:\\n" + reqs.map { |r| "  #{r.name} (#{r.requirement})"}.join("\\n") }

      activated = activated.dup
      # Pull off the first requirement so that we can resolve it
      current   = reqs.shift

      debug { "Attempting:\\n  #{current.name} (#{current.requirement})"}

      # Check if the gem has already been activated, if it has, we will make sure
      # that the currently activated gem satisfies the requirement.
      if existing = activated[current.name]
        if current.requirement.satisfied_by?(existing.version)
          debug { "    * [SUCCESS] Already activated" }
          @errors.delete(existing.name)
          # Since the current requirement is satisfied, we can continue resolving
          # the remaining requirements.
          resolve(reqs, activated)
        else
          debug { "    * [FAIL] Already activated" }
          @errors[existing.name] = [existing, current]
          debug { current.required_by.map {|d| "      * #{d.name} (#{d.requirement})" }.join("\\n") }
          # debug { "    * All current conflicts:\\n" + @errors.keys.map { |c| "      - #{c}" }.join("\\n") }
          # Since the current requirement conflicts with an activated gem, we need
          # to backtrack to the current requirement's parent and try another version
          # of it (maybe the current requirement won't be present anymore). If the
          # current requirement is a root level requirement, we need to jump back to
          # where the conflicting gem was activated.
          parent = current.required_by.last || existing.required_by.last
          # We track the spot where the current gem was activated because we need
          # to keep a list of every spot a failure happened.
          debug { "    -> Jumping to: #{parent.name}" }
          throw parent.name, existing.required_by.last.name
        end
      else
        # There are no activated gems for the current requirement, so we are going
        # to find all gems that match the current requirement and try them in decending
        # order. We also need to keep a set of all conflicts that happen while trying
        # this gem. This is so that if no versions work, we can figure out the best
        # place to backtrack to.
        conflicts = Set.new

        # Fetch all gem versions matching the requirement
        #
        # TODO: Warn / error when no matching versions are found.
        matching_versions = search(current)

        if matching_versions.empty?
          if current.required_by.empty?
            if current.source
              name = current.name
              versions = @source_requirements[name][name].map { |s| s.version }
              message  = "Could not find gem '#{current}' in #{current.source}.\\n"
              if versions.any?
                message << "Source contains '#{current.name}' at: #{versions.join(', ')}"
              else
                message << "Source does not contain any versions of '#{current}'"
              end

              raise GemNotFound, message
            else
              raise GemNotFound, "Could not find gem '#{current}' in any of the sources."
            end
            location = current.source ? current.source.to_s : "any of the sources"
            raise GemNotFound, "Could not find gem '#{current}' in #{location}.\\n" 
          else
            @errors[current.name] = [nil, current]
          end
        end

        matching_versions.reverse_each do |spec|
          conflict = resolve_requirement(spec, current, reqs.dup, activated.dup)
          conflicts << conflict if conflict
        end
        # If the current requirement is a root level gem and we have conflicts, we
        # can figure out the best spot to backtrack to.
        if current.required_by.empty? && !conflicts.empty?
          # Check the current "catch" stack for the first one that is included in the
          # conflicts set. That is where the parent of the conflicting gem was required.
          # By jumping back to this spot, we can try other version of the parent of
          # the conflicting gem, hopefully finding a combination that activates correctly.
          @stack.reverse_each do |savepoint|
            if conflicts.include?(savepoint)
              debug { "    -> Jumping to: #{savepoint}" }
              throw savepoint
            end
          end
        end
      end
    end

    def resolve_requirement(spec, requirement, reqs, activated)
      # We are going to try activating the spec. We need to keep track of stack of
      # requirements that got us to the point of activating this gem.
      spec.required_by.replace requirement.required_by
      spec.required_by << requirement

      activated[spec.name] = spec
      debug { "  Activating: #{spec.name} (#{spec.version})" }
      debug { spec.required_by.map { |d| "    * #{d.name} (#{d.requirement})" }.join("\\n") }

      # Now, we have to loop through all child dependencies and add them to our
      # array of requirements.
      debug { "    Dependencies"}
      spec.dependencies.each do |dep|
        next if dep.type == :development
        debug { "    * #{dep.name} (#{dep.requirement})" }
        dep.required_by.replace(requirement.required_by)
        dep.required_by << requirement
        reqs << dep
      end

      # We create a savepoint and mark it by the name of the requirement that caused
      # the gem to be activated. If the activated gem ever conflicts, we are able to
      # jump back to this point and try another version of the gem.
      length = @stack.length
      @stack << requirement.name
      retval = catch(requirement.name) do
        resolve(reqs, activated)
      end
      # Since we're doing a lot of throw / catches. A push does not necessarily match
      # up to a pop. So, we simply slice the stack back to what it was before the catch
      # block.
      @stack.slice!(length..-1)
      retval
    end

    def search(dep)
      index = @source_requirements[dep.name] || @index
      index.search(dep)
    end

  end
end
