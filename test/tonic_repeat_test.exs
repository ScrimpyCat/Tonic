defmodule TonicRepeatTests do
    defmodule EmptyRepeat do
        use ExUnit.Case
        use Tonic

        repeat :values, 4 do
        end
        
        test "empty repeat" do
            assert { { { :values, [{}, {}, {}, {}] } }, <<1,2,3,4>> } == Tonic.load(<<1,2,3,4>>, __MODULE__)
        end
    end

    defmodule RepeatZeroTimes do
        use ExUnit.Case
        use Tonic

        repeat :values, 0 do
        end
        
        test "repeat zero times" do
            assert { { { :values, [] } }, <<1,2,3,4>> } == Tonic.load(<<1,2,3,4>>, __MODULE__)
        end
    end

    defmodule RepeatSingleTypeBlock do
        use ExUnit.Case
        use Tonic

        repeat :values, 4 do
            uint8 :v
        end

        test "block based repeat to capture four values" do
            assert { { { :values, [{ { :v, 1 } }, { { :v, 2 } }, { { :v, 3 } }, { { :v, 4 } }] } }, <<>> } == Tonic.load(<<1,2,3,4>>, __MODULE__)
        end
    end

    defmodule RepeatSingleUnammedTypeBlock do
        use ExUnit.Case
        use Tonic

        repeat :values, 4 do
            uint8
        end

        test "block based repeat to capture four unnamed values" do
            assert { { { :values, [{ 1 }, { 2 }, { 3 }, { 4 }] } }, <<>> } == Tonic.load(<<1,2,3,4>>, __MODULE__)
        end
    end

    defmodule RepeatTypeBlock do
        use ExUnit.Case
        use Tonic

        repeat :values, 2 do
            uint8 :a
            uint8 :b
        end

        test "block based repeat to capture 2x2 values" do
            assert { { { :values, [{ { :a, 1 }, { :b, 2 } }, { { :a, 3 }, { :b, 4 } }] } }, <<>> } == Tonic.load(<<1,2,3,4>>, __MODULE__)
        end
    end

    defmodule RepeatComplexBlock do
        use ExUnit.Case
        use Tonic

        repeat :values, 2 do
            repeat :four, 2 do
                group :test do
                    uint8 :a
                    uint8 :b
                end
            end
            uint8 :c
        end

        test "block based repeat to capture 2 times a group that repeats 2 times and a value" do
            assert { { { :values, [{ { :four, [{ { :test, { :a, 1 }, { :b, 2 } } }, { { :test, { :a, 3 }, { :b, 4 } } }] }, { :c, 5 } }, { { :four, [{ { :test, { :a, 6 }, { :b, 7 } } }, { { :test, { :a, 8 }, { :b, 9 } } }] }, { :c, 10 } }] } }, <<>> } == Tonic.load(<<1,2,3,4,5,6,7,8,9,10>>, __MODULE__)
        end
    end

    defmodule RepeatBlockWrap do
        use ExUnit.Case
        use Tonic

        repeat :values, 4, fn { _, value } -> value end do
            uint8 :v
        end

        test "block based repeat with function to strip repeat name" do
            assert { { [{ { :v, 1 } }, { { :v, 2 } }, { { :v, 3 } }, { { :v, 4 } }] }, <<>> } == Tonic.load(<<1,2,3,4>>, __MODULE__)
        end
    end

    defmodule RepeatBlockWrapComplex do
        use ExUnit.Case
        use Tonic

        repeat :values, 4, fn { _, value } ->
            Enum.map value, fn { i } -> i end
        end do
            uint8
        end

        test "block based repeat with a function to strip out repeat and index names" do
            assert { { [1, 2, 3, 4] }, <<>> } == Tonic.load(<<1,2,3,4>>, __MODULE__)
        end
    end

    defmodule RepeatUnnamedType do
        use ExUnit.Case
        use Tonic

        repeat :values, 4, :uint8

        test "repeat an unnamed type" do
            assert { { { :values, [1, 2, 3, 4] } }, <<>> } == Tonic.load(<<1,2,3,4>>, __MODULE__)
        end
    end

    defmodule UnnamedRepeatUnnamedType do
        use ExUnit.Case
        use Tonic

        repeat 4, :uint8

        test "an unnamed repeat of an unnamed type" do
            assert { { [1, 2, 3, 4] }, <<>> } == Tonic.load(<<1,2,3,4>>, __MODULE__)
        end
    end

    defmodule UnnamedRepeatBlock do
        use ExUnit.Case
        use Tonic

        repeat 4 do
            uint8 :v
        end

        test "an unnamed repeat of an named type" do
            assert { { [v: 1, v: 2, v: 3, v: 4] }, <<>> } == Tonic.load(<<1,2,3,4>>, __MODULE__)
        end
    end

    defmodule MultipleUnnamedRepeatBlock do
        use ExUnit.Case
        use Tonic

        repeat 2 do
            uint8 :a
        end

        repeat 2 do
            uint8 :b
        end

        test "multiple unnamed repeats of an named type" do
            assert { { [a: 1, a: 2], [b: 3, b: 4] }, <<>> } == Tonic.load(<<1,2,3,4>>, __MODULE__)
        end
    end
end
