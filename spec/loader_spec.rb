require_relative "../loader"

RSpec.describe Loader do
  it "test thing" do
    d = {}

    it = thing(d, :abc, "def", "path", {"ghi" => "jkl"})
    it2 = thing(it, :xyz, "456", "path2")

    thing1 = {:type=>:abc, :name=>"def", :fqn=>"def", "ghi"=>"jkl",
              :path=>"path", :xyz=>[it2]}
    expect(thing1).to eq(it)

    thing2 = {:type=>:xyz, :name=>"456", :fqn=>"def::456",
              :path=>"path2", :parent=>it}
    expect(thing2).to eq(it2)
    expect(d[:abc]).to eq([it])
  end
  context "yml loader" do
    it "should load the playbook yml files" do
      expect(Loader.ls_yml("sample")).to contain_exactly("playbook1.yml", "playbookA.yml")
    end
    it "should not load any yml if there are none" do
      expect(Loader.ls_yml("none", {})).to eq([])
    end
  end

  context "dir loader" do
    it "should have playbook and roles" do
      expect(Loader.new.load_dir("sample")).to include(:playbook, :role)
    end
  end

  context "role loader" do
    before(:each) do
       @role = Loader.new.mk_role({}, "sample/roles", "role1")
    end
    it "has all varfiles loaded" do
      expect(@role[:varfile].map{ |v| v[:name] }).to contain_exactly("main", "extra", "maininc")
    end
    it "has all vardefaults loaded" do
      expect(@role[:vardefaults].map{ |v| v[:name] }).to contain_exactly("main")
    end
    it "has all tasks loaded" do
      expect(@role[:task].map{ |v| v[:name] }).to contain_exactly("main", "task1", "task2")
    end
    it "has the proper dependencies" do
      expect(@role[:role_deps]).to contain_exactly("roleA")
    end
    it "has the proper name" do
      expect(@role[:name]).to eq("role1")
    end
    it "has the proper path" do
      expect(@role[:path]).to eq("sample/roles/role1")
    end
  end

  context "thing loader" do
    it "should load vars" do
      role = thing({}, :role, "role", "rolepath")
      varfile = Loader.new.load_thing(role, :varfile, "sample/roles/role1/vars", "main.yml")
      varfile.delete :data
      expected_varfile = thing(
        role, :varfile, "main","sample/roles/role1/vars/main.yml", {:parent => {}}
      )
      expect(expected_varfile).to eq(varfile)
    end
  end
end
