#Example (non-FAT) Mach-O loader (parses a few different load commands) and performs some minor additional formatting
defmodule MachO.Types do
    import Tonic
    import Tonic.Types
    import Bitwise

    type :cpu_type, fn
        <<0x01000007 :: integer-size(32)-unsigned-little, 0x80000003 :: integer-size(32)-unsigned-little, data :: binary>>, name, :little -> { { name, :cpu_type_x86_64, :cpu_subtype_x86_64_all }, data }
        <<0x01000007 :: integer-size(32)-unsigned-big, 0x80000003 :: integer-size(32)-unsigned-big, data :: binary>>, name, :big -> { { name, :cpu_type_x86_64, :cpu_subtype_x86_64_all }, data }
        <<0x01000007 :: integer-size(32)-unsigned-native, 0x80000003 :: integer-size(32)-unsigned-native, data :: binary>>, name, :native -> { { name, :cpu_type_x86_64, :cpu_subtype_x86_64_all }, data }
        <<_ :: integer-size(32)-unsigned, _ :: integer-size(32)-unsigned, data :: binary>>, name, _ -> { { name, :cpu_type_invalid, :cpu_subtype_invalid }, data }
    end
    type :vm_prot_t, :uint32


    defmacro fat_magic, do: 0xcafebabe
    defmacro fat_cigam, do: 0xbebafeca

    defmacro mh_magic, do: 0xfeedface
    defmacro mh_cigam, do: 0xcefaedfe
    defmacro mh_magic_64, do: 0xfeedfacf
    defmacro mh_cigam_64, do: 0xcffaedfe

    defmacro lc_req_dyld(cmd), do: bor(cmd, 0x80000000)
end

