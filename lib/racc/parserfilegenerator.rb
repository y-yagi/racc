# Copyright (c) 1999-2006 Minero Aoki
#
# This program is free software.
# You can distribute/modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.
# For details of the GNU LGPL, see the file "COPYING".

require 'enumerator'
require 'racc/sourcetext'
require 'racc/parser-text'
require 'rbconfig'

module Racc

  class ParserFileGenerator

    class Params
      def self.bool_attr(name)
        module_eval(<<-End)
          def #{name}?
            @#{name}
          end

          def #{name}=(b)
            @#{name} = b
          end
        End
      end

      attr_accessor :filename
      attr_accessor :classname
      attr_accessor :superclass
      bool_attr :omit_action_call
      bool_attr :result_var
      attr_accessor :header
      attr_accessor :inner
      attr_accessor :footer

      bool_attr :debug_parser
      bool_attr :convert_line
      bool_attr :convert_line_all
      bool_attr :embed_runtime
      bool_attr :make_executable
      attr_accessor :interpreter

      def initialize
        # Parameters derived from parser
        self.filename = nil
        self.classname = nil
        self.superclass = 'Racc::Parser'
        self.omit_action_call = true
        self.result_var = true
        self.header = []
        self.inner  = []
        self.footer = []

        # Parameters derived from command line options
        self.debug_parser = false
        self.convert_line = true
        self.convert_line_all = false
        self.embed_runtime = false
        self.make_executable = false
        self.interpreter = nil
      end
    end

    def initialize(states, params)
      @states = states
      @grammar = states.grammar
      @params = params
    end

    def generate_parser
      string_io = StringIO.new

      init_line_conversion_system
      @f = string_io
      parser_file

      string_io.rewind
      string_io.read
    end

    def generate_parser_file(destpath)
      init_line_conversion_system
      File.open(destpath, 'w') {|f|
        @f = f
        parser_file
      }
      File.chmod 0755, destpath if @params.make_executable?
    end

    private

    def parser_file
      shebang @params.interpreter if @params.make_executable?
      notice
      line
      if @params.embed_runtime?
        embed_library runtime_source()
      else
        require 'racc/parser.rb'
      end
      header
      parser_class(@params.classname, @params.superclass) {
        inner
        state_transition_table
      }
      footer
    end

    c = ::RbConfig::CONFIG
    RUBY_PATH = "#{c['bindir']}/#{c['ruby_install_name']}#{c['EXEEXT']}"

    def shebang(path)
      line '#!' + (path == 'ruby' ? RUBY_PATH : path)
    end

    def notice
      line %q[#]
      line %q[# DO NOT MODIFY!!!!]
      line %Q[# This file is automatically generated by Racc #{Racc::Version}]
      line %Q[# from Racc grammar file "#{@params.filename}".]
      line %q[#]
    end

    def runtime_source
      SourceText.new(::Racc::PARSER_TEXT, 'racc/parser.rb', 1)
    end

    def embed_library(src)
      line %[###### #{src.filename} begin]
      line %[unless $".index '#{src.filename}']
      line %[$".push '#{src.filename}']
      put src, @params.convert_line?
      line %[end]
      line %[###### #{src.filename} end]
    end

    def require(feature)
      line "require '#{feature}'"
    end

    def parser_class(classname, superclass)
      mods = classname.split('::')
      classid = mods.pop
      mods.each do |mod|
        indent; line "module #{mod}"
        cref_push mod
      end
      indent; line "class #{classid} < #{superclass}"
      cref_push classid
      yield
      cref_pop
      indent; line "end   \# class #{classid}"
      mods.reverse_each do |mod|
        indent; line "end   \# module #{mod}"
        cref_pop
      end
    end

    def header
      @params.header.each do |src|
        line
        put src, @params.convert_line_all?
      end
    end

    def inner
      @params.inner.each do |src|
        line
        put src, @params.convert_line?
      end
    end

    def footer
      @params.footer.each do |src|
        line
        put src, @params.convert_line_all?
      end
    end

    # Low Level Routines

    def put(src, convert_line = false)
      if convert_line
        replace_location(src) {
          @f.puts src.text
        }
      else
        @f.puts src.text
      end
    end

    def line(str = '')
      @f.puts str
    end

    def init_line_conversion_system
      @cref = []
      @used_separator = {}
    end

    def cref_push(name)
      @cref.push name
    end

    def cref_pop
      @cref.pop
    end

    def indent
      @f.print '  ' * @cref.size
    end

    def toplevel?
      @cref.empty?
    end

    def replace_location(src)
      sep = make_separator(src)
      @f.print 'self.class.' if toplevel?
      @f.puts "module_eval(<<'#{sep}', '#{src.filename}', #{src.lineno})"
      yield
      @f.puts sep
    end

    def make_separator(src)
      sep = unique_separator(src.filename)
      sep *= 2 while src.text.index(sep)
      sep
    end

    def unique_separator(id)
      sep = "...end #{id}/module_eval..."
      while @used_separator.key?(sep)
        sep.concat sprintf('%02x', rand(255))
      end
      @used_separator[sep] = true
      sep
    end

    #
    # State Transition Table Serialization
    #

    public

    def put_state_transition_table(f)
      @f = f
      state_transition_table
    end

    private

    def state_transition_table
      table = @states.state_transition_table
      table.use_result_var = @params.result_var?
      table.debug_parser = @params.debug_parser?

      line "##### State transition tables begin ###"
      line
      integer_list 'racc_action_table', table.action_table
      line
      integer_list 'racc_action_check', table.action_check
      line
      integer_list 'racc_action_pointer', table.action_pointer
      line
      integer_list 'racc_action_default', table.action_default
      line
      integer_list 'racc_goto_table', table.goto_table
      line
      integer_list 'racc_goto_check', table.goto_check
      line
      integer_list 'racc_goto_pointer', table.goto_pointer
      line
      integer_list 'racc_goto_default', table.goto_default
      line
      i_i_sym_list 'racc_reduce_table', table.reduce_table
      line
      line "racc_reduce_n = #{table.reduce_n}"
      line
      line "racc_shift_n = #{table.shift_n}"
      line
      sym_int_hash 'racc_token_table', table.token_table
      line
      line "racc_nt_base = #{table.nt_base}"
      line
      line "racc_use_result_var = #{table.use_result_var}"
      line
      @f.print(unindent_auto(<<-End))
        Racc_arg = [
          racc_action_table,
          racc_action_check,
          racc_action_default,
          racc_action_pointer,
          racc_goto_table,
          racc_goto_check,
          racc_goto_default,
          racc_goto_pointer,
          racc_nt_base,
          racc_reduce_table,
          racc_token_table,
          racc_shift_n,
          racc_reduce_n,
          racc_use_result_var ]
      End
      line
      string_list 'Racc_token_to_s_table', table.token_to_s_table
      line
      line "Racc_debug_parser = #{table.debug_parser}"
      line
      line '##### State transition tables end #####'
      actions
    end

    def integer_list(name, table)
      lines = table.inspect.split(/((?:\w+, ){15})/).reject { |s| s.empty? }
      line "#{name} = #{lines.join("\n")}"
    end

    def i_i_sym_list(name, table)
      sep = ''
      line "#{name} = ["
      table.each_slice(3) do |len, target, mid|
        @f.print sep; sep = ",\n"
        @f.printf '  %d, %d, %s', len, target, mid.inspect
      end
      line " ]"
    end

    def sym_int_hash(name, h)
      sep = "\n"
      @f.print "#{name} = {"
      h.to_a.sort_by {|sym, i| i }.each do |sym, i|
        @f.print sep; sep = ",\n"
        @f.printf "  %s => %d", sym.serialize, i
      end
      line " }"
    end

    def string_list(name, list)
      sep = "  "
      line "#{name} = ["
      list.each do |s|
        @f.print sep; sep = ",\n  "
        @f.print s.dump
      end
      line ' ]'
    end

    def actions
      @grammar.each do |rule|
        unless rule.action.source?
          raise "racc: fatal: cannot generate parser file when any action is a Proc"
        end
      end

      if @params.result_var?
        decl = ', result'
        retval = "\n    result"
        default_body = ''
      else
        decl = ''
        retval = ''
        default_body = 'val[0]'
      end
      @grammar.each do |rule|
        line
        if rule.action.empty? and @params.omit_action_call?
          line "# reduce #{rule.ident} omitted"
        else
          src0 = rule.action.source || SourceText.new(default_body, __FILE__, 0)
          if @params.convert_line?
            src = remove_blank_lines(src0)
            delim = make_delimiter(src.text)
            @f.printf unindent_auto(<<-End),
              module_eval(<<'%s', '%s', %d)
                def _reduce_%d(val, _values%s)
                  %s%s
                end
              %s
            End
                      delim, src.filename, src.lineno - 1,
                        rule.ident, decl,
                        src.text, retval,
                      delim
          else
            src = remove_blank_lines(src0)
            @f.printf unindent_auto(<<-End),
              def _reduce_%d(val, _values%s)
              %s%s
              end
            End
                      rule.ident, decl,
                      src.text, retval
          end
        end
      end
      line
      @f.printf unindent_auto(<<-'End'), decl
        def _reduce_none(val, _values%s)
          val[0]
        end
      End
      line
    end

    def remove_blank_lines(src)
      body = src.text.dup
      line = src.lineno
      while body.slice!(/\A[ \t\f]*(?:\n|\r\n|\r)/)
        line += 1
      end
      SourceText.new(body, src.filename, line)
    end

    def make_delimiter(body)
      delim = '.,.,'
      while body.index(delim)
        delim *= 2
      end
      delim
    end

    def unindent_auto(str)
      lines = str.lines.to_a
      n = minimum_indent(lines)
      lines.map {|line| detab(line).sub(indent_re(n), '').rstrip + "\n" }.join('')
    end

    def minimum_indent(lines)
      lines.map {|line| n_indent(line) }.min
    end

    def n_indent(line)
      line.slice(/\A\s+/).size
    end

    RE_CACHE = {}

    def indent_re(n)
      RE_CACHE[n] ||= /\A {#{n}}/
    end

    def detab(str, ts = 8)
      add = 0
      len = nil
      str.gsub(/\t/) {
        len = ts - ($`.size + add) % ts
        add += len - 1
        ' ' * len
      }
    end

  end

end
