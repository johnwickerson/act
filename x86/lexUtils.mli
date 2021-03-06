(****************************************************************************)
(*                           the diy toolsuite                              *)
(*                                                                          *)
(* Jade Alglave, University College London, UK.                             *)
(* Luc Maranget, INRIA Paris-Rocquencourt, France.                          *)
(*                                                                          *)
(* Copyright 2010-present Institut National de Recherche en Informatique et *)
(* en Automatique and the authors. All rights reserved.                     *)
(*                                                                          *)
(* This software is governed by the CeCILL-B license under French law and   *)
(* abiding by the rules of distribution of free software. You can use,      *)
(* modify and/ or redistribute the software under the terms of the CeCILL-B *)
(* license as circulated by CEA, CNRS and INRIA at the following URL        *)
(* "http://www.cecill.info". We also give a copy in LICENSE.txt.            *)
(****************************************************************************)

(** Utility functions for lexers *)

(* The Lexing module of standard library defines
     - input buffers for ocamllex lexers [type lexbuf]
     - position in streams being lexed [type position]
*)
open Lexing

module type Config = sig
  val debug : bool
end

module Default : Config

module Make : functor (O:Config) -> sig

(* Lexer used elsewhere *)
val skip_comment : lexbuf -> unit
val skip_c_comment : lexbuf -> unit
val skip_c_line_comment : lexbuf -> unit
val skip_string : lexbuf -> unit
end
