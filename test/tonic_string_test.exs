defmodule TonicStringTests do
    defmodule StringTillEnd do
        use ExUnit.Case
        use Tonic

        string :name

        test "string with no options" do
            assert { { { :name, "12345678" } }, <<>> } == Tonic.load(<<"12345678">>, __MODULE__)
        end
    end

    defmodule StringLength do
        use ExUnit.Case
        use Tonic

        string :name, length: 4

        test "string with length" do
            assert { { { :name, "1234" } }, <<"5678">> } == Tonic.load(<<"12345678">>, __MODULE__)
        end
    end

    defmodule StringNullTerminator do
        use ExUnit.Case
        use Tonic

        string :name, 0

        test "string with null terminator" do
            assert { { { :name, "1234" } }, <<"5678">> } == Tonic.load(<<"1234", 0, "5678">>, __MODULE__)
        end
    end

    defmodule StringLengthWithNullTerminator do
        use ExUnit.Case
        use Tonic

        string :name, length: 5, terminator: ?\n
        string :name, length: 5, terminator: ?\n

        test "string with length" do
            assert { { { :name, "1234" }, { :name, "56789" } }, <<"\n">> } == Tonic.load(<<"1234\n56789\n">>, __MODULE__)
        end
    end

    defmodule StringStrip do
        use ExUnit.Case
        use Tonic

        string :name, length: 5, strip: ?\n
        string :name, terminator: ?0, strip: ?\n

        test "string strip character" do
            assert { { { :name, "1234" }, { :name, "56789" } }, <<>> } == Tonic.load(<<"1234\n56789\n\n\n\n0">>, __MODULE__)
        end
    end

    defmodule UnnamedStringTillEnd do
        use ExUnit.Case
        use Tonic

        string

        test "unnamed string with no options" do
            assert { { "12345678" }, <<>> } == Tonic.load(<<"12345678">>, __MODULE__)
        end
    end

    defmodule UnnamedStringLength do
        use ExUnit.Case
        use Tonic

        string length: 4

        test "unnamed string with length" do
            assert { { "1234" }, <<"5678">> } == Tonic.load(<<"12345678">>, __MODULE__)
        end
    end

    defmodule UnnamedStringNullTerminator do
        use ExUnit.Case
        use Tonic

        string 0

        test "unnamed string with null terminator" do
            assert { { "1234" }, <<"5678">> } == Tonic.load(<<"1234", 0, "5678">>, __MODULE__)
        end
    end

    defmodule UnnamedStringLengthWithNullTerminator do
        use ExUnit.Case
        use Tonic

        string length: 5, terminator: ?\n
        string length: 5, terminator: ?\n

        test "unnamed string with length" do
            assert { { "1234", "56789" }, <<"\n">> } == Tonic.load(<<"1234\n56789\n">>, __MODULE__)
        end
    end

    defmodule UnnamedStringStrip do
        use ExUnit.Case
        use Tonic

        string length: 5, strip: ?\n
        string terminator: ?0, strip: ?\n

        test "unnamed string strip character" do
            assert { { "1234", "56789" }, <<>> } == Tonic.load(<<"1234\n56789\n\n\n\n0">>, __MODULE__)
        end
    end
end
