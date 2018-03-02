#!/usr/bin/ruby

require "ansible_viz/cli"

def main
  options = get_options()

  options.playbook_dirs.each do |playbook_dir|
    divider "Loading #{playbook_dir}"
    data = Loader.new.load_dir(options.playbook_dir)
  end

  graph = graph_from_data(data, options)

  divider "Rendering graph"
  write(graph, options.output_filename)
end

if __FILE__ == $0
  main
end
