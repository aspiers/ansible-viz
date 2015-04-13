#!/usr/bin/ruby
# vim: set ts=2 sw=2 tw=100:

require 'rubygems'
require 'pp'


class VarFinder
  # Vars can appear:
  #   * In role[:varfile][:var], when defined in vars/
  #   * In role[:task][:var], when defined by set_fact
  class <<self
    def walk(tree, &block)
      case tree
      when Hash
        res = (yield(:hash, tree) or [])
        res + tree.flat_map {|k,v| walk(v, &block) }.compact
      when Enumerable
        res = (yield(:list, tree) or [])
        res + tree.flat_map {|i| walk(i, &block) }.compact
      else
        yield(:scalar, tree)
      end
    end
  end

  def process(dict)
    dict[:role].each {|role|
      role[:task].each {|task|
        find_var_uses(dict, task)
      }
      (role[:varfile] + role[:vardefaults]).each {|vf|
        vf[:used_vars] = find_vars_in_varfile(vf, vf[:data]).uniq
      }
      role[:template].each {|tm|
        tm[:used_vars] = find_vars_in_template(tm, tm[:data]).uniq
      }
    }
  end

  def find_var_uses(dict, task)
    task[:used_vars] = find_vars_in_task(task, task[:data]).uniq

    # TODO control this with a flag
    task[:used_vars] = task[:used_vars].flat_map {|v|
      v =~ /_default$/ and [] or [v]
    }.uniq

    raise_if_nil("#{task[:fqn]} used vars", task[:used_vars])
  end

  def raise_if_nil(name, it)
    if it == nil
      raise "#{name} is nil"
    elsif it.include? nil
      raise "#{name} includes nil"
    end
  end

  def find_vars_in_task(task, data)
    VarFinder.walk(data) {|type, obj|
      case type
      when :hash
        find_vars_in_with_and_when(task, obj)
      when :scalar
        find_vars_in_string(obj)
      end
    }
  end

  def find_vars_in_varfile(varfile, data)
    VarFinder.walk(data) {|type, obj|
      case type
      when :scalar
        find_vars_in_string(obj)
      end
    }
  end

  def find_vars_in_template(template, data)
    data.flat_map {|line|
      find_vars_in_string(line)
    }
  end

  def find_vars_in_string(data)
    # This really needs a proper parser. For example, it can't handle nested {{ }}
    # and it strips strings really badly.
    # Maybe use the Python ast module? Oh wait we're in Ruby.
    # rubypython gem didn't work for me, with Ruby 1.9.3 or 2.2.1.
    rej = %w(join int item dirname basename regex_replace search abspath isdir
             is defined failed skipped success True False update in
             Vagrant)
    data.to_s.scan(/\{\{\s*(.*?)\s*\}\}/).
      map {|m| m[0] }.
#      map {|s| if s =~ /virsh_vol_list_result/ then pp s end; s }.
      map {|s|
        # Turn all "f(x)" into "x", vars can't be function names
        os = nil
        while os != s
          os = s
          s = s.gsub(/\w+\((.*?)\)/, '\1')
        end
        s
      }.
      flat_map {|s| s.gsub(/".*?"/, "") }.
      flat_map {|s| s.gsub(/'.*?'/, "") }.
      flat_map {|s| s.gsub(/not /, "") }.
      flat_map {|s| s.split("|") }.
      flat_map {|s| s.split(" and ") }.
      flat_map {|s| s.split(" or ") }.
      flat_map {|s| s.split(" ") }.
      reject {|s| s =~ /\w+\.stdout/ }.
      map {|s| s.split(".")[0] }.
      map {|s| s.split("[")[0] }.
      map {|s| s.gsub(/[^[:alnum:]_-]/, '') }.
      reject {|s| rej.include? s }.
      reject {|s| s =~ /^\d*$/ }.
      reject {|s| s =~ /^ansible_/ }.
      reject {|s| s.empty? }
  end

  def find_vars_in_with_and_when(task, data)
    items = data['with_items'] || []
    items = if items.is_a?(String)
      find_vars_in_string("{{ #{items} }}")
    else
      items.flat_map {|s| find_vars_in_string(s) }
    end

    with_dict = [data['with_dict']].flat_map {|s|
      find_vars_in_string("{{ #{s} }}")
    }
#    if with_dict.length > 0 then pp with_dict end

    _when = [data['when']].flat_map {|s|
      find_vars_in_string("{{ #{s} }}")
    }
#    if _when.length > 0 then pp _when end

    items + with_dict + _when
  end
end
