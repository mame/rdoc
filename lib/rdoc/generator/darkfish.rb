# -*- mode: ruby; ruby-indent-level: 2; tab-width: 2 -*-

require 'pathname'
require 'fileutils'
require 'erb'

require 'rdoc/generator/markup'

##
# Darkfish RDoc HTML Generator
#
# $Id: darkfish.rb 52 2009-01-07 02:08:11Z deveiant $
#
# == Author/s
# * Michael Granger (ged@FaerieMUD.org)
#
# == Contributors
# * Mahlon E. Smith (mahlon@martini.nu)
# * Eric Hodel (drbrain@segment7.net)
#
# == License
#
# Copyright (c) 2007, 2008, Michael Granger. All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# * Redistributions of source code must retain the above copyright notice,
#   this list of conditions and the following disclaimer.
#
# * Redistributions in binary form must reproduce the above copyright notice,
#   this list of conditions and the following disclaimer in the documentation
#   and/or other materials provided with the distribution.
#
# * Neither the name of the author/s, nor the names of the project's
#   contributors may be used to endorse or promote products derived from this
#   software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
# SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
# CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
# OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#
class RDoc::Generator::Darkfish

  RDoc::RDoc.add_generator self

  module Options

    ##
    # Character-set for HTML output.  #encoding is peferred over #charset

    attr_accessor :charset

    ##
    # Old rdoc behavior: hyperlink all words that match a method name,
    # even if not preceded by '#' or '::'

    attr_accessor :hyperlink_all

    ##
    # Include line numbers in the source code

    attr_accessor :line_numbers

    ##
    # Name of the file, class or module to display in the initial index page (if
    # not specified the first file we encounter is used)

    attr_accessor :main_page

    ##
    # Include the '#' at the front of hyperlinked instance method names

    attr_accessor :show_hash

    ##
    # URL of the stylesheet to use. +nil+ by default.

    attr_accessor :stylesheet_url

    ##
    # The number of columns in a tab

    attr_accessor :tab_width

    ##
    # Template to be used when generating output

    attr_accessor :template

    ##
    # Documentation title

    attr_accessor :title

    ##
    # URL of web cvs frontend

    attr_accessor :webcvs

  end

  include ERB::Util

  ##
  # Subversion rev

  SVNRev = %$Rev: 52 $

  ##
  # Subversion ID

  SVNId = %$Id: darkfish.rb 52 2009-01-07 02:08:11Z deveiant $

  # Path to this file's parent directory. Used to find templates and other
  # resources.

  GENERATOR_DIR = File.join 'rdoc', 'generator'

  # Release Version

  VERSION = '1.1.6'

  # Directory where generated classes live relative to the root

  CLASS_DIR = nil

  # Directory where generated files live relative to the root

  FILE_DIR = nil

  # Standard generator factory method

  def self.for options
    new options
  end

  def self.setup_options options
    options.extend Options # HACK make this automatic

    opt = options.option_parser

    opt.separator nil
    opt.separator 'Darkfish generator options:'
    opt.separator nil

    opt.on("--charset=CHARSET", "-c",
           "Specifies the output HTML character-set.",
           "Use --encoding instead of --charset if",
           "available.") do |value|
      options.charset = value
    end

    opt.separator nil

    opt.on("--hyperlink-all", "-A",
           "Generate hyperlinks for all words that",
           "correspond to known methods, even if they",
           "do not start with '#' or '::' (legacy",
           "behavior).") do |value|
      options.hyperlink_all = value
    end

    opt.separator nil

    opt.on("--line-numbers", "-N",
           "Include line numbers in the source code.",
           "By default, only the number of the first",
           "line is displayed, in a leading comment.") do |value|
      options.line_numbers = value
    end

    opt.separator nil

    opt.on("--main=NAME", "-m",
           "NAME will be the initial page displayed.") do |value|
      options.main_page = value
    end

    opt.separator nil

    opt.on("--show-hash", "-H",
           "A name of the form #name in a comment is a",
           "possible hyperlink to an instance method",
           "name. When displayed, the '#' is removed",
           "unless this option is specified.") do |value|
      options.show_hash = value
    end

    opt.separator nil

    opt.on("--style=URL", "-s",
           "Specifies the URL of a stylesheet to use",
           "in lieu of the default stylesheet of the",
           "template.") do |value|
      options.stylesheet_url = value
    end

    opt.separator nil

    opt.on("--tab-width=WIDTH", "-w", OptionParser::DecimalInteger,
           "Set the width of tab characters.") do |value|
      options.tab_width = value
    end

    opt.separator nil

    opt.on("--template=NAME", "-T",
           "Set the template used when generating",
           "output. The default is 'TODO'.") do |value|
      options.template = value
    end

    opt.separator nil

    opt.on("--title=TITLE", "-t",
           "Set TITLE as the title for HTML output.") do |value|
      options.title = value
    end

    opt.separator nil

    opt.on("--webcvs=URL", "-W",
           "Specify a URL for linking to a web frontend",
           "to CVS. If the URL contains a '\%s', the",
           "name of the current file will be",
           "substituted; if the URL doesn't contain a",
           "'\%s', the filename will be appended to it.") do |value|
      options.webcvs = value
    end

    opt.separator nil
  end

  ##
  # Initialize a few instance variables before we start

  def initialize options
    @options = options

    template = @options.template || 'darkfish'

    template_dir = $LOAD_PATH.map do |path|
      File.join File.expand_path(path), GENERATOR_DIR, 'template', template
    end.find do |dir|
      File.directory? dir
    end

    raise RDoc::Error, "could not find template #{template.inspect}" unless
    template_dir

    @template_dir = Pathname.new File.expand_path(template_dir)

    @files      = nil
    @classes    = nil

    @basedir = Pathname.pwd.expand_path
  end

  ##
  # The output directory

  attr_reader :outputdir

  ##
  # Output progress information if debugging is enabled

  def debug_msg *msg
    return unless $DEBUG_RDOC
    $stderr.puts(*msg)
  end

  def class_dir
    CLASS_DIR
  end

  def file_dir
    FILE_DIR
  end

  ##
  # Create the directories the generated docs will live in if they don't
  # already exist.

  def gen_sub_directories
    @outputdir.mkpath
  end

  ##
  # Copy over the stylesheet into the appropriate place in the output
  # directory.

  def write_style_sheet
    debug_msg "Copying static files"
    options = { :verbose => $DEBUG_RDOC, :noop => @options.dry_run }

    FileUtils.cp @template_dir + 'rdoc.css', '.', options

    Dir[(@template_dir + "{js,images}/**/*").to_s].each do |path|
      next if File.directory? path
      next if File.basename(path) =~ /^\./

        dst = Pathname.new(path).relative_path_from @template_dir

      # I suck at glob
      dst_dir = dst.dirname
      FileUtils.mkdir_p dst_dir, options unless File.exist? dst_dir

      FileUtils.cp @template_dir + path, dst, options
    end
  end

  ##
  # Build the initial indices and output objects based on an array of TopLevel
  # objects containing the extracted information.

  def generate top_levels
    @outputdir = Pathname.new(@options.op_dir).expand_path(@basedir)

    @files = top_levels.sort
    @classes = RDoc::TopLevel.all_classes_and_modules.sort
    @methods = @classes.map { |m| m.method_list }.flatten.sort
    @modsort = get_sorted_module_list(@classes)

    # Now actually write the output
    write_style_sheet
    generate_index
    generate_class_files
    generate_file_files

  rescue StandardError => err
    debug_msg "%s: %s\n  %s" % [
      err.class.name, err.message, err.backtrace.join("\n  ")
    ]

    raise
  end

  protected

  ##
  # Return a list of the documented modules sorted by salience first, then
  # by name.

  def get_sorted_module_list(classes)
    nscounts = classes.inject({}) do |counthash, klass|
      top_level = klass.full_name.gsub(/::.*/, '')
      counthash[top_level] ||= 0
      counthash[top_level] += 1

      counthash
    end

    # Sort based on how often the top level namespace occurs, and then on the
    # name of the module -- this works for projects that put their stuff into
    # a namespace, of course, but doesn't hurt if they don't.
    classes.sort_by do |klass|
      top_level = klass.full_name.gsub( /::.*/, '' )
      [nscounts[top_level] * -1, klass.full_name]
    end.select do |klass|
      klass.document_self
    end
  end

  ##
  # Generate an index page which lists all the classes which are documented.

  def generate_index
    template_file = @template_dir + 'index.rhtml'
    return unless template_file.exist?

    debug_msg "Rendering the index page..."

    template_src = template_file.read
    template = ERB.new template_src, nil, '<>'
    template.filename = template_file.to_s
    context = binding

    output = nil

    begin
      output = template.result context
    rescue NoMethodError => err
      raise RDoc::Error, "Error while evaluating %s: %s (at %p)" % [
        template_file,
        err.message,
        eval("_erbout[-50,50]", context)
      ], err.backtrace
    end

    outfile = @basedir + @options.op_dir + 'index.html'

    unless @options.dry_run then
      debug_msg "Outputting to %s" % [outfile.expand_path]
      outfile.open 'w', 0644 do |io|
        io.set_encoding @options.encoding if Object.const_defined? :Encoding
        io.write output
      end
    else
      debug_msg "Would have output to %s" % [outfile.expand_path]
    end
  end

  ##
  # Generate a documentation file for each class

  def generate_class_files
    template_file = @template_dir + 'classpage.rhtml'
    return unless template_file.exist?
    debug_msg "Generating class documentation in #@outputdir"

    @classes.each do |klass|
      debug_msg "  working on %s (%s)" % [klass.full_name, klass.path]
      outfile    = @outputdir + klass.path
      rel_prefix = @outputdir.relative_path_from outfile.dirname
      svninfo    = self.get_svninfo klass

      debug_msg "  rendering #{outfile}"
      self.render_template template_file, binding, outfile
    end
  end

  ##
  # Generate a documentation file for each file

  def generate_file_files
    template_file = @template_dir + 'filepage.rhtml'
    return unless template_file.exist?
    debug_msg "Generating file documentation in #@outputdir"

    @files.each do |file|
      outfile     = @outputdir + file.path
      debug_msg "  working on %s (%s)" % [ file.full_name, outfile ]
      rel_prefix  = @outputdir.relative_path_from outfile.dirname

      debug_msg "  rendering #{outfile}"
      self.render_template template_file, binding, outfile
    end
  end

  ##
  # Return a string describing the amount of time in the given number of
  # seconds in terms a human can understand easily.

  def time_delta_string seconds
    return 'less than a minute'          if seconds < 60
    return "#{seconds / 60} minute#{seconds / 60 == 1 ? '' : 's'}" if
                                            seconds < 3000     # 50 minutes
    return 'about one hour'              if seconds < 5400     # 90 minutes
    return "#{seconds / 3600} hours"     if seconds < 64800    # 18 hours
    return 'one day'                     if seconds < 86400    #  1 day
    return 'about one day'               if seconds < 172800   #  2 days
    return "#{seconds / 86400} days"     if seconds < 604800   #  1 week
    return 'about one week'              if seconds < 1209600  #  2 week
    return "#{seconds / 604800} weeks"   if seconds < 7257600  #  3 months
    return "#{seconds / 2419200} months" if seconds < 31536000 #  1 year
    return "#{seconds / 31536000} years"
  end

  # %q$Id: darkfish.rb 52 2009-01-07 02:08:11Z deveiant $"
  SVNID_PATTERN = /
    \$Id:\s
    (\S+)\s                # filename
    (\d+)\s                # rev
    (\d{4}-\d{2}-\d{2})\s  # Date (YYYY-MM-DD)
    (\d{2}:\d{2}:\d{2}Z)\s # Time (HH:MM:SSZ)
    (\w+)\s                # committer
    \$$
  /x

  ##
  # Try to extract Subversion information out of the first constant whose
  # value looks like a subversion Id tag. If no matching constant is found,
  # and empty hash is returned.

  def get_svninfo klass
    constants = klass.constants or return {}

    constants.find { |c| c.value =~ SVNID_PATTERN } or return {}

    filename, rev, date, time, committer = $~.captures
    commitdate = Time.parse "#{date} #{time}"

    return {
      :filename    => filename,
      :rev         => Integer(rev),
      :commitdate  => commitdate,
      :commitdelta => time_delta_string(Time.now - commitdate),
      :committer   => committer,
    }
  end

  # Load and render the erb template in the given +template_file+ within the
  # specified +context+ (a Binding object) and write it out to +outfile+.
  # Both +template_file+ and +outfile+ should be Pathname-like objects.

  def render_template template_file, context, outfile
    template_src = template_file.read
    template = ERB.new template_src, nil, '<>'
    template.filename = template_file.to_s

    output = begin
               template.result context
             rescue NoMethodError => err
               raise RDoc::Error, "Error while evaluating %s: %s (at %p)" % [
                 template_file.to_s,
                 err.message,
                 eval("_erbout[-50,50]", context)
               ], err.backtrace
             end

    unless @options.dry_run then
      outfile.dirname.mkpath
      outfile.open 'w', 0644 do |io|
        io.set_encoding @options.encoding if Object.const_defined? :Encoding
        io.write output
      end
    else
      debug_msg "  would have written %d bytes to %s" % [
        output.length, outfile
      ]
    end
  end

end

