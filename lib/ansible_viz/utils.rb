# FIXME: evil evil global, get rid of this!
$debug_level = 1

def debug(level, msg)
  $stderr.puts msg if $debug_level >= level
end

def tty_width
  ENV['COLUMNS'] ? ENV['COLUMNS'].to_i : 78
end

def wrap_indent(indent, list)
  list.join(" ") \
    .wrap(tty_width - indent.size) \
    .gsub(/^/, indent)
end

def default_options
  OpenStruct.new(
    format: :hot,
    output_filename: "viz.html",
    show_tasks: true,
    show_varfiles: true,
    show_templates: true,
    show_vars: false,
    show_vardefaults: true,
    show_usage: true,
  )
end
