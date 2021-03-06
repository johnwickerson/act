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

(** Language lookup and module building support

    The various top-level act commands need to invoke the
   language-independent bits of act (in the [Lib] module) using the
   appropriate language-dependent bits.  This module works out which
   language is needed by looking at the 'emits' clause of a compiler
   spec, and hooks up the correct language-dependent modules. *)

open Core
open Lib

(** [asm_runner_from_spec spec] generates an assembly job runner from
   [spec]. *)
val asm_runner_from_spec
  :  Compiler.Spec.With_id.t
  -> (module Asm_job.Runner) Or_error.t
;;

(** [asm_runner_from_emits emits] generates an assembly job runner
   from an emits clause [emits]. *)
val asm_runner_from_emits
  :  string list
  -> (module Asm_job.Runner) Or_error.t
;;

(** [compiler_from_spec spec] generates a compiler module from
    [spec]. *)
val compiler_from_spec
  :  Compiler.Spec.With_id.t
  -> (module Compiler.S) Or_error.t
;;

(** [load_and_process_config ?compiler_predicate ?machine_predicate
   ?with_compiler_tests path] loads the config file at [path] and
   optionally tests all machines and compilers therein.

    If [machine_predicate] (a Blang expression) is present, only
   machines satisfying it will be enabled.

    If [compilers_predicate] (also a Blang expression) is present,
   only compilers satisfying it (on enabled machines) will be
   accepted.

    If [with_compiler_tests] is absent, or present and true, compilers
   will be tested for reachability. *)
val load_and_process_config
  :  ?compiler_predicate:Compiler.Property.t Blang.t
  -> ?machine_predicate:Machine.Property.t Blang.t
  -> ?with_compiler_tests:bool (* default true *)
  -> string
  -> Config.M.t Or_error.t
;;
