defmodule DataTypeTester do
    defp binary_parameters(type, 0, _, endianness) do
        {
            :-, [], [
                { type, [], nil },
                { endianness, [], nil }
            ]
        }
    end
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

    defp get_type_value(datatype, value) do
        { datatype, [], [value] }
    end

    defmacro single_type(datatype, value, type, size \\ 0, signedness \\ :signed, endianness \\ :native) do
        quote do
            single_type_verbose(unquote(datatype), :value, unquote(value), { :value, unquote(value) }, unquote(type), unquote(size), unquote(signedness), unquote(endianness))
        end
    end

    defmacro single_type_verbose(datatype, name, value, result, type, size \\ 0, signedness \\ :signed, endianness \\ :native) do
        quote do
            defmodule String.to_atom("Single" <> unquote(to_string(datatype) |> String.capitalize)) do
                use ExUnit.Case
                use Tonic

                unquote(get_type_value(datatype, name))

                test "load single " <> unquote(to_string(datatype)) <> " from single "  <> unquote(to_string(datatype)) <>  " data" do
                    assert { { unquote(result) }, <<>> } == Tonic.load(<<unquote(value) :: unquote(binary_parameters(type, size, signedness, endianness))>>, __MODULE__)
                end
                test "load single " <> unquote(to_string(datatype)) <> " from multiple bit data" do
                    assert { { unquote(result) }, <<0 :: size(24)>> } == Tonic.load(<<unquote(value) :: unquote(binary_parameters(type, size, signedness, endianness)), 0 :: size(24)>>, __MODULE__)
                end
            end
        end
    end
end

defmodule TonicTypeTest do
    defmodule TonicTypes do
        import DataTypeTester

        single_type(:int8, -1, :integer, 8, :signed)
        single_type(:uint8, 0xff, :integer, 8, :unsigned)
        single_type(:int16, -1, :integer, 16, :signed)
        single_type(:uint16, 0xffff, :integer, 16, :unsigned)
        single_type(:int32, -1, :integer, 32, :signed)
        single_type(:uint32, 0xffffffff, :integer, 32, :unsigned)
        single_type(:int64, -1, :integer, 64, :signed)
        single_type(:uint64, 0xffffffffffffffff, :integer, 64, :unsigned)

        single_type(:float32, 0.5, :float, 32)
        single_type(:float64, 0.5, :float, 64)
    end

    defmodule CustomTypes do
        defmodule DeclareTypes do
            use Tonic

            def func(data, name, :native) do
                <<value :: binary-size(5)-native, data :: binary>> = data
                { { name, value }, data }
            end

            #type/1
            type :custom_named_func_type, &DeclareTypes.func/3
            type :custom_func_type, fn data, name, :native ->
                <<value :: binary-size(5)-native, data :: binary>> = data
                { { name, value }, data }
            end
            type :custom_func_type_value, fn data, _name, :native ->
                <<value :: binary-size(5)-native, data :: binary>> = data
                { value, data }
            end

            #type/2
            type :custom_wrap_int32, :int32

            #type/3
            type :custom_wrap_lint32, :int32, :little
            type :custom_wrap_bint32, :int32, :big

            #type/4
            type :custom_int24, :integer, 24, :signed

            #type/5
            type :custom_lint24, :integer, 24, :signed, :little
            type :custom_bint24, :integer, 24, :signed, :big
        end

        defmodule CustomTypeTesters do
            import DataTypeTester
            import DeclareTypes

            single_type(:custom_named_func_type, <<"hello">>, :binary)
            single_type(:custom_func_type, <<"hello">>, :binary)
            single_type_verbose(:custom_func_type_value, nil, <<"hello">>, <<"hello">>, :binary)
            single_type(:custom_wrap_int32, -123, :integer, 32, :signed)
            single_type(:custom_wrap_lint32, 1, :integer, 32, :signed, :little)
            single_type(:custom_wrap_bint32, 1, :integer, 32, :signed, :big)
            single_type(:custom_int24, -123, :integer, 24, :signed)
            single_type(:custom_lint24, 1, :integer, 24, :signed, :little)
            single_type(:custom_bint24, 1, :integer, 24, :signed, :big)
        end
    end
end
