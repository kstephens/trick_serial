
module Cnu
  class Serializer
    attr_accessor :proxy_class_map
    attr_reader :root

    @@proxy_class_map = nil

    def initialize
      @proxy_class_map ||= @@proxy_class_map
    end

    def encode! x
      @root = x
      @visited = { }
      @proxyable = @proxy_class_map.keys
      @object_to_proxy_map = { }
      @class_proxy_cache = { }
      # debugger
      _encode! x
      x
    end

    def _encode! x
      # pp [ :_encode!, x.class, x ]

      case x
      when ObjectProxy
        x

      when Array
        return x if @visited[x.object_id]
        @visited[x.object_id] = x
        extended = false
        x.map! do | v |
          v = _encode! v
          if ObjectProxy === v && ! extended
            x.extend ProxySwizzlingArray
            extended = true
          end
          v
        end

      when Hash
        return x if @visited[x.object_id]
        @visited[x.object_id] = x
        extended = false
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
          x = proxy
        end
      end

      x
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
        @object ||= 
          eval(@cls.to_s).find(@id) || 
          (raise Error::DisappearingObject, "#{@cls.inspect} #{@id.inspect}")
      end
    end
 
    ##################################################################

    module ProxySwizzlingArray
      def [](i)
        if ! @does_not_have_proxies && ObjectProxy === (p = super)
          p = self[i] = p.object
        end
        p
      end

      def each
        unless @does_not_have_proxies
          super { | x | }
          @does_not_have_proxies = false
        end
        super
      end
    end
    module ProxySwizzlingHash

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

      def values
        keys.to_a.each do | k |
          self[k]
        end
        super
      end
    end
  end # class
end # module


