#Example (non-FAT) Mach-O loader (parses a few different load commands) and performs minimal formatting
defmodule MachO.Types do
    import Tonic
    import Tonic.Types
    import Bitwise

    type :cpu_type_t, :uint32
    type :cpu_subtype_t, :uint32
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
    uint32 :magic, :big
    endian get(:magic, fn
        mh_cigam_64() -> :little
        mh_cigam() -> :little
        mh_magic_64() -> :big
        mh_magic() -> :big
    end)

    cpu_type_t :cputype
    cpu_subtype_t :cpusubtype
    uint32 :filetype
    uint32 :ncmds
    uint32 :sizeofcmds
    uint32 :flags
    uint32 :reserved

    repeat get(:ncmds) do
        uint32 :cmd
        uint32 :cmdsize

        chunk get(:cmdsize, fn cmdsize -> cmdsize - 8 end) do
            on get(:cmd) do
                # 0x1 ->                    #segment
                0x2 ->                    #symtab
                    uint32 :symoff
                    uint32 :nsyms
                    uint32 :stroff
                    uint32 :strsize
                # 0x3 ->                    #symseg
                # 0x4 ->                    #thread
                # 0x5 ->                    #unixthread
                # 0x6 ->                    #loadfvmlib
                # 0x7 ->                    #idfvmlib
                # 0x8 ->                    #ident
                # 0x9 ->                    #fvmfile
                # 0xa ->                    #prepage
                0xb ->                    #dysymtab
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
                0xc ->                    #load_dylib
                    group :dylib do
                        skip do
                            group :lc_str do
                                uint32
                                optional do #only on 32bit
                                    on get(:magic) do
                                        32 -> uint32
                                    end
                                end
                            end
                        end
                        uint32 :timestamp
                        uint32 :current_version
                        uint32 :compatibility_version
                        string :name, strip: ?\0
                    end
                # 0xd ->                    #id_dylib
                0xe ->                    #load_dylinker
                    skip do
                        group :lc_str do
                            uint32
                            optional do #only on 32bit
                                on get(:magic) do
                                    32 -> uint32
                                end
                            end
                        end
                    end
                    string :name, strip: ?\0
                # 0xf ->                    #id_dylinker
                # 0x10 ->                   #prebound_dylib
                # 0x11 ->                   #routines
                # 0x12 ->                   #sub_framework
                # 0x13 ->                   #sub_umbrella
                # 0x14 ->                   #sub_client
                # 0x15 ->                   #sub_library
                # 0x16 ->                   #twolevel_hints
                # 0x17 ->                   #prebind_cksum
                # lc_req_dyld(0x18) ->      #load_weak_dylib
                0x19 ->                   #segment_64
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
                        uint32 :reserved1
                        uint32 :reserved2
                        uint32 :reserved3
                    end
                # 0x1a ->                   #routines_64
                # 0x1b ->                   #uuid
                # lc_req_dyld(0x1c) ->      #rpath
                # 0x1d ->                   #code_signature
                # 0x1e ->                   #segment_split_info
                # lc_req_dyld(0x1f) ->      #reexport_dylib
                # 0x20 ->                   #lazy_load_dylib
                # 0x21 ->                   #encryption_info
                0x22 ->                   #dyld_info
                    uint32 :rebase_off
                    uint32 :rebase_size
                    uint32 :bind_off
                    uint32 :bind_size
                    uint32 :weak_bind_off
                    uint32 :weak_bind_size
                    uint32 :lazy_bind_off
                    uint32 :lazy_bind_size
                    uint32 :export_off
                    uint32 :export_size
                lc_req_dyld(0x22) ->      #dyld_info_only
                    uint32 :rebase_off
                    uint32 :rebase_size
                    uint32 :bind_off
                    uint32 :bind_size
                    uint32 :weak_bind_off
                    uint32 :weak_bind_size
                    uint32 :lazy_bind_off
                    uint32 :lazy_bind_size
                    uint32 :export_off
                    uint32 :export_size
                # lc_req_dyld(0x23) ->      #load_upward_dylib
                # 0x24 ->                   #version_min_macosx
                # 0x25 ->                   #version_min_iphoneos
                # 0x26 ->                   #function_starts
                # 0x27 ->                   #dyld_environment
                # lc_req_dyld(0x28) ->      #main
                # 0x29 ->                   #data_in_code
                # 0x2A ->                   #source_version
                # 0x2B ->                   #dylib_code_sign_drs
                # 0x2C ->                   #encryption_info_64

                _ -> repeat :uint8
            end
        end
    end
end

