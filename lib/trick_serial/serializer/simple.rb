
require 'trick_serial/serializer'

module TrickSerial
class Serializer
  # Simple, non-swizzling coder.
  # This requires encode and decode operations.
  # Array and Hash are not extended to support swizzling.
  # Ivar swizzling is not used.
  class Simple < self
    def _encode! x
      @traverse_mode = :_encode!
      _traverse! x
    end

    def _decode! x
      @traverse_mode = :_decode!
      _traverse! x
    end

    def _traverse! x
      # pp [ :_traverse!, @traverse_mode, x.class, x ] if @debug >= 1

      case x
      when *@do_not_traverse
        # NOTHING

      when ObjectProxy
        if @traverse_mode == :_decode!
          x = x.object
        end

      when Struct
        if o = @visited[x.object_id]
          return o.first
        end
        o = x
        x = _copy_with_extensions(x)
        @visited[o.object_id] = [ x, o ]
        x.class.members.each do | m |
          v = x.send(m)
          v = _traverse! v
          x.send(:"#{m}=", v)
        end

      when OpenStruct
        if o = @visited[x.object_id]
          return o.first
        end
        o = x
        x = _copy_with_extensions(x)
        @visited[o.object_id] = [ x, o ]
        t = x.instance_variable_get("@table")
        t.keys.to_a.each do | k |
          v = t._get_without_trick_serial(k)
          v = _traverse! v
          x.send(:"#{k}=", v)
        end

      when Array
        if o = @visited[x.object_id]
          return o.first
        end
        o = x
        x = _copy_with_extensions(x)
        @visited[o.object_id] = [ x, o ]
        x.map! do | v |
          _traverse! v
        end

      when Hash
        if o = @visited[x.object_id]
          return o.first
        end
        o = x
        x = _copy_with_extensions(x)
        @visited[o.object_id] = [ x, o ]
        x.keys.to_a.each do | k |
          x[k] = _traverse!(x[k])
        end

      when *@proxyable
        if proxy = @object_to_proxy_map[x.object_id]
          return proxy.first
        end
        # debugger
        o = x
        proxy_cls = nil
        if class_option = self._class_option(x)
          proxy_cls = class_option[:proxy_class]
          # Deeply encode instance vars?
          if ivs = class_option[:instance_vars]
            ivs = x.instance_variables if ivs == true
            x = _copy_with_extensions(x)
            @object_to_proxy_map[o.object_id] = [ x, o ]
            ivs.each do | ivar |
              v = x.instance_variable_get(ivar)
              v = _traverse!(v)
              x.instance_variable_set(ivar, v)
            end
          end
        end
        if @traverse_mode == :_decode!
          @object_to_proxy_map[o.object_id] ||= [ x, o ]
        else
          x = _make_proxy o, x, proxy_cls
        end
      end # case

      # pp [ :_traverse!, @traverse_mode, :RESULT, x.class, x ] if @debug >= 2

      x
    end # def

  end # class
end # class
end # module


