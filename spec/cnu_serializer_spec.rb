require File.expand_path('../spec_helper', __FILE__)

require 'cnu/serializer'

######################################################################

module Cnu
  class Serializer
    module Test
      class PhonyActiveRecord
        attr_accessor :id

        @@find_map = { }
        def self.find_map
          @@find_map
        end

        def initialize
          @id = object_id
        end
        def self.find(id)
          obj = new
          obj.id = id
          # $stderr.puts "  #{self}.find(#{id.inspect}) => #{obj.inspect}"
          # (@@find_map[id] ||= 0) += 1 # Shouldn't Ruby parse this?
          @@find_map[id] ||= 0
          @@find_map[id] += 1
          obj
        end
      end
      
      class Model < PhonyActiveRecord
        attr_accessor :state
        def initialize x = nil
          super()
          @state = x
        end
      end
    end
  end
end

describe "CnuSerializer" do
  before(:each) do 
    @s = Cnu::Serializer.new
    @s.proxy_class_map = { 
      Cnu::Serializer::Test::PhonyActiveRecord => Cnu::Serializer::ActiveRecordProxy,
    }
    Cnu::Serializer::Test::PhonyActiveRecord.find_map.clear

    @m = Cnu::Serializer::Test::Model.new(123)
    @m_unsaved = Cnu::Serializer::Test::Model.new(:unsaved)
    @m_unsaved.id = nil
    @h = {
      :a => 1,
      'b' => 2,
      :obj => Object.new,
      :m => @m,
      :a => [ 0, 1, @m, 3, 4, @m ],
      :m_unsaved => @m_unsaved,
    }
    @h[:a2] = @h[:a]
    @h[:h2] = @h
  end

  it "should handle #encode!" do
    @h[:m].should == @m
    @h[:a][2].should == @m

    result = @s.encode!(@h)

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

  it "should handle proxy swizzling" do
    @s.encode!(@h)
    p = @h[:m]
    # pp [ :p=, p ]
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
    a = @h[:a].select { | e | Cnu::Serializer::Test::Model === e }
    a.should == [ p, p ]
  end

  it "should handle proxy swizzling through Array#find" do
    @s.encode!(@h)
    p = @h[:m]
    a = @h[:a].find { | e | Cnu::Serializer::Test::Model === e }
    a.should == p
  end

  it "should lazily traverse proxies" do
    fm = Cnu::Serializer::Test::PhonyActiveRecord.find_map

    fm[@m.id].should == nil

    @s.encode!(@h)

    @h = Marshal.load(Marshal.dump(@h))

    fm[@m.id].should == nil

    p = @h[:m]

    fm[@m.id].should == 1

    @h[:m].object_id.should == p.object_id
    @h[:a][2].object_id.should == p.object_id
    @h[:a][5].object_id.should == p.object_id

    fm[@m.id].should == 1
  end

  it "should preserve object identity" do
    @s.encode!(@h)

    p = @h[:m]

    @h[:m].object_id.should == p.object_id
    @h[:m2].object_id.should == p.object_id
    @h[:a][2].object_id.should == p.object_id
    @h[:a][5].object_id.should == p.object_id
  end

  it "should produce a serializable result" do
    @s.encode!(@h)

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

end
