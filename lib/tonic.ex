defmodule Tonic do
    defmacro __using__(_options) do
        quote do
            import Tonic
            import Tonic.Types

            @before_compile unquote(__MODULE__)
            @tonic_current_scheme :load
            @tonic_previous_scheme []
            @tonic_data_scheme Map.put(%{}, @tonic_current_scheme, [])
        end
    end

    defp create_call({ function }), do: quote do: unquote(function)(data, nil, endian, fn { _, value } -> value end)
    defp create_call({ function, name }), do: quote do: unquote(function)(data, unquote(name), endian)
    defp create_call({ function, name, fun }) when is_function(fun) or is_tuple(fun), do: quote do: unquote(function)(data, unquote(name), endian, unquote(fun))
    defp create_call({ function, name, endianness }), do: quote do: unquote(function)(data, unquote(name), unquote(endianness))
    defp create_call({ :repeat, function, name, length }), do: quote do: repeater(unquote({ :&, [], [{ :/, [], [{ function, [], __MODULE__ }, 3] }] }), unquote(length), data, unquote(name), endian)
    defp create_call({ function, name, endianness, fun }), do: quote do: unquote(function)(data, unquote(name), unquote(endianness), unquote(fun))
    defp create_call({ :repeat, function, name, length, fun }), do: quote do: repeater(unquote({ :&, [], [{ :/, [], [{ function, [], __MODULE__ }, 3] }] }), unquote(length), data, unquote(name), endian, unquote(fun))

    defp expand_data_scheme([], init_value), do: [quote([do: { unquote(init_value), data }])]
    defp expand_data_scheme(scheme, init_value) do
        [quote([do: loaded = unquote(init_value)])|expand_operation(scheme, [quote([do: { loaded, data }])])]
    end

    defp expand_operation([], ops), do: ops
    defp expand_operation([{ :endian, endianness }|scheme], ops), do: expand_operation(scheme, [quote([do: endian = unquote(endianness)])|ops])
    defp expand_operation([op|scheme], ops) do
        expand_operation(scheme, [
            quote([do: { value, data } = unquote(create_call(op))]),
            quote([do: loaded = :erlang.append_element(loaded, value)])
        |ops])
    end

    defmacro __before_compile__(env) do
        quote do
            unquote({ :__block__, [], Map.keys(Module.get_attribute(env.module, :tonic_data_scheme)) |> Enum.map(fn scheme ->
                    { :def, [context: __MODULE__, import: Kernel], [
                            { scheme, [context: __MODULE__], [{ :data, [], __MODULE__ }, { :name, [], __MODULE__ }, { :endian, [], __MODULE__ }] },
                            [do: { :__block__, [], expand_data_scheme(Module.get_attribute(env.module, :tonic_data_scheme)[scheme], case to_string(scheme) do
                                <<"load_group_", _ :: binary>> -> quote do: { name }
                                _ -> quote do: {} #load, load_repeat_
                            end) }]
                        ] 
                    }
                end)
            })
        end
    end

    #loading
    def load(data, module) when is_binary(data) do
        module.load(data, nil, :native)
    end

    def load_file(file, module) do
        { :ok, data } = File.read(file)
        load(data, module)
    end

    #endian
    #endian :little
    defmacro endian(endianness) do
        quote do
            @tonic_data_scheme Map.put(@tonic_data_scheme, @tonic_current_scheme, [{ :endian, unquote(endianness) }|@tonic_data_scheme[@tonic_current_scheme]])
        end
    end

    #repeat
    #repeat times, :type
    defmacro repeat(length, type) when is_atom(type) do
        quote do
            repeat(nil, unquote(length), fn { _, value } ->
                Enum.map(value, fn { i } -> i end)
            end, [do: unquote(type)()])
        end
    end

    #repeat times, do: nil
    defmacro repeat(length, block) do
        quote do
            repeat(nil, unquote(length), fn { _, value } ->
                Enum.map(value, fn { i } -> i end)
            end, unquote(block))
        end
    end

    #repeat :new_repeat, times, :type
    defmacro repeat(name, length, type) when is_atom(type) do
        quote do
            repeat(unquote(name), unquote(length), fn { name, value } ->
                { name, Enum.map(value, fn { i } -> i end) }
            end, [do: unquote(type)()])
        end
    end

    #repeat :new_repeat, times, do: nil
    defmacro repeat(name, length, block) do
        repeat_func_name = String.to_atom("load_repeat_" <> to_string(name))

        quote do
            @tonic_data_scheme Map.put(@tonic_data_scheme, @tonic_current_scheme, [{ :repeat, unquote(repeat_func_name), unquote(name), unquote(length) }|@tonic_data_scheme[@tonic_current_scheme]])

            @tonic_previous_scheme [@tonic_current_scheme|@tonic_previous_scheme]
            @tonic_current_scheme unquote(repeat_func_name)
            @tonic_data_scheme Map.put(@tonic_data_scheme, @tonic_current_scheme, [])

            unquote(block)

            [current|previous] = @tonic_previous_scheme
            @tonic_previous_scheme previous
            @tonic_current_scheme current
        end
    end

    #repeat :new_repeat, times, fn { name, value } -> value end, do: nil
    defmacro repeat(name, length, fun, block) do
        repeat_func_name = String.to_atom("load_repeat_" <> to_string(name))

        quote do
            @tonic_data_scheme Map.put(@tonic_data_scheme, @tonic_current_scheme, [{ :repeat, unquote(repeat_func_name), unquote(name), unquote(length), unquote(Macro.escape(fun)) }|@tonic_data_scheme[@tonic_current_scheme]])

            @tonic_previous_scheme [@tonic_current_scheme|@tonic_previous_scheme]
            @tonic_current_scheme unquote(repeat_func_name)
            @tonic_data_scheme Map.put(@tonic_data_scheme, @tonic_current_scheme, [])

            unquote(block)

            [current|previous] = @tonic_previous_scheme
            @tonic_previous_scheme previous
            @tonic_current_scheme current
        end
    end

    defp repeater_(_func, 0, list, data, name, _endian), do: { { name, :lists.reverse(list) }, data }
    defp repeater_(func, n, list, data, name, endian) do
        { value, data } = func.(data, nil, endian)
        repeater_(func, n - 1, [value|list], data, name, endian)
    end

    def repeater(func, n, data, name, endian), do: repeater_(func, n, [], data, name, endian)
    def repeater(func, n, data, name, endian, fun) when is_function(fun) do
        { value, data } = repeater_(func, n, [], data, name, endian)
        { fun.(value), data }
    end


    #group
    #group :new_group, do: nil
    defmacro group(name, block) do
        group_func_name = String.to_atom("load_group_" <> to_string(name))
        
        quote do
            @tonic_data_scheme Map.put(@tonic_data_scheme, @tonic_current_scheme, [{ unquote(group_func_name), unquote(name) }|@tonic_data_scheme[@tonic_current_scheme]])

            @tonic_previous_scheme [@tonic_current_scheme|@tonic_previous_scheme]
            @tonic_current_scheme unquote(group_func_name)
            @tonic_data_scheme Map.put(@tonic_data_scheme, @tonic_current_scheme, [])

            unquote(block)

            [current|previous] = @tonic_previous_scheme
            @tonic_previous_scheme previous
            @tonic_current_scheme current
        end
    end

    #type creation
    defp binary_parameters(type, size, signedness, endianness) do
        {
            :-, [], [
                {
                    :-, [], [
                        {
                            :-, [], [
                                { :size, [], [size] },
                                { signedness, [], nil }
                            ]
                        },
                        { endianness, [], nil }
                    ]
                },
                { type, [], nil }
            ]
        }
    end

    #type alias of other type
    #type :new_type, :old_type
    defmacro type(name, type) when is_atom(type) do
        quote do
            defmacro unquote(name)() do
                quote do
                    @tonic_data_scheme Map.put(@tonic_data_scheme, @tonic_current_scheme, [{ :erlang.element(1, unquote(__ENV__.function)) }|@tonic_data_scheme[@tonic_current_scheme]])
                end
            end

            defmacro unquote(name)(label) do
                quote do
                    @tonic_data_scheme Map.put(@tonic_data_scheme, @tonic_current_scheme, [{ :erlang.element(1, unquote(__ENV__.function)), unquote(label) }|@tonic_data_scheme[@tonic_current_scheme]])
                end
            end

            defmacro unquote(name)(label, endianness_or_fun) do
                quote do
                    @tonic_data_scheme Map.put(@tonic_data_scheme, @tonic_current_scheme, [{ :erlang.element(1, unquote(__ENV__.function)), unquote(label), unquote(Macro.escape(endianness_or_fun)) }|@tonic_data_scheme[@tonic_current_scheme]])
                end
            end

            def unquote(name)(data, name, endianness), do: unquote(type)(data, name, endianness)
            def unquote(name)(data, name, endianness, fun) do
                { value, data } = unquote(type)(data, name, endianness)
                { fun.(value), data }
            end
        end
    end

    #type with function
    #type :new_type, fn data, name, endian -> { nil, data } end
    defmacro type(name, fun) do
        quote do
            defmacro unquote(name)() do
                quote do
                    @tonic_data_scheme Map.put(@tonic_data_scheme, @tonic_current_scheme, [{ :erlang.element(1, unquote(__ENV__.function)) }|@tonic_data_scheme[@tonic_current_scheme]])
                end
            end

            defmacro unquote(name)(label) do
                quote do
                    @tonic_data_scheme Map.put(@tonic_data_scheme, @tonic_current_scheme, [{ :erlang.element(1, unquote(__ENV__.function)), unquote(label) }|@tonic_data_scheme[@tonic_current_scheme]])
                end
            end

            defmacro unquote(name)(label, endianness_or_fun) do
                quote do
                    @tonic_data_scheme Map.put(@tonic_data_scheme, @tonic_current_scheme, [{ :erlang.element(1, unquote(__ENV__.function)), unquote(label), unquote(Macro.escape(endianness_or_fun)) }|@tonic_data_scheme[@tonic_current_scheme]])
                end
            end

            def unquote(name)(data, name, endianness), do: unquote(fun).(data, name, endianness)
            def unquote(name)(data, name, endianness, f) do
                { value, data } = unquote(fun).(data, name, endianness)
                { f.(value), data }
            end
        end
    end

    #type alias of other type, overriding endianness
    #type :new_type, :old_type, :little
    defmacro type(name, type, endianness) do
        quote do
            defmacro unquote(name)() do
                quote do
                    @tonic_data_scheme Map.put(@tonic_data_scheme, @tonic_current_scheme, [{ :erlang.element(1, unquote(__ENV__.function)) }|@tonic_data_scheme[@tonic_current_scheme]])
                end
            end

            defmacro unquote(name)(label) do
                quote do
                    @tonic_data_scheme Map.put(@tonic_data_scheme, @tonic_current_scheme, [{ :erlang.element(1, unquote(__ENV__.function)), unquote(label) }|@tonic_data_scheme[@tonic_current_scheme]])
                end
            end

            defmacro unquote(name)(label, endianness_or_fun) do
                quote do
                    @tonic_data_scheme Map.put(@tonic_data_scheme, @tonic_current_scheme, [{ :erlang.element(1, unquote(__ENV__.function)), unquote(label), unquote(Macro.escape(endianness_or_fun)) }|@tonic_data_scheme[@tonic_current_scheme]])
                end
            end

            def unquote(name)(data, name, _), do: unquote(type)(data, name, unquote(endianness))
            def unquote(name)(data, name, _, fun) do
                { value, data } = unquote(type)(data, name, unquote(endianness))
                { fun.(value), data }
            end
        end
    end

    #type with binary type, size, and signedness. applies to all endian types
    #type :new_type, :integer, :32, :signed
    defmacro type(name, type, size, signedness) do
        quote do
            defmacro unquote(name)() do
                quote do
                    @tonic_data_scheme Map.put(@tonic_data_scheme, @tonic_current_scheme, [{ :erlang.element(1, unquote(__ENV__.function)) }|@tonic_data_scheme[@tonic_current_scheme]])
                end
            end

            defmacro unquote(name)(label) do
                quote do
                    @tonic_data_scheme Map.put(@tonic_data_scheme, @tonic_current_scheme, [{ :erlang.element(1, unquote(__ENV__.function)), unquote(label) }|@tonic_data_scheme[@tonic_current_scheme]])
                end
            end

            defmacro unquote(name)(label, endianness_or_fun) do
                quote do
                    @tonic_data_scheme Map.put(@tonic_data_scheme, @tonic_current_scheme, [{ :erlang.element(1, unquote(__ENV__.function)), unquote(label), unquote(Macro.escape(endianness_or_fun)) }|@tonic_data_scheme[@tonic_current_scheme]])
                end
            end

            # note: adding supporting for using values currently loaded will likely mean adding a new argument to the data,name,endiannes,[fun] functions, which would this macro/3 could become available
            # defmacro unquote(name)(label, endianness, fun) do
            #     quote do
            #         @tonic_data_scheme Map.put(@tonic_data_scheme, @tonic_current_scheme, [{ :erlang.element(1, unquote(__ENV__.function)), unquote(label), unquote(endianness), unquote(Macro.escape(fun)) }|@tonic_data_scheme[@tonic_current_scheme]])
            #     end
            # end

            def unquote(name)(data, name, :little) do
                <<value :: unquote(binary_parameters(type, size, signedness, :little)), data :: binary>> = data
                { { name, value }, data }
            end

            def unquote(name)(data, name, :little, fun) do
                <<value :: unquote(binary_parameters(type, size, signedness, :little)), data :: binary>> = data
                { fun.({ name, value }), data }
            end

            def unquote(name)(data, name, :native) do
                <<value :: unquote(binary_parameters(type, size, signedness, :native)), data :: binary>> = data
                { { name, value }, data }
            end

            def unquote(name)(data, name, :native, fun) do
                <<value :: unquote(binary_parameters(type, size, signedness, :native)), data :: binary>> = data
                { fun.({ name, value }), data }
            end

            def unquote(name)(data, name, :big) do
                <<value :: unquote(binary_parameters(type, size, signedness, :big)), data :: binary>> = data
                { { name, value }, data }
            end

            def unquote(name)(data, name, :big, fun) do
                <<value :: unquote(binary_parameters(type, size, signedness, :big)), data :: binary>> = data
                { fun.({ name, value }), data }
            end
        end
    end

    #type with binary type, size, signedness, and endianness
    #type :new_type, :integer, :32, :signed, :little
    defmacro type(name, type, size, signedness, endianness) do
        quote do
            defmacro unquote(name)() do
                quote do
                    @tonic_data_scheme Map.put(@tonic_data_scheme, @tonic_current_scheme, [{ :erlang.element(1, unquote(__ENV__.function)) }|@tonic_data_scheme[@tonic_current_scheme]])
                end
            end

            defmacro unquote(name)(label) do
                quote do
                    @tonic_data_scheme Map.put(@tonic_data_scheme, @tonic_current_scheme, [{ :erlang.element(1, unquote(__ENV__.function)), unquote(label) }|@tonic_data_scheme[@tonic_current_scheme]])
                end
            end

            defmacro unquote(name)(label, endianness_or_fun) do
                quote do
                    @tonic_data_scheme Map.put(@tonic_data_scheme, @tonic_current_scheme, [{ :erlang.element(1, unquote(__ENV__.function)), unquote(label), unquote(Macro.escape(endianness_or_fun)) }|@tonic_data_scheme[@tonic_current_scheme]])
                end
            end

            def unquote(name)(data, name, _) do
                <<value :: unquote(binary_parameters(type, size, signedness, endianness)), data :: binary>> = data
                { { name, value }, data }
            end

            def unquote(name)(data, name, _, fun) do
                <<value :: unquote(binary_parameters(type, size, signedness, endianness)), data :: binary>> = data
                { fun.({ name, value }), data }
            end
        end
    end
end

defmodule Tonic.Types do
    import Tonic

    type :int8, :integer, 8, :signed
    type :int16, :integer, 16, :signed
    type :int32, :integer, 32, :signed
    type :int64, :integer, 64, :signed

    type :uint8, :integer, 8, :unsigned
    type :uint16, :integer, 16, :unsigned
    type :uint32, :integer, 32, :unsigned
    type :uint64, :integer, 64, :unsigned

    type :float32, :float, 32, :signed
    type :float64, :float, 64, :signed
end
