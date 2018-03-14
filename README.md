[![Build Status](https://travis-ci.org/aspiers/ansible-viz.svg?branch=master)](https://travis-ci.org/aspiers/ansible-viz)

ansible-viz
===========

GraphViz depiction of Ansible dependencies.

Run:

    gem install bundler
    bundle install
    bundle exec ruby bin/ansible-viz.rb <path-to-playbook-dir>

Now browse `viz.html` or `with-vars.html`. The diagram is drawn
client-side with [`viz.js`](https://github.com/mdaines/viz.js/).

There are probably still a few bugs, particularly around var usage tracking.

See [`sample/README.txt`](sample/README.txt) for details on test
data. Run

    bundle exec rake test

to execute tests and generate a coverage report. The tests create a
graph of the sample data in `test.html`.

## Example

![](example.png)

## History

This tool was [originally written](https://github.com/lxsli/ansible-viz)
by [Alexis Lee](https://github.com/lxsli/ansible-viz), who kindly
[agreed to transfer maintainership over](https://github.com/lxsli/ansible-viz/issues/3)
so that the project could be revived.

## Similar projects

- [ARA](https://github.com/openstack/ara) is an awesome tool, but it
  doesn't generate graphs. It also relies on run-time analysis, which
  has both pros and cons vs. static analysis.

- [ansigenome](https://github.com/nickjj/ansigenome) has lots of cool
  things rather than specialising on graphing.  The current maintainer
  actually tried it before trying ansible-viz (let alone before
  accidentally becoming maintainer), but it didn't meet his graphing
  needs at the time.  Still potentially worth looking at though.

- [ansible-roles-graph](https://github.com/sebn/ansible-roles-graph)
  is similar but much simpler and is written in Python.
