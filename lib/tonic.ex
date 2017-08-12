defmodule Tonic do
    @moduledoc """
      A DSL for conveniently loading binary data/files.

      The DSL is designed to closely represent the structure of the actual binary data
      layout. So it aims to be easy to read, and easy to change.

      The DSL defines functionality to represent types, endianness, groups, chunks,
      repeated data, branches, optional segments. Where the majority of these functions
      can be further extended to customize the behaviour and result.

      The default behaviour of these operations is to remove the data that was read from the
      current binary data, and append the value to the current block. Values by default are
      in the form of a tagged value if a name is supplied `{ :name, value }`, otherwise are
      simply `value` if no name is supplied. The default return value behaviour can be
      overridden by passing in a function.

      The most common types are defined in `Tonic.Types` for convenience. These are
      common integer and floating point types, and strings. The behaviour of types can
      further be customized when used otherwise new types can be defined using the `type/2`
      function.

      To use the DSL, call `use Tonic` in your module and include any additional type modules
      you may require. Then you are free to write the DSL directly inside the module. Certain
      options may be passed to the library on `use`, to indicate additional behaviours. The
      currently supported options are:

      `optimize:` which can be passed `true` to enable all optimizations, or a keyword list
      enabling the specific optimizations. Enabling optimizations may make debugging issues
      trickier, so best practice is to enable after it's been tested. Current specific
      optimizations include:
        :reduce #Enables the code reduction optimization, so the generated code is reduced as much as possible.


      Example
      -------
        defmodule PNG do
            use Tonic, optimize: true

            endian :big
            repeat :magic, 8, :uint8
            repeat :chunks do
                uint32 :length
                string :type, length: 4
                chunk get(:length) do
                    on get(:type) do
                        "IHDR" ->
                            uint32 :width
                            uint32 :height
                            uint8 :bit_depth
                            uint8 :colour_type
                            uint8 :compression_type
                            uint8 :filter_method
                            uint8 :interlace_method
                        "gAMA" ->
                            uint32 :gamma, fn { name, value } -> { name, value / 100000 } end
                        "cHRM" ->
                            group :white_point do
                                uint32 :x, fn { name, value } -> { name, value / 100000 } end
                                uint32 :y, fn { name, value } -> { name, value / 100000 } end
                            end
                            group :red do
                                uint32 :x, fn { name, value } -> { name, value / 100000 } end
                                uint32 :y, fn { name, value } -> { name, value / 100000 } end
                            end
                            group :green do
                                uint32 :x, fn { name, value } -> { name, value / 100000 } end
                                uint32 :y, fn { name, value } -> { name, value / 100000 } end
                            end
                            group :blue do
                                uint32 :x, fn { name, value } -> { name, value / 100000 } end
                                uint32 :y, fn { name, value } -> { name, value / 100000 } end
                            end
                        "iTXt" ->
                            string :keyword, ?\\0
                            string :text
                        _ -> repeat :uint8
                    end
                end
                uint32 :crc
            end
        end

        \#Example load result:
        \#{{:magic, [137, 80, 78, 71, 13, 10, 26, 10]},
        \# {:chunks,
        \#  [{{:length, 13}, {:type, "IHDR"}, {:width, 48}, {:height, 40},
        \#    {:bit_depth, 8}, {:colour_type, 6}, {:compression_type, 0},
        \#    {:filter_method, 0}, {:interlace_method, 0}, {:crc, 3095886193}},
        \#   {{:length, 4}, {:type, "gAMA"}, {:gamma, 0.45455}, {:crc, 201089285}},
        \#   {{:length, 32}, {:type, "cHRM"}, {:white_point, {:x, 0.3127}, {:y, 0.329}},
        \#    {:red, {:x, 0.64}, {:y, 0.33}}, {:green, {:x, 0.3}, {:y, 0.6}},
        \#    {:blue, {:x, 0.15}, {:y, 0.06}}, {:crc, 2629456188}},
        \#   {{:length, 345}, {:type, "iTXt"}, {:keyword, "XML:com.adobe.xmp"},
        \#    {:text,
        \#     <<0, 0, 0, 0, 60, 120, 58, 120, 109, 112, 109, 101, 116, 97, 32, 120, 109, 108, 110, 115, 58, 120, 61, 34, 97, 100, 111, 98, 101, 58, 110, 115, 58, 109, 101, 116, 97, 47, 34, ...>>},
        \#    {:crc, 1287792473}},
        \#   {{:length, 1638}, {:type, "IDAT"},
        \#    [88, 9, 237, 216, 73, 143, 85, 69, 24, 198, 241, 11, 125, 26, 68, 148, 25,
        \#     109, 4, 154, 102, 114, 192, 149, 70, 137, 137, 209, 152, 152, 24, 19, 190,
        \#     131, 75, 22, 234, 55, 224, 59, ...], {:crc, 2269121590}},
        \#   {{:length, 0}, {:type, "IEND"}, [], {:crc, 2923585666}}]}}
    """

    @type block(body) :: [do: body]
    @type callback :: ({ any, any } -> any)
    @type ast :: Macro.t
    @type endianness :: :little | :big | :native
    @type signedness :: :signed | :unsigned
    @type length :: non_neg_integer | (list -> boolean)

    @doc false
    defp optimize_flags(flag, options) when is_list(options), do: options[flag] == true
    defp optimize_flags(_flag, options), do: options == true

    defmacro __using__(options) do
        quote do
            import Tonic
            import Tonic.Types

            @before_compile unquote(__MODULE__)
            @tonic_current_scheme :load
            @tonic_previous_scheme []
            @tonic_data_scheme Map.put(%{}, @tonic_current_scheme, [])
            @tonic_unique_function_id 0
            @tonic_enable_optimization [
                reduce: unquote(optimize_flags(:reduce, options[:optimize]))
            ]
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
    def fixup_value({ :get, value }), do: quote do: get_value([scope|currently_loaded], unquote(value))
    def fixup_value({ :get, _, [value] }), do: fixup_value({ :get, value })
    def fixup_value({ :get, _, [value, fun] }), do: fixup_value({ :get, { value, fun } })
    def fixup_value(value), do: quote do: unquote(value)

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
        end|[quote([do: data = unquote({ String.to_atom("next_data" <> to_string(id)), [], __MODULE__ })])|ops]]])
    end
    defp expand_operation([{ :on, _, :match, match }|scheme], ops) do
        [clause, { :__block__, [], body }] = expand_operation(scheme, [[match], { :__block__, [], ops }])
        [clause, { :__block__, [], body ++ [quote(do: { loaded, scope, data, endian })] }]
    end
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
            { loaded, scope, data, endian } =  case unquote(fixup_value(condition)) do
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

    @doc false
    defp find_used_variables(ast = { name, [], __MODULE__ }, unused) do
        { unused, _ } = Enum.map_reduce(unused, nil, fn
            vars, :found -> { vars, :found }
            vars, _ ->
                { value, new } = Keyword.get_and_update(vars, name, &({ &1, true }))
                if(value != nil, do: { new, :found }, else: { vars, nil })
        end)
        { ast, unused }
    end
    defp find_used_variables(ast, unused), do: { ast, unused }

    @doc false
    defp find_unused_variables({ :=, _, [variable|init] }, unused) do
        { _, names } = Macro.prewalk(variable, [], fn
            ast = { name, [], __MODULE__ }, acc -> { ast, [{ name, false }|acc] }
            ast, acc -> { ast, acc }
        end)

        { _, unused } = Macro.prewalk(init, unused, &find_used_variables/2)

        [names|unused]
    end
    defp find_unused_variables({ :__block__, _, ops }, unused), do: Enum.reduce(ops, unused, &find_unused_variables/2)
    defp find_unused_variables(op, unused) do
        { _, unused } = Macro.prewalk(op, unused, &find_used_variables/2)
        unused
    end

    @doc false
    defp mark_unused_variables(functions) do
        Enum.map(functions, fn { :def, ctx, [{ name, name_ctx, args }, [do: body]] } ->
            unused = Enum.reverse(find_unused_variables(body, []))
            { body, _ } = mark_unused_variables(body, unused)

            #Run it a second time to prevent cases where: var1 is initialized, var1 is assigned to var2, var2 is not used and so removed making var1 also now unused (so needs to be removed)
            [arg_unused|unused] = Enum.reverse(find_unused_variables(body, [Enum.map(args, fn { arg, _, _ } -> { arg, false } end)]))
            { body, _ } = mark_unused_variables(body, Enum.map(unused, fn
                variables -> Enum.filter(variables, fn { name, _ } -> !(to_string(name) |> String.starts_with?("_")) end)
            end))

            { :def, ctx, [{ name, name_ctx, underscore_variables(args, arg_unused) }, [do: body]] }
        end)
    end

    @doc false
    defp mark_unused_variables({ :=, ctx, [variable|init] }, [assignment|unused]) do
        used = Enum.reduce(assignment, false, fn
            { _, used }, false -> used
            _, _ -> true
        end)
        { if(used, do: { :=, ctx, [underscore_variables(variable, assignment)|init] }, else: { :__block__, [], [] }), unused }
    end
    defp mark_unused_variables({ :__block__, ctx, ops }, unused) do
        { ops, unused } = Enum.map_reduce(ops, unused, &mark_unused_variables/2)
        ops = Enum.filter(ops, fn
            { :__block__, [], [] } -> false
            _ -> true
        end)
        { { :__block__, ctx, ops }, unused }
    end
    defp mark_unused_variables(op, unused), do: { op, unused }

    @doc false
    defp underscore_variables(variables, assignment) do
        Macro.prewalk(variables, fn
            { name, [], __MODULE__ } -> { if(Keyword.get(assignment, name, true), do: name, else: String.to_atom("_" <> to_string(name))), [], __MODULE__ }
            ast -> ast
        end)
    end

    @doc false
    defp reduce_functions(functions), do: reduce_functions(functions, { [], [], %{} })

    @doc false
    defp reduce_functions([func = { :def, ctx, [{ name, name_ctx, args }, body] }|functions], { reduced, unique, replace }) do
        f = { :def, ctx, [{ nil, name_ctx, args }, Macro.prewalk(body, fn t -> Macro.update_meta(t, &Keyword.delete(&1, :line)) end)] }
        reduce_functions(functions, case Enum.find(unique, fn { _, func } -> func == f end) do
            { replacement, _ } -> { reduced, unique, Map.put(replace, name, replacement) }
            _ -> { [func|reduced], [{ name, f }|unique], replace }
        end)
    end
    defp reduce_functions([other|functions], { reduced, unique, replace }), do: reduce_functions(functions, { [other|reduced], unique, replace })
    defp reduce_functions([], { reduced, _unique, replace }) do
        List.foldl(reduced, [], fn
            { :def, ctx, [func, body] }, acc ->
                [{ :def, ctx, [func, Macro.prewalk(body, fn
                    { name, ctx, args } when is_atom(name) -> { replace[name] || name, ctx, args }
                    t -> t
                end)] }|acc]
            other, acc -> [other|acc]
        end)
    end

    defmacro __before_compile__(env) do
        code = quote do
            unquote(Map.keys(Module.get_attribute(env.module, :tonic_data_scheme)) |> Enum.map(fn scheme ->
                { :def, [context: __MODULE__, import: Kernel], [
                        { scheme, [context: __MODULE__], [{ :currently_loaded, [], __MODULE__ }, { :data, [], __MODULE__ }, { :name, [], __MODULE__ }, { :endian, [], __MODULE__ }] },
                        [do: { :__block__, [], expand_data_scheme(Module.get_attribute(env.module, :tonic_data_scheme)[scheme], case to_string(scheme) do
                            <<"load_group_", _ :: binary>> -> quote do: { name }
                            <<"load_skip_", _ :: binary>> -> quote do: { name }
                            _ -> quote do: {} #load, load_repeat_
                        end) }]
                    ]
                }
            end))
        end

        code = if(Module.get_attribute(env.module, :tonic_enable_optimization)[:reduce] == true, do: reduce_functions(code), else: code)
        code = mark_unused_variables(code)

        { :__block__, [], Enum.map(code, fn function -> { :__block__, [], [quote(do: @doc false), function] } end) }
    end

    #loading
    @doc """
      Loads the binary data using the spec from a given module.

      The return value consists of the loaded values and the remaining data that wasn't read.
    """
    @spec load(bitstring, module) :: { any, bitstring }
    def load(data, module) when is_bitstring(data) do
        module.load([], data, nil, :native)
    end

    @doc """
      Loads the file data using the spec from a given module.

      The return value consists of the loaded values and the remaining data that wasn't read.
    """
    @spec load_file(Path.t, module) :: { any, bitstring }
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


      **<code class="inline">chunk(<a href="#t:length/0">length</a>, <a href="#t:block/1">block(any)</a>) :: <a href="#t:ast/0">ast</a></code>**  
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


      **<code class="inline">skip(atom) :: <a href="#t:ast/0">ast</a></code>**  
      Skip the given type.

      **<code class="inline">skip(<a href="#t:block/1">block(any)</a>) :: <a href="#t:ast/0">ast</a></code>**  
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


      **<code class="inline">optional(atom) :: <a href="#t:ast/0">ast</a></code>**  
      Optionally load the given type.

      **<code class="inline">optional(<a href="#t:block/1">block(any)</a>) :: <a href="#t:ast/0">ast</a></code>**  
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


      **<code class="inline">repeat(atom) :: <a href="#t:ast/0">ast</a></code>**  
      Uses the type as the load operation to be repeated.

      **<code class="inline">repeat(<a href="#t:block/1">block(any)</a>) :: <a href="#t:ast/0">ast</a></code>**  
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


      **<code class="inline">repeat(atom, atom) :: <a href="#t:ast/0">ast</a></code>**  
      Uses the type as the load operation to be repeated. And wraps the output with the given
      name.

      **<code class="inline">repeat(atom, <a href="#t:block/1">block(any)</a>) :: <a href="#t:ast/0">ast</a></code>**  
      Uses the block as the load operation to be repeated. And wraps the output with the given
      name.

      **<code class="inline">repeat(<a href="#t:length/0">length</a>, atom) :: <a href="#t:ast/0">ast</a></code>**  
      Uses the type as the load operation to be repeated. And repeats for length.

      **<code class="inline">repeat(<a href="#t:length/0">length</a>, <a href="#t:block/1">block(any)</a>) :: <a href="#t:ast/0">ast</a></code>**  
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


      **<code class="inline">repeat(atom, <a href="#t:length/0">length</a>, atom) :: <a href="#t:ast/0">ast</a></code>**  
      Uses the type as the load operation to be repeated. And wraps the output with the given
      name. Repeats for length.

      **<code class="inline">repeat(atom, <a href="#t:length/0">length</a>, <a href="#t:block/1">block(any)</a>) :: <a href="#t:ast/0">ast</a></code>**  
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


      **<code class="inline">type(atom, atom) :: <a href="#t:ast/0">ast</a></code>**  
      Create the new type as an alias of another type.

      **<code class="inline">type(atom, (bitstring, atom, <a href="#t:endianness/0">endianness</a> -> { any, bitstring })) :: <a href="#t:ast/0">ast</a></code>**  
      Implement the type as a function.


      Examples
      --------
        type :myint8, :int8

        type :myint8, fn data, name, _ ->
            <<value :: integer-size(8)-signed, data :: bitstring>> data
            { { name, value }, data }
        end

        type :myint16, fn
            data, name, :little ->
                <<value :: integer-size(16)-signed-little, data :: bitstring>> = data
                { { name, value }, data }
            data, name, :big ->
                <<value :: integer-size(16)-signed-big, data :: bitstring>> = data
                { { name, value }, data }
            data, name, :native ->
                <<value :: integer-size(16)-signed-native, data :: bitstring>> = data
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
    @spec type(atom, (bitstring, atom, endianness -> { any, bitstring })) :: ast
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
                <<value :: unquote(binary_parameters(type, size, signedness, :little)), data :: bitstring>> = data
                { { name, value }, data }
            end

            def unquote(name)(currently_loaded, data, name, :native) do
                <<value :: unquote(binary_parameters(type, size, signedness, :native)), data :: bitstring>> = data
                { { name, value }, data }
            end

            def unquote(name)(currently_loaded, data, name, :big) do
                <<value :: unquote(binary_parameters(type, size, signedness, :big)), data :: bitstring>> = data
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
                <<value :: unquote(binary_parameters(type, size, signedness, endianness)), data :: bitstring>> = data
                { { name, value }, data }
            end
        end
    end