defmodule MachO do
    use Tonic
    import MachO.Types

    #only for non-FAT binaries
    uint32 :magic, :big, fn
        { name, mh_cigam_64() } -> {name, 64, :little }
        { name, mh_cigam() } -> {name, 32, :little }
        { name, mh_magic_64() } -> {name, 64, :big }
        { name, mh_magic() } -> {name, 32, :big }
    end
    endian get(:magic, fn { _, _, endianness } -> endianness end)

    cpu_type :cpu
    uint32 :filetype, fn
        { _, 0x1 } -> :object
        { _, 0x2 } -> :execute
        { _, 0x3 } -> :fvmlib
        { _, 0x4 } -> :core
        { _, 0x5 } -> :preload
        { _, 0x6 } -> :dylib
        { _, 0x7 } -> :dylinker
        { _, 0x8 } -> :bundle
        { _, 0x9 } -> :dylib_stub
        { _, 0xa } -> :dsym
        { _, 0xb } -> :kext_bundle
        { _, _ } -> :file_type_invalid
    end

    uint32 :ncmds
    uint32 :sizeofcmds
    uint32 :flags
    skip :uint32 #reserved

    repeat get(:ncmds) do
        uint32 :cmd, fn
            { _, 0x1 } ->                    :segment
            { _, 0x2 } ->                    :symtab
            { _, 0x3 } ->                    :symseg
            { _, 0x4 } ->                    :thread
            { _, 0x5 } ->                    :unixthread
            { _, 0x6 } ->                    :loadfvmlib
            { _, 0x7 } ->                    :idfvmlib
            { _, 0x8 } ->                    :ident
            { _, 0x9 } ->                    :fvmfile
            { _, 0xa } ->                    :prepage
            { _, 0xb } ->                    :dysymtab
            { _, 0xc } ->                    :load_dylib
            { _, 0xd } ->                    :id_dylib
            { _, 0xe } ->                    :load_dylinker
            { _, 0xf } ->                    :id_dylinker
            { _, 0x10 } ->                   :prebound_dylib
            { _, 0x11 } ->                   :routines
            { _, 0x12 } ->                   :sub_framework
            { _, 0x13 } ->                   :sub_umbrella
            { _, 0x14 } ->                   :sub_client
            { _, 0x15 } ->                   :sub_library
            { _, 0x16 } ->                   :twolevel_hints
            { _, 0x17 } ->                   :prebind_cksum
            { _, lc_req_dyld(0x18) } ->      :load_weak_dylib
            { _, 0x19 } ->                   :segment_64
            { _, 0x1a } ->                   :routines_64
            { _, 0x1b } ->                   :uuid
            { _, lc_req_dyld(0x1c) } ->      :rpath
            { _, 0x1d } ->                   :code_signature
            { _, 0x1e } ->                   :segment_split_info
            { _, lc_req_dyld(0x1f) } ->      :reexport_dylib
            { _, 0x20 } ->                   :lazy_load_dylib
            { _, 0x21 } ->                   :encryption_info
            { _, 0x22 } ->                   :dyld_info
            { _, lc_req_dyld(0x22) } ->      :dyld_info_only
            { _, lc_req_dyld(0x23) } ->      :load_upward_dylib
            { _, 0x24 } ->                   :version_min_macosx
            { _, 0x25 } ->                   :version_min_iphoneos
            { _, 0x26 } ->                   :function_starts
            { _, 0x27 } ->                   :dyld_environment
            { _, lc_req_dyld(0x28) } ->      :main
            { _, 0x29 } ->                   :data_in_code
            { _, 0x2A } ->                   :source_version
            { _, 0x2B } ->                   :dylib_code_sign_drs
            { _, 0x2C } ->                   :encryption_info_64
            cmd -> cmd
        end
        uint32 :cmdsize

        chunk get(:cmdsize, fn cmdsize -> cmdsize - 8 end) do
            on get(:cmd) do
                #segment
                :symtab ->
                    uint32 :symoff
                    uint32 :nsyms
                    uint32 :stroff
                    uint32 :strsize
                #symseg
                #thread
                #unixthread
                #loadfvmlib
                #idfvmlib
                #ident
                #fvmfile
                #prepage
                :dysymtab ->
                    uint32 :ilocalsym
                    uint32 :nlocalsym
                    uint32 :iextdefsym
                    uint32 :nextdefsym
                    uint32 :iundefsym
                    uint32 :nundefsym
                    uint32 :tocoff
                    uint32 :ntoc
                    uint32 :modtaboff
                    uint32 :nmodtab
                    uint32 :extrefsymoff
                    uint32 :nextrefsyms
                    uint32 :indirectsymoff
                    uint32 :nindirectsyms
                    uint32 :extreloff
                    uint32 :nextrel
                    uint32 :locreloff
                    uint32 :nlocrel
                :load_dylib ->
                    group :dylib do
                        skip do
                            group :lc_str do
                                uint32
                                optional do #only on 32bit
                                    on get(:magic) do
                                        { _, 32, _ } -> uint32
                                    end
                                end
                            end
                        end
                        uint32 :timestamp
                        uint32 :current_version, fn { name, value } ->
                            <<x :: size(16)-big, y :: big, z :: big>> = <<value :: size(32)-big>>
                            { name, { x, y, z } }
                        end
                        uint32 :compatibility_version, fn { name, value } ->
                            <<x :: size(16)-big, y :: big, z :: big>> = <<value :: size(32)-big>>
                            { name, { x, y, z } }
                        end
                        string :name, strip: ?\0
                    end
                #id_dylib
                :load_dylinker ->
                    skip do
                        group :lc_str do
                            uint32
                            optional do #only on 32bit
                                on get(:magic) do
                                    { _, 32, _ } -> uint32
                                end
                            end
                        end
                    end
                    string :name, strip: ?\0
                #id_dylinker
                #prebound_dylib
                #routines
                #sub_framework
                #sub_umbrella
                #sub_client
                #sub_library
                #twolevel_hints
                #prebind_cksum
                #load_weak_dylib
                :segment_64 ->
                    string :segname, length: 16, strip: ?\0
                    uint64 :vmaddr
                    uint64 :vmsize
                    uint64 :fileoff
                    uint64 :filesize
                    vm_prot_t :maxprot
                    vm_prot_t :initprot
                    uint32 :nsects
                    uint32 :flags

                    repeat get(:nsects) do
                        string :sectname, length: 16, strip: ?\0
                        string :segname, length: 16, strip: ?\0
                        uint64 :addr
                        uint64 :size
                        uint32 :offset
                        uint32 :align
                        uint32 :reloff
                        uint32 :nreloc
                        uint32 :flags
                        skip :uint32 #reserved1
                        skip :uint32 #reserved2
                        skip :uint32 #reserved3
                    end
                #routines_64
                #uuid
                #rpath
                #code_signature
                #segment_split_info
                #reexport_dylib
                #lazy_load_dylib
                #encryption_info
                :dyld_info ->
                    group :rebase do
                        uint32
                        uint32
                    end
                    group :bind do
                        uint32
                        uint32
                    end
                    group :weak_bind do
                        uint32
                        uint32
                    end
                    group :lazy_bind do
                        uint32
                        uint32
                    end
                    group :export do
                        uint32
                        uint32
                    end
                :dyld_info_only ->
                    group :rebase do
                        uint32
                        uint32
                    end
                    group :bind do
                        uint32
                        uint32
                    end
                    group :weak_bind do
                        uint32
                        uint32
                    end
                    group :lazy_bind do
                        uint32
                        uint32
                    end
                    group :export do
                        uint32
                        uint32
                    end
                #load_upward_dylib
                #version_min_macosx
                #version_min_iphoneos
                #function_starts
                #dyld_environment
                #main
                #data_in_code
                #source_version
                #dylib_code_sign_drs
                #encryption_info_64

                _ -> repeat :uint8
            end
        end
    end
