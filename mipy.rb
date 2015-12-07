#!/usr/bin/env ruby

def usage msg=nil
  STDERR.puts "Usage:"
  STDERR.puts "mipy <name>"
  exit (msg ? 1 : 0)
end

def build_package
end

RPMDIR = "/tmp/osb/openSUSE_Tumbleweed/"

class Spec
  private
  def find what
    result = {}
    nr = 0
    @spec.each do |line|
      if line =~ what
        result[$1] = nr
      end
      nr += 1
    end
    result
  end
  public

  attr_reader :spec

  def initialize name = nil
    unless name
      Dir.open(".").each do |n|
        next unless n =~ /\.spec$/
        name = n
        break
      end
    end
    names = name.split(".")
    @name = names[0]
    if names[1] == "spec"
      @file = name
    else
      @file = "#{name}.spec"
    end
    @spec = []
    unless File.readable?(@file)
      usage "No such .spec: #{name}"
    end
    File.open @file do |f|
      f.each do |line|
        @spec << line
      end
    end
  end

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
        STDERR.puts "Couldn't find .rpm for #{name}"
        exit 1
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

  def sitelibs
    @sitelibs ||= find /%{python_sitelib}/
  end

#packages.each do |k,v|
#  puts "Package[#{k.inspect}] #{v.inspect}"
#end
#files.each do |k,v|
#  puts "File[#{k.inspect}] #{v.inspect}"
#end
#sitelibs.each do |k,v|
#  puts "%{python_sitelib}[#{k.inspect}] #{v.inspect}"
#end
#

  # insert lines at position, return new position
  def insert_at pos, lines
    lines.each do |l|
      spec.insert pos, l
      pos += 1
    end
    pos
  end
end


name = ARGV.shift

spec = Spec.new name

puts spec.content

exit 0

puts "#{name}: #{spec.spec.size} lines, #{spec.packages.size} %package, #{spec.files.size} %files, #{spec.sitelibs.size} %{python_sitelib}"


# insert %files source
#  after %files with %{python_sitelib}

_, sitelibs_position = spec.sitelibs.first

unless sitelibs_position
  STDERR.puts "Couldn't find %python_sitelib position"
  exit 1
end

# find the next %files after sitelibs_position

pivot = nil
spec.files.each do |k,v|
  if v > sitelibs_position
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
          "%defattr(-,root,root)",
          "%{python_sitelib}/*/*.py",
          "%{python_sitelib}/*/*/*.py",
          "%{python_sitelib}/*/*/*/*.py",
          ""
          ]

# add %exclude

spec.insert_at sitelibs_position, [ "%exclude %{python_sitelib}/*/*.py",
  "%exclude %{python_sitelib}/*/*/*.py",
  "%exclude %{python_sitelib}/*/*/*/*.py",
  ]

# insert %package source
#  before first sub-package

spec.insert_at pivot, [ "%files source",
  "%defattr(-,root,root)",
  "%{python_sitelib}/*/*.py",
  "%{python_sitelib}/*/*/*.py",
  "%{python_sitelib}/*/*/*/*.py",
  ""
  ]

# will raise without sub-packages

_, pivot = packages.first

unless pivot
  STDERR.puts "Couldn't find %package position"
end

spec.insert_at pivot, [ "%package source",
  "Summary:  source files",
  "Group:    Development/Languages/Python",
  "%description source",
  "Python source (.py) files",
  ""
  ]
  
spec.write