#Example load result:
#{{:magic, 3489328638}, {:cputype, 16777223}, {:cpusubtype, 2147483651},
# {:filetype, 2}, {:ncmds, 22}, {:sizeofcmds, 2176}, {:flags, 2097285},
# {:reserved, 0},
# [{{:cmd, 25}, {:cmdsize, 72}, {:segname, "__PAGEZERO"}, {:vmaddr, 0},
#   {:vmsize, 4294967296}, {:fileoff, 0}, {:filesize, 0}, {:maxprot, 0},
#   {:initprot, 0}, {:nsects, 0}, {:flags, 0}, []},
#  {{:cmd, 25}, {:cmdsize, 632}, {:segname, "__TEXT"}, {:vmaddr, 4294967296},
#   {:vmsize, 4096}, {:fileoff, 0}, {:filesize, 4096}, {:maxprot, 7},
#   {:initprot, 5}, {:nsects, 7}, {:flags, 0},
#   [{{:sectname, "__text"}, {:segname, "__TEXT"}, {:addr, 4294970752},
#     {:size, 388}, {:offset, 3456}, {:align, 4}, {:reloff, 0}, {:nreloc, 0},
#     {:flags, 2147484672}, {:reserved1, 0}, {:reserved2, 0}, {:reserved3, 0}},
#    {{:sectname, "__stubs"}, {:segname, "__TEXT"}, {:addr, 4294971140},
#     {:size, 30}, {:offset, 3844}, {:align, 1}, {:reloff, 0}, {:nreloc, 0},
#     {:flags, 2147484680}, {:reserved1, 0}, {:reserved2, 6}, {:reserved3, 0}},
#    {{:sectname, "__stub_helper"}, {:segname, "__TEXT"}, {:addr, 4294971172},
#     {:size, 66}, {:offset, 3876}, {:align, 2}, {:reloff, 0}, {:nreloc, 0},
#     {:flags, 2147484672}, {:reserved1, 0}, {:reserved2, 0}, {:reserved3, 0}},
#    {{:sectname, "__objc_methname"}, {:segname, "__TEXT"}, {:addr, 4294971238},
#     {:size, 49}, {:offset, 3942}, {:align, 0}, {:reloff, 0}, {:nreloc, 0},
#     {:flags, 2}, {:reserved1, 0}, {:reserved2, 0}, {:reserved3, 0}},
#    {{:sectname, "__cstring"}, {:segname, "__TEXT"}, {:addr, 4294971287},
#     {:size, 3}, {:offset, 3991}, {:align, 0}, {:reloff, 0}, {:nreloc, 0},
#     {:flags, 2}, {:reserved1, 0}, {:reserved2, 0}, {:reserved3, 0}},
#    {{:sectname, "__unwind_info"}, {:segname, "__TEXT"}, {:addr, 4294971290},
#     {:size, 72}, {:offset, 3994}, {:align, 0}, {:reloff, 0}, {:nreloc, 0},
#     {:flags, 0}, {:reserved1, 0}, {:reserved2, 0}, {:reserved3, 0}},
#    {{:sectname, "__eh_frame"}, {:segname, "__TEXT"}, {:addr, 4294971368},
#     {:size, 24}, {:offset, 4072}, {:align, 3}, {:reloff, 0}, {:nreloc, 0},
#     {:flags, 0}, {:reserved1, 0}, {:reserved2, 0}, {:reserved3, 0}}]},
#  {{:cmd, 25}, {:cmdsize, 552}, {:segname, "__DATA"}, {:vmaddr, 4294971392},
#   {:vmsize, 4096}, {:fileoff, 4096}, {:filesize, 4096}, {:maxprot, 7},
#   {:initprot, 3}, {:nsects, 6}, {:flags, 0},
#   [{{:sectname, "__nl_symbol_ptr"}, {:segname, "__DATA"}, {:addr, 4294971392},
#     {:size, 16}, {:offset, 4096}, {:align, 3}, {:reloff, 0}, {:nreloc, 0},
#     {:flags, 6}, {:reserved1, 5}, {:reserved2, 0}, {:reserved3, 0}},
#    {{:sectname, "__la_symbol_ptr"}, {:segname, "__DATA"}, {:addr, 4294971408},
#     {:size, 40}, {:offset, 4112}, {:align, 3}, {:reloff, 0}, {:nreloc, 0},
#     {:flags, 7}, {:reserved1, 7}, {:reserved2, 0}, {:reserved3, 0}},
#    {{:sectname, "__objc_imageinfo"}, {:segname, "__DATA"}, {:addr, 4294971448},
#     {:size, 8}, {:offset, 4152}, {:align, 2}, {:reloff, 0}, {:nreloc, 0},
#     {:flags, 0}, {:reserved1, 0}, {:reserved2, 0}, {:reserved3, 0}},
#    {{:sectname, "__objc_selrefs"}, {:segname, "__DATA"}, {:addr, 4294971456},
#     {:size, 24}, {:offset, 4160}, {:align, 3}, {:reloff, 0}, {:nreloc, 0},
#     {:flags, 268435461}, {:reserved1, 0}, {:reserved2, 0}, {:reserved3, 0}},
#    {{:sectname, "__objc_classrefs"}, {:segname, "__DATA"}, {:addr, 4294971480},
#     {:size, 16}, {:offset, 4184}, {:align, 3}, {:reloff, 0}, {:nreloc, 0},
#     {:flags, 268435456}, {:reserved1, 0}, {:reserved2, 0}, {:reserved3, 0}},
#    {{:sectname, "__cfstring"}, {:segname, "__DATA"}, {:addr, 4294971496},
#     {:size, 32}, {:offset, 4200}, {:align, 3}, {:reloff, 0}, {:nreloc, 0},
#     {:flags, 0}, {:reserved1, 0}, {:reserved2, 0}, {:reserved3, 0}}]},
#  {{:cmd, 25}, {:cmdsize, 72}, {:segname, "__LINKEDIT"}, {:vmaddr, 4294975488},
#   {:vmsize, 4096}, {:fileoff, 8192}, {:filesize, 1024}, {:maxprot, 7},
#   {:initprot, 1}, {:nsects, 0}, {:flags, 0}, []},
#  {{:cmd, 2147483682}, {:cmdsize, 48}, {:rebase_off, 8192}, {:rebase_size, 8},
#   {:bind_off, 8200}, {:bind_size, 128}, {:weak_bind_off, 0},
#   {:weak_bind_size, 0}, {:lazy_bind_off, 8328}, {:lazy_bind_size, 120},
#   {:export_off, 8448}, {:export_size, 48}},
#  {{:cmd, 2}, {:cmdsize, 24}, {:symoff, 8752}, {:nsyms, 12}, {:stroff, 8992},
#   {:strsize, 224}},
#  {{:cmd, 11}, {:cmdsize, 80}, {:ilocalsym, 0}, {:nlocalsym, 1},
#   {:iextdefsym, 1}, {:nextdefsym, 2}, {:iundefsym, 3}, {:nundefsym, 9},
#   {:tocoff, 0}, {:ntoc, 0}, {:modtaboff, 0}, {:nmodtab, 0}, {:extrefsymoff, 0},
#   {:nextrefsyms, 0}, {:indirectsymoff, 8944}, {:nindirectsyms, 12},
#   {:extreloff, 0}, {:nextrel, 0}, {:locreloff, 0}, {:nlocrel, 0}},
#  {{:cmd, 14}, {:cmdsize, 32}, {:name, "/usr/lib/dyld"}},
#  {{:cmd, 27}, {:cmdsize, 24},
#   [124, 179, 41, 151, 153, 204, 61, 164, 147, 167, 144, 61, 53, 151, 95, 236]},
#  {{:cmd, 36}, {:cmdsize, 16}, [0, 9, 10, 0, 0, 9, 10, 0]},
#  {{:cmd, 42}, {:cmdsize, 16}, [0, 0, 0, 0, 0, 0, 0, 0]},
#  {{:cmd, 2147483688}, {:cmdsize, 24},
#   [128, 13, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]},
#  {{:cmd, 12}, {:cmdsize, 72},
#   {:dylib, {:timestamp, 2}, {:current_version, 65536},
#    {:compatibility_version, 65536},
#    {:name, "@rpath/CommonC.framework/Versions/A/CommonC"}}},
#  {{:cmd, 12}, {:cmdsize, 80},
#   {:dylib, {:timestamp, 2}, {:current_version, 65536},
#    {:compatibility_version, 65536},
#    {:name, "@rpath/CommonObjc.framework/Versions/A/CommonObjc"}}},
#  {{:cmd, 12}, {:cmdsize, 72},
#   {:dylib, {:timestamp, 2}, {:current_version, 65536},
#    {:compatibility_version, 65536},
#    {:name, "@rpath/CommonGL.framework/Versions/A/CommonGL"}}},
#  {{:cmd, 12}, {:cmdsize, 56},
#   {:dylib, {:timestamp, 2}, {:current_version, 78446849},
#    {:compatibility_version, 65536}, {:name, "/usr/lib/libSystem.B.dylib"}}},
#  {{:cmd, 12}, {:cmdsize, 56},
#   {:dylib, {:timestamp, 2}, {:current_version, 14942208},
#    {:compatibility_version, 65536}, {:name, "/usr/lib/libobjc.A.dylib"}}},
#  {{:cmd, 12}, {:cmdsize, 96},
#   {:dylib, {:timestamp, 2}, {:current_version, 69209344},
#    {:compatibility_version, 19660800},
#    {:name,
#     "/System/Library/Frameworks/Foundation.framework/Versions/C/Foundation"}}},
#  {{:cmd, 12}, {:cmdsize, 104},
#   {:dylib, {:timestamp, 2}, {:current_version, 56037632},
#    {:compatibility_version, 9830400},
#    {:name,
#     "/System/Library/Frameworks/CoreFoundation.framework/Versions/A/CoreFoundation"}}},
#  {{:cmd, 38}, {:cmdsize, 16}, [48, 33, 0, 0, 8, 0, 0, 0]},
#  {{:cmd, 41}, {:cmdsize, 16}, [56, 33, 0, 0, 0, 0, 0, 0]},
#  {{:cmd, 43}, {:cmdsize, 16}, [56, 33, 0, 0, 248, 0, 0, 0]}]}