end

#Example load result:
#{{:magic, 64, :little}, {:cpu, :cpu_type_x86_64, :cpu_subtype_x86_64_all},
# :execute, {:ncmds, 22}, {:sizeofcmds, 2176}, {:flags, 2097285}, {:reserved, 0},
# [{:segment_64, {:cmdsize, 72}, {:segname, "__PAGEZERO"}, {:vmaddr, 0},
#   {:vmsize, 4294967296}, {:fileoff, 0}, {:filesize, 0}, {:maxprot, 0},
#   {:initprot, 0}, {:nsects, 0}, {:flags, 0}, []},
#  {:segment_64, {:cmdsize, 632}, {:segname, "__TEXT"}, {:vmaddr, 4294967296},
#   {:vmsize, 4096}, {:fileoff, 0}, {:filesize, 4096}, {:maxprot, 7},
#   {:initprot, 5}, {:nsects, 7}, {:flags, 0},
#   [{{:sectname, "__text"}, {:segname, "__TEXT"}, {:addr, 4294970752},
#     {:size, 388}, {:offset, 3456}, {:align, 4}, {:reloff, 0}, {:nreloc, 0},
#     {:flags, 2147484672}},
#    {{:sectname, "__stubs"}, {:segname, "__TEXT"}, {:addr, 4294971140},
#     {:size, 30}, {:offset, 3844}, {:align, 1}, {:reloff, 0}, {:nreloc, 0},
#     {:flags, 2147484680}},
#    {{:sectname, "__stub_helper"}, {:segname, "__TEXT"}, {:addr, 4294971172},
#     {:size, 66}, {:offset, 3876}, {:align, 2}, {:reloff, 0}, {:nreloc, 0},
#     {:flags, 2147484672}},
#    {{:sectname, "__objc_methname"}, {:segname, "__TEXT"}, {:addr, 4294971238},
#     {:size, 49}, {:offset, 3942}, {:align, 0}, {:reloff, 0}, {:nreloc, 0},
#     {:flags, 2}},
#    {{:sectname, "__cstring"}, {:segname, "__TEXT"}, {:addr, 4294971287},
#     {:size, 3}, {:offset, 3991}, {:align, 0}, {:reloff, 0}, {:nreloc, 0},
#     {:flags, 2}},
#    {{:sectname, "__unwind_info"}, {:segname, "__TEXT"}, {:addr, 4294971290},
#     {:size, 72}, {:offset, 3994}, {:align, 0}, {:reloff, 0}, {:nreloc, 0},
#     {:flags, 0}},
#    {{:sectname, "__eh_frame"}, {:segname, "__TEXT"}, {:addr, 4294971368},
#     {:size, 24}, {:offset, 4072}, {:align, 3}, {:reloff, 0}, {:nreloc, 0},
#     {:flags, 0}}]},
#  {:segment_64, {:cmdsize, 552}, {:segname, "__DATA"}, {:vmaddr, 4294971392},
#   {:vmsize, 4096}, {:fileoff, 4096}, {:filesize, 4096}, {:maxprot, 7},
#   {:initprot, 3}, {:nsects, 6}, {:flags, 0},
#   [{{:sectname, "__nl_symbol_ptr"}, {:segname, "__DATA"}, {:addr, 4294971392},
#     {:size, 16}, {:offset, 4096}, {:align, 3}, {:reloff, 0}, {:nreloc, 0},
#     {:flags, 6}},
#    {{:sectname, "__la_symbol_ptr"}, {:segname, "__DATA"}, {:addr, 4294971408},
#     {:size, 40}, {:offset, 4112}, {:align, 3}, {:reloff, 0}, {:nreloc, 0},
#     {:flags, 7}},
#    {{:sectname, "__objc_imageinfo"}, {:segname, "__DATA"}, {:addr, 4294971448},
#     {:size, 8}, {:offset, 4152}, {:align, 2}, {:reloff, 0}, {:nreloc, 0},
#     {:flags, 0}},
#    {{:sectname, "__objc_selrefs"}, {:segname, "__DATA"}, {:addr, 4294971456},
#     {:size, 24}, {:offset, 4160}, {:align, 3}, {:reloff, 0}, {:nreloc, 0},
#     {:flags, 268435461}},
#    {{:sectname, "__objc_classrefs"}, {:segname, "__DATA"}, {:addr, 4294971480},
#     {:size, 16}, {:offset, 4184}, {:align, 3}, {:reloff, 0}, {:nreloc, 0},
#     {:flags, 268435456}},
#    {{:sectname, "__cfstring"}, {:segname, "__DATA"}, {:addr, 4294971496},
#     {:size, 32}, {:offset, 4200}, {:align, 3}, {:reloff, 0}, {:nreloc, 0},
#     {:flags, 0}}]},
#  {:segment_64, {:cmdsize, 72}, {:segname, "__LINKEDIT"}, {:vmaddr, 4294975488},
#   {:vmsize, 4096}, {:fileoff, 8192}, {:filesize, 1024}, {:maxprot, 7},
#   {:initprot, 1}, {:nsects, 0}, {:flags, 0}, []},
#  {:dyld_info_only, {:cmdsize, 48}, {:rebase, 8192, 8}, {:bind, 8200, 128},
#   {:weak_bind, 0, 0}, {:lazy_bind, 8328, 120}, {:export, 8448, 48}},
#  {:symtab, {:cmdsize, 24}, {:symoff, 8752}, {:nsyms, 12}, {:stroff, 8992},
#   {:strsize, 224}},
#  {:dysymtab, {:cmdsize, 80}, {:ilocalsym, 0}, {:nlocalsym, 1},
#   {:iextdefsym, 1}, {:nextdefsym, 2}, {:iundefsym, 3}, {:nundefsym, 9},
#   {:tocoff, 0}, {:ntoc, 0}, {:modtaboff, 0}, {:nmodtab, 0}, {:extrefsymoff, 0},
#   {:nextrefsyms, 0}, {:indirectsymoff, 8944}, {:nindirectsyms, 12},
#   {:extreloff, 0}, {:nextrel, 0}, {:locreloff, 0}, {:nlocrel, 0}},
#  {:load_dylinker, {:cmdsize, 32}, {:name, "/usr/lib/dyld"}},
#  {:uuid, {:cmdsize, 24},
#   [124, 179, 41, 151, 153, 204, 61, 164, 147, 167, 144, 61, 53, 151, 95, 236]},
#  {:version_min_macosx, {:cmdsize, 16}, [0, 9, 10, 0, 0, 9, 10, 0]},
#  {:source_version, {:cmdsize, 16}, [0, 0, 0, 0, 0, 0, 0, 0]},
#  {:main, {:cmdsize, 24}, [128, 13, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]},
#  {:load_dylib, {:cmdsize, 72},
#   {:dylib, {:timestamp, 2}, {:current_version, {1, 0, 0}},
#    {:compatibility_version, {1, 0, 0}},
#    {:name, "@rpath/CommonC.framework/Versions/A/CommonC"}}},
#  {:load_dylib, {:cmdsize, 80},
#   {:dylib, {:timestamp, 2}, {:current_version, {1, 0, 0}},
#    {:compatibility_version, {1, 0, 0}},
#    {:name, "@rpath/CommonObjc.framework/Versions/A/CommonObjc"}}},
#  {:load_dylib, {:cmdsize, 72},
#   {:dylib, {:timestamp, 2}, {:current_version, {1, 0, 0}},
#    {:compatibility_version, {1, 0, 0}},
#    {:name, "@rpath/CommonGL.framework/Versions/A/CommonGL"}}},
#  {:load_dylib, {:cmdsize, 56},
#   {:dylib, {:timestamp, 2}, {:current_version, {1197, 1, 1}},
#    {:compatibility_version, {1, 0, 0}},
#    {:name, "/usr/lib/libSystem.B.dylib"}}},
#  {:load_dylib, {:cmdsize, 56},
#   {:dylib, {:timestamp, 2}, {:current_version, {228, 0, 0}},
#    {:compatibility_version, {1, 0, 0}}, {:name, "/usr/lib/libobjc.A.dylib"}}},
#  {:load_dylib, {:cmdsize, 96},
#   {:dylib, {:timestamp, 2}, {:current_version, {1056, 13, 0}},
#    {:compatibility_version, {300, 0, 0}},
#    {:name,
#     "/System/Library/Frameworks/Foundation.framework/Versions/C/Foundation"}}},
#  {:load_dylib, {:cmdsize, 104},
#   {:dylib, {:timestamp, 2}, {:current_version, {855, 17, 0}},
#    {:compatibility_version, {150, 0, 0}},
#    {:name,
#     "/System/Library/Frameworks/CoreFoundation.framework/Versions/A/CoreFoundation"}}},
#  {:function_starts, {:cmdsize, 16}, [48, 33, 0, 0, 8, 0, 0, 0]},
#  {:data_in_code, {:cmdsize, 16}, [56, 33, 0, 0, 0, 0, 0, 0]},
#  {:dylib_code_sign_drs, {:cmdsize, 16}, [56, 33, 0, 0, 248, 0, 0, 0]}]}
