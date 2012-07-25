require File.expand_path('../../spec_helper', __FILE__)

require 'trick_serial/serializer'
require 'ostruct'

######################################################################

describe "TrickSerial::Serializer" do
  def t
    TrickSerial::Serializer::Test
  end
  before(:each) do 
    @s = TrickSerial::Serializer.new
    @s.class_option_map = {
      t::PhonyActiveRecord => { :proxy_class => TrickSerial::Serializer::ActiveRecordProxy, },
      t::A => { :instance_vars => true },
      t::B => { :instance_vars => [ "@x" ] },
      ::OpenStruct => { :instance_vars => true },
    }
    TrickSerial::Serializer::Test::PhonyActiveRecord.find_map.clear
    # Note: Structs are anonymous Classes and cannot be Marshal'ed.
    @struct = Struct.new :sm, :sa, :sb
    @m = TrickSerial::Serializer::Test::Model.new(123)
    @m2 = TrickSerial::Serializer::Test::Model.new(456)
    @m_unsaved = TrickSerial::Serializer::Test::Model.new(:unsaved)
    @m_unsaved.id = nil
    @h = {
      :a => 1,
      'b' => 2,
      :obj => Object.new,
      :m => @m,
      :a => [ 0, 1, @m, 3, 4, @m ],
      :m_unsaved => @m_unsaved,
      :s => @struct.new,
      :os => OpenStruct.new,
    }
    @h[:s].sm = @m2
    @h[:s].sa = @h
    @h[:s].sb = 'b'
    @h[:os].osm = @m
    @h[:os].osa = @h
    @h[:os].osb = 'b'
    @h[:a2] = @h[:a]
    @h[:h2] = @h
  end

  it "should handle #encode!" do
    @h[:m].should == @m
    @h[:a][2].should == @m

    result = @s.encode!(@h)

    result.object_id.should == @h.object_id
  end

  it "should handle #encode! of Struct" do
    @h[:s].sm.should == @m2
    @h[:s].sa.should == @h
    @h[:s].sb = @h[:s] # self-reference

    result = @s.encode!(@h)

    result.object_id.should == @h.object_id
    result[:s].class.should == @struct
    result[:s].sm.object_id.should_not == @m2.object_id
    result[:s].sm.id.should == @m2.id
    result[:s].sm.class.should == TrickSerial::Serializer::ActiveRecordProxy
    result[:s].sa.object_id.should == @h.object_id
    result[:s].sb.object_id.should == @h[:s].sb.object_id
    result[:s].sb.object_id.should == result[:s].object_id
  end

  it "should handle #encode of Struct" do
    @h[:s].sm.should == @m2
    @h[:s].sa.should == @h
    @h[:s].sb = @h[:s] # self-reference

    result = @s.encode(@h)

    result.object_id.should_not == @h.object_id
    result[:s].class.should == @struct
    result[:s].sm.object_id.should_not == @m2.object_id
    result[:s].sm.id.should == @m2.id
    result[:s].sm.class.should == TrickSerial::Serializer::ActiveRecordProxy
    result[:s].sa.object_id.should_not == @h.object_id
    result[:s].sb.object_id.should_not == @h[:s].sb.object_id
    result[:s].sb.object_id.should == result[:s].object_id
  end

  it "should handle #encode! of OpenStruct" do
    @h[:os].osm.should == @m
    @h[:os].osa.should == @h
    @h[:os].osos = @h[:os] # self-reference
    os = @h[:os]

    os.respond_to?(:osm).should == true
    os.respond_to?(:osa).should == true
    os.respond_to?(:osos).should == true

    result = @s.encode!(@h)

    result.object_id.should == @h.object_id
    result[:os].class.should == @h[:os].class
    result[:os].osm.id.should == @m.id
    result[:os].osm.class.should == TrickSerial::Serializer::ActiveRecordProxy
    result[:os].osa.object_id.should == @h.object_id
    result[:os].osb.object_id.should == @h[:os].osb.object_id
    result[:os].osos.object_id.should == result[:os].object_id

    os = result[:os]
    os.respond_to?(:osm).should == true
    os.respond_to?(:osa).should == true
    os.respond_to?(:osos).should == true
  end

  it "should handle #encode of OpenStruct" do
    @h[:os].osm.should == @m
    @h[:os].osa.should == @h
    @h[:os].osos = @h[:os] # self-reference
    os = @h[:os]

    os.respond_to?(:osm).should == true
    os.respond_to?(:osa).should == true
    os.respond_to?(:osos).should == true

    result = @s.encode(@h)

    result.object_id.should_not == @h.object_id
    result[:os].class.should == @h[:os].class
    result[:os].object_id.should_not == @h[:os].object_id
    result[:os].osm.id.should == @m.id
    result[:os].osm.class.should == TrickSerial::Serializer::ActiveRecordProxy
    result[:os].osa.object_id.should_not == @h.object_id
    result[:os].osb.object_id.should == @h[:os].osb.object_id
    # result[:os].osos.object_id.should == result[:os].object_id

    os = result[:os]
    os.respond_to?(:osm).should == true
    os.respond_to?(:osa).should == true
    os.respond_to?(:osos).should == true
  end

  it "should honor #enabled?" do
    enabled = true
    @s.enabled = lambda { | | enabled }
    result = @s.encode(@h)
    result.object_id.should_not == @h.object_id

    enabled = false
    result = @s.encode(@h)    
    result.object_id.should == @h.object_id
  end

  it "should proxy unsaved models" do
    @o = @s.encode!(@h)

    @o[:m].object_id.should_not == @m.object_id
    @o[:m].class.should == @m.class
    @o[:m].id.should == @m.id
  end

  it "should not proxy unsaved models" do
    @o = @s.encode!(@h)

    @o[:m_unsaved].object_id.should == @m_unsaved.object_id
  end

  it "should handle proxy swizzling through Hash#[]" do
    @s.encode!(@h)
    p = @h[:m]
    # pp [ :p=, p ]
    p.class.should == @m.class
  end

  it "should handle proxy swizzling through Hash#values" do
    @s.encode!(@h)
    p = @h.values
    p.select{|m| @m.class == m.class}.size.should == 2
  end

  it "should handle proxy swizzling through Array#[]" do
    @s.encode!(@h)
    p = @h[:a][2]
    p.class.should == @m.class
  end

  it "should handle proxy swizzling through Array#each" do
    @s.encode!(@h)
    p = @h[:m]
    a = [ ]
    @h[:a].each do | e |
      a << e
    end
    a.should == [ 0, 1, p, 3, 4, p ]
  end

  it "should handle proxy swizzling through Array#map" do
    @s.encode!(@h)
    p = @h[:m]
    a = @h[:a].each { | e | e }
    a.should == [ 0, 1, p, 3, 4, p ]
  end

  it "should handle proxy swizzling through Array#map!" do
    @s.encode!(@h)
    p = @h[:m]
    a = @h[:a].map! { | e | 1; e }
    a.should == [ 0, 1, p, 3, 4, p ]
  end

  it "should handle proxy swizzling through Array#select" do
    @s.encode!(@h)
    p = @h[:m]
    a = @h[:a].select { | e | @m.class == e.class }
    a.should == [ p, p ]
  end

  it "should handle proxy swizzling through Array#find" do
    @s.encode!(@h)
    p = @h[:m]
    a = @h[:a].find { | e | @m.class == e.class }
    a.should == p
  end

  it "should lazily traverse proxies" do
    fm = TrickSerial::Serializer::Test::PhonyActiveRecord.find_map

    fm[@m.id].should == nil

    @s.encode!(@h)

    # Note: Structs are anonymous Classes and cannot be Marshal'ed.
    @h[:s] = nil
    @h = Marshal.load(Marshal.dump(@h))

    fm[@m.id].should == nil

    p = @h[:m]

    fm[@m.id].should == 1

    @h[:m].object_id.should == p.object_id
    @h[:a][2].object_id.should == p.object_id
    @h[:a][5].object_id.should == p.object_id

    fm[@m.id].should == 1
    fm.keys.size.should == 1
  end

  it "should preserve object identity" do
    @s.encode!(@h)

    p = @h[:m]

    @h[:m].object_id.should == p.object_id
    @h[:a2].object_id.should == @h[:a].object_id
    @h[:a][2].object_id.should == p.object_id
    @h[:a][5].object_id.should == p.object_id
  end

  it "should produce a serializable result" do
    @s.encode!(@h)

    # Note: Structs are anonymous Classes and cannot be Marshal'ed.
    @h[:s] = nil
    @o = Marshal.load(Marshal.dump(@h))

    p = @o[:m]
    p.class.should == @m.class

    @o[:m].object_id.should == p.object_id
    @o[:a][2].object_id.should == p.object_id
    @o[:a][5].object_id.should == p.object_id
    @o[:h2].object_id.should == @o.object_id
  end

  it "should copy core collections" do
    @o = @s.encode(@h)

    @o.object_id.should_not == @h.object_id
    @o[:a].object_id.should_not == @h[:a].object_id
    @o[:a2].object_id.should == @o[:a].object_id

    @o[:m].object_id.should_not == @h[:m].object_id
    @o[:h2].object_id.should == @o.object_id
  end

  it "should honor :instance_vars option" do
    obj = t::A.new
    obj.x = @m
    obj.y = @m
    obj = @s.encode!(obj)
    e = Marshal.load(str = Marshal.dump(obj))
    # $stderr.puts "marshal = #{str.inspect}"

    e.class.should == t::A
    e.x._proxy_class.should == TrickSerial::Serializer::ProxySwizzlingIvar
    # e.instance_variable_get("@x").class.should == TrickSerial::Serializer::ProxySwizzlingIvar # BUG!?!?!
    e.x.class.should == TrickSerial::Serializer::Test::Model
    e.instance_variable_get("@x").class.should == TrickSerial::Serializer::Test::Model

    e.y._proxy_class.should == TrickSerial::Serializer::ProxySwizzlingIvar
    # e.instance_variable_get("@y").class.should == TrickSerial::Serializer::ProxySwizzlingIvar # BUG!?!?!
    e.y.class.should == TrickSerial::Serializer::Test::Model
    e.instance_variable_get("@y").class.should == TrickSerial::Serializer::Test::Model
    e.x.object_id.should == e.y.object_id

    obj = t::B.new
    obj.x = @m
    obj.y = @m
    obj = @s.encode!(obj)
    e = Marshal.load(str = Marshal.dump(obj))
    # $stderr.puts "marshal = #{str.inspect}"

    e.class.should == t::B
    e.x._proxy_class.should == TrickSerial::Serializer::ProxySwizzlingIvar
    # e.instance_variable_get("@x").class.should == TrickSerial::Serializer::ProxySwizzlingIvar # BUG!?!?!
    e.x.class.should == @m.class
    e.instance_variable_get("@x").class.should == TrickSerial::Serializer::Test::Model
    lambda { e.y._proxy_class }.should raise_error
    e.instance_variable_get("@y").class.should == TrickSerial::Serializer::Test::Model
    e.y.class.should == @m2.class
    e.x.id.should == @m.id
    e.y.id.should == @m.id
    e.x.object_id.should_not == @m.object_id
    e.x.object_id.should_not == e.y.object_id
    e.y.object_id.should_not == @m.object_id
  end

end
