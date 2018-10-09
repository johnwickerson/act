open Core
open Utils
open Utils.MyContainers

type t =
  { basename   : string
  ; c_path     : string
  ; litc_path  : string
  ; out_root   : string
  ; a_paths    : (string, string) List.Assoc.t
  ; lita_paths : (string, string) List.Assoc.t
  }

type ent_type =
  | File
  | Dir
  | Nothing
  | Unknown

let get_ent_type (path : string) : ent_type =
  match Sys.file_exists path with
  | `No -> Nothing
  | `Unknown -> Unknown
  | `Yes ->
     match Sys.is_directory path with
     | `No -> File
     | `Unknown -> Unknown
     | `Yes -> Dir

(** [mkdir path] tries to make a directory at path [path].
    If [path] exists and is a directory, it does nothing.
    If [path] exists but is a file, or another error occurred, it returns
    an error message. *)
let mkdir (path : string) =
  let open Or_error in
  match get_ent_type path with
  | Dir -> Result.ok_unit
  | File -> error "path exists, but is a file" path [%sexp_of: string]
  | Unknown -> error "couldn't determine whether path already exists" path [%sexp_of: string]
  | Nothing -> Or_error.try_with (fun () -> Unix.mkdir path)

let c_path_of results_path : string -> string =
  Filename.concat (Filename.concat results_path "C")
let litc_path_of results_path : string -> string =
  Filename.concat (Filename.concat results_path "litmus")

let a_dir_of (root : string) (cname : string) : string =
  Filename.concat root (cname ^ "_asm")

let a_path_of (root : string) (file : string) (cname : string) : string =
  Filename.concat (a_dir_of root cname) file

let lita_dir_of (root : string) (cname : string) : string =
  Filename.concat root (cname ^ "_litmus")

let lita_path_of (root : string) (file : string) (cname : string) : string =
  Filename.concat (lita_dir_of root cname) file

let make_dir_structure ps =
  let open Or_error in
  try_with_join
    ( fun () ->
        if Sys.is_directory_exn ps.out_root
        then MyList.iter_result
            mkdir
            (List.map ~f:(fun (c, _) -> a_dir_of ps.out_root c) ps.a_paths
             @ List.map ~f:(fun (c, _) -> lita_dir_of ps.out_root c) ps.lita_paths)
        else error "not a directory" ps.out_root [%sexp_of: string]
    )

let make specs ~root_path ~results_path ~c_fname =
  let basename   = Filename.basename (Filename.chop_extension c_fname) in
  let lit_fname  = basename ^ ".litmus" in
  let spec_map f = List.map ~f:(fun (c, _) -> (c, f c)) specs in
  let asm_fname  = basename ^ ".s" in
  { basename     = basename
  ; out_root     = root_path
  ; c_path       = c_path_of    results_path c_fname
  ; litc_path    = litc_path_of results_path lit_fname
  ; a_paths      = spec_map (a_path_of root_path asm_fname)
  ; lita_paths   = spec_map (lita_path_of root_path lit_fname)
  }

let pp f ps =
  Format.pp_open_vbox f 4;
  Format.fprintf f "@[Paths for '%s'@ --@]" ps.basename;

  let p dir (k, v) =
    Format.pp_print_cut f ();
    MyFormat.pp_kv f (sprintf "%s (%s)" k dir) String.pp v
  in

  let in_paths =
    [ "C", ps.c_path
    ; "C/litmus", ps.litc_path
    ]
  in
  List.iter in_paths ~f:(p "in");

  let out_paths =
    List.map ~f:(fun (c, p) -> (c, p)) ps.a_paths
    @ List.map ~f:(fun (c, p) -> (c ^ "/litmus", p)) ps.lita_paths
  in
  List.iter out_paths ~f:(p "out");

  Format.pp_close_box f ()

