require 'trick_serial'

module TrickSerial
  # Serializes objects using proxies for classes defined in #proxy_class_map.
  # Instances of the keys in #proxy_class_map are replaced by proxies if
  # the proxy class returns true for #can_proxy?(instance).
  #
  # Container classes are extended with ProxySwizzling to automatically replace
  # the Proxy objects with their #object when accessed.
  #
  # The result of this class does not require explicit decoding.  However,
  # this particular class only works with serializers that can handle
  # Hash and Array objects extended with Modules.
  #
  # See Serializer::Simple for support for simpler encode/decode behavior
  # without ProxySwizzling support.
  class Serializer
    # Boolean or Proc.
    attr_accessor :enabled

    attr_accessor :logger, :logger_level
    attr_accessor :verbose, :debug
    attr_reader :root

    attr_accessor :class_option_map
    @@class_option_map = nil
    def self.class_option_map 
      @@class_option_map
    end
    def self.class_option_map= x
      @@class_option_map = x
    end

    @@default = nil
    def self.default
      Thread.current[:'TrickSerial::Serializer.default'] ||
        @@default
    end
    def self.default= x
      @@default = x
    end

    def initialize
      @class_option_map ||= @@class_option_map || EMPTY_Hash
      @enabled = true
      @debug = 0
    end

    def enabled?
      case @enabled
      when Proc
        @enabled.call
      else
        @enabled
      end
    end

    # Same as #encode!, but copies Array and Hash structures
    # recursively.
    # Does not copy structure if #enabled? is false.
    def encode x
      return x unless enabled?
      @copy = true
      encode! x
    end

    # Encodes using #proxy_class_map in-place.
    def encode! x
      _prepare x do
        _encode! x
      end
    end

    # Same as #decode!, but copies Array and Hash structures
    # recursively.
    # Does not copy structure if #enabled? is false.
    # Only implemented by some subclasses.
    def decode x
      return x unless enabled?
      @copy = true
      decode! x
    end

    # Decodes using #proxy_class_map in-place.
    # Only implemented by some subclasses.
    def decode! x
      _prepare x do 
        _decode! x
      end
    end

    def _prepare x
      return x unless enabled?
      proxyable
      @root = x
      @visited = { }
      @object_to_proxy_map = { }
      # debugger
      yield
    ensure
      @visited.clear if @visited
      @object_to_proxy_map.clear if @object_to_proxy_map
      @copy =
      @visited =
        @object_to_proxy_map = 
        @root = nil
    end

    # Returns a list of Modules that are proxable based on the configuration.
    def proxyable
      unless @proxyable
        @proxyable = @class_option_map.keys.select{|cls| ! @class_option_map[cls][:do_not_traverse]}
        @do_not_traverse ||= @class_option_map.keys.select{|cls| @class_option_map[cls][:do_not_traverse]} << ObjectProxy
        @class_option_cache ||= { }
        @proxyable.freeze
      end
      @proxyable
    end


    ##################################################################


    def _encode! x
      # pp [ :_encode!, x.class, x.object_id, x.to_s ] if @debug >= 1

      case x
      when *@do_not_traverse
        # NOTHING

      when ObjectProxy
        # NOTHING

      when Struct
        if o = @visited[x.object_id]
          return o.first
        end
        o = x
        x = _copy_with_extensions(x)
        @visited[o.object_id] = [ x, o ]
        x = o
        x.class.members.each do | m |
          v = x.send(m)
          v = _encode! v
          x.send(:"#{m}=", v)
        end

      when OpenStruct
        if o = @visited[x.object_id]
          return o.first
        end
        o = x
        x = _copy_with_extensions(x)
        @visited[o.object_id] = [ x, o ]
        x = o
        t = x.instance_variable_get("@table")
        t.each do | k, v |
          t[k] = _encode! v
        end

      when Array
        if o = @visited[x.object_id]
          return o.first
        end
        o = x
        x = _copy_with_extensions(x)
        @visited[o.object_id] = [ x, o ]
        extended = false
        x.map! do | v |
          v = _encode! v
          if ! extended && ObjectProxy === v
            x.extend ProxySwizzlingArray
            extended = true
          end
          v
        end

      when Hash
        if o = @visited[x.object_id]
          return o.first
        end
        o = x
        x = _copy_with_extensions(x)
        @visited[o.object_id] = [ x, o ]
        extended = false
        x.keys.to_a.each do | k |
          # pp [ :Hash_key, k ] if @debug >= 1
          v = x[k] = _encode!(x[k])
          if ! extended && ObjectProxy === v
            x.extend ProxySwizzlingHash
            extended = true
          end
        end

      when *@proxyable
        if proxy = @object_to_proxy_map[x.object_id]
          # if @debug >= 1
          #   o = proxy.first
          #   $stderr.puts "  #{x.class} #{x.object_id} ==>> (#{o.class} #{o.object_id})"
          # end
          return proxy.first
        end
        # debugger

        o = x
        proxy_x = proxy_cls = nil
        if class_option = _class_option(x)
          proxy_cls = class_option[:proxy_class]
          # Deeply encode instance vars?
          if ivs = class_option[:instance_vars]
            ivs = x.instance_variables if ivs == true
            x = _copy_with_extensions x
            proxy_x = _make_proxy o, x, proxy_cls
            ivs.each do | ivar |
              v = x.instance_variable_get(ivar)
              v = _encode!(v)
              if ObjectProxy === v
                ivar.freeze
                v = ProxySwizzlingIvar.new(x, ivar, v)
              end
              x.instance_variable_set(ivar, v)
            end
          else
            proxy_x = _make_proxy o, x, proxy_cls
          end
        end
        x = proxy_x if proxy_cls
      end

      # pp [ :"_encode!=>", x.class, x.object_id, x.to_s ] if @debug >= 1

      x
    end # def
    
    def _class_option x
      (@class_option_cache[x.class] ||=
       [
        x.class.ancestors.
        map { |c| @class_option_map[c] }.
        find { |c| c }
       ]).first
    end

    # Create a proxy for x for original object o.
    # x may be a dup of o.
    def _make_proxy o, x, proxy_cls
      # Can the object x be proxied for the original object o?
      # i.e. does it have an id?
      if proxy_cls && proxy_cls.can_proxy?(x)
        x = proxy_cls.new(x, self)
        _log { "created proxy #{x} for #{o.class} #{o.id}" }
      end
      @object_to_proxy_map[o.object_id] = [ x, o ]
      x
    end

    def _copy_with_extensions x
      if @copy 
        o = x.dup
        (_extended_by(x) - _extended_by(o)).reverse_each do | m |
          o.extend(m)
        end rescue nil # :symbol.extend(m) => TypeError: can't define singleton
        x = o
      end
      x
    end

    # This is similar to Rails Object#extended_by.
    def _extended_by x
      # Note: if Symbol === x this happens:
      # #<TypeError: no virtual class for Symbol>
      (class << x; ancestors; end) rescue [ ]
    end

    def _log msg = nil
      if @logger
        msg ||= yield if block_given?
        @logger.send(@logger_level, msg) if msg
      end
    end


    module ObjectProxy
      class Error < ::Exception
        class DisappearingObject < self; end
      end

      attr_reader :cls, :id

      def self.included target
        super
      end

      def initialize obj, serializer
        self.object = obj
      end

      def resolve_class
        @resolve_class ||=
          eval("::#{@cls.to_s}")
      end

      def object= x
        # @object = x
        @cls = x && x.class.name.to_sym
        @id = x && x.id
      end
    end # module

    class ActiveRecordProxy
      include ObjectProxy

      def self.can_proxy?(obj)
        obj.id
      end

      def object
        # STDERR.puts "#{self}#object find #{@cls.inspect} #{@id.inspect}" unless @object
        @object ||= 
          resolve_class.find(@id) || 
          (raise Error::DisappearingObject, "#{@cls.inspect} #{@id.inspect}")
      end
    end # class
 
    ##################################################################

    # Base module for all ProxySwizzling.
    # http://en.wikipedia.org/wiki/Pointer_swizzling
    module ProxySwizzling
    end

    class ProxySwizzlingIvar
      include ProxySwizzling
      alias :_proxy_class :class
      def class
        method_missing :class
      end
      
      alias :_proxy_object_id :object_id
      def object_id
        method_missing :object_id
      end

      alias :_proxy_id :id
      def id
        method_missing :id
      end

      def initialize owner, name, value
        @owner, @name, @value = owner, name, value
      end
      private :initialize

      def method_missing sel, *args, &blk
        if @owner
          if ObjectProxy === @value
            @value = @value.object
          end
          @owner.instance_variable_set(@name, @value)
          @owner = @name = nil
        end
        @value.__send__(sel, *args, &blk)
      end
    end # class

    module ProxySwizzlingArray
      include ProxySwizzling
      def [](i)
        p = super
        if ! @does_not_have_proxies && ObjectProxy === p
          p = self[i] = p.object
        end
        p
      end

      def each
        unless @does_not_have_proxies
          size.times do | i |
            self[i]
          end
          @does_not_have_proxies = false
        end
        super
      end

      def map!
        each { | e | e }
        super
      end
      
      def select
        each { | e | }
        super
      end
    end # module

    module ProxySwizzlingHash
      include ProxySwizzling
      def [](i)
        if ObjectProxy === (p = super)
          p = self[i] = p.object
        end
        p
      end

      def each
        values
        super
      end

      def each_pair 
        values
        super
      end

      def values
        keys.to_a.each do | k |
          self[k]
        end
        super
      end
    end # module

  end # class
end # module


