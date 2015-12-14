#
# spec.rb
#
# A Ruby class for manipulating rpm .spec files

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
    unless name
      raise "No .spec found"
    end
    names = name.split(".")
    if names[-1] == "spec"
      @file = name
      names.pop
      @name = names.join(".")
    else
      @name = name
      @file = "#{@name}.spec"
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
    #
    # insert chunks
    #   a chunk is an array of strings (lines) to add
    #   there can be multiple chunks all added *before* <line-number>
    # (you never add something at the end of the .spec since %changelog is supposed to be at the end)
    #
    # Hash of <line-number> : [ [ "line", ...], ["line", ...] ]
    @inserts = {}
  end

  # return spec macro depending on actual site_path used in package
  def site_macro
    @site_macro ||= case site_path
                    when SITELIB
                      "%{python_sitelib}"
                    when SITEARCH
                      "%{python_sitearch}"
                    else
                      STDERR.puts "%{python_sitelib}/%{python_sitearch} not found"
                      exit 1
                    end
  end

  # extract content from RPM
  #  rpmdir - directory of pre-built rpms
  #
  def content rpmdir=RPMDIR
    unless @content
      rpmname = nil
      puts "Extracting content from #{@name}-\\d.rpm"
      begin
        Dir.open(rpmdir).each do |n|
          next unless n =~ /^#{@name}-\d/
          next unless n =~ /\.rpm$/
          next if n =~ /\.src\.rpm$/
          rpmname = n
          break
        end
      rescue
        rpmname = nil
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
      rpmpath = File.join(rpmdir, rpmname)
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
  def site_pathes_depth pattern
    p = pattern.gsub(/\./, "\\1")
    regexp = Regexp.new "(#{SITELIB}|#{SITEARCH})/(.*)#{p}(.*)"
    unless @site_pathes_depth
      @site_pathes_depth = 0
      i = -1
      content().each_line do |l|
        i += 1
        next unless l =~ regexp
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
      lno = 0
      insert_points = @inserts.keys.sort
      next_insert_at = insert_points.shift
      @spec.each do |l|
        if lno == next_insert_at
          @inserts[lno].each do |inserts|
            inserts.each do |ll|
              f.puts ll
            end
          end
          next_insert_at = insert_points.shift
        end
        f.puts l
        lno += 1
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
    inserts = @inserts[pos] || []
    lines.map! { |l| "#{prepend}#{l}" } if prepend
    inserts << lines
    @inserts[pos] = inserts
  end
end

#
# -----------------------------------------------------------------------------
#

if __FILE__ == $0
  name = ARGV.shift

  spec = Spec.new name

  puts "#{spec.name}: #{spec.spec.size} lines, #{spec.packages.size} %package, #{spec.files.size} %files"

  # computes spec.site_path and spec.size_path_position
  puts "#{spec.name}: max depth #{spec.site_pathes_depth} @ #{spec.site_path}, #{spec.docs.size} doc files"

end
