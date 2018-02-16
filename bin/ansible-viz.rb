#!/usr/bin/ruby

require "ansible_viz/cli"

def main
  options = get_options()

  divider "Loading"
  data = Loader.new.load_dir(options.playbook_dir)
  graph = graph_from_data(data, options)

  divider "Rendering graph"
  write(graph, options.output_filename)
end

if __FILE__ == $0
  main
end
