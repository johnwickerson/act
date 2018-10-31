(* This file is part of 'act'.

   Copyright (c) 2018 by Matt Windsor

   Permission is hereby granted, free of charge, to any person
   obtaining a copy of this software and associated documentation
   files (the "Software"), to deal in the Software without
   restriction, including without limitation the rights to use, copy,
   modify, merge, publish, distribute, sublicense, and/or sell copies
   of the Software, and to permit persons to whom the Software is
   furnished to do so, subject to the following conditions:

   The above copyright notice and this permission notice shall be
   included in all copies or substantial portions of the Software.

   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
   EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
   MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
   NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
   BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
   ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
   CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
   SOFTWARE. *)

open Core
open Utils.MyContainers

include Sanitiser_intf

module Make_null_hook (LS : Language.Intf) = struct
  module L = LS
  module Ctx = Sanitiser_ctx.Make (LS) (Sanitiser_ctx.NoCustomWarn)

  let on_program = Ctx.return
  let on_statement = Ctx.return
  let on_instruction = Ctx.return
  let on_location = Ctx.return
end

let mangler =
  (* We could always just use something like Base36 here, but this
     seems a bit more human-readable. *)
  String.Escaping.escape_gen_exn
    ~escape_char:'Z'
    (* We escape some things that couldn't possibly appear in legal
       x86 assembler, but _might_ be generated during sanitisation. *)
    ~escapeworthy_map:[ '+', 'A' (* Add *)
                      ; ',', 'C' (* Comma *)
                      ; '$', 'D' (* Dollar *)
                      ; '.', 'F' (* Full stop *)
                      ; '-', 'M' (* Minus *)
                      ; '%', 'P' (* Percent *)
                      ; '@', 'T' (* aT *)
                      ; '_', 'U' (* Underscore *)
                      ; 'Z', 'Z' (* Z *)
                      ]
let mangle = Staged.unstage mangler

let%expect_test "mangle: sample" =
  print_string (mangle "_foo$bar.BAZ@lorem-ipsum+dolor,sit%amet");
  [%expect {| ZUfooZDbarZFBAZZZTloremZMipsumZAdolorZCsitZPamet |}]

