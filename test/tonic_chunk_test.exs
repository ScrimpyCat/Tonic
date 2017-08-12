defmodule TonicChunkTests do
    defmodule UnusedChunk do
        use ExUnit.Case
        use Tonic

        chunk 4 do
        end

        test "unused chunk" do
            assert { {}, <<>> } == Tonic.load(<<1,2,3,4>>, __MODULE__)
        end
    end

    defmodule PartiallyUsedChunk do
        use ExUnit.Case
        use Tonic

        chunk 4 do
            uint8()
            uint8()
        end

        test "partially used chunk" do
            assert { { 1, 2 }, <<>> } == Tonic.load(<<1,2,3,4>>, __MODULE__)
        end
    end

    defmodule PartiallyUsedChunkNotEmpty do
        use ExUnit.Case
        use Tonic

        chunk 4 do
            uint8()
            uint8()
            empty!()
        end

        test "partially used chunk is not empty" do
            assert_raise Tonic.NotEmpty, fn -> Tonic.load(<<1,2,3,4>>, __MODULE__) end
        end
    end

    defmodule FullyUsedChunk do
        use ExUnit.Case
        use Tonic

        chunk 4 do
            repeat :uint8
        end

        test "fully used chunk" do
            assert { { [1, 2, 3, 4] }, <<>> } == Tonic.load(<<1,2,3,4>>, __MODULE__)
        end
    end

    defmodule FullyUsedChunkEmpty do
        use ExUnit.Case
        use Tonic

        chunk 4 do
            repeat :uint8
            empty!()
        end

        test "fully used chunk is empty" do
            assert { { [1, 2, 3, 4] }, <<>> } == Tonic.load(<<1,2,3,4>>, __MODULE__)
        end
    end

    defmodule NestedChunk do
        use ExUnit.Case
        use Tonic

        chunk 2 do
            uint8()
            chunk 1 do
                uint8()
            end
        end

        test "nested chunk" do
            assert { { 1, 2 }, <<3,4>> } == Tonic.load(<<1,2,3,4>>, __MODULE__)
        end
    end

    defmodule MultipleChunks do
        use ExUnit.Case
        use Tonic

        chunk 2 do
            uint8 :a
        end

        chunk 1 do
            uint8 :b
        end

        test "multiple chunks" do
            assert { { { :a, 1 }, { :b, 3 } }, <<4>> } == Tonic.load(<<1,2,3,4>>, __MODULE__)
        end
    end

    defmodule GetLengthChunk do
        use ExUnit.Case
        use Tonic

        uint8 :length
        chunk get(:length) do
            uint8()
        end

        test "get length chunk" do
            assert { { { :length, 1 }, 2 }, <<3,4>> } == Tonic.load(<<1,2,3,4>>, __MODULE__)
        end
    end
end
