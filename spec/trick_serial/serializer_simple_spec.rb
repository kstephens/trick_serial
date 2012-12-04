require File.expand_path('../../spec_helper', __FILE__)

require 'trick_serial/serializer/simple'

######################################################################

describe "TrickSerial::Serializer::Simple" do
  def t
    TrickSerial::Serializer::Test
  end
  before(:each) do 
    @s = TrickSerial::Serializer::Simple.new
    @s.class_option_map = {
      t::PhonyActiveRecord => { :proxy_class => TrickSerial::Serializer::ActiveRecordProxy, },
      t::A => { :instance_vars => true },
      t::B => { :instance_vars => [ "@x" ] },
    }
    TrickSerial::Serializer::Test::PhonyActiveRecord.find_map.clear
    # Note: Structs are anonymous Classes and cannot be Marshal'ed.
    @struct = Struct.new :sm, :sa, :sb
    @m = TrickSerial::Serializer::Test::Model.new(123)
    @m2 = TrickSerial::Serializer::Test::Model.new(456)
    @m_unsaved = TrickSerial::Serializer::Test::Model.new(:unsaved)
    @m_unsaved.id = nil
    @os = OpenStruct.new
    @h = {
      :a => 1,
      'b' => 2,
      :obj => Object.new,
      :m => @m,
      :a => [ 0, 1, @m, 3, 4, @m ],
      :m_unsaved => @m_unsaved,
      :os => @os,
    }
    @os.osm = @m
    @os.osa = @h
    @os.osb = 'b'
    @h[:a2] = @h[:a]
    @h[:h2] = @h
  end

  it "should handle #encode!" do
    @h[:m].should == @m
    @h[:a][2].should == @m

    result = @s.encode!(@h)

    result.object_id.should == @h.object_id
  end

  it "should handle #decode!" do
    @h[:m].should == @m
    @h[:a][2].should == @m

    result = @s.decode!(@h)

    result.object_id.should == @h.object_id
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

  it "should proxy saved models directly" do
    @s.debug = 0

    @o = @s.encode!(@m)
    @o.object_id.should_not == @m.object_id
    @o.class.should == TrickSerial::Serializer::ActiveRecordProxy
    @o.cls.should == @m.class.name.to_sym
    @o.id.should == @m.id

    @o = @s.decode!(@o)

    @o.object_id.should_not == @m.object_id
    @o.class.should == @m.class
    @o.id.should == @m.id
  end

  it "should not proxy saved models twice" do
    @s.debug = 0

    @o = @s.encode!(@m)
    @o.object_id.should_not == @m.object_id
    @o.class.should == TrickSerial::Serializer::ActiveRecordProxy
    @o.cls.should == @m.class.name.to_sym
    @o.id.should == @m.id

    @o1 = @o
    @o = @s.encode!(@o)
    @o.object_id.should == @o1.object_id
    @o.class.should == TrickSerial::Serializer::ActiveRecordProxy
  end

  it "should proxy saved models" do
    @o = @s.encode!(@h)
    @o = @s.decode!(@o)
    @o[:m].object_id.should_not == @m.object_id
    @o[:m].class.should == @m.class
    @o[:m].id.should == @m.id
  end

  it "should not proxy unsaved models" do
    @o = @s.encode!(@h)
    @o = @s.decode!(@o)
    @o[:m_unsaved].object_id.should == @m_unsaved.object_id
  end

  it "should handle encode/decode through Hash#[]" do
    @s.encode!(@h)
    @s.decode!(@h)
    p = @h[:m]
    # pp [ :p=, p ]
    p.class.should == @m.class
  end

  it "should handle encode/decode through Hash#values" do
    @s.encode!(@h)
    p = @h.values
    p.select{|m| @m.class == m.class}.size.should == 1 # one of them is not proxyable.

    @s.decode!(@h)
    p = @h.values
    p.select{|m| @m.class == m.class}.size.should == 2
  end

  it "should handle encode/decode through Array#[]" do
    @s.encode!(@h)
    p = @h[:a][2]
    p.class.should_not == @m.class

    @s.decode!(@h)
    p = @h[:a][2]
    p.class.should == @m.class
  end

  it "should handle encode/decode through Array#each" do
    @s.encode!(@h)
    p = @h[:m]
    a = [ ]
    @h[:a].each do | e |
      a << e
    end
    a.should == [ 0, 1, p, 3, 4, p ]

    @s.decode!(@h)
    p = @h[:m]
    a = [ ]
    @h[:a].each do | e |
      a << e
    end
    a.should == [ 0, 1, p, 3, 4, p ]
  end

  it "should handle encode/decode through Array#map" do
    @s.encode!(@h)
    @s.decode!(@h)
    p = @h[:m]
    a = @h[:a].each { | e | e }
    a.should == [ 0, 1, p, 3, 4, p ]
  end

  it "should handle encode/decode through Array#map!" do
    @s.encode!(@h)
    @s.decode!(@h)
    p = @h[:m]
    a = @h[:a].map! { | e | 1; e }
    a.should == [ 0, 1, p, 3, 4, p ]
  end

  it "should handle encode/decode through Array#select" do
    @s.encode!(@h)
    @s.decode!(@h)
    p = @h[:m]
    a = @h[:a].select { | e | @m.class == e.class }
    a.should == [ p, p ]
  end

  it "should handle encode/decode through Array#find" do
    @s.encode!(@h)
    @s.decode!(@h)
    p = @h[:m]
    a = @h[:a].find { | e | @m.class == e.class }
    a.should == p
  end

  it "should handle encode/decode through OpenStruct" do
    @o = @s.encode!(@os)
    @o.osm.class.should == TrickSerial::Serializer::ActiveRecordProxy
    @o = @s.decode!(@o)
    @o.object_id.should == @os.object_id
    @o.osm.class.should == TrickSerial::Serializer::Test::Model
  end

  it "should handle encode/decode through OpenStruct" do
    s = @struct.new
    s.sm = @m
    s.sa = 'a'
    s.sb = :b

    @o = @s.encode!(s)
    @o.sm.class.should == TrickSerial::Serializer::ActiveRecordProxy
    @o = @s.decode!(@o)
    @o.object_id.should == s.object_id
    @o.sm.class.should == TrickSerial::Serializer::Test::Model
  end

  it "should lazily traverse proxies" do
    fm = TrickSerial::Serializer::Test::PhonyActiveRecord.find_map

    fm[@m.id].should == nil

    @s.encode!(@h)
    @h = Marshal.load(Marshal.dump(@h))

    fm[@m.id].should == nil

    @s.decode!(@h)
    fm[@m.id].should == 1

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
    @s.decode!(@h)

    p = @h[:m]

    @h[:m].object_id.should == p.object_id
    @h[:a2].object_id.should == @h[:a].object_id
    @h[:a][2].object_id.should == p.object_id
    @h[:a][5].object_id.should == p.object_id
  end

  it "should produce a serializable result" do
    @s.encode!(@h)

    @o = Marshal.load(Marshal.dump(@h))
    @o = @s.decode!(@o)

    p = @o[:m]
    p.class.should == @m.class

    @o[:m].object_id.should == p.object_id
    @o[:a][2].object_id.should == p.object_id
    @o[:a][5].object_id.should == p.object_id
    @o[:h2].object_id.should == @o.object_id
  end

  it "should copy core collections" do
    @o = @s.encode(@h)
    @o = @s.decode(@o)

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

    e.class.should == t::A
    e.instance_variable_get("@x").class.should == TrickSerial::Serializer::ActiveRecordProxy
    e.instance_variable_get("@y").class.should == TrickSerial::Serializer::ActiveRecordProxy

    @s.verbose = true; @s.debug = 0
    obj = @s.decode!(e)
    # $stderr.puts "marshal = #{str.inspect}"

    e.class.should == t::A
    e.instance_variable_get("@x").class.should == TrickSerial::Serializer::Test::Model
    e.instance_variable_get("@y").class.should == TrickSerial::Serializer::Test::Model
    e.x.object_id.should == e.y.object_id

    obj = t::B.new
    obj.x = @m # should be encoded
    obj.y = @m # should not be encoded
    @s.verbose = false; @s.debug = 0
    obj = @s.encode!(obj)
    e = Marshal.load(str = Marshal.dump(obj))

    e.class.should == t::B
    e.instance_variable_get("@x").class.should == TrickSerial::Serializer::ActiveRecordProxy
    e.instance_variable_get("@y").class.should == TrickSerial::Serializer::Test::Model

    @s.verbose = true; @s.debug = 0
    obj = @s.decode!(e)
    # $stderr.puts "marshal = #{str.inspect}"

    e.class.should == t::B
    e.instance_variable_get("@x").class.should == TrickSerial::Serializer::Test::Model
    e.x.class.should == @m.class
    e.instance_variable_get("@y").class.should == TrickSerial::Serializer::Test::Model
    e.y.class.should == @m.class
    e.x.id.should == @m.id
    e.y.id.should == @m.id
    e.x.object_id.should_not == @m.object_id
    e.x.object_id.should_not == e.y.object_id
    e.y.object_id.should_not == @m.object_id
  end

end