module Make (B : Basic)
  : S with type statement = B.L.Statement.t
       and type sym = B.L.Symbol.t
       and type 'a Program_container.t = 'a B.Program_container.t = struct
  module Ctx = B.Ctx
  module Warn = B.Ctx.Warn
  module L = B.L

  module Program_container = B.Program_container

  (* Modules for building context-sensitive traversals over program
     containers and lists *)
  module Ctx_Pcon = Program_container.On_monad (Ctx)
  module Ctx_List = MyList.On_monad (Ctx)

  type statement = L.Statement.t
  type sym = L.Symbol.t

  module Output = struct
    type t =
      { result    : statement list Program_container.t
      ; warnings  : Warn.t list
      ; redirects : (sym, sym) List.Assoc.t
      } [@@deriving fields]
  end

  let make_programs_uniform nop ps =
    B.Program_container.right_pad ~padding:nop ps

  let change_stack_to_heap ins =
    let open Ctx.Let_syntax in
    let%map name = Ctx.get_prog_name in
    let f ln =
      match L.Location.abs_type ln with
      | Abstract.Location.StackOffset i ->
        L.Location.make_heap_loc
          (sprintf "t%ss%d" name i)
      | _ -> ln
    in L.Instruction.OnLocations.map ~f ins
  ;;

  (** [warn_unknown_instructions stm] emits warnings for each
      instruction in [stm] without a high-level analysis. *)
  let warn_unknown_instructions ins =
    let open Ctx.Let_syntax in
    match L.Instruction.abs_type ins with
     | Abstract.Instruction.Unknown ->
       let%map () = Ctx.warn (Warn.UnknownElt (Warn.Instruction ins)) in ins
     | _ -> return ins

  (** [warn_operands stm] emits warnings for each instruction
     in [stm] whose operands don't have a high-level analysis,
      or are erroneous. *)
  let warn_operands ins =
    (* Don't emit warnings for unknown instructions---the
       upper warning should be enough. *)
    let open Ctx.Let_syntax in
    let%map () =
      match L.Instruction.abs_type ins with
      | Abstract.Instruction.Unknown ->
        Ctx.return ()
      | _ ->
        begin
          match L.Instruction.abs_operands ins with
          | Abstract.Operands.Unknown ->
            Ctx.warn (Warn.UnknownElt (Warn.Operands ins))
          | Erroneous ->
            Ctx.warn (Warn.ErroneousElt (Warn.Operands ins))
          | _ -> Ctx.return ()
        end
    in ins
  ;;

  (** [mangle_and_redirect sym] mangles [sym], either by
      generating and installing a new mangling into
      the redirects table if none already exists; or by
      fetching the existing mangle. *)
  let mangle_and_redirect sym =
    let open Ctx.Let_syntax in
    match%bind Ctx.get_redirect sym with
    | Some sym' when not (L.Symbol.equal sym sym') ->
      (* There's an existing redirect, so we assume it's a
         mangled version. *)
      Ctx.return sym'
    | Some _ | None ->
      let sym' = L.Symbol.OnStrings.map ~f:mangle sym in
      Ctx.redirect ~src:sym ~dst:sym' >>| fun () -> sym'
  ;;

  let change_ret_to_end_jump ins =
    let open Ctx.Let_syntax in
    match L.Instruction.abs_type ins with
    | Abstract.Instruction.Return ->
      begin
        match%bind Ctx.get_end_label with
        | None ->
          let%map () = Ctx.warn Warn.MissingEndLabel in ins
        | Some endl ->
          return (L.Instruction.jump endl)
      end
    | _ -> Ctx.return ins
  ;;

  (** [sanitise_loc] performs sanitisation at the single location
      level. *)
  let sanitise_loc loc =
    let open Ctx in
    let open Sanitiser_pass in
    return loc
    >>= (LangHooks      |-> B.on_location)

  (** [sanitise_all_locs loc] iterates location sanitisation over
     every location in [loc], threading the context through
     monadically. *)
  let sanitise_all_locs =
    let module Loc = L.Instruction.OnLocations.On_monad (Ctx) in
    Loc.mapM ~f:sanitise_loc
  ;;

  (** [sanitise_ins] performs sanitisation at the single instruction
      level. *)
  let sanitise_ins ins =
    let open Ctx in
    let open Sanitiser_pass in
    return ins
    >>= (LangHooks      |-> B.on_instruction)
    >>= (Warn           |-> warn_unknown_instructions)
    >>= (Warn           |-> warn_operands)
    >>= sanitise_all_locs
    >>= (SimplifyLitmus |-> change_ret_to_end_jump)
    >>= (SimplifyLitmus |-> change_stack_to_heap)

  (** [mangle_identifiers progs] reduces identifiers across a program
      container [progs] into a form that herd can parse. *)
  let mangle_identifiers progs =
    let module Ctx_Stm_Sym = L.Statement.OnSymbols.On_monad (Ctx) in
    (* Nested mapping:
       over symbols in statements in statement lists in programs. *)
    Ctx_Pcon.mapM progs
      ~f:(Ctx_List.mapM ~f:(Ctx_Stm_Sym.mapM ~f:mangle_and_redirect))
  ;;

  (** [warn_unknown_statements stm] emits warnings for each statement in
      [stm] without a high-level analysis. *)
  let warn_unknown_statements stm =
    let open Ctx.Let_syntax in
    match L.Statement.abs_type stm with
    | Abstract.Statement.Other ->
      let%map () = Ctx.warn (Warn.UnknownElt (Warn.Statement stm)) in stm
    | _ -> return stm

  (** [sanitise_all_ins stm] iterates instruction sanitisation over
     every instruction in [stm], threading the context through
     monadically. *)
  let sanitise_all_ins =
    let module L = L.Statement.OnInstructions.On_monad (Ctx) in
    L.mapM ~f:sanitise_ins
  ;;

  (** [sanitise_stm] performs sanitisation at the single statement
      level. *)
  let sanitise_stm _ stm =
    let open Ctx in
    let open Sanitiser_pass in
    return stm
    >>= (LangHooks |-> B.on_statement)
    (* Do warnings after the language-specific hook has done any
       reduction necessary, but before we start making broad-brush
       changes to the statements. *)
    >>= (Warn |-> warn_unknown_statements)
    >>= sanitise_all_ins

  let any (fs : ('a -> bool) list) (a : 'a) : bool =
    List.exists ~f:(fun f -> f a) fs

  (** [irrelevant_instruction_types] lists the high-level types of
      instruction that can be thrown out when converting to a litmus
      test. *)
  let irrelevant_instruction_types =
    Abstract.Instruction.(
      Set.of_list
        [ Call (* -not- Return: these need more subtle translation *)
        ; Stack
        ]
    )

  let instruction_is_irrelevant =
    L.Statement.instruction_mem irrelevant_instruction_types

  (** [proglen_fix f prog] runs [f] on [prog] until the
      reported program length no longer changes. *)
  let proglen_fix f prog =
    let rec mu prog ctx =
      match
        Ctx.run
          (let open Ctx.Let_syntax in
           let%bind proglen  = Ctx.get_prog_length in
           let%bind prog'    = f prog in
           let%bind proglen' = Ctx.get_prog_length in
           let%map  ctx'     = Ctx.peek Fn.id in
           (ctx', proglen, proglen', prog'))
          ctx
      with
      | Ok (ctx', proglen, proglen', prog') ->
        if Int.equal proglen proglen'
        then Ok (ctx', prog') (* Fixed point *)
        else mu prog' ctx'
      | Error e -> Error e
    in
    Ctx.Monadic.make (mu prog)

  (** [remove_generally_irrelevant_statements prog] completely removes
     statements in [prog] that have no use in general and cannot be
     rewritten. *)
  let remove_generally_irrelevant_statements prog =
    let open Ctx.Let_syntax in
    let%bind syms = Ctx.get_symbol_table in
    let%map remove_boundaries =
      Ctx.is_pass_enabled Sanitiser_pass.RemoveBoundaries
    in
    let ignore_boundaries = not remove_boundaries in
    let matchers =
      L.Statement.(
        [ is_nop
        ; is_directive
        ; is_unused_label ~ignore_boundaries ~syms
        ])
    in
    MyList.exclude ~f:(any matchers) prog


  (** [remove_litmus_irrelevant_statements prog] completely removes
     statements in [prog] that have no use in Litmus and cannot be
     rewritten. *)
  let remove_litmus_irrelevant_statements prog =
    Ctx.return
      (let matchers =
         L.Statement.(
           [ instruction_is_irrelevant
           ; is_stack_manipulation
           ])
       in
       MyList.exclude ~f:(any matchers) prog)

  let remove_useless_jumps prog =
    let rec mu skipped ctx =
      function
      | x::x'::xs when L.Statement.is_jump_pair x x' ->
        let open Or_error.Let_syntax in
        let f = Ctx.(dec_prog_length >>= fun () -> peek Fn.id) in
        let%bind ctx' = Ctx.run f ctx in
        mu skipped ctx' (x'::xs)
      | x::x'::xs ->
        mu (x::skipped) ctx (x'::xs)
      | [] -> Or_error.return (ctx, List.rev skipped)
      | [x] -> Or_error.return (ctx, List.rev (x::skipped))
    in
    Ctx.Monadic.make (Fn.flip (mu []) prog)

  let update_symbol_tables
      (prog : statement list) =
    let open Ctx.Let_syntax in
    let%map () = Ctx.set_symbol_table (L.symbols prog) in
    prog
  ;;

  (** [add_end_label] adds an end-of-program label to the current
     program. *)
  let add_end_label (prog : statement list)
    : (statement list) Ctx.t =
    let open Ctx.Let_syntax in
    (* Don't generate duplicate endlabels! *)
    match%bind Ctx.get_end_label with
    | Some _ -> return prog
    | None ->
      let%bind progname = Ctx.get_prog_name in
      let prefix = "END" ^ progname in
      let%bind lbl = Ctx.make_fresh_label prefix in
      let%map () = Ctx.set_end_label lbl in
      prog @ [L.Statement.label lbl]
  ;;

  (** [remove_fix prog] performs a loop of statement-removing
     operations until we reach a fixed point in the program length. *)
  let remove_fix (prog : L.Statement.t list)
    : L.Statement.t list Ctx.t =
    let mu prog =
      Ctx.(
        return prog
        >>= update_symbol_tables
        >>= (RemoveUseless |-> remove_generally_irrelevant_statements)
        >>= (RemoveLitmus  |-> remove_litmus_irrelevant_statements)
        >>= (RemoveUseless |-> remove_useless_jumps)
      )
    in
    proglen_fix mu prog

  (** [sanitise_program] performs sanitisation on a single program. *)
  let sanitise_program
      (i : int) (prog : L.Statement.t list)
    : (L.Statement.t list) Ctx.t =
    let name = sprintf "%d" i in
    Ctx.(
      enter_program ~name prog
      (* Initial table population. *)
      >>= update_symbol_tables
      >>= (SimplifyLitmus |-> add_end_label)
      >>= (LangHooks      |-> B.on_program)
      (* The language hook might have invalidated the symbol
         tables. *)
      >>= update_symbol_tables
      (* Need to sanitise statements first, in case the sanitisation
         pass makes irrelevant statements (like jumps) relevant
         again. *)
      >>= Ctx_List.mapiM ~f:sanitise_stm
      >>= remove_fix
    )
  ;;

  (** [find_initial_redirects symbols] tries to find the compiler-mangled
      version of each symbol in [symbols].  In each case, it sets up a
      redirect in the redirects table.

      If it fails to find at least one of the symbols, it'll raise a
      warning. *)
  let find_initial_redirects symbols progs =
    let open Ctx in
    if List.is_empty symbols
    then return ()
    else begin
      let all_progs = Program_container.to_list progs in
      (* Build a map src->dst, where each dst is a symbol in the
         assembly, and src is one possible demangling of dst.
         We're assuming that there'll only be one unique dst for
         each src, and taking the most recent dst. *)
      let symbol_map =
        all_progs
        |> List.concat_map
            ~f:(List.concat_map ~f:L.Statement.OnSymbols.to_list)
        |> List.concat_map ~f:(
          fun dst ->
            List.map (L.Symbol.abstract_demangle dst)
              ~f:(fun src -> (src, dst))
        )
        |> String.Map.of_alist_reduce ~f:(fun _ y -> y)
      in
      Ctx_List.mapM symbols ~f:(
        fun src ->
          match String.Map.find symbol_map (L.Symbol.to_string src) with
          | Some dst -> Ctx.redirect ~src ~dst
          | None     -> Ctx.warn (Warn.SymbolRedirFail src)
      ) >>| (fun _ -> ())
    end
  ;;

  let sanitise_with_ctx symbols progs =
    let open Ctx.Let_syntax in
    let%bind () = find_initial_redirects symbols progs in
    let%bind progs' =
      Ctx_Pcon.mapiM ~f:sanitise_program progs
      (* We do this last, for two reasons: first, in case the
         instruction sanitisers have introduced invalid identifiers;
         and second, so that we know that the manglings agree across
         program boundaries.*)
      >>= Ctx.(MangleSymbols |-> mangle_identifiers)
    in
    let%bind warns = Ctx.take_warnings in
    let%map redirs = Ctx.get_redirect_alist symbols in
    Output.(
      { result = make_programs_uniform (L.Statement.empty ()) progs'
      ; warnings = warns
      ; redirects = redirs
      }
    )
  ;;

  let sanitise ?passes ?(symbols=[]) stms =
    let passes' = Option.value ~default:(Sanitiser_pass.all_set ()) passes in
    Ctx.(
      run
      (Monadic.return (B.split stms) >>= sanitise_with_ctx symbols)
      (initial ~passes:passes')
    )
  ;;
end

module Make_single (H : Hook) = Make(struct
    include H
    module Program_container = Utils.Fold_map.Singleton

    let split = Or_error.return (* no operation *)
  end)

module Make_multi (H : Hook) = Make(struct
    include H
    module Program_container = Utils.Fold_map.List

    let split stms =
      (* Adding a nop to the start forces there to be some
         instructions before the first program, meaning we can
         simplify discarding such instructions. *)
      let progs =
        (L.Statement.empty() :: stms)
        |> List.group ~break:(Fn.const L.Statement.is_program_boundary)
      in
      Or_error.return (List.drop progs 1)
      (* TODO(MattWindsor91): divine the end of the program. *)
  end)
