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

(** [Id] is a module for compiler and machine identifiers.

    Identifiers contain an ordered list of case-insensitive elements,
    called 'tags'.
*)

open Core

(** [t] is the type of compiler and machine identifiers. *)
type t

(** [to_string_list id] returns a list of each tag in [id]. *)
val to_string_list : t -> string list

(** [has_tag id tag] decides whether [id] contains the tag
    [tag], modulo case. *)
val has_tag : t -> string -> bool

(** [is_prefix id ~prefix] decides whether [prefix] is a prefix of
    [id].

    An ID is a prefix of another ID if its list of tags is
    a prefix of the other ID's list of tags, modulo case. *)
val is_prefix : t -> prefix:t -> bool

(** We can use [t] as an [Identifiable]. *)
include Identifiable.S with type t := t

(** [Property] contains a mini-language for querying IDs, suitable
    for use in [Blang]. *)
module Property : sig
  (** [id] is a synonym for the identifier type. *)
  type id = t

  (** [t] is the opaque type of property queries. *)
  type t [@@deriving sexp]

  (** [has_tag s str] constructs a membership test over a string [str]. *)
  val has_tag : string -> t

  (** [is str] constructs an equality test over a string [str]. *)
  val is : string -> t

  (** [has_prefix str] constructs a prefix test over a string [str]. *)
  val has_prefix : string -> t

  (** [eval id property] decides whether [property] holds for [id]. *)
  val eval : id -> t -> bool

  (** [eval_b id expr] evaluates a [Blang] expression [expr] over
     [id]. *)
  val eval_b : id -> t Blang.t -> bool
end
