# All the tasks to manage building the Rubinius kernel--which is essentially
# the Ruby core library plus Rubinius-specific files. The kernel bootstraps
# a Ruby environment to the point that user code can be loaded and executed.
#
# The basic rule is that any generated file should be specified as a file
# task, not hidden inside some arbitrary task. Generated files are created by
# rule (e.g. the rule for compiling a .rb file into a .rbc file) or by a block
# attached to the file task for that particular file.
#
# The only tasks should be those names needed by the user to invoke specific
# parts of the build (including the top-level build task for generating the
# entire kernel).

# drake does not allow invoke to be called inside tasks
def kernel_clean
  rm_f Dir["**/*.rbc",
           "**/.*.rbc",
           "kernel/**/signature.rb",
           "spec/capi/ext/*.{o,sig,#{$dlext}}",
           "runtime/**/load_order.txt",
           "runtime/platform.conf"],
    :verbose => $verbose
end

require 'kernel/bootstrap/iseq.rb'

# So that the compiler can try and use the config
module Rubinius
  Config = { 'eval.cache' => false }
end

# TODO: Build this functionality into the compiler
class KernelCompiler
  def self.compile(version, file, output, line, transforms)
    compiler = Rubinius::Compiler.new :file, :compiled_file

    parser = compiler.parser
    parser.root Rubinius::AST::Script

    writer = compiler.writer

    # Not ready to enable them yet
    case version
    when "18"
      parser.processor Rubinius::Melbourne
      writer.version = 18
    when "19"
      parser.processor Rubinius::Melbourne19
      writer.version = 19
    when "20"
      parser.processor Rubinius::Melbourne20
      writer.version = 20
    end

    if transforms.kind_of? Array
      transforms.each { |t| parser.enable_category t }
    else
      parser.enable_category transforms
    end

    parser.input file, line

    writer = compiler.writer
    writer.name = output

    compiler.run
  end
end

# The rule for compiling all kernel Ruby files
rule ".rbc" do |t|
  source = t.prerequisites.first
  version = t.name.match(%r[^runtime/(\d+)])[1]
  puts "RBC #{version.split(//).join('.')} #{source}"
  KernelCompiler.compile version, source, t.name, 1, [:default, :kernel]
end

# Collection of all files in the kernel runtime. Modified by
# various tasks below.
runtime = FileList["runtime/platform.conf"]

# Names of subdirectories of the language directories.
dir_names = %w[
  bootstrap
  platform
  common
  delta
]

# Generate file tasks for all kernel and load_order files.
def file_task(re, runtime, signature, version, rb, rbc)
  rbc ||= rb.sub(re, "runtime/#{version}") + "c"

  file rbc => [rb, signature]
  runtime << rbc
end

def kernel_file_task(runtime, signature, version, rb, rbc=nil)
  file_task(/^kernel/, runtime, signature, version, rb, rbc)
end

def compiler_file_task(runtime, signature, version, rb, rbc=nil)
  file_task(/^lib/, runtime, signature, version, rb, rbc)
end

# Compile all compiler files during build stage
opcodes = "lib/compiler/opcodes.rb"

# Generate a digest of the Rubinius runtime files
signature_file = "kernel/signature.rb"

compiler_files = FileList[
  "lib/compiler.rb",
  "lib/compiler/**/*.rb",
  opcodes,
  "lib/compiler/generator_methods.rb",
  "lib/melbourne.rb",
  "lib/melbourne/**/*.rb",
  "vm/marshal.[ch]pp"
]

parser_files = FileList[
  "lib/ext/melbourne/**/*.{c,h}pp",
  "lib/ext/melbourne/grammar18.y",
  "lib/ext/melbourne/grammar19.y",
  "lib/ext/melbourne/lex.c.tab",
  "lib/ext/melbourne/lex.c.blt"
]

kernel_files = FileList[
  "kernel/**/*.txt",
  "kernel/**/*.rb"
].exclude(signature_file)

config_files = FileList[
  "Rakefile",
  "config.rb",
  "rakelib/*.rb",
  "rakelib/*.rake"
]

signature_files = compiler_files + parser_files + kernel_files + config_files