end

defmodule Tonic.Types do
    import Tonic

    @doc """
      Read a single bit boolean value.
    """
    type :bit, fn <<value :: size(1), data :: bitstring>>, name, _ ->
        { { name, value == 1 }, data }
    end


    @doc """
      Read an 8-bit signed integer.
    """
    type :int8, :integer, 8, :signed

    @doc """
      Read a 16-bit signed integer.
    """
    type :int16, :integer, 16, :signed

    @doc """
      Read a 32-bit signed integer.
    """
    type :int32, :integer, 32, :signed

    @doc """
      Read a 64-bit signed integer.
    """
    type :int64, :integer, 64, :signed


    @doc """
      Read an 8-bit unsigned integer.
    """
    type :uint8, :integer, 8, :unsigned

    @doc """
      Read a 16-bit unsigned integer.
    """
    type :uint16, :integer, 16, :unsigned

    @doc """
      Read a 32-bit unsigned integer.
    """
    type :uint32, :integer, 32, :unsigned

    @doc """
      Read a 64-bit unsigned integer.
    """
    type :uint64, :integer, 64, :unsigned


    @doc """
      Read a 32-bit floating point.
    """
    type :float32, :float, 32, :signed

    @doc """
      Read a 64-bit floating point.
    """
    type :float64, :float, 64, :signed


    defp list_to_string_drop_last_value(values, string \\ "")
    defp list_to_string_drop_last_value([], string), do: string
    defp list_to_string_drop_last_value([_], string), do: string
    defp list_to_string_drop_last_value([{ c }|values], string), do: list_to_string_drop_last_value(values, string <> <<c>>)

    def convert_to_string_without_last_byte({ name, values }), do: { name, convert_to_string_without_last_byte(values) }
    def convert_to_string_without_last_byte(values), do: list_to_string_drop_last_value(values)

    def convert_to_string({ name, values }), do: { name, convert_to_string(values) }
    def convert_to_string(values), do: List.foldl(values, "", fn { c }, s -> s <> <<c>> end)

    @doc """
      Read a string.

      Default will read until end of data. Otherwise a length value can be specified `length: 10`,
      or it can read up to a terminator `?\\n` or `terminator: ?\\n`, or both limits can be applied.

      Examples
      --------
        string :read_to_end
        string :read_8_chars, length: 8
        string :read_till_nul, 0
        string :read_till_newline, ?\\n
        string :read_till_newline_or_8_chars, length: 8, terminator: ?\\n
    """
    defmacro string(name \\ [], options \\ [])
    defmacro string(terminator, []) when is_integer(terminator), do: quote do: string(terminator: unquote(terminator))

    defmacro string([terminator: terminator], []) do
        quote do
            repeat nil, fn [{ c }|_] -> c == unquote(fixup_value(terminator)) end, fn { _, values } -> convert_to_string_without_last_byte(values) end, do: uint8()
        end
    end

    defmacro string([length: length], []) do
        quote do
            repeat nil, unquote(length), fn { _, values } -> convert_to_string(values) end, do: uint8()
        end
    end

    defmacro string([], []) do
        quote do
            repeat nil, fn _ -> false end, fn { _, values } -> convert_to_string(values) end, do: uint8()
        end
    end

    defmacro string(options, []) when is_list(options) do
        quote do
            repeat nil, fn chars = [{ c }|_] ->
                c == unquote(fixup_value(options[:terminator])) or length(chars) == unquote(fixup_value(options[:length])) #todo: should change repeat step callback to pass in the length too
            end, fn { _, values } ->
                str = case List.last(values) == { unquote(fixup_value(options[:terminator])) } do #maybe repeat callbacks shouldn't pre-reverse the list and instead leave it up to the callback to reverse?
                    true -> convert_to_string_without_last_byte(values)
                    _ -> convert_to_string(values)
                end

                unquote(if options[:strip] != nil do
                    quote do: String.rstrip(str, unquote(fixup_value(options[:strip])))
                else
                    quote do: str
                end)
            end, do: uint8()
        end
    end

    defmacro string(name, terminator) when is_integer(terminator), do: quote do: string(unquote(name), terminator: unquote(terminator))
    defmacro string(name, [terminator: terminator]) do
        quote do
            repeat unquote(name), fn [{ c }|_] -> c == unquote(fixup_value(terminator)) end, &convert_to_string_without_last_byte/1, do: uint8()
        end
    end

    defmacro string(name, [length: length]) do
        quote do
            repeat unquote(name), unquote(length), &convert_to_string/1, do: uint8()
        end
    end

    defmacro string(name, []) do
        quote do
            repeat unquote(name), fn _ -> false end, &convert_to_string/1, do: uint8()
        end
    end

    defmacro string(name, options) do
        quote do
            repeat unquote(name), fn chars = [{ c }|_] ->
                c == unquote(fixup_value(options[:terminator])) or length(chars) == unquote(fixup_value(options[:length])) #todo: should change repeat step callback to pass in the length too
            end, fn charlist = { _, values } ->
                { name, str } = case List.last(values) == { unquote(fixup_value(options[:terminator])) } do #maybe repeat callbacks shouldn't pre-reverse the list and instead leave it up to the callback to reverse?
                    true -> convert_to_string_without_last_byte(charlist)
                    _ -> convert_to_string(charlist)
                end

                { name, unquote(if options[:strip] != nil do
                    quote do: String.rstrip(str, unquote(fixup_value(options[:strip])))
                else
                    quote do: str
                end) }
            end, do: uint8()
        end
    end
end

defmodule Tonic.MarkNotFound do
    defexception [:message, :name]

    def exception(option), do: %Tonic.MarkNotFound{ message: "no loaded value marked with name: #{option[:name]}", name: option[:name] }
end
