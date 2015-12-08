#!/usr/bin/env ruby

def usage msg=nil
  STDERR.puts "*** #{msg}" if msg
  STDERR.puts "Usage:"
  STDERR.puts "mipy <name>"
  exit (msg ? 1 : 0)
end

def build_package
end

RPMDIR = "/tmp/osb/openSUSE_Tumbleweed/"
SITELIB = "/usr/lib/python2.7/site-packages"
SITEARCH = "/usr/lib64/python2.7/site-packages"

class Spec
  private
  def find what
    result = {}
    nr = 0
    @spec.each do |line|
      begin
        if line =~ what
          result[$1] = nr
        end
      rescue Exception => e
        STDERR.puts "Can't match #{what.inspect} to\n#{line.inspect}\n\t#{e}"
      end
      nr += 1
    end
    result
  end
  public

  attr_reader :spec, :name, :file, :site_path

  def initialize name = nil
    unless name
      Dir.open(".").each do |n|
        next unless n =~ /\.spec$/
        name = n
        break
      end
    end
    names = name.split(".")
    puts names.inspect
    @name = names[0]
    if names[-1] == "spec"
      @file = name
    else
      @file = "#{name}.spec"
    end
    @spec = []
    unless File.readable?(@file)
      usage "No such .spec: #{name} : #{@file.inspect}"
    end
    File.open @file do |f|
      f.each do |line|
        @spec << line
      end
    end
  end

  # extract content from RPM
  def content
    unless @content
      rpmname = nil
      Dir.open(RPMDIR).each do |n|
        next unless n =~ /^#{@name}-\d/
        next unless n =~ /\.rpm$/
        next if n =~ /\.src\.rpm$/
        rpmname = n
        break
      end
      unless rpmname
        if @built
          STDERR.puts "Couldn't build .rpm for #{name}"
          exit 1
        else
          puts "No .rpm found, building it ..."
          @built = true
          system "osb openSUSE_Tumbleweed"
          return content
        end
      end
      rpmpath = File.join(RPMDIR, rpmname)
      pipe = nil
      begin
        pipe = IO.popen("rpm -qlp #{rpmpath}", "r")
      rescue Exception => e
        STDERR.puts "rpm -qlp failed for #{rpmpath}: #{e}"
      end
      @content = pipe.gets(nil)
      pipe.close
    end
    @content
  end

  # find first Summary
  #
  def summary
    unless @summary
      spec.each do |l|
        next unless l =~ /^Summary:(\s+)(.*)/
        @summary = $2
        break
      end
    end
    @summary
  end

  # extract pathes with %python_sitelib / %python_sitearch
  #  return max depth
  def site_pathes_depth
    unless @site_pathes_depth
      @site_pathes_depth = 0
      i = -1
      content().each_line do |l|
        i += 1
        next unless l =~ %r{(#{SITELIB}|#{SITEARCH})/(.*)\.py}
        @site_path_position ||= i
        @site_path ||= $1
        depth = $2.split("/").count
        if depth > @site_pathes_depth
          @site_pathes_depth = depth
        end
      end
    end
    @site_pathes_depth
  end

  # extract doc pathes from content
  def docs
    unless @docs
      @docs = []
      content().each_line do |l|
        next unless l =~ %r{/usr/share/doc/packages}
        @docs << l
      end
    end
    @docs
  end

  def write
    File.open(@file, "w+") do |f|
      @spec.each do |l|
        f.puts l
      end
    end
  end

  def packages
    @packages ||= find /^%package(.*)$/
  end

  def files
    @files ||= find /^%files(.*)$/
  end

  def changelog_position
    @changelog_position ||= find(/^%changelog/).first[1]
  end

  def prep_position
    @prep_position ||= find(/^%prep/).first[1]
  end

#packages.each do |k,v|
#  puts "Package[#{k.inspect}] #{v.inspect}"
#end
#files.each do |k,v|
#  puts "File[#{k.inspect}] #{v.inspect}"
#end

  # insert lines at position, return new position
  def insert_at pos, lines, prepend = nil
    lines.each do |l|
      spec.insert pos, "#{prepend}#{l}"
      pos += 1
    end
    pos
  end
end


name = ARGV.shift

spec = Spec.new name

puts "#{spec.name}: #{spec.spec.size} lines, #{spec.packages.size} %package, #{spec.files.size} %files"

# computes spec.site_path and spec.size_path_position
puts "#{spec.name}: max depth #{spec.site_pathes_depth} @ #{spec.site_path}, #{spec.docs.size} doc files"

# sitelib_pathes_depth returns the number of components
#  after %{python_sitelib}/%python_sitearch
#  the last component is the .py file itself
#
#          "%{python_sitelib}/*/*.py",
#          "%{python_sitelib}/*/*/*.py",
#          "%{python_sitelib}/*/*/*/*.py",

site_macro = case spec.site_path
        when SITELIB
          "%{python_sitelib}"
        when SITEARCH
          "%{python_sitearch}"
        else
          STDERR.puts "%{python_sitelib}/%{python_sitearch} not found"
        end

site_pathes = []
for i in 2 .. spec.site_pathes_depth
  site_pathes << (site_macro + ("/*" * i) + ".py")
end

# find the first site_macro in %files

_, pivot = spec.files.first

site_macro_position = nil

while pivot < spec.spec.size
  if spec.spec[pivot] =~ /^#{site_macro}/
    site_macro_position = pivot
    break
  end
  pivot += 1
end

unless site_macro_position
  STDERR.puts "Could not find #{site_macro} in %files"
  exit 1
end

# insert %files source
#  after %files with %{python_sitelib/sitearch}

# find the next %files after sitelibs_position

pivot = spec.changelog_position # or use the %changelog entry
spec.files.each do |k,v|
  if v > site_macro_position
    pivot = v
    break
  end
end

unless pivot
  STDERR.puts "Couldn't find %files position"
  exit 1
end

# add %files source

pivot = spec.insert_at pivot, [ "%files source",
          "%defattr(-,root,root)"] + site_pathes + [""]

# add %exclude
  def site_path_position
    unless @site_path_position
      spec.each_line do |l|
        next unless l =~ /^Summary:(\s+)(.*)/
        @summary = $2
        break
      end
    end
    @summary
  end


spec.insert_at site_macro_position, site_pathes, "%exclude "

# insert %package source
#  before first sub-package

_, pivot = spec.packages.first

pivot ||= spec.prep_position # use %prep if no %package found

unless pivot
  STDERR.puts "Couldn't find %package position: #{spec.packages.inspect}"
  exit 1
end

spec.insert_at pivot, [ "%package source",
  "Summary:  Source files for #{spec.name}",
  "Group:    Development/Languages/Python",
  "%description source",
  "Python source (.py) files for #{spec.name} (#{spec.summary})",
  ""
  ]
  
spec.write