file signature_file => signature_files do
  require 'digest/sha1'
  digest = Digest::SHA1.new

  signature_files.each do |name|
    File.open name, "r" do |file|
      while chunk = file.read(1024)
        digest << chunk
      end
    end
  end

  # Collapse the digest to a 64bit quantity
  hd = digest.hexdigest
  SIGNATURE_HASH = hd[0, 16].to_i(16) ^ hd[16,16].to_i(16) ^ hd[32,8].to_i(16)

  File.open signature_file, "wb" do |file|
    file.puts "# This file is generated by rakelib/kernel.rake. The signature"
    file.puts "# is used to ensure that the runtime files and VM are in sync."
    file.puts "#"
    file.puts "Rubinius::Signature = #{SIGNATURE_HASH}"
  end
end

signature_header = "vm/gen/signature.h"

file signature_header => signature_file do |t|
  File.open t.name, "wb" do |file|
    file.puts "#define RBX_SIGNATURE          #{SIGNATURE_HASH}ULL"
  end
end

# Index files for loading a particular version of the kernel.
BUILD_CONFIG[:version_list].each do |ver|
  directory(runtime_base_dir = "runtime/#{ver}")
  runtime << runtime_base_dir

  runtime_index = "#{runtime_base_dir}/index"
  runtime << runtime_index

  file runtime_index => runtime_base_dir do |t|
    File.open t.name, "wb" do |file|
      file.puts dir_names
    end
  end

  signature = "runtime/#{ver}/signature"
  file signature => signature_file do |t|
    File.open t.name, "wb" do |file|
      puts "GEN #{t.name}"
      file.puts Rubinius::Signature
    end
  end
  runtime << signature

  # All the kernel files
  dir_names.each do |dir|
    directory(runtime_dir = "runtime/#{ver}/#{dir}")
    runtime << runtime_dir

    load_order = "runtime/#{ver}/#{dir}/load_order.txt"
    runtime << load_order

    kernel_load_order = "kernel/#{dir}/load_order#{ver}.txt"

    file load_order => kernel_load_order do |t|
      cp t.prerequisites.first, t.name, :verbose => $verbose
    end

    kernel_dir  = "kernel/#{dir}/"
    runtime_dir = "runtime/#{ver}/#{dir}/"

    IO.foreach kernel_load_order do |name|
      rbc = runtime_dir + name.chomp!
      rb  = kernel_dir + name.chop
      kernel_file_task runtime, signature_file, ver, rb, rbc
    end
  end

  [ signature_file,
    "kernel/alpha.rb",
    "kernel/loader.rb"
  ].each do |name|
    kernel_file_task runtime, signature_file, ver, name
  end

  compiler_files.map { |f| File.dirname f }.uniq.each do |dir|
    directory dir
  end

  compiler_files.each do |name|
    compiler_file_task runtime, signature_file, ver, name
  end
end

namespace :compiler do
  signature_path = File.expand_path("../../kernel/signature", __FILE__)

  Rubinius::COMPILER_PATH = libprefixdir
  Rubinius::PARSER_PATH = "#{libprefixdir}/melbourne"
  Rubinius::PARSER_EXT_PATH = "#{libprefixdir}/ext/melbourne/build/melbourne20"

  melbourne = "lib/ext/melbourne/build/melbourne.#{$dlext}"

  file melbourne => "extensions:melbourne_build"

  task :load => ['compiler:generate', melbourne] + compiler_files do

    if BUILD_CONFIG[:which_ruby] == :ruby
      require "#{Rubinius::COMPILER_PATH}/mri_bridge"
    elsif BUILD_CONFIG[:which_ruby] == :rbx && RUBY_VERSION =~ /^1\.8/
      require "#{Rubinius::COMPILER_PATH}/rbx_bridge"
    end

    require "#{Rubinius::COMPILER_PATH}/compiler"
    require signature_path
  end

  task :generate => [signature_file]
end

desc "Build all kernel files (alias for kernel:build)"
task :kernel => 'kernel:build'

namespace :kernel do
  desc "Build all kernel files"
  task :build => ['compiler:load'] + runtime

  desc "Delete all .rbc files"
  task :clean do
    kernel_clean
  end
end
