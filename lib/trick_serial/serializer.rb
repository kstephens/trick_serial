
module TrickSerial
  # Serializes objects using proxies for classes defined in #proxy_class_map.
  # Instances of the keys in #proxy_class_map are replaced by proxies if
  # the proxy class returns true for #can_proxy?(instance).
  #
  # Container classes are extended with ProxySwizzling to automatically replace
  # the Proxy objects with their #object when accessed.
  class Serializer
    attr_accessor :proxy_class_map, :logger, :logger_level
    attr_reader :root

    @@proxy_class_map = nil
    def self.proxy_class_map 
      @@proxy_class_map
    end
    def self.proxy_class_map= x
      @@proxy_class_map = x
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
      @proxy_class_map ||= @@proxy_class_map
    end

    # Same as #encode!, but copies Array and Hash structures
    # recursively.
    def encode x
      @copy = true
      encode! x
    end

    # Encodes using #proxy_class_map in-place.
    def encode! x
      @root = x
      @visited = { }
      @proxyable = @proxy_class_map.keys
      @object_to_proxy_map = { }
      @class_proxy_cache = { }
      # debugger
      o = _encode! x
      @copy =
      @visited = @proxyable = 
        @object_to_proxy_map = 
        @class_proxy_cache = 
        @root = nil
      o
    end

    def _encode! x
      # pp [ :_encode!, x.class, x ]

      case x
      when ObjectProxy
        x

      when Array
        if o = @visited[x.object_id]
          return o
        end
        extended = false
        o = @copy ? x.dup : x
        @visited[x.object_id] = o
        x = o
        x.map! do | v |
          v = _encode! v
          if ObjectProxy === v && ! extended
            x.extend ProxySwizzlingArray
            extended = true
          end
          v
        end

      when Hash
        if o = @visited[x.object_id]
          return o
        end
        extended = false
        o = @copy ? x.dup : x
        @visited[x.object_id] = o
        x = o
        x.keys.to_a.each do | k |
          v = x[k] = _encode!(x[k])
          if ObjectProxy === v && ! extended
            x.extend ProxySwizzlingHash
            extended = true
          end
        end

      when *@proxyable
        if proxy = @object_to_proxy_map[x.object_id]
          return proxy
        end
        # debugger

        # Get the proxy class for this object.
        proxy_cls = 
          @class_proxy_cache[x.class] ||= 
          x.class.ancestors.
          map { |c| @proxy_class_map[c] }.
          find { |c| c }

        # Can the object be proxied?
        # i.e. does it have an id?
        if proxy_cls.can_proxy?(x)
          proxy = proxy_cls.new(x)
          @object_to_proxy_map[x.object_id] = proxy
          _log { "created proxy #{proxy} for #{x.class} #{x.id}" }
          x = proxy
        end
      end

      x
    end

    def _log msg = nil
      msg ||= yield if block_given?
      if msg && @logger
        @logger.send(@logger_level, msg)
      end
    end


    module ObjectProxy
      class Error < ::Exception
        class DisappearingObject < self; end
      end

      attr_reader :cls, :id

      def self.included target
        super
        target.extend(ClassMethods)
      end

      def initialize obj
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

=begin
      def _dump *args
        # @object = nil
        Marshal.dump([ @cls, @id ])
      end
=end
      module ClassMethods
=begin
        def _load str
          @cls, @id = Marshal.load(str)
        end
=end
      end

    end

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
    end
 
    ##################################################################

    module ProxySwizzling
    end

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
    end

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
    end
  end # class
end # module


