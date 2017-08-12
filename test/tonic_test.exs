defmodule TonicTest do
    defmodule OrderTest do
        use ExUnit.Case
        use Tonic

        uint32 :a
        uint8 :b
        float32 :c
        uint8 :d

        setup do
            {
                :ok, data: <<
                    1 :: integer-size(32)-unsigned-native,
                    2 :: integer-size(8)-unsigned-native,
                    3.5 :: float-size(32)-native,
                    4 :: integer-size(8)-unsigned-native
                >>
            }
        end

        test "load all values in correct order from data", %{ data: data } do
            assert { {
                { :a, 1 },
                { :b, 2 },
                { :c, 3.5 },
                { :d, 4 }
            }, <<>> } == Tonic.load(data, __MODULE__)
        end
    end

    defmodule BitTests do
        use ExUnit.Case
        use Tonic

        bit :a
        bit :b
        bit :c
        bit :d
        uint8 :e
        bit :f
        bit :g
        bit :h
        bit :i

        setup do
            {
                :ok, data: <<
                    0xaef5 :: integer-size(16)-unsigned-big
                >>
            }
        end

        test "load all values in correct order from data", %{ data: data } do
            assert { {
                { :a, true },
                { :b, false },
                { :c, true },
                { :d, false },
                { :e, 0xef },
                { :f, false },
                { :g, true },
                { :h, false },
                { :i, true }
            }, <<>> } == Tonic.load(data, __MODULE__)
        end
    end

    defmodule EmptyTests do
        use ExUnit.Case
        use Tonic

        int8 :a
        int8 :b
        empty!()

        setup do
            {
                :ok, data: <<1, 2>>
            }
        end

        test "data is empty", %{ data: data } do
            assert { {
                { :a, 1 },
                { :b, 2 }
            }, <<>> } == Tonic.load(data, __MODULE__)
        end

        test "data is not empty", %{ data: data } do
            assert_raise Tonic.NotEmpty, fn -> Tonic.load(<<data :: binary, 3>>, __MODULE__) end
        end
    end

    defmodule LoadOptionTests do
        defmodule CustomTypes do
            use Tonic

            #type/1
            type :custom_func_type_endian, fn data, name, endian ->
                <<_ :: integer-signed-size(32)-little, data :: binary>> = data
                { { name, endian }, data }
            end
            type :custom_func_type_lint32, fn data, name, _ ->
                <<value :: integer-signed-size(32)-little, data :: binary>> = data
                { { name, value }, data }
            end

            #type/2
            type :custom_wrap_int32, :int32

            #type/3
            type :custom_wrap_lint32, :int32, :little
            type :custom_wrap_bint32, :int32, :big

            #type/4
            type :custom_int32, :integer, 32, :signed

            #type/5
            type :custom_lint32, :integer, 32, :signed, :little
            type :custom_bint32, :integer, 32, :signed, :big
        end

        defmodule EndianOverride do
            use ExUnit.Case
            use Tonic
            import CustomTypes

            endian :little
            int32 :a, :big
            custom_func_type_endian :b, :big #endianness is returned by the function so it can be override
            custom_func_type_lint32 :c, :big #endianness specified inside the function so cannot be overriden
            custom_wrap_int32 :d, :big
            custom_wrap_lint32 :e, :big #endianness specified in type declaration so cannot be overriden
            custom_wrap_bint32 :f, :big #endianness specified in type declaration so cannot be overriden
            custom_int32 :g, :big
            custom_lint32 :h, :big #endianness specified in type declaration so cannot be overriden
            custom_bint32 :i, :big #endianness specified in type declaration so cannot be overriden

            setup do
                {
                    :ok, data: <<
                        1 :: integer-size(32)-signed-big,
                        2 :: integer-size(32)-signed-big,
                        3 :: integer-size(32)-signed-little,
                        4 :: integer-size(32)-signed-big,
                        5 :: integer-size(32)-signed-little,
                        6 :: integer-size(32)-signed-big,
                        7 :: integer-size(32)-signed-big,
                        8 :: integer-size(32)-signed-little,
                        9 :: integer-size(32)-signed-big
                    >>
                }
            end

            test "endian overriding of types", %{ data: data } do
                assert { {
                    { :a, 1 },
                    { :b, :big },
                    { :c, 3 },
                    { :d, 4 },
                    { :e, 5 },
                    { :f, 6 },
                    { :g, 7 },
                    { :h, 8 },
                    { :i, 9 }
                }, <<>> } == Tonic.load(data, __MODULE__)
            end
        end

        defmodule Unnamed do
            use ExUnit.Case
            use Tonic
            import CustomTypes

            endian :little
            int32()
            custom_func_type_endian()
            custom_func_type_lint32()
            custom_wrap_int32()
            custom_wrap_lint32()
            custom_int32()
            custom_lint32()

            setup do
                {
                    :ok, data: <<
                        1 :: integer-size(32)-signed-little,
                        2 :: integer-size(32)-signed-little,
                        3 :: integer-size(32)-signed-little,
                        4 :: integer-size(32)-signed-little,
                        5 :: integer-size(32)-signed-little,
                        6 :: integer-size(32)-signed-little,
                        7 :: integer-size(32)-signed-little
                    >>
                }
            end

            test "unnamed types", %{ data: data } do
                assert { {
                    1,
                    :little,
                    3,
                    4,
                    5,
                    6,
                    7
                }, <<>> } == Tonic.load(data, __MODULE__)
            end
        end

        defmodule WrapOutput do
            use ExUnit.Case
            use Tonic
            import CustomTypes

            def fun({ _, value }), do: value

            endian :little
            int32 :a, fn { _, value } -> value end
            custom_func_type_endian :b, fn { _, value } -> value end
            custom_wrap_int32 :c, fn { _, value } -> value end
            custom_wrap_lint32 :d, fn { _, value } -> value end
            custom_int32 :e, fn { _, value } -> value end
            custom_lint32 :f, fn { _, value } -> value end
            int32 :g, &WrapOutput.fun/1
            custom_func_type_endian :h, &WrapOutput.fun/1
            custom_wrap_int32 :i, &WrapOutput.fun/1
            custom_wrap_lint32 :j, &WrapOutput.fun/1
            custom_int32 :k, &WrapOutput.fun/1
            custom_lint32 :l, &WrapOutput.fun/1

            setup do
                {
                    :ok, data: <<
                        1 :: integer-size(32)-signed-little,
                        2 :: integer-size(32)-signed-little,
                        3 :: integer-size(32)-signed-little,
                        4 :: integer-size(32)-signed-little,
                        5 :: integer-size(32)-signed-little,
                        6 :: integer-size(32)-signed-little,
                        7 :: integer-size(32)-signed-little,
                        8 :: integer-size(32)-signed-little,
                        9 :: integer-size(32)-signed-little,
                        10 :: integer-size(32)-signed-little,
                        11 :: integer-size(32)-signed-little,
                        12 :: integer-size(32)-signed-little
                    >>
                }
            end

            test "custom functions for types", %{ data: data } do
                assert { {
                    1,
                    :little,
                    3,
                    4,
                    5,
                    6,
                    7,
                    :little,
                    9,
                    10,
                    11,
                    12
                }, <<>> } == Tonic.load(data, __MODULE__)
            end
        end

        defmodule WrapEndianOutput do
            use ExUnit.Case
            use Tonic
            import CustomTypes

            def fun({ _, value }), do: value

            endian :little
            int32 :a, :big, fn { _, value } -> value end
            custom_func_type_endian :b, :big, fn { _, value } -> value end
            custom_wrap_int32 :c, :big, fn { _, value } -> value end
            custom_wrap_lint32 :d, :big, fn { _, value } -> value end
            custom_int32 :e, :big, fn { _, value } -> value end
            custom_lint32 :f, :big, fn { _, value } -> value end
            int32 :g, :big, &WrapOutput.fun/1
            custom_func_type_endian :h, :big, &WrapOutput.fun/1
            custom_wrap_int32 :i, :big, &WrapOutput.fun/1
            custom_wrap_lint32 :j, :big, &WrapOutput.fun/1
            custom_int32 :k, :big, &WrapOutput.fun/1
            custom_lint32 :l, :big, &WrapOutput.fun/1

            setup do
                {
                    :ok, data: <<
                        1 :: integer-size(32)-signed-big,
                        2 :: integer-size(32)-signed-big,
                        3 :: integer-size(32)-signed-big,
                        4 :: integer-size(32)-signed-little,
                        5 :: integer-size(32)-signed-big,
                        6 :: integer-size(32)-signed-little,
                        7 :: integer-size(32)-signed-big,
                        8 :: integer-size(32)-signed-big,
                        9 :: integer-size(32)-signed-big,
                        10 :: integer-size(32)-signed-little,
                        11 :: integer-size(32)-signed-big,
                        12 :: integer-size(32)-signed-little
                    >>
                }
            end

            test "custom functions for types and overriding endianness", %{ data: data } do
                assert { {
                    1,
                    :big,
                    3,
                    4,
                    5,
                    6,
                    7,
                    :big,
                    9,
                    10,
                    11,
                    12
                }, <<>> } == Tonic.load(data, __MODULE__)
            end
        end
    end
end
