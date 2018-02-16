#!/usr/bin/ruby

require 'minitest/autorun'

require_relative 'test_helper'
require 'ansible_viz/resolver'

class TC_ResolverA < Minitest::Test
  def setup
    skip
    @d = {}
  end

  def test_role_deps
#    assert_has_all %w(), @roleA[:role_deps].smap(:name)
  end

  def test_task_includes
  end

  def test_task_include_vars
  end
end


class TC_Resolver1 < Minitest::Test
  def setup
    skip
    @d = {}
  end

  def test_role_deps
#    assert_has_all %w(), @roleA[:role_deps].smap(:name)
  end

  def test_task_includes
  end

  def test_task_include_vars
  end
end
