defmodule TonicGroupTests do
    defmodule EmptyGroup do
        use ExUnit.Case
        use Tonic

        group :group_a do
        end
        
        test "empty group" do
            assert { { { :group_a } }, <<>> } == Tonic.load(<<>>, __MODULE__)
        end
    end

    defmodule NestedEmptyGroup do
        use ExUnit.Case
        use Tonic

        group :group_a do
            group :group_a_a do
                group :group_a_a_a do
                    group :group_a_a_a_a do
                    end
                end
                group :group_a_a_b do
                end
            end
            group :group_a_b do
            end
            group :group_a_c do
                group :group_a_c_a do
                end
            end
            group :group_a_d do
            end
        end

        group :group_b do
        end
        
        test "nested empty groups" do
            assert { {
                {
                    :group_a,
                    {
                        :group_a_a,
                        {
                            :group_a_a_a,
                            {
                                :group_a_a_a_a
                            }
                        },
                        {
                            :group_a_a_b
                        }
                    },
                    {
                        :group_a_b
                    },
                    {
                        :group_a_c,
                        {
                            :group_a_c_a
                        }
                    },
                    {
                        :group_a_d
                    }
                },
                {
                    :group_b
                }
            }, <<>> } == Tonic.load(<<>>, __MODULE__)
        end
    end

    defmodule NestedGroupData do
        use ExUnit.Case
        use Tonic

        endian :little
        uint8 :a
        group :group_a do
            uint8 :a_a
            group :group_a_a do
                group :group_a_a_a do
                    uint8 :a_a_a_a
                    uint8 :a_a_a_b
                end
            end
            uint8 :a_b
            group :group_a_b do
                uint8 :a_b_a
            end
        end
        uint8 :b
        group :group_b do
            uint8 :b_a
        end

        setup do
            {
                :ok, data: <<
                    1 :: integer-size(8)-unsigned-little,
                    2 :: integer-size(8)-unsigned-little,
                    3 :: integer-size(8)-unsigned-little,
                    4 :: integer-size(8)-unsigned-little,
                    5 :: integer-size(8)-unsigned-little,
                    6 :: integer-size(8)-unsigned-little,
                    7 :: integer-size(8)-unsigned-little,
                    8 :: integer-size(8)-unsigned-little
                >>
            }
        end
        
        test "grouped data", %{ data: data } do
            assert { {
                { :a, 1 },
                { :group_a,
                    { :a_a, 2 },
                    { :group_a_a,
                        { :group_a_a_a, { :a_a_a_a, 3 }, { :a_a_a_b, 4 } }
                    },
                    { :a_b, 5 },
                    { :group_a_b, { :a_b_a, 6 } }
                },
                {:b, 7},
                { :group_b, { :b_a, 8 } }
            }, <<>> } == Tonic.load(data, __MODULE__)
        end
    end

    defmodule Scope do
        use ExUnit.Case
        use Tonic

        endian :little                  #set little
        uint16 :a                       #little
        group :group_a do               #little
            endian :big                 #set big
            uint16 :a_a                 #big
            group :group_a_a do         #big
                group :group_a_a_a do   #big
                    uint16 :a_a_a_a     #big
                    endian :little      #set little
                    uint16 :a_a_a_b     #little
                end                     #big
            end                         #big
            uint16 :a_b                 #big
            group :group_a_b do         #big
                uint16 :a_b_a           #big
            end                         #big
        end                             #little
        uint16 :b                       #little
        endian :big                     #set big
        group :group_b do               #big
            uint16 :b_a                 #big
        end                             #big

        setup do
            {
                :ok, data: <<
                    1 :: integer-size(16)-unsigned-little,
                    2 :: integer-size(16)-unsigned-big,
                    3 :: integer-size(16)-unsigned-big,
                    4 :: integer-size(16)-unsigned-little,
                    5 :: integer-size(16)-unsigned-big,
                    6 :: integer-size(16)-unsigned-big,
                    7 :: integer-size(16)-unsigned-little,
                    8 :: integer-size(16)-unsigned-big
                >>
            }
        end
        
        test "group scope", %{ data: data } do
            assert { {
                { :a, 1 },
                { :group_a,
                    { :a_a, 2 },
                    { :group_a_a,
                        { :group_a_a_a, { :a_a_a_a, 3 }, { :a_a_a_b, 4 } }
                    },
                    { :a_b, 5 },
                    { :group_a_b, { :a_b_a, 6 } }
                },
                {:b, 7},
                { :group_b, { :b_a, 8 } }
            }, <<>> } == Tonic.load(data, __MODULE__)
        end
    end

    defmodule GroupWrapper do
        use ExUnit.Case
        use Tonic

        endian :little
        group :group_a, fn { _, value } -> value end do
            uint32 :value
        end

        test "group custom functions" do
            assert { { { :value, 1 } }, <<>> } == Tonic.load(<<1 :: size(32)-little>>, __MODULE__)
        end
    end

    defmodule UnnamedGroupWrapper do
        use ExUnit.Case
        use Tonic

        endian :little
        group do
            uint16 :a
            uint16 :b
        end

        test "unnamed group" do
            assert { { { { :a, 1 }, { :b, 0 } } }, <<>> } == Tonic.load(<<1 :: size(32)-little>>, __MODULE__)
        end
    end

    defmodule MultipleUnnamedGroups do
        use ExUnit.Case
        use Tonic

        endian :little
        group do
            uint8 :a
            uint8 :b
        end

        group do
            uint8 :c
            uint8 :d
        end

        test "multiple unnamed groups" do
            assert { { { { :a, 1 }, { :b, 0 } }, { { :c, 0 }, { :d, 0 } } }, <<>> } == Tonic.load(<<1 :: size(32)-little>>, __MODULE__)
        end
    end
end
