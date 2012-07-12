
require 'trick_serial/serializer'

module TrickSerial
class Serializer
  # Simple, non-swizzling coder.
  # This requires encode and decode operations.
  # Array and Hash are not extended to support swizzling.
  # Ivar swizzling is not used.
  class Simple < self
    def _encode! x
      # pp [ :_encode!, x.class, x ]

      case x
      when ObjectProxy
        x

      when Array
        if o = @visited[x.object_id]
          return o.first
        end
        extended = false
        o = x
        x = x.dup if @copy
        @visited[o.object_id] = [ x, o ]
        x.map! do | v |
          _encode! v
        end

      when Hash
        if o = @visited[x.object_id]
          return o.first
        end
        extended = false
        o = x
        x = x.dup if @copy
        @visited[o.object_id] = [ x, o ]
        x.keys.to_a.each do | k |
          x[k] = _encode!(x[k])
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
            x = x.dup if @copy
            @object_to_proxy_map[o.object_id] = [ x, o ]
            ivs.each do | ivar |
              v = x.instance_variable_get(ivar)
              v = _encode!(v)
              x.instance_variable_set(ivar, v)
            end
          end
        end
        
        x = _make_proxy o, x, proxy_cls
      end

      x
    end # def

    def _decode! x
      case x
      when ObjectProxy
        x = x.object

      when Array
        if o = @visited[x.object_id]
          return o.first
        end
        extended = false
        o = x
        x = x.dup if @copy
        @visited[o.object_id] = [ x, o ]
        x.map! do | v |
          _decode! v
        end
        
      when Hash
        if o = @visited[x.object_id]
          return o.first
        end
        extended = false
        o = x
        x = x.dup if @copy
        @visited[o.object_id] = [ x, o ]
        x.keys.to_a.each do | k |
          x[k] = _decode!(x[k])
        end
        
      when *@proxyable
        if proxy = @object_to_proxy_map[x.object_id]
          return proxy.first
        end
        # debugger
        o = x
        if class_option = _class_option(x)
          # Deeply encode instance vars?
          if ivs = class_option[:instance_vars]
            ivs = x.instance_variables if ivs == true
            x = x.dup if @copy
            @object_to_proxy_map[o.object_id] = [ x, o ]
            ivs.each do | ivar |
              v = x.instance_variable_get(ivar)
              # $stderr.puts "\n#{x.class} #{x.object_id} ivar #{ivar} #{v.inspect}" if @debug
              v = _decode!(v)
              x.instance_variable_set(ivar, v)
            end
          end
        end
        @object_to_proxy_map[o.object_id] ||= [ x, o ]
      end # case
      
      x
    end # def
    
  end # class
end # class
end # module


