#!/usr/bin/env ruby

# Copyright (C) 2014 Tobias V. Langhoff <tobias@langhoff.no>. All Rights Reserved.
# This file is licensed under GPLv2+. Please see COPYING for more information.
# 
# 1Password Importer
# 
# Reads files exported from 1Password and imports them into pass. Supports comma
# and tab delimited text files, as well as logins (but not other items) stored
# in the 1Password Interchange File (1PIF) format.
# 
# Supports using the title (default) or URL as pass-name, depending on your
# preferred organization. Also supports importing metadata, adding them with
# `pass insert --multiline`; the username and URL are compatible with
# https://github.com/jvenant/passff.

require "optparse"
require "ostruct"

accepted_formats = [".txt", ".1pif"]

ignore_entries = ["Tags"]

# Default options
options = OpenStruct.new
options.force = false
options.name = :title
options.notes = true
options.meta = true

optparse = OptionParser.new do |opts|
  opts.banner = "Usage: #{opts.program_name}.rb [options] filename"
  opts.on_tail("-h", "--help", "Display this screen") { puts opts; exit }
  opts.on("-f", "--force", "Overwrite existing passwords") do
    options.force = true
  end
  opts.on("-d", "--default [FOLDER]", "Place passwords into FOLDER") do |group|
    options.group = group
  end
  opts.on("-n", "--name [PASS-NAME]", [:title, :url],
          "Select field to use as pass-name: title (default) or URL") do |name|
    options.name = name
  end
  opts.on("-m", "--[no-]meta",
          "Import metadata and insert it below the password") do |meta|
    options.meta = meta
  end

  begin 
    opts.parse!
  rescue OptionParser::InvalidOption
    $stderr.puts optparse
    exit
  end
end

# Check for a valid filename
filename = ARGV.pop
unless filename
  abort optparse.to_s
end
unless accepted_formats.include?(File.extname(filename.downcase))
  abort "Supported file types: comma/tab delimited .txt files."
end

passwords = []

# Parse comma or tab delimited text
if File.extname(filename) =~ /.txt/i
  require "csv"

  # Very simple way to guess the delimiter
  delimiter = ""
  File.open(filename) do |file|
    first_line = file.readline
    if first_line =~ /,/
      delimiter = ","
    elsif first_line =~ /\t/
      delimiter = "\t"
    else
      abort "Supported file types: comma/tab delimited .txt files."
    end
  end

  # Read Headers
  CSV.foreach(filename, {col_sep: delimiter, headers: true}) do |entry|
    pass = {}
    entry.each do |e|
      if ( !e[0].nil? and !e[1].nil? and !ignore_entries.include?(e[0]) )
        pass[e[0]] = e[1]
        # puts "#{e[0]}: #{e[1]}"
      end
    end
    passwords << pass
  end

end

puts "Read #{passwords.length} passwords."

errors = []
# Save the passwords
passwords.each do |pass|
  name = "#{pass['Type']}/#{pass['Title']}"
  IO.popen("pass insert #{"-f " if options.force}-m '#{name}' > /dev/null", "w") do |io|
    io.puts pass['Password'] unless pass['Password'].to_s.empty?
    pass.each do |key,value|
      io.puts "#{key}: #{value}"
    end
  end
  if $? == 0
    puts "Imported #{name}"
  else
    $stderr.puts "ERROR: Failed to import #{pass}"
    errors << pass
  end
end

if errors.length > 0
  $stderr.puts "Failed to import #{errors.map {|e| e['Title']}.join ", "}"
  $stderr.puts "Check the errors. Make sure these passwords do not already "\
               "exist. If you're sure you want to overwrite them with the "\
               "new import, try again with --force."
end
