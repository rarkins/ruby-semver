# frozen_string_literal: false
require_relative "./version"
# require "rubygems/deprecate" # removed for JavaScript compatibility

# If we're being loaded after yaml was already required, then
# load our yaml + workarounds now.
# Gem.load_yaml if defined? ::YAML # removed for JavaScript compatibility

##
# A Requirement is a set of one or more version restrictions. It supports a
# few (<tt>=, !=, >, <, >=, <=, ~></tt>) different restriction operators.
#
# See GemVersion for a description on how versions and requirements work
# together in RubyGems.

# Class name flattened from Gem::Requirement to simplify compiled JavaScript
class GemRequirement
  OPS = { #:nodoc:
    "="  =>  lambda { |v, r| v == r },
    "!=" =>  lambda { |v, r| v != r },
    ">"  =>  lambda { |v, r| v >  r },
    "<"  =>  lambda { |v, r| v <  r },
    ">=" =>  lambda { |v, r| v >= r },
    "<=" =>  lambda { |v, r| v <= r },
    "~>" =>  lambda { |v, r| v >= r && v.release < r.bump }
  }

  SOURCE_SET_REQUIREMENT = Struct.new(:for_lockfile).new "!" # :nodoc:

  quoted  = OPS.keys.map { |k| Regexp.quote k }.join "|"
  PATTERN_RAW = "\\s*(#{quoted})?\\s*(#{GemVersion::VERSION_PATTERN})\\s*" # :nodoc:

  ##
  # A regular expression that matches a requirement

  # Altered for JavaScript compatibility
  # PATTERN = /\A#{PATTERN_RAW}\z/
  PATTERN = /^#{PATTERN_RAW}$/


  ##
  # The default requirement matches any version

  DefaultRequirement = [">=", GemVersion.new(0)]

  ##
  # Raised when a bad requirement is encountered

  class BadRequirementError < ArgumentError; end

  ##
  # Factory method to create a GemRequirement object.  Input may be
  # a Version, a String, or nil.  Intended to simplify client code.
  #
  # If the input is "weird", the default version requirement is
  # returned.

  def self.create input
    case input
    when GemRequirement then
      input
    when GemVersion, Array then
      new input
    when '!' then
      source_set
    else
      if input.respond_to? :to_str then
        new [input.to_str]
      else
        default
      end
    end
  end

  ##
  # A default "version requirement" can surely _only_ be '>= 0'.

  def self.default
    new '>= 0'
  end

  ###
  # A source set requirement, used for Gemfiles and lockfiles

  def self.source_set # :nodoc:
    SOURCE_SET_REQUIREMENT
  end

  ##
  # Parse +obj+, returning an <tt>[op, version]</tt> pair. +obj+ can
  # be a String or a GemVersion.
  #
  # If +obj+ is a String, it can be either a full requirement
  # specification, like <tt>">= 1.2"</tt>, or a simple version number,
  # like <tt>"1.2"</tt>.
  #
  #     parse("> 1.0")                 # => [">", GemVersion.new("1.0")]
  #     parse("1.0")                   # => ["=", GemVersion.new("1.0")]
  #     parse(GemVersion.new("1.0")) # => ["=,  GemVersion.new("1.0")]

  def self.parse obj
    return ["=", obj] if GemVersion === obj

    unless PATTERN =~ obj.to_s
      raise BadRequirementError, "Illformed requirement [#{obj.inspect}]"
    end

    if $1 == ">=" && $2 == "0"
      DefaultRequirement
    else
      [$1 || "=", GemVersion.new($2)]
    end
  end

  ##
  # An array of requirement pairs. The first element of the pair is
  # the op, and the second is the GemVersion.

  attr_reader :requirements #:nodoc:

  ##
  # Constructs a requirement from +requirements+. Requirements can be
  # Strings, GemVersions, or Arrays of those. +nil+ and duplicate
  # requirements are ignored. An empty set of +requirements+ is the
  # same as <tt>">= 0"</tt>.

  def initialize *requirements
    requirements = requirements.flatten
    requirements.compact!
    requirements.uniq!

    if requirements.empty?
      @requirements = [DefaultRequirement]
    else
      @requirements = requirements.map! { |r| self.class.parse r }
    end
  end

  ##
  # Concatenates the +new+ requirements onto this requirement.

  def concat new
    new = new.flatten
    new.compact!
    new.uniq!
    new = new.map { |r| self.class.parse r }

    @requirements.concat new
  end

  ##
  # Formats this requirement for use in a GemRequestSet::Lockfile.

  def for_lockfile # :nodoc:
    return if [DefaultRequirement] == @requirements

    list = requirements.sort_by { |_, version|
      version
    }.map { |op, version|
      "#{op} #{version}"
    }.uniq

    " (#{list.join ', '})"
  end

  ##
  # true if this gem has no requirements.

  def none?
    if @requirements.size == 1
      @requirements[0] == DefaultRequirement
    else
      false
    end
  end

  ##
  # true if the requirement is for only an exact version

  def exact?
    return false unless @requirements.size == 1
    @requirements[0][0] == "="
  end

  def as_list # :nodoc:
    requirements.map { |op, version| "#{op} #{version}" }.sort
  end

  def hash # :nodoc:
    requirements.sort.hash
  end

  def marshal_dump # :nodoc:
    fix_syck_default_key_in_requirements

    [@requirements]
  end

  def marshal_load array # :nodoc:
    @requirements = array[0]

    fix_syck_default_key_in_requirements
  end

  def yaml_initialize(tag, vals) # :nodoc:
    vals.each do |ivar, val|
      instance_variable_set "@#{ivar}", val
    end

    Gem.load_yaml
    fix_syck_default_key_in_requirements
  end

  def init_with coder # :nodoc:
    yaml_initialize coder.tag, coder.map
  end

  def to_yaml_properties # :nodoc:
    ["@requirements"]
  end

  def encode_with coder # :nodoc:
    coder.add 'requirements', @requirements
  end

  ##
  # A requirement is a prerelease if any of the versions inside of it
  # are prereleases

  def prerelease?
    requirements.any? { |r| r.last.prerelease? }
  end

  def pretty_print q # :nodoc:
    q.group 1, 'GemRequirement.new(', ')' do
      q.pp as_list
    end
  end

  ##
  # True if +version+ satisfies this Requirement.

  def satisfied_by? version
    raise ArgumentError, "Need a GemVersion: #{version.inspect}" unless
      GemVersion === version
    # #28965: syck has a bug with unquoted '=' YAML.loading as YAML::DefaultKey
    requirements.all? { |op, rv| (OPS[op] || OPS["="]).call version, rv }
  end

  alias :=== :satisfied_by?
  alias :=~ :satisfied_by?

  ##
  # True if the requirement will not always match the latest version.

  def specific?
    return true if @requirements.length > 1 # GIGO, > 1, > 2 is silly

    not %w[> >=].include? @requirements.first.first # grab the operator
  end

  def to_s # :nodoc:
    as_list.join ", "
  end

  def == other # :nodoc:
    GemRequirement === other and to_s == other.to_s
  end

  private

  def fix_syck_default_key_in_requirements # :nodoc:
    Gem.load_yaml

    # Fixup the Syck DefaultKey bug
    @requirements.each do |r|
      if r[0].kind_of? GemSyckDefaultKey
        r[0] = "="
      end
    end
  end
end

class GemVersion
  # This is needed for compatibility with older yaml
  # gemspecs.

  Requirement = GemRequirement # :nodoc:
end
