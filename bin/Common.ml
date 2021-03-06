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
open Lib

let get_target cfg = function
  | `Id id ->
    let open Or_error.Let_syntax in
    let%map spec = Compiler.Spec.Set.get (Config.M.compilers cfg) id in
    `Spec spec
  | `Arch _ as arch -> Or_error.return arch
;;

let arch_of_target = function
  | `Spec spec -> Compiler.Spec.With_id.emits spec
  | `Arch arch -> arch
;;

let runner_of_target = function
  | `Spec spec -> Language_support.asm_runner_from_spec spec
  | `Arch arch -> Language_support.asm_runner_from_emits arch
;;

let compile_with_compiler
    (c : (module Compiler.S)) o ~name ~infile ~outfile compiler_id =
  let open Or_error.Let_syntax in
  let module C = (val c) in
  Output.log_stage o ~stage:"CC" ~file:name compiler_id;

  let start_time = Time.now () in
  let%map () =
    Or_error.tag ~tag:"While compiling to assembly"
      (C.compile ~infile ~outfile)
  in
  let end_time = Time.now() in

  Time.diff end_time start_time
;;

let lift_command
    ?compiler_predicate
    ?machine_predicate
    ?with_compiler_tests
    ~f
    standard_args
  =
  let o =
    Output.make
      ~verbose:(Standard_args.is_verbose standard_args)
      ~warnings:(Standard_args.are_warnings_enabled standard_args)
  in
  Or_error.(
    Language_support.load_and_process_config
      ?compiler_predicate
      ?machine_predicate
      ?with_compiler_tests
      (Standard_args.spec_file standard_args)
    >>= f o
  ) |> Output.print_error o
;;

let litmusify ?programs_only (o : Output.t) inp outp symbols
    target =
  let open Result.Let_syntax in
  let%bind runner = runner_of_target target in
  let module Runner = (val runner) in
  let input =
    { Asm_job.inp
    ; outp
    ; passes = Sanitiser_pass.all_set ()
    ; symbols
    }
  in
  let%map output =
    Or_error.tag ~tag:"While translating assembly to litmus"
      (Runner.litmusify ?programs_only input)
  in
  Asm_job.warn output o.wf;
  Asm_job.symbol_map output
;;
