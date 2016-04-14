ansible-viz
===========

GraphViz depiction of Ansible dependencies.

Run::

<pre>
  gem install bundler
  bundle install
  ruby ansible-viz.rb <path-to-playbook-dir>
</pre>

Now browse viz.html or with-vars.html. The diagram is drawn client-side with
viz.js (https://github.com/mdaines/viz.js/).

There are probably still a few bugs, particularly around var usage tracking.

See sample/README.txt for details on test data. Run test-viz.rb to execute
tests and generate a coverage report. The tests create a graph of the sample
data in test.html.

Example: http://imgur.com/gallery/UC5Sv5f
