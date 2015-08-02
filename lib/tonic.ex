defmodule Tonic do
    @moduledoc """
      A DSL for conveniently loading binary data/files.
    """

    @type block(body) :: [do: body]
    @type callback :: ({ any, any } -> any)
    @type ast :: Macro.t
    @type endianness :: :little | :big | :native
    @type signedness :: :signed | :unsigned
    @type length :: non_neg_integer | (list -> boolean)

    defmacro __using__(_options) do
        quote do
            import Tonic
            import Tonic.Types

            @before_compile unquote(__MODULE__)
            @tonic_current_scheme :load
            @tonic_previous_scheme []
            @tonic_data_scheme Map.put(%{}, @tonic_current_scheme, [])
            @tonic_unique_function_id 0
        end
    end

    @doc false
    defp op_name({ _, name }), do: name
    defp op_name({ _, name, _ }), do: name
    defp op_name({ :repeat, _, name, _ }), do: name
    defp op_name({ _, name, _, _ }), do: name
    defp op_name({ :repeat, _, name, _, _ }), do: name
    defp op_name(_), do: nil

    @doc false
    def var_entry(name, v = { name, _ }), do: v
    def var_entry(name, value), do: { name, value }

    @doc false
    defp fixup_value({ :get, value }), do: quote do: get_value([scope|currently_loaded], unquote(value))
    defp fixup_value({ :get, _, [value] }), do: fixup_value({ :get, value })
    defp fixup_value({ :get, _, [value, fun] }), do: fixup_value({ :get, { value, fun } })
    defp fixup_value(value), do: quote do: unquote(value)

    @doc false
    def callback({ value, data }, fun), do: { fun.(value), data }

    @doc false
    defp create_call({ function }), do: quote do: callback(unquote(function)([scope|currently_loaded], data, nil, endian), fn { _, value } -> value end)
    defp create_call({ function, name }), do: quote do: unquote(function)([scope|currently_loaded], data, unquote(fixup_value(name)), endian)
    defp create_call({ function, name, fun }) when is_function(fun) or is_tuple(fun), do: quote do: callback(unquote(function)([scope|currently_loaded], data, unquote(fixup_value(name)), endian), unquote(fun))
    defp create_call({ function, name, endianness }), do: quote do: unquote(function)([scope|currently_loaded], data, unquote(fixup_value(name)), unquote(fixup_value(endianness)))
    defp create_call({ :repeat, function, name, length }), do: quote do: repeater(unquote({ :&, [], [{ :/, [], [{ function, [], __MODULE__ }, 4] }] }), unquote(fixup_value(length)), [scope|currently_loaded], data, unquote(fixup_value(name)), endian)
    defp create_call({ function, name, endianness, fun }), do: quote do: callback(unquote(function)([scope|currently_loaded], data, unquote(fixup_value(name)), unquote(fixup_value(endianness))), unquote(fun))
    defp create_call({ :repeat, function, name, length, fun }), do: quote do: repeater(unquote({ :&, [], [{ :/, [], [{ function, [], __MODULE__ }, 4] }] }), unquote(fixup_value(length)), [scope|currently_loaded], data, unquote(fixup_value(name)), endian, unquote(fun))

    @doc false
    defp expand_data_scheme([], init_value), do: [quote([do: { unquote(init_value), data }])]
    defp expand_data_scheme(scheme, init_value) do
        [quote([do: loaded = unquote(init_value)]), quote([do: scope = []])|expand_operation(scheme, [quote([do: { loaded, data }])])]
    end

    @doc false
    defp expand_operation([], ops), do: ops
    defp expand_operation([{ :endian, endianness }|scheme], ops), do: expand_operation(scheme, [quote([do: endian = unquote(fixup_value(endianness))])|ops])
    defp expand_operation([{ :optional, :end }|scheme], ops) do
        { optional, [{ :optional }|scheme] } = Enum.split_while(scheme, fn
            { :optional } -> false
            _ -> true
        end)

        expand_operation(scheme, [quote do
            { loaded, scope, data } = try do
                unquote_splicing(expand_operation(optional, []))
                { loaded, scope, data }
            rescue
                _ in MatchError -> { loaded, scope, data }
                _ in CaseClauseError -> { loaded, scope, data }
            end
        end|ops])
    end
    defp expand_operation([{ :chunk, id, :end }|scheme], ops) do
        { match, _ } = Code.eval_quoted(quote([do: fn
            { :chunk, _, :end } -> true
            { :chunk, unquote(id), _ } -> false
            _ -> true
        end]))

        { chunk, [{ :chunk, _, length }|scheme] } = Enum.split_while(scheme, match)

        expand_operation(scheme, [quote do
            size = unquote(fixup_value(length))
            unquote({ String.to_atom("next_data" <> to_string(id)), [], __MODULE__ }) = binary_part(data, size, byte_size(data) - size)
            data = binary_part(data, 0, size)
        end|[quote do
            unquote_splicing(expand_operation(chunk, []))
            { loaded, scope, data }
        end|[quote([do: data = unquote({ String.to_atom("next_data" <> to_string(id)), [], __MODULE__ })])|ops]]])
    end
    defp expand_operation([{ :on, _, :match, match }|scheme], ops), do: expand_operation(scheme, [[match], { :__block__, [], ops }])
    defp expand_operation([{ :on, id, :end }|scheme], ops) do
        { fun, _ } = Code.eval_quoted(quote([do: fn
            { :on, unquote(id), _ } -> false
            _ -> true
        end]))

        { matches, [{ :on, _, condition }|scheme] } = Enum.split_while(scheme, fun)

        { fun, _ } = Code.eval_quoted(quote([do: fn
            { :on, unquote(id), :match, _ } -> true
            _ -> false
        end]))

        expand_operation(scheme, [quote do
            case unquote(fixup_value(condition)) do
                unquote(Enum.chunk_by(matches, fun) |> Enum.chunk(2) |> Enum.map(fn [branch, match|_] ->
                    { :->, [], expand_operation(branch ++ match, []) }
                end) |> Enum.reverse)
            end
        end|ops])
    end
    defp expand_operation([{ :skip, op }|scheme], ops) do
        expand_operation(scheme, [
            quote([do: { _, data } = unquote(create_call(op))])
        |ops])
    end
    defp expand_operation([op|scheme], ops) do
        expand_operation(scheme, [
            quote([do: { value, data } = unquote(create_call(op))]),
            quote([do: loaded = :erlang.append_element(loaded, value)]),
            quote([do: scope = [var_entry(unquote(op_name(op)), value)|scope]])
        |ops])
    end

    defmacro __before_compile__(env) do
        quote do
            unquote({ :__block__, [], Map.keys(Module.get_attribute(env.module, :tonic_data_scheme)) |> Enum.map(fn scheme ->
                    { :def, [context: __MODULE__, import: Kernel], [
                            { scheme, [context: __MODULE__], [{ :currently_loaded, [], __MODULE__ }, { :data, [], __MODULE__ }, { :name, [], __MODULE__ }, { :endian, [], __MODULE__ }] },
                            [do: { :__block__, [], expand_data_scheme(Module.get_attribute(env.module, :tonic_data_scheme)[scheme], case to_string(scheme) do
                                <<"load_group_", _ :: binary>> -> quote do: { name }
                                <<"load_skip_", _ :: binary>> -> quote do: { name }
                                _ -> quote do: {} #load, load_repeat_
                            end) }]
                        ]
                    }
                end)
            })
        end
    end

    #loading
    @doc """
      Loads the binary data using the spec from a given module
    """
    @spec load(binary, module) :: { any, binary }
    def load(data, module) when is_binary(data) do
        module.load([], data, nil, :native)
    end

    @doc """
      Loads the file data using the spec from a given module
    """
    @spec load_file(Path.t, module) :: { any, binary }
    def load_file(file, module) do
        { :ok, data } = File.read(file)
        load(data, module)
    end

    #get
    @doc false
    defp get_value([], [], name), do: raise(Tonic.MarkNotFound, name: name)
    defp get_value([scope|loaded], [], name), do: get_value(loaded, scope, name)
    defp get_value(_, [{ name, value }|_], name), do: value
    defp get_value(loaded, [_|vars], name), do: get_value(loaded, vars, name)

    @doc false
    def get_value(loaded, { name, fun }), do: fun.(get_value(loaded, [], name))
    def get_value(loaded, fun) when is_function(fun), do: fun.(loaded)
    def get_value(loaded, name), do: get_value(loaded, [], name)

    #get
    @doc """
      Get the loaded value by using either a name to lookup the value, or a function to manually
      look it up.


      **`get(atom) :: any`**  
      Using a name for the lookup will cause it to search for that matched name in the current 
      loaded data scope and containing scopes (but not separate branched scopes). If the name
      is not found, an exception will be raised `Tonic.MarkNotFound`.

      **`get(fun) :: any`**  
      Using a function for the lookup will cause it to pass the current state to the function.
      where the function can return the value you want to get.


      Examples
      --------
        uint8 :length
        repeat get(:length), :uint8

        uint8 :length
        repeat get(fn [[{ :length, length }]] -> length end), :uint8
    """
    #get fn loaded -> 0 end
    #get :value
    @spec get(atom) :: ast
    @spec get((list -> any)) :: ast
    defmacro get(name_or_fun) do
        quote do
            { :get, unquote(Macro.escape(name_or_fun)) }
        end
    end

    @doc """
      Get the loaded value with name, and pass the value into a function.

      Examples
      --------
        uint8 :length
        repeat get(:length, fn length -> length - 1 end)
    """
    #get :value, fn value -> value end
    @spec get(atom, (list -> any)) :: ast
    defmacro get(name, fun) do
        quote do
            { :get, { unquote(name), unquote(Macro.escape(fun)) } }
        end
    end

    #on
    @doc """
      Executes the given load operations of a particular clause that matches the condition.

      Examples
      --------
        uint8 :type
        on get(:type) do
            1 -> uint32 :value
            2 -> float32 :value
        end
    """
    @spec on(term, [do: [{ :->, any, any }]]) :: ast
    defmacro on(condition, [do: clauses]) do
        quote do
            on_id = @tonic_unique_function_id
            @tonic_unique_function_id @tonic_unique_function_id + 1

            @tonic_data_scheme Map.put(@tonic_data_scheme, @tonic_current_scheme, [{ :on, on_id, unquote(Macro.escape(condition)) }|@tonic_data_scheme[@tonic_current_scheme]])

            unquote({ :__block__, [], Enum.map(clauses, fn { :->, _, [[match]|args] } ->
                quote do
                    @tonic_data_scheme Map.put(@tonic_data_scheme, @tonic_current_scheme, [{ :on, on_id, :match, unquote(Macro.escape(match)) }|@tonic_data_scheme[@tonic_current_scheme]])
                    unquote({ :__block__, [], args })
                end
            end) })

            @tonic_data_scheme Map.put(@tonic_data_scheme, @tonic_current_scheme, [{ :on, on_id, :end }|@tonic_data_scheme[@tonic_current_scheme]])
        end
    end

    #chunk
    @doc """
      Extract a chunk of data for processing.

      Executes the load operations only on the given chunk.


      **`chunk(`<code class="inline"><a href="#t:length/0">length</a></code>`, `<code class="inline"><a href="#t:block/1">block(any)</a></code>`) ::` <code class="inline"><a href="#t:ast/0">ast</a></code>**  
      Uses the block as the load operation on the chunk of length.


      Example
      -------
        chunk 4 do
            uint8 :a
            uint8 :b
        end

        chunk 4 do
            repeat :uint8
        end
    """
    #chunk 4, do: nil
    @spec chunk(length, block(any)) :: ast
    defmacro chunk(length, block) do
        quote do
            chunk_id = @tonic_unique_function_id
            @tonic_unique_function_id @tonic_unique_function_id + 1

            @tonic_data_scheme Map.put(@tonic_data_scheme, @tonic_current_scheme, [{ :chunk, chunk_id, unquote(Macro.escape(length)) }|@tonic_data_scheme[@tonic_current_scheme]])

            unquote(block)

            @tonic_data_scheme Map.put(@tonic_data_scheme, @tonic_current_scheme, [{ :chunk, chunk_id, :end }|@tonic_data_scheme[@tonic_current_scheme]])
        end
    end

    #skip
    @doc """
      Skip the given load operations.

      Executes the load operations but doesn't return the loaded data.


      **`skip(atom) ::` <code class="inline"><a href="#t:ast/0">ast</a></code>**  
      Skip the given type.

      **`skip(`<code class="inline"><a href="#t:block/1">block(any)</a></code>`) ::` <code class="inline"><a href="#t:ast/0">ast</a></code>**  
      Skip the given block.


      Example
      -------
        skip :uint8

        skip do
            uint8 :a
            uint8 :b
        end
    """
    #skip :type
    @spec skip(atom) :: ast
    defmacro skip(type) when is_atom(type) do
        quote do
            skip([do: unquote(type)()])
        end
    end

    #skip do: nil
    @spec skip(block(any)) :: ast
    defmacro skip(block) do
        quote do
            skip_func_name = String.to_atom("load_skip_" <> to_string(:__tonic_anon__) <> "_" <> to_string(unquote(__CALLER__.line)) <> "_" <> to_string(@tonic_unique_function_id))
            @tonic_unique_function_id @tonic_unique_function_id + 1


            @tonic_data_scheme Map.put(@tonic_data_scheme, @tonic_current_scheme, [{ :skip, { skip_func_name, :__tonic_anon__ } }|@tonic_data_scheme[@tonic_current_scheme]])

            @tonic_previous_scheme [@tonic_current_scheme|@tonic_previous_scheme]
            @tonic_current_scheme skip_func_name
            @tonic_data_scheme Map.put(@tonic_data_scheme, @tonic_current_scheme, [])

            unquote(block)

            [current|previous] = @tonic_previous_scheme
            @tonic_previous_scheme previous
            @tonic_current_scheme current
        end
    end

    #optional
    @doc """
      Optionally execute the given load operations.

      Usually if the current data does not match what is trying to be loaded, a match error
      will be raised and the data will not be loaded successfully. Using `optional` is a way
      to avoid that. If there is a match error the load operations it attempted to execute
      will be skipped, and it will continue on with the rest of the data spec. If there
      isn't a match error then the load operations that were attempted will be combined with
      the current loaded data.


      **`optional(atom) ::` <code class="inline"><a href="#t:ast/0">ast</a></code>**  
      Optionally load the given type.

      **`optional(`<code class="inline"><a href="#t:block/1">block(any)</a></code>`) ::` <code class="inline"><a href="#t:ast/0">ast</a></code>**  
      Optionally load the given block.


      Example
      -------
        optional :uint8

        optional do
            uint8 :a
            uint8 :b
        end
    """
    #optional :type
    @spec optional(atom) :: ast
    defmacro optional(type) when is_atom(type) do
        quote do
            optional([do: unquote(type)()])
        end
    end

    #optional do: nil
    @spec optional(block(any)) :: ast
    defmacro optional(block) do
        quote do
            @tonic_data_scheme Map.put(@tonic_data_scheme, @tonic_current_scheme, [{ :optional }|@tonic_data_scheme[@tonic_current_scheme]])

            unquote(block)

            @tonic_data_scheme Map.put(@tonic_data_scheme, @tonic_current_scheme, [{ :optional, :end }|@tonic_data_scheme[@tonic_current_scheme]])
        end
    end

    #endian
    @doc """
      Sets the default endianness used by types where endianness is not specified.

      Examples
      --------
        endian :little
        uint32 :value #little endian

        endian :big
        uint32 :value #big endian

        endian :little
        uint32 :value, :big #big endian
    """
    #endian :little
    @spec endian(endianness) :: ast
    defmacro endian(endianness) do
        quote do
            @tonic_data_scheme Map.put(@tonic_data_scheme, @tonic_current_scheme, [{ :endian, unquote(endianness) }|@tonic_data_scheme[@tonic_current_scheme]])
        end
    end

    #repeat
    @doc """
      Repeat the given load operations until it reaches the end.


      **`repeat(atom) ::` <code class="inline"><a href="#t:ast/0">ast</a></code>**  
      Uses the type as the load operation to be repeated.

      **`repeat(`<code class="inline"><a href="#t:block/1">block(any)</a></code>`) ::` <code class="inline"><a href="#t:ast/0">ast</a></code>**  
      Uses the block as the load operation to be repeated.


      Examples
      --------
        repeat :uint8

        repeat do
            uint8 :a
            uint8 :b
        end
    """
    #repeat :type
    @spec repeat(atom) :: ast
    defmacro repeat(type) when is_atom(type) do
        quote do
            repeat(fn _ -> false end, unquote(type))
        end
    end

    #repeat do: nil
    @spec repeat(block(any)) :: ast
    defmacro repeat(block) do
        quote do
            repeat(fn _ -> false end, unquote(block))
        end
    end

    @doc """
      Repeat the given load operations until it reaches the end or for length.


      **`repeat(atom, atom) ::` <code class="inline"><a href="#t:ast/0">ast</a></code>**  
      Uses the type as the load operation to be repeated. And wraps the output with the given
      name.

      **`repeat(atom, `<code class="inline"><a href="#t:block/1">block(any)</a></code>`) ::` <code class="inline"><a href="#t:ast/0">ast</a></code>**  
      Uses the block as the load operation to be repeated. And wraps the output with the given
      name.

      **`repeat(`<code class="inline"><a href="#t:length/0">length</a></code>`, atom) ::` <code class="inline"><a href="#t:ast/0">ast</a></code>**  
      Uses the type as the load operation to be repeated. And repeats for length.

      **`repeat(`<code class="inline"><a href="#t:length/0">length</a></code>`, `<code class="inline"><a href="#t:block/1">block(any)</a></code>`) ::` <code class="inline"><a href="#t:ast/0">ast</a></code>**  
      Uses the block as the load operation to be repeated. And repeats for length.


      Examples
      --------
        repeat :values, :uint8

        repeat :values do
            uint8 :a
            uint8 :b
        end

        repeat 4, :uint8

        repeat fn _ -> false end, :uint8

        repeat 2 do
            uint8 :a
            uint8 :b
        end

        repeat fn _ -> false end do
            uint8 :a
            uint8 :b
        end
    """
    #repeat :new_repeat, :type
    @spec repeat(atom, atom) :: ast
    defmacro repeat(name, type) when is_atom(name) and is_atom(type) do
        quote do
            repeat(unquote(name), fn _ -> false end, unquote(type))
        end
    end

    #repeat :new_repeat, do: nil
    @spec repeat(atom, block(any)) :: ast
    defmacro repeat(name, block) when is_atom(name) do
        quote do
            repeat(unquote(name), fn _ -> false end, unquote(block))
        end
    end

    #repeat times, :type
    @spec repeat(length, atom) :: ast
    defmacro repeat(length, type) when is_atom(type) do
        quote do
            repeat(:__tonic_anon__, unquote(length), fn { _, value } ->
                Enum.map(value, fn { i } -> i end)
            end, [do: unquote(type)()])
        end
    end

    #repeat times, do: nil
    @spec repeat(length, block(any)) :: ast
    defmacro repeat(length, block) do
        quote do
            repeat(:__tonic_anon__, unquote(length), fn { _, value } ->
                value
            end, unquote(block))
        end
    end

    @doc """
      Repeat the given load operations for length.


      **`repeat(atom, `<code class="inline"><a href="#t:length/0">length</a></code>`, atom) ::` <code class="inline"><a href="#t:ast/0">ast</a></code>**  
      Uses the type as the load operation to be repeated. And wraps the output with the given
      name. Repeats for length.

      **`repeat(atom, `<code class="inline"><a href="#t:length/0">length</a></code>`, `<code class="inline"><a href="#t:block/1">block(any)</a></code>`) ::` <code class="inline"><a href="#t:ast/0">ast</a></code>**  
      Uses the block as the load operation to be repeated. And wraps the output with the given
      name. Repeats for length.


      Examples
      --------
        repeat :values, 4, :uint8

        repeat :values, fn _ -> false end, :uint8

        repeat :values, 4 do
            uint8 :a
            uint8 :b
        end

        repeat :values, fn _ -> false end do
            uint8 :a
            uint8 :b
        end
    """
    #repeat :new_repeat, times, :type
    @spec repeat(atom, length, atom) :: ast
    defmacro repeat(name, length, type) when is_atom(type) do
        quote do
            repeat(unquote(name), unquote(length), fn { name, value } ->
                { name, Enum.map(value, fn { i } -> i end) }
            end, [do: unquote(type)()])
        end
    end

    #repeat :new_repeat, times, do: nil
    @spec repeat(atom, length, block(any)) :: ast
    defmacro repeat(name, length, block) do
        quote do
            repeat_func_name = String.to_atom("load_repeat_" <> to_string(unquote(name)) <> "_" <> to_string(unquote(__CALLER__.line)) <> "_" <> to_string(@tonic_unique_function_id))
            @tonic_unique_function_id @tonic_unique_function_id + 1


            @tonic_data_scheme Map.put(@tonic_data_scheme, @tonic_current_scheme, [{ :repeat, repeat_func_name, unquote(name), unquote(Macro.escape(length)) }|@tonic_data_scheme[@tonic_current_scheme]])

            @tonic_previous_scheme [@tonic_current_scheme|@tonic_previous_scheme]
            @tonic_current_scheme repeat_func_name
            @tonic_data_scheme Map.put(@tonic_data_scheme, @tonic_current_scheme, [])

            unquote(block)

            [current|previous] = @tonic_previous_scheme
            @tonic_previous_scheme previous
            @tonic_current_scheme current
        end
    end

    @doc """
      Repeats the load operations for length, passing the result to a callback.

      Examples
      --------
        repeat :values, 4, fn result -> result end, :uint8

        repeat :values, 4, fn { name, value } -> value end, :uint8

        repeat :values, fn _ -> false end, fn result -> result end, :uint8

        repeat :values, 4, fn result -> result end do
            uint8 :a
            uint8 :b
        end

        repeat :values, 4, fn { name, value } -> value end do
            uint8 :a
            uint8 :b
        end

        repeat :values, fn _ -> false end, fn result -> result end do
            uint8 :a
            uint8 :b
        end
    """
    #repeat :new_repeat, times, fn { name, value } -> value end, do: nil
    @spec repeat(atom, length, callback, block(any)) :: ast
    defmacro repeat(name, length, fun, block) do
        quote do
            repeat_func_name = String.to_atom("load_repeat_" <> to_string(unquote(name)) <> "_" <> to_string(unquote(__CALLER__.line)) <> "_" <> to_string(@tonic_unique_function_id))
            @tonic_unique_function_id @tonic_unique_function_id + 1


            @tonic_data_scheme Map.put(@tonic_data_scheme, @tonic_current_scheme, [{ :repeat, repeat_func_name, unquote(name), unquote(Macro.escape(length)), unquote(Macro.escape(fun)) }|@tonic_data_scheme[@tonic_current_scheme]])

            @tonic_previous_scheme [@tonic_current_scheme|@tonic_previous_scheme]
            @tonic_current_scheme repeat_func_name
            @tonic_data_scheme Map.put(@tonic_data_scheme, @tonic_current_scheme, [])

            unquote(block)

            [current|previous] = @tonic_previous_scheme
            @tonic_previous_scheme previous
            @tonic_current_scheme current
        end
    end

    @doc false
    defp repeater_(_, should_stop, list, _, <<>>, name, _) when is_function(should_stop) or should_stop === nil, do: { { name, :lists.reverse(list) }, <<>> }
    defp repeater_(func, should_stop, list, currently_loaded, data, name, endian) when is_function(should_stop) do
        { value, data } = func.(currently_loaded, data, nil, endian)
        case should_stop.(list = [value|list]) do
            true -> { { name, :lists.reverse(list) }, data }
            _ -> repeater_(func, should_stop, list, currently_loaded, data, name, endian)
        end
    end

    @doc false
    defp repeater_(_, 0, list, _, data, name, _), do: { { name, :lists.reverse(list) }, data }
    defp repeater_(func, n, list, currently_loaded, data, name, endian) do
        { value, data } = func.(currently_loaded, data, nil, endian)
        repeater_(func, n - 1, [value|list], currently_loaded, data, name, endian)
    end

    @doc false
    def repeater(func, n, currently_loaded, data, name, endian), do: repeater_(func, n, [], currently_loaded, data, name, endian)

    @doc false
    def repeater(func, n, currently_loaded, data, name, endian, fun) when is_function(fun), do: callback(repeater_(func, n, [], currently_loaded, data, name, endian), fun)


    #group
    @doc """
      Group the load operations.

      Examples
      --------
        group do
            uint8 :a
            uint8 :b
        end
    """
    #group do: nil
    @spec group(block(any)) :: ast
    defmacro group(block) do
        quote do
            group(:__tonic_anon__, fn group -> :erlang.delete_element(1, group) end, unquote(block))
        end
    end

    @doc """
      Group the load operations, wrapping them with the given name.

      Examples
      --------
        group :values do
            uint8 :a
            uint8 :b
        end 
    """
    #group :new_group, do: nil
    @spec group(atom, block(any)) :: ast
    defmacro group(name, block) do
        quote do
            group_func_name = String.to_atom("load_group_" <> to_string(unquote(name)) <> "_" <> to_string(unquote(__CALLER__.line)) <> "_" <> to_string(@tonic_unique_function_id))
            @tonic_unique_function_id @tonic_unique_function_id + 1


            @tonic_data_scheme Map.put(@tonic_data_scheme, @tonic_current_scheme, [{ group_func_name, unquote(name) }|@tonic_data_scheme[@tonic_current_scheme]])

            @tonic_previous_scheme [@tonic_current_scheme|@tonic_previous_scheme]
            @tonic_current_scheme group_func_name
            @tonic_data_scheme Map.put(@tonic_data_scheme, @tonic_current_scheme, [])

            unquote(block)

            [current|previous] = @tonic_previous_scheme
            @tonic_previous_scheme previous
            @tonic_current_scheme current
        end
    end

    @doc """
      Group the load operations, wrapping them with the given name and passing the result to a callback.

      Examples
      --------
        group :values, fn { _, value } -> value end do
            uint8 :a
            uint8 :b
        end 
    """
    #group :new_group, fn { name, value } -> value end, do: nil
    @spec group(atom, callback, block(any)) :: ast
    defmacro group(name, fun, block) do
        quote do
            group_func_name = String.to_atom("load_group_" <> to_string(unquote(name)) <> "_" <> to_string(unquote(__CALLER__.line)) <> "_" <> to_string(@tonic_unique_function_id))
            @tonic_unique_function_id @tonic_unique_function_id + 1


            @tonic_data_scheme Map.put(@tonic_data_scheme, @tonic_current_scheme, [{ group_func_name, unquote(name), unquote(Macro.escape(fun)) }|@tonic_data_scheme[@tonic_current_scheme]])

            @tonic_previous_scheme [@tonic_current_scheme|@tonic_previous_scheme]
            @tonic_current_scheme group_func_name
            @tonic_data_scheme Map.put(@tonic_data_scheme, @tonic_current_scheme, [])

            unquote(block)

            [current|previous] = @tonic_previous_scheme
            @tonic_previous_scheme previous
            @tonic_current_scheme current
        end
    end

    #type creation
    @doc false
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

    @doc """
      Declare a new type as an alias of another type or of a function.


      **`type(atom, atom) ::` <code class="inline"><a href="#t:ast/0">ast</a></code>**  
      Create the new type as an alias of another type.

      **`type(atom, (binary, atom, ` <code class="inline"><a href="#t:endianness/0">endianness</a></code> ` -> { any, binary })) ::` <code class="inline"><a href="#t:ast/0">ast</a></code>**  
      Implement the type as a function. 


      Examples
      --------
        type :myint8, :int8

        type :myint8, fn data, name, _ ->
            <<value :: integer-size(8)-signed, data :: binary>> data
            { { name, value }, data }
        end

        type :myint16, fn 
            data, name, :little ->
                <<value :: integer-size(16)-signed-little, data :: binary>> = data
                { { name, value }, data }
            data, name, :big ->
                <<value :: integer-size(16)-signed-big, data :: binary>> = data
                { { name, value }, data }
            data, name, :native ->
                <<value :: integer-size(16)-signed-native, data :: binary>> = data
                { { name, value }, data }
        end
    """
    #type alias of other type
    #type :new_type, :old_type
    @spec type(atom, atom) :: ast
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

            defmacro unquote(name)(label, endianness, fun) do
                quote do
                    @tonic_data_scheme Map.put(@tonic_data_scheme, @tonic_current_scheme, [{ :erlang.element(1, unquote(__ENV__.function)), unquote(label), unquote(endianness), unquote(Macro.escape(fun)) }|@tonic_data_scheme[@tonic_current_scheme]])
                end
            end

            def unquote(name)(currently_loaded, data, name, endianness), do: unquote(type)(currently_loaded, data, name, endianness)
        end
    end

    #type with function
    #type :new_type, fn data, name, endian -> { nil, data } end
    @spec type(atom, (binary, atom, endianness -> { any, binary })) :: ast
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

            defmacro unquote(name)(label, endianness, fun) do
                quote do
                    @tonic_data_scheme Map.put(@tonic_data_scheme, @tonic_current_scheme, [{ :erlang.element(1, unquote(__ENV__.function)), unquote(label), unquote(endianness), unquote(Macro.escape(fun)) }|@tonic_data_scheme[@tonic_current_scheme]])
                end
            end

            def unquote(name)(currently_loaded, data, name, endianness), do: unquote(fun).(data, name, endianness)
        end
    end

    @doc """
      Declare a new type as an alias of another type with an overriding (fixed) endianness.

      Examples
      --------
        type :mylittleint16, :int16, :little
    """
    #type alias of other type, overriding endianness
    #type :new_type, :old_type, :little
    @spec type(atom, atom, endianness) :: ast
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

            defmacro unquote(name)(label, endianness, fun) do
                quote do
                    @tonic_data_scheme Map.put(@tonic_data_scheme, @tonic_current_scheme, [{ :erlang.element(1, unquote(__ENV__.function)), unquote(label), unquote(endianness), unquote(Macro.escape(fun)) }|@tonic_data_scheme[@tonic_current_scheme]])
                end
            end

            def unquote(name)(currently_loaded, data, name, _), do: unquote(type)(currently_loaded, data, name, unquote(endianness))
        end
    end

    @doc """
      Declare a new type for a binary type of size with signedness (if used).

      Examples
      --------
        type :myint16, :integer, 16, :signed
    """
    #type with binary type, size, and signedness. applies to all endian types
    #type :new_type, :integer, 32, :signed
    @spec type(atom, atom, non_neg_integer, signedness) :: ast
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

            defmacro unquote(name)(label, endianness, fun) do
                quote do
                    @tonic_data_scheme Map.put(@tonic_data_scheme, @tonic_current_scheme, [{ :erlang.element(1, unquote(__ENV__.function)), unquote(label), unquote(endianness), unquote(Macro.escape(fun)) }|@tonic_data_scheme[@tonic_current_scheme]])
                end
            end

            def unquote(name)(currently_loaded, data, name, :little) do
                <<value :: unquote(binary_parameters(type, size, signedness, :little)), data :: binary>> = data
                { { name, value }, data }
            end

            def unquote(name)(currently_loaded, data, name, :native) do
                <<value :: unquote(binary_parameters(type, size, signedness, :native)), data :: binary>> = data
                { { name, value }, data }
            end

            def unquote(name)(currently_loaded, data, name, :big) do
                <<value :: unquote(binary_parameters(type, size, signedness, :big)), data :: binary>> = data
                { { name, value }, data }
            end
        end
    end

    @doc """
      Declare a new type for a binary type of size with signedness (if used) and a overriding
      (fixed) endianness.

      Examples
      --------
        type :mylittleint16, :integer, 16, :signed, :little
    """
    #type with binary type, size, signedness, and endianness
    #type :new_type, :integer, :32, :signed, :little
    @spec type(atom, atom, non_neg_integer, signedness, endianness) :: ast
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

            defmacro unquote(name)(label, endianness, fun) do
                quote do
                    @tonic_data_scheme Map.put(@tonic_data_scheme, @tonic_current_scheme, [{ :erlang.element(1, unquote(__ENV__.function)), unquote(label), unquote(endianness), unquote(Macro.escape(fun)) }|@tonic_data_scheme[@tonic_current_scheme]])
                end
            end

            def unquote(name)(currently_loaded, data, name, _) do
                <<value :: unquote(binary_parameters(type, size, signedness, endianness)), data :: binary>> = data
                { { name, value }, data }
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


    defp list_to_string_drop_last_value(values, string \\ "")
    defp list_to_string_drop_last_value([], string), do: string
    defp list_to_string_drop_last_value([_], string), do: string
    defp list_to_string_drop_last_value([{ c }|values], string), do: list_to_string_drop_last_value(values, string <> <<c>>)

    def convert_to_string_without_last_byte({ name, values }), do: { name, convert_to_string_without_last_byte(values) }
    def convert_to_string_without_last_byte(values), do: list_to_string_drop_last_value(values)

    def convert_to_string({ name, values }), do: { name, convert_to_string(values) }
    def convert_to_string(values), do: List.foldl(values, "", fn { c }, s -> s <> <<c>> end)

    defmacro string(name \\ [], options \\ [])
    defmacro string(terminator, []) when is_integer(terminator), do: quote do: string(terminator: unquote(terminator))

    defmacro string([terminator: terminator], []) do
        quote do
            repeat nil, fn [{ c }|_] -> c == unquote(terminator) end, fn { _, values } -> convert_to_string_without_last_byte(values) end, do: uint8
        end
    end

    defmacro string([length: length], []) do
        quote do
            repeat nil, unquote(length), fn { _, values } -> convert_to_string(values) end, do: uint8
        end
    end

    defmacro string([], []) do
        quote do
            repeat nil, fn _ -> false end, fn { _, values } -> convert_to_string(values) end, do: uint8
        end
    end

    defmacro string(options, []) when is_list(options) do
        quote do
            repeat nil, fn chars = [{ c }|_] ->
                c == unquote(options[:terminator]) or length(chars) == unquote(options[:length]) #todo: should change repeat step callback to pass in the length too
            end, fn { _, values } ->
                str = case List.last(values) do #maybe repeat callbacks shouldn't pre-reverse the list and instead leave it up to the callback to reverse?
                    { unquote(options[:terminator]) } -> convert_to_string_without_last_byte(values)
                    _ -> convert_to_string(values)
                end

                unquote(if options[:strip] != nil do
                    quote do: String.rstrip(str, unquote(options[:strip]))
                else
                    quote do: str
                end)
            end, do: uint8
        end
    end

    defmacro string(name, terminator) when is_integer(terminator), do: quote do: string(unquote(name), terminator: unquote(terminator))
    defmacro string(name, [terminator: terminator]) do
        quote do
            repeat unquote(name), fn [{ c }|_] -> c == unquote(terminator) end, &convert_to_string_without_last_byte/1, do: uint8
        end
    end

    defmacro string(name, [length: length]) do
        quote do
            repeat unquote(name), unquote(length), &convert_to_string/1, do: uint8
        end
    end

    defmacro string(name, []) do
        quote do
            repeat unquote(name), fn _ -> false end, &convert_to_string/1, do: uint8
        end
    end

    defmacro string(name, options) do
        quote do
            repeat unquote(name), fn chars = [{ c }|_] ->
                c == unquote(options[:terminator]) or length(chars) == unquote(options[:length]) #todo: should change repeat step callback to pass in the length too
            end, fn charlist = { _, values } ->
                { name, str } = case List.last(values) do #maybe repeat callbacks shouldn't pre-reverse the list and instead leave it up to the callback to reverse?
                    { unquote(options[:terminator]) } -> convert_to_string_without_last_byte(charlist)
                    _ -> convert_to_string(charlist)
                end

                { name, unquote(if options[:strip] != nil do
                    quote do: String.rstrip(str, unquote(options[:strip]))
                else
                    quote do: str
                end) }
            end, do: uint8
        end
    end
end

defmodule Tonic.MarkNotFound do
    defexception [:message, :name]

    def exception(option), do: %Tonic.MarkNotFound{ message: "no loaded value marked with name: #{option[:name]}", name: option[:name] }
end
