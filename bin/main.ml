open Core
open Rresult
open Lib
open Lang

type config =
  {
    verbose : bool ref;

    out_root_path : string ref;

    results_paths : string Queue.t;

    spec_file : string ref;
  }

let usage = "act [paths to comparator output]"

let asm_path_of (cc_id : string) (ps : Pathset.t) : string =
  List.Assoc.find_exn ps.a_paths cc_id ~equal:(=)

let summarise_pathset (vf : Format.formatter) (ps : Pathset.t) : unit =
  List.iter
    ~f:(fun (io, t, v) -> Format.fprintf vf "@[[%s] %s file:@ %s@]@." io t v)
    ( [ ("in" , "C"         , ps.c_path)
      ; ("in" , "C Litmus"  , ps.litc_path)
      ]
      @ List.map ~f:(fun (c, p) -> ("out", c, p)) ps.a_paths
      @ List.map ~f:(fun (c, p) -> ("out", c ^ " (litmus)", p)) ps.lita_paths)

let format_to_string pp v : string =
  let buf = Buffer.create 16 in
  let f = Format.formatter_of_buffer buf in
  Format.pp_open_box f 0;
  pp f v;
  Format.pp_close_box f ();
  Format.pp_print_flush f ();
  Buffer.contents buf

let c_asm (cn : string) (ps : Pathset.t) =
  R.reword_error
    (function
     | LangParser.Parse(perr) ->
        R.msg (format_to_string X86ATT.Frontend.pp_perr perr)
     | LangParser.Lex(lerr) ->
        R.msg (format_to_string X86ATT.Frontend.pp_lerr lerr)
    )
    (X86ATT.Frontend.run_file ~file:(asm_path_of cn ps))

let proc_c (cfg : config) (cc_specs : CompilerSpec.set) vf results_path c_fname =
  let root = !(cfg.out_root_path) in
  let paths = Pathset.make cc_specs
                           ~root_path:root
                           ~results_path:results_path
                           ~c_fname:c_fname in
  summarise_pathset vf paths;
  Pathset.make_dir_structure paths |>
    R.reword_error_msg (fun _ -> R.msg "couldn't make dir structure")
  >>= (
    fun _ -> Utils.iter_result
               (fun (cn, cs) ->
                 Compiler.compile cn cs paths
                 >>= (fun _ -> Result.map ~f:ignore (c_asm cn paths))

               ) cc_specs
  )

let proc_results (cfg : config) (cc_specs : CompilerSpec.set) (vf : Format.formatter) (results_path : string) =
  let c_path = Filename.concat results_path "C" in
  try
    Sys.readdir c_path
    |> Array.filter ~f:(fun file -> snd (Filename.split_extension file) = Some "c")
    |> Array.fold_result
         ~init:()
         ~f:(fun _ -> proc_c cfg cc_specs vf results_path)
  with
    Sys_error e -> R.error_msgf "system error: %s" e

let pp_config (f : Format.formatter) (cfg : config) : unit =
  Format.pp_open_vbox f 0;
  Format.pp_print_string f "Config --";
  Format.pp_print_break f 0 4;
  Format.pp_open_vbox f 0;
  MyFormat.pp_kv f "Reading compiler specs from" MyFormat.pp_sr cfg.spec_file;
  Format.pp_print_cut f ();
  MyFormat.pp_kv f "memalloy results paths" MyFormat.pp_sq cfg.results_paths;
  Format.pp_close_box f ();
  Format.pp_print_cut f ();
  Format.pp_close_box f ();
  Format.pp_print_flush f ()

let pp_specs (f : Format.formatter) (specs : CompilerSpec.set) : unit =
  Format.pp_open_vbox f 0;
  Format.pp_print_string f "Compiler specs --";
  Format.pp_print_break f 0 4;
  Format.pp_open_vbox f 0;
  List.iter ~f:(fun (c, s) -> MyFormat.pp_kv f c CompilerSpec.pp s) specs;
  Format.pp_close_box f ();
  Format.pp_print_cut f ();
  Format.pp_close_box f ();
  Format.pp_print_flush f ()

(** [make_compiler_specs specpath] reads in the compiler spec list at
    [specpath], converting it to a [compiler_spec_set]. *)

let make_compiler_specs (specpath : string) =
  CompilerSpec.load_specs ~path:specpath
  |> List.fold_result ~init:[]
                      ~f:(fun specs (c, spec) ->
                        Compiler.test spec >>| (fun _ -> (c, spec)::specs)
                      )
let () =
  let cfg : config =
    { verbose = ref false
    ; results_paths = Queue.create ()
    ; out_root_path = ref Filename.current_dir_name
    ; spec_file = ref (Filename.concat Filename.current_dir_name "compiler.spec")
    }
  in

  let spec =
    [ ("-o", Arg.Set_string cfg.out_root_path,
       "The path under which output directories will be created.")
    ; ("-v", Arg.Set cfg.verbose,
       "Verbose mode.")
    ; ("-c", Arg.Set_string cfg.spec_file,
       "The compiler spec file to use.")
    ; ("--", Arg.Rest (Queue.enqueue cfg.results_paths), "")
    ]
  in
  Arg.parse spec (Queue.enqueue cfg.results_paths) usage;

  let verbose_fmt =
    if !(cfg.verbose)
    then Format.err_formatter
    else MyFormat.null_formatter ()
  in
  pp_config verbose_fmt cfg;

  make_compiler_specs !(cfg.spec_file) |>
    R.reword_error_msg (fun _ -> R.msg "Compiler specs are invalid.")
  >>= (
    fun specs ->
    pp_specs verbose_fmt specs;
    Queue.fold_result cfg.results_paths
                      ~init:()
                      ~f:(fun _ -> proc_results cfg specs verbose_fmt);
  )
  |>
    function
    | Ok _ -> ()
    | Error err ->
       Format.eprintf "@[Fatal error:@.@[%a@]@]@." R.pp_msg err
