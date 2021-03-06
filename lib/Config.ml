(* This file is part of 'act'.

Copyright (c) 2018 by Matt Windsor

Permission is hereby granted, free of charge, to any person obtaining
a copy of this software and associated documentation files (the
"Software"), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to
the following conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. *)

open Core
open Utils

module type S = sig
  module C : Compiler.S_spec

  type t [@@deriving sexp]

  val herd : t -> Herd.Config.t option
  val compilers : t -> C.Set.t
  val machines : t -> Machine.Spec.Set.t
end

module Raw = struct
  module CI
    : S with module C = Compiler.Cfg_spec = struct
    module C = Compiler.Cfg_spec

    type t =
      { compilers : C.Set.t
      ; machines  : Machine.Spec.Set.t
      ; herd      : Herd.Config.t sexp_option
      }
    [@@deriving sexp, fields]
    ;;
  end

  include CI
  include Loadable.Of_sexpable (CI)
end

let part_chain_fst f g x =
  match f x with
  | `Fst y -> g y
  | `Snd y -> `Snd y
;;

(** Helpers for partitioning specs, parametrised on the spec
    type interface. *)
module Part_helpers (S : Spec.S) = struct
  (** [part_enabled x] is a partition_map function that
      sorts [x] into [`Fst] if they're enabled and [`Snd] if not. *)
  let part_enabled (x : S.With_id.t) =
    if S.With_id.is_enabled x
    then `Fst x
    else `Snd (S.With_id.id x, None)
  ;;

  (** [part_hook hook x] is a partition_map function that
      runs [hook] on [x], and sorts the result into [`Fst] if it
      succeeded and [`Snd] if not. *)
  let part_hook
      (hook : S.With_id.t -> S.With_id.t option Or_error.t)
      (x : S.With_id.t) =
    match hook x with
    | Result.Ok (Some x') -> `Fst x'
    | Result.Ok None      -> `Snd (S.With_id.id x, None)
    | Result.Error err    -> `Snd (S.With_id.id x, Some err)
  ;;
end

module M = struct
  module C = Compiler.Spec

  type t =
    { compilers          : C.Set.t
    ; machines           : Machine.Spec.Set.t
    ; herd               : Herd.Config.t sexp_option
    ; disabled_compilers : (Id.t, Error.t option) List.Assoc.t
    ; disabled_machines  : (Id.t, Error.t option) List.Assoc.t
    }
  [@@deriving sexp, fields]
  ;;

  module RP = Part_helpers (Raw.C);;
  module CP = Part_helpers (C);;
  module MP = Part_helpers (Machine.Spec);;

  (** ['t hook] is the type of testing hooks sent to [from_raw]. *)
  type 't hook = ('t -> 't option Or_error.t);;

  let machines_from_raw
      (hook : Machine.Spec.With_id.t hook)
      (ms : Machine.Spec.Set.t)
    : (Machine.Spec.Set.t * (Id.t, Error.t option) List.Assoc.t) Or_error.t =
    let open Or_error.Let_syntax in
    Machine.Spec.Set.(
      let enabled, disabled =
        partition_map
          ~f:(part_chain_fst MP.part_enabled (MP.part_hook hook))
          ms
      in
      (** TODO(@MattWindsor91): test machines *)
      let%map enabled' = Machine.Spec.Set.of_list enabled in
      (enabled', disabled)
    )
  ;;

  let build_compiler
      (rawc : Raw.C.With_id.t) (mach : Machine.Spec.With_id.t) : C.t =
    Raw.C.With_id.(
      C.create
        ~enabled:(is_enabled rawc)
        ~style:(style rawc)
        ~emits:(emits rawc)
        ~cmd:(cmd rawc)
        ~argv:(argv rawc)
        ~herd:(herd rawc)
        ~machine:mach
    )
  ;;

  let find_machine enabled disabled mach =
    Or_error.(
      match Machine.Spec.Set.get enabled mach with
      | Ok m -> return (`Fst m)
      | _ ->
        match List.Assoc.find ~equal:Id.equal disabled mach with
        | Some e -> return (`Snd (mach, e))
        | None -> error_s [%message "Machine doesn't exist" ~id:(mach : Id.t)]
    )
  ;;

  let part_resolve enabled disabled c =
    let machine_id = Raw.C.With_id.machine c in
    match find_machine enabled disabled machine_id with
    | (* Machine enabled *)
      Result.Ok (`Fst mach) ->
      `Fst
        (C.With_id.create
           ~id:(Raw.C.With_id.id c)
           ~spec:(build_compiler c mach))
    | (* Machine disabled, possibly because of error *)
      Result.Ok (`Snd (_, err)) ->
      `Snd
        ( Raw.C.With_id.id c
        , Option.map
            ~f:(Error.tag ~tag:"Machine was disabled because:")
            err
        )
    | (* Error actually finding the machine *)
      Result.Error err ->
      `Snd
        ( Raw.C.With_id.id c
        , Some (Error.tag ~tag:"Error finding machine:" err)
        )
  ;;

  let compilers_from_raw
      (ms : Machine.Spec.Set.t)
      (ms_disabled : (Id.t, Error.t option) List.Assoc.t)
      (hook : C.With_id.t hook)
      (cs : Raw.C.Set.t)
    : (C.Set.t * (Id.t, Error.t option) List.Assoc.t) Or_error.t =
    let open Or_error.Let_syntax in
    Raw.C.Set.(
      let enabled, disabled =
        partition_map
          ~f:(
            part_chain_fst
              (* First, remove disabled compilers... *)
              RP.part_enabled
              (* ...then, resolve machine IDs and remove compilers with
                 no enabled machine... *)
              (part_chain_fst
                 (part_resolve ms ms_disabled)
                 (* ...then, run the given testing/filtering hook. *)
                 (CP.part_hook hook))
          ) cs in
      (* TODO(@MattWindsor91): move compiler testing here. *)
      let%map enabled' = C.Set.of_list enabled in
      (enabled', disabled)
  )
  ;;

  let from_raw
      ?(chook=(Fn.compose Result.return Option.some))
      ?(mhook=(Fn.compose Result.return Option.some))
      (c : Raw.t)
    : t Or_error.t =
    let open Or_error.Let_syntax in
    let raw_ms = Raw.machines c in
    let%bind (machines, disabled_machines) = machines_from_raw mhook raw_ms in
    let raw_cs = Raw.compilers c in
    let%map (compilers, disabled_compilers) =
      compilers_from_raw machines disabled_machines chook raw_cs in
    { compilers
    ; machines
    ; disabled_compilers
    ; disabled_machines
    ; herd = Raw.herd c
    }
  ;;
end
