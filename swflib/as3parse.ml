(*
 *  This file is part of SwfLib
 *  Copyright (c)2004-2006 Nicolas Cannasse
 *
 *  This program is free software; you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation; either version 2 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program; if not, write to the Free Software
 *  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
 *)
open As3

let parse_idents = true
let parse_base_rights = true && parse_idents
let parse_rights = true && parse_base_rights
let parse_types = true && parse_rights
let parse_mtypes = true && parse_types
let parse_metadata = true && parse_mtypes
let parse_classes = true && parse_metadata
let parse_statics = true && parse_classes
let parse_inits = true && parse_statics

let magic_index (i : int) : 'a index =
	Obj.magic i

let index (t : 'a array) (i : int) : 'a index =
	if i <= 0 || i - 1 >= Array.length t then assert false;
	magic_index i

let index_opt t i =
	if i = 0 then
		None
	else
		Some (index t i)

let index_nz (t : 'a array) (i : int) : 'a index_nz =
	if i < 0 || i >= Array.length t then assert false;
	Obj.magic i

let index_int (i : 'a index) =
	(Obj.magic i : int)

let index_nz_int (i : 'a index_nz) =
	(Obj.magic i : int)

let iget (t : 'a array) (i : 'a index) : 'a =
	t.(index_int i - 1)

let no_nz (i : 'a index_nz) : 'a index =
	Obj.magic ((Obj.magic i) + 1)

(* ************************************************************************ *)
(* LENGTH *)

let as3_empty_index ctx =
	let empty_index = ref 0 in
	try
		Array.iteri (fun i x -> if x = "" then begin empty_index := (i + 1); raise Exit; end) ctx.as3_idents;
		if parse_idents then assert false;
		magic_index 0
	with Exit ->
		index ctx.as3_idents (!empty_index)

let as3_int_length i =
	if Int32.compare (Int32.shift_right_logical i 28) 0l > 0 then
		5
	else if Int32.compare (Int32.shift_right i 21) 0l > 0 then
		4
	else if Int32.compare (Int32.shift_right i 14) 0l > 0 then
		3
	else if Int32.compare (Int32.shift_right i 7) 0l > 0 then
		2
	else
		1

let sum f l =
	List.fold_left (fun acc n -> acc + f n) 0 l

let int_length i =
	as3_int_length (Int32.of_int i)

let idx_length i =
	int_length (index_int i)

let idx_length_nz i =
	int_length (index_nz_int i)

let idx_opt_length = function
	| None -> int_length 0
	| Some i -> idx_length i

let as3_ident_length s =
	let n = String.length s in
	n + int_length n

let as3_base_right_length ei = function
	| A3RUnknown2 o
	| A3RPrivate o ->
		1 + (match o with None -> int_length 0 | Some n -> idx_length n)
	| A3RPublic o
	| A3RInternal o ->
		1 + idx_length (match o with None -> ei | Some n -> n)
	| A3RUnknown1 n
	| A3RProtected n ->
		1 + idx_length n

let as3_rights_length l =
	int_length (List.length l) + sum idx_length l

let as3_type_length t =
	1 +
	match t with
	| A3TClassInterface (id,r) ->
		idx_length id + idx_length r
	| A3TMethodVar (id,r) ->
		idx_length r + idx_length id
	| A3TUnknown1 (_,i) ->
		int_length i
	| A3TUnknown2 (_,i1,i2) ->
		int_length i1 + int_length i2

let as3_value_length extra = function
	| A3VNone -> if extra then 2 else 1
	| A3VNull | A3VBool _ -> 2
	| A3VString s -> 1 + idx_length s
	| A3VInt s -> 1 + idx_length s
	| A3VFloat s -> 1 + idx_length s
	| A3VNamespace s -> 1 + idx_length s

let as3_method_type_length m =
	1 +
	idx_opt_length m.mt3_ret +
	sum idx_opt_length m.mt3_args +
	int_length m.mt3_unk +
	1 +
	(match m.mt3_dparams with None -> 0 | Some l -> 1 + sum (as3_value_length true) l) +
	(match m.mt3_pnames with None -> 0 | Some l -> sum idx_length l)

let list_length f l =
	match Array.length l with
	| 0 -> int_length 0
	| n ->
		Array.fold_left (fun acc x -> acc + f x) (int_length (n + 1)) l

let list2_length f l =
	Array.fold_left (fun acc x -> acc + f x) (int_length (Array.length l)) l

let as3_field_length f =
	idx_length f.f3_name +
	1 +
	int_length f.f3_slot +
	(match f.f3_kind with
	| A3FMethod m ->
		idx_length_nz m.m3_type
	| A3FClass c ->
		idx_length_nz c
	| A3FVar v ->
		idx_opt_length v.v3_type + as3_value_length false v.v3_value) +
	match f.f3_metas with
	| None -> 0
	| Some l -> list2_length idx_length_nz l

let as3_class_length c =
	idx_length c.cl3_name +
	idx_opt_length c.cl3_super +
	1 +
	(match c.cl3_rights with None -> 0 | Some r -> idx_length r) +
	list2_length idx_length c.cl3_implements +
	int_length c.cl3_slot +
	list2_length as3_field_length c.cl3_fields

let as3_static_length s =
	int_length s.st3_slot +
	list2_length as3_field_length s.st3_fields

let as3_inits_length i =
	int_length i.in3_slot +
	list2_length as3_field_length i.in3_fields

let as3_metadata_length m =
	idx_length m.meta3_name +
	list2_length (fun (i1,i2) -> idx_length i1 + idx_length i2) m.meta3_data

let as3_length ctx =
	let ei = as3_empty_index ctx in
	String.length ctx.as3_unknown +
	(match ctx.as3_id with None -> 0 | Some (id,f) -> 4 + String.length f + 1) +
	4 +
	list_length as3_int_length ctx.as3_ints +
	1 +
	list_length (fun _ -> 8) ctx.as3_floats
	+ if parse_idents then list_length as3_ident_length ctx.as3_idents
	+ if parse_base_rights then list_length (as3_base_right_length ei) ctx.as3_base_rights
	+ if parse_rights then list_length as3_rights_length ctx.as3_rights
	+ if parse_types then list_length as3_type_length ctx.as3_types
	+ if parse_mtypes then list2_length as3_method_type_length ctx.as3_method_types
	+ if parse_metadata then list2_length as3_metadata_length ctx.as3_metadatas
	+ if parse_classes then list2_length as3_class_length ctx.as3_classes
	+ if parse_statics then Array.fold_left (fun acc x -> acc + as3_static_length x) 0 ctx.as3_statics
	+ if parse_inits then list2_length as3_inits_length ctx.as3_inits
	  else 0 else 0 else 0 else 0 else 0 else 0 else 0 else 0 else 0

(* ************************************************************************ *)
(* PARSING *)

let read_as3_int ch =
	let a = IO.read_byte ch in
	if a < 128 then
		Int32.of_int a
	else
	let a = a land 127 in
	let b = IO.read_byte ch in
	if b < 128 then
		Int32.of_int ((b lsl 7) lor a)
	else
	let b = b land 127 in
	let c = IO.read_byte ch in
	if c < 128 then
		Int32.of_int ((c lsl 14) lor (b lsl 7) lor a)
	else
	let c = c land 127 in
	let d = IO.read_byte ch in
	if d < 128 then
		Int32.of_int ((d lsl 21) lor (c lsl 14) lor (b lsl 7) lor a)
	else
	let d = d land 127 in
	let e = IO.read_byte ch in
	if e > 15 then assert false;
	let small = Int32.of_int ((d lsl 21) lor (c lsl 14) lor (b lsl 7) lor a) in
	let big = Int32.shift_left (Int32.of_int e) 28 in
	Int32.logor big small

let read_int ch =
	Int32.to_int (read_as3_int ch)

let read_ident ch =
	IO.nread ch (read_int ch)

let read_base_right idents ch =
	let k = IO.read_byte ch in
	let p = index_opt idents (read_int ch) in
	match k with
	| 0x05 ->
		A3RPrivate p
	| 0x08 ->
		(match p with
		| None -> assert false
		| Some idx -> A3RUnknown1 idx)
	| 0x16 ->
		(match p with
		| None -> assert false
		| Some p when iget idents p = "" -> A3RPublic None
		| _ -> A3RPublic p)
	| 0x17 ->
		(match p with
		| None -> assert false
		| Some p when iget idents p = "" -> A3RInternal None
		| _ -> A3RInternal p)
	| 0x18 ->
		(match p with
		| None -> assert false
		| Some idx -> A3RProtected idx)
	| 0x1A ->
		A3RUnknown2 p
	| _ ->
		assert false

let read_rights base_rights ch =
	let rec loop n =
		if n = 0 then
			[]
		else
			let r = index base_rights (read_int ch) in
			r :: loop (n - 1)
	in
	loop (IO.read_byte ch)

let read_type ctx ch =
	let k = IO.read_byte ch in
	match k with
	| 0x09 ->
		let id = index ctx.as3_idents (read_int ch) in
		let rights = index ctx.as3_base_rights (read_int ch) in
		A3TClassInterface (id,rights)
	| 0x07 ->
		let rights = index ctx.as3_base_rights (read_int ch) in
		let id = index ctx.as3_idents (read_int ch) in
		A3TMethodVar (id,rights)
	| 0x1B ->
		A3TUnknown1 (k,read_int ch)
	| 0x0E ->
		let i1 = read_int ch in
		let i2 = read_int ch in
		A3TUnknown2 (k,i1,i2)
	| n ->
		assert false

let read_value ctx ch extra =
	let idx = read_int ch in
	if idx = 0 then begin
		if extra && IO.read_byte ch <> 0 then assert false;
		A3VNone
	end else match IO.read_byte ch with
	| 0x01 ->
		A3VString (index ctx.as3_idents idx)
	| 0x03 ->
		A3VInt (index ctx.as3_ints idx)
	| 0x06 ->
		A3VFloat (index ctx.as3_floats idx)
	| 0x08 ->
		A3VNamespace (index ctx.as3_base_rights idx)
	| 0x0A ->
		if idx <> 0x0A then assert false;
		A3VBool false
	| 0x0B ->
		if idx <> 0x0B then assert false;
		A3VBool true
	| 0x0C ->
		if idx <> 0x0C then assert false;
		A3VNull
	| _ ->
		assert false

let read_method_type ctx ch =
	let nargs = IO.read_byte ch in
	let tret = index_opt ctx.as3_types (read_int ch) in
	let targs = Array.to_list (Array.init nargs (fun _ -> index_opt ctx.as3_types (read_int ch))) in
	let unk = read_int ch in
	let flags = IO.read_byte ch in
	let dparams = (if flags land 0x08 <> 0 then
		Some (Array.to_list (Array.init (IO.read_byte ch) (fun _ -> read_value ctx ch true)))
	else
		None
	) in
	let pnames = (if flags land 0x80 <> 0 then
		Some (Array.to_list (Array.init nargs (fun _ -> index ctx.as3_idents (read_int ch))))
	else
		None
	) in
	{
		mt3_ret = tret;
		mt3_args = targs;
		mt3_var_args = flags land 0x04 <> 0;
		mt3_native = flags land 0x20 <> 0;
		mt3_unk = unk;
		mt3_dparams = dparams;
		mt3_pnames = pnames;
		mt3_unk_flags = (flags land 0x01 <> 0, flags land 0x02 <> 0, flags land 0x10 <> 0, flags land 0x40 <> 0);
	}

let read_list ch f =
	match read_int ch with
	| 0 -> [||]
	| n -> Array.init (n - 1) (fun _ -> f ch)

let read_list2 ch f =
	Array.init (read_int ch) (fun _ -> f ch)

let read_field ctx ch =
	let name = index ctx.as3_types (read_int ch) in
	let is_fun = IO.read_byte ch in
	if is_fun land 0x80 <> 0 then assert false;
	let has_meta = is_fun land 0x40 <> 0 in
	let is_fun = is_fun land 0x3F in
	let slot = read_int ch in
	let kind = (match is_fun with
		| 0x00 | 0x06 ->
			let t = index_opt ctx.as3_types (read_int ch) in
			let value = read_value ctx ch false in
			A3FVar {
				v3_type = t;
				v3_value = value;
				v3_const = is_fun = 0x06;
			}
		| 0x02 | 0x12 | 0x22 | 0x32
		| 0x03 | 0x13 | 0x23 | 0x33
		| 0x01 | 0x11 | 0x21 | 0x31 ->
			let meth = index_nz ctx.as3_method_types (read_int ch) in
			let final = is_fun land 0x10 <> 0 in
			let override = is_fun land 0x20 <> 0 in
			A3FMethod {
				m3_type = meth;
				m3_final = final;
				m3_override = override;
				m3_kind = (match is_fun land 0xF with 0x01 -> MK3Normal | 0x02 -> MK3Getter | 0x03 -> MK3Setter | _ -> assert false);
			}
		| 0x04 ->
			let c = index_nz ctx.as3_classes (read_int ch) in
			A3FClass c
		| _ ->
			assert false
	) in
	let metas = (if has_meta then
		Some (read_list2 ch (fun _ -> index_nz ctx.as3_metadatas (read_int ch)))
	else
		None
	) in
	{
		f3_name = name;
		f3_slot = slot;
		f3_kind = kind;
		f3_metas = metas;
	}

let read_class ctx ch =
	let name = index ctx.as3_types (read_int ch) in
	let csuper = index_opt ctx.as3_types (read_int ch) in
	let flags = IO.read_byte ch in
	let rights =
		if flags land 8 <> 0 then
			let r = index ctx.as3_base_rights (read_int ch) in
			Some r
		else
			None
	in
	let impls = read_list2 ch (fun _ -> index ctx.as3_types (read_int ch)) in
	let slot = read_int ch in
	let fields = read_list2 ch (read_field ctx) in
	{
		cl3_name = name;
		cl3_super = csuper;
		cl3_sealed = (flags land 1) <> 0;
		cl3_final = (flags land 2) <> 0;
		cl3_interface = (flags land 4) <> 0;
		cl3_rights = rights;
		cl3_implements = impls;
		cl3_slot = slot;
		cl3_fields = fields;
	}

let read_static ctx ch =
	let slot = read_int ch in
	let fields = read_list2 ch (read_field ctx) in
	{
		st3_slot = slot;
		st3_fields = fields;
	}

let read_inits ctx ch =
	let slot = read_int ch in
	let fields = read_list2 ch (read_field ctx) in
	{
		in3_slot = slot;
		in3_fields = fields;
	}

let read_metadata ctx ch =
	let name = index ctx.as3_idents (read_int ch) in
	let data = read_list2 ch (fun _ -> index ctx.as3_idents (read_int ch)) in
	let data = Array.map (fun i1 -> i1 , index ctx.as3_idents (read_int ch)) data in
	{
		meta3_name = name;
		meta3_data = data;
	}

let header_magic = 0x002E0010

let parse ch len has_id =
	let data = IO.nread ch len in
	let ch = IO.input_string data in
	let id = (if has_id then
		let id = IO.read_i32 ch in
		let frame = IO.read_string ch in
		Some (id,frame)
	else
		None
	) in
	if IO.read_i32 ch <> header_magic then assert false;
	let ints = read_list ch read_as3_int in
	if IO.read_byte ch <> 0 then assert false;
	let floats = read_list ch IO.read_double in
	let idents = (if parse_idents then read_list ch read_ident else [||]) in
	let base_rights = (if parse_base_rights then read_list ch (read_base_right idents) else [||]) in
	let rights = (if parse_rights then read_list ch (read_rights base_rights) else [||]) in
	let ctx = {
		as3_id = id;
		as3_ints = ints;
		as3_floats = floats;
		as3_idents = idents;
		as3_base_rights = base_rights;
		as3_rights = rights;
		as3_types = [||];
		as3_method_types = [||];
		as3_metadatas = [||];
		as3_classes = [||];
		as3_statics = [||];
		as3_inits = [||];
		as3_unknown = "";
		as3_original_data = data;
	} in
	if parse_types then ctx.as3_types <- read_list ch (read_type ctx);
	if parse_mtypes then ctx.as3_method_types <- read_list2 ch (read_method_type ctx);
	if parse_metadata then ctx.as3_metadatas <- read_list2 ch (read_metadata ctx);
	if parse_classes then ctx.as3_classes <- read_list2 ch (read_class ctx);
	if parse_statics then ctx.as3_statics <- Array.map (fun _ -> read_static ctx ch) ctx.as3_classes;
	if parse_inits then ctx.as3_inits <- read_list2 ch (read_inits ctx);
	ctx.as3_unknown <- IO.read_all ch;
	if as3_length ctx <> len then assert false;
	ctx

(* ************************************************************************ *)
(* WRITING *)

let write_as3_int ch i =
	let e = Int32.to_int (Int32.shift_right_logical i 28) in
	let d = Int32.to_int (Int32.shift_right i 21) land 0x7F in
	let c = Int32.to_int (Int32.shift_right i 14) land 0x7F in
	let b = Int32.to_int (Int32.shift_right i 7) land 0x7F in
	let a = Int32.to_int (Int32.logand i 0x7Fl) in
	if b <> 0 || c <> 0 || d <> 0 || e <> 0 then begin
		IO.write_byte ch (a lor 0x80);
		if c <> 0 || d <> 0 || e <> 0 then begin
			IO.write_byte ch (b lor 0x80);
			if d <> 0 || e <> 0 then begin
				IO.write_byte ch (c lor 0x80);
				if e <> 0 then begin
					IO.write_byte ch (d lor 0x80);
					IO.write_byte ch e;
				end else
					IO.write_byte ch d;
			end else
				IO.write_byte ch c;
		end else
			IO.write_byte ch b;
	end else
		IO.write_byte ch a

let write_int ch i =
	write_as3_int ch (Int32.of_int i)

let write_index ch n =
	write_int ch (index_int n)

let write_index_nz ch n =
	write_int ch (index_nz_int n)

let write_index_opt ch = function
	| None -> write_int ch 0
	| Some n -> write_index ch n

let write_as3_ident ch id =
	write_int ch (String.length id);
	IO.nwrite ch id

let write_base_right empty_index ch = function
	| A3RPrivate n ->
		IO.write_byte ch 0x05;
		(match n with
		| None -> write_int ch 0
		| Some n -> write_index ch n);
	| A3RPublic n ->
		IO.write_byte ch 0x16;
		(match n with
		| None -> write_index ch empty_index
		| Some n -> write_index ch n);
	| A3RInternal n ->
		IO.write_byte ch 0x17;
		(match n with
		| None -> write_index ch empty_index
		| Some n -> write_index ch n);
	| A3RProtected n ->
		IO.write_byte ch 0x18;
		write_index ch n
	| A3RUnknown1 n ->
		IO.write_byte ch 0x08;
		write_index ch n
	| A3RUnknown2 n ->
		IO.write_byte ch 0x1A;
		(match n with
		| None -> write_int ch 0
		| Some n -> write_index ch n)

let write_rights ch l =
	IO.write_byte ch (List.length l);
	List.iter (write_index ch) l

let write_type ch = function
	| A3TClassInterface (id,r) ->
		IO.write_byte ch 0x09;
		write_index ch id;
		write_index ch r;
	| A3TMethodVar (id,r) ->
		IO.write_byte ch 0x07;
		write_index ch r;
		write_index ch id
	| A3TUnknown1 (t,i) ->
		IO.write_byte ch t;
		write_int ch i
	| A3TUnknown2 (t,i1,i2) ->
		IO.write_byte ch t;
		write_int ch i1;
		write_int ch i2

let write_value ch extra v =
	match v with
	| A3VNone ->
		IO.write_byte ch 0x00;
		if extra then IO.write_byte ch 0x00;
	| A3VNull ->
		IO.write_byte ch 0x0C;
		IO.write_byte ch 0x0C;
	| A3VBool b ->
		IO.write_byte ch (if b then 0x0B else 0x0A);
		IO.write_byte ch (if b then 0x0B else 0x0A);
	| A3VString s ->
		write_index ch s;
		IO.write_byte ch 0x01;
	| A3VInt s ->
		write_index ch s;
		IO.write_byte ch 0x03;
	| A3VFloat s ->
		write_index ch s;
		IO.write_byte ch 0x06
	| A3VNamespace s ->
		write_index ch s;
		IO.write_byte ch 0x08

let write_method_type ch m =
	let nargs = List.length m.mt3_args in
	IO.write_byte ch nargs;
	write_index_opt ch m.mt3_ret;
	List.iter (write_index_opt ch) m.mt3_args;
	write_int ch m.mt3_unk;
	let f1 , f2, f10, f40 = m.mt3_unk_flags in
	let flags =
		(if f1 then 0x01 else 0) lor
		(if f2 then 0x02 else 0) lor
		(if m.mt3_var_args then 0x04 else 0) lor
		(if m.mt3_dparams <> None then 0x08 else 0) lor
		(if f10 then 0x10 else 0) lor
		(if m.mt3_native then 0x20 else 0) lor
		(if f40 then 0x40 else 0) lor
		(if m.mt3_pnames <> None then 0x80 else 0)
	in
	IO.write_byte ch flags;
	(match m.mt3_dparams with
	| None -> ()
	| Some l ->
		IO.write_byte ch (List.length l);
		List.iter (write_value ch true) l);
	match m.mt3_pnames with
	| None -> ()
	| Some l ->
		if List.length l <> nargs then assert false;
		List.iter (write_index ch) l

let write_list ch f l =
	match Array.length l with
	| 0 -> IO.write_byte ch 0
	| n ->
		write_int ch (n + 1);
		Array.iter (f ch) l

let write_list2 ch f l =
	write_int ch (Array.length l);
	Array.iter (f ch) l

let write_field ch f =
	write_index ch f.f3_name;
	let flags = (if f.f3_metas <> None then 0x40 else 0) in
	(match f.f3_kind with
	| A3FMethod m ->
		let base = (match m.m3_kind with MK3Normal -> 0x01 | MK3Getter -> 0x02 | MK3Setter -> 0x03) in
		let flags = flags lor (if m.m3_final then 0x10 else 0) lor (if m.m3_override then 0x20 else 0) in
		IO.write_byte ch (base lor flags);
		write_int ch f.f3_slot;
		write_index_nz ch m.m3_type;
	| A3FClass c ->		
		IO.write_byte ch (0x04 lor flags);
		write_int ch f.f3_slot;
		write_index_nz ch c
	| A3FVar v ->
		IO.write_byte ch (flags lor (if v.v3_const then 0x06 else 0x00));
		write_int ch f.f3_slot;
		write_index_opt ch v.v3_type;
		write_value ch false v.v3_value);
	match f.f3_metas with
	| None -> ()
	| Some l ->
		write_list2 ch write_index_nz l

let write_class ch c =
	write_index ch c.cl3_name;
	write_index_opt ch c.cl3_super;
	let flags =
		(if c.cl3_sealed then 1 else 0) lor
		(if c.cl3_final then 2 else 0) lor
		(if c.cl3_interface then 4 else 0) lor
		(if c.cl3_rights <> None then 8 else 0)
	in
	IO.write_byte ch flags;
	(match c.cl3_rights with
	| None -> ()
	| Some r -> write_index ch r);
	write_list2 ch write_index c.cl3_implements;
	write_int ch c.cl3_slot;
	write_list2 ch write_field c.cl3_fields

let write_static ch s =
	write_int ch s.st3_slot;
	write_list2 ch write_field s.st3_fields

let write_inits ch i =
	write_int ch i.in3_slot;
	write_list2 ch write_field i.in3_fields

let write_metadata ch m =
	write_index ch m.meta3_name;
	write_list2 ch (fun _ (i1,_) -> write_index ch i1) m.meta3_data;
	Array.iter (fun (_,i2) -> write_index ch i2) m.meta3_data

let write ch1 ctx =
	let ch = IO.output_string() in
	let empty_index = as3_empty_index ctx in
	(match ctx.as3_id with
	| None -> ()
	| Some (id,frame) ->
		IO.write_i32 ch id;
		IO.write_string ch frame);
	IO.write_i32 ch header_magic;
	write_list ch write_as3_int ctx.as3_ints;
	IO.write_byte ch 0;
	write_list ch IO.write_double ctx.as3_floats;
	if parse_idents then write_list ch write_as3_ident ctx.as3_idents;
	if parse_base_rights then write_list ch (write_base_right empty_index) ctx.as3_base_rights;
	if parse_rights then write_list ch write_rights ctx.as3_rights;
	if parse_types then write_list ch write_type ctx.as3_types;
	if parse_mtypes then write_list2 ch write_method_type ctx.as3_method_types;
	if parse_metadata then write_list2 ch write_metadata ctx.as3_metadatas;
	if parse_classes then write_list2 ch write_class ctx.as3_classes;
	if parse_statics then Array.iter (write_static ch) ctx.as3_statics;
	if parse_inits then write_list2 ch write_inits ctx.as3_inits;
	IO.nwrite ch ctx.as3_unknown;
	let str = IO.close_out ch in
	if str <> ctx.as3_original_data then begin
		let l1 = String.length str in
		let l2 = String.length ctx.as3_original_data in
		let l = if l1 < l2 then l1 else l2 in
		let frame = (match ctx.as3_id with None -> "<unknown>" | Some (_,f) -> f) in
		for i = 0 to l - 1 do
			if str.[i] <> ctx.as3_original_data.[i] then failwith (Printf.sprintf "Corrupted data in %s at 0x%X" frame i);
		done;
		if l1 < l2 then failwith (Printf.sprintf "Missing %d bytes in %s" (l2 - l1) frame);
		failwith (Printf.sprintf "Too many %d bytes in %s" (l1 - l2) frame);
	end;
	IO.nwrite ch1 str

(* ************************************************************************ *)
(* DUMP *)

let ident_str ctx i =
	iget ctx.as3_idents i

let base_right_str ctx i =
	match iget ctx.as3_base_rights i with
	| A3RPrivate None -> "private"
	| A3RPrivate (Some n) -> "private:" ^ ident_str ctx n
	| A3RPublic None -> "public"
	| A3RPublic (Some n) -> "public:" ^ ident_str ctx n
	| A3RInternal None -> "internal"
	| A3RInternal (Some n) -> "internal:" ^ ident_str ctx n
	| A3RProtected n -> "protected:" ^ ident_str ctx n
	| A3RUnknown2 None -> "unknown2"
	| A3RUnknown2 (Some n) -> "unknown2:" ^ ident_str ctx n
	| A3RUnknown1 n -> "unknown1:" ^ ident_str ctx n

let rights_str ctx i =
	let l = iget ctx.as3_rights i in
	String.concat " " (List.map (fun r -> base_right_str ctx r) l)

let type_str ctx kind t =
	match iget ctx.as3_types t with
	| A3TClassInterface (id,r) -> Printf.sprintf "[%s %s%s]" (base_right_str ctx r) kind (ident_str ctx id)
	| A3TMethodVar (id,r) -> Printf.sprintf "%s %s%s" (base_right_str ctx r) kind (ident_str ctx id)
	| A3TUnknown1 (t,i) -> Printf.sprintf "unknown1:0x%X:%d" t i
	| A3TUnknown2 (t,i1,i2) -> Printf.sprintf "unknown2:0x%X:%d:%d" t i1 i2

let value_str ctx v =
	match v with
	| A3VNone -> "<none>"
	| A3VNull -> "null"
	| A3VString s -> "\"" ^ ident_str ctx s ^ "\""
	| A3VBool b -> if b then "true" else "false"
	| A3VInt s -> Printf.sprintf "%ld" (iget ctx.as3_ints s)
	| A3VFloat s -> Printf.sprintf "%f" (iget ctx.as3_floats s)
	| A3VNamespace s -> base_right_str ctx s

let metadata_str ctx i =
	let m = iget ctx.as3_metadatas i in
	let data = List.map (fun (i1,i2) -> Printf.sprintf "%s=\"%s\"" (ident_str ctx i1) (ident_str ctx i2)) (Array.to_list m.meta3_data) in
	Printf.sprintf "%s(%s)" (ident_str ctx m.meta3_name) (String.concat ", " data)

let method_str ctx m =
	let m = iget ctx.as3_method_types m in
	let pcount = ref 0 in
	Printf.sprintf "%s(%s%s)%s" 
	(if m.mt3_native then " native " else "")
	(String.concat ", " (List.map (fun a ->
		let id = (match m.mt3_pnames with
			| None -> "p" ^ string_of_int !pcount
			| Some l -> ident_str ctx (List.nth l !pcount)
		) in
		let p = (match a with None -> id | Some t -> type_str ctx (id ^ " : ") t) in

		let p = (match m.mt3_dparams with
		| None -> p
		| Some l ->
			let vargs = List.length m.mt3_args - List.length l in
			if !pcount >= vargs then
				let v = List.nth l (!pcount - vargs) in
				p  ^ " = " ^ value_str ctx v
			else
				p
		) in
		incr pcount;
		p
	) m.mt3_args))
	(if m.mt3_var_args then " ..." else "")
	(match m.mt3_ret with None -> "" | Some t -> " : " ^ type_str ctx "" t)	

let dump_field ctx ch stat f =
(*	(match f.f3_metas with
	| None -> ()
	| Some l -> Array.iter (fun i -> IO.printf ch "    [%s]\n" (metadata_str ctx (no_nz i))) l);
*)	IO.printf ch "    ";
	if stat then IO.printf ch "static ";
	(match f.f3_kind with
	| A3FVar v ->
		IO.printf ch "%s" (type_str ctx (if v.v3_const then "const " else "var ") f.f3_name);
		(match v.v3_type with
		| None -> ()
		| Some id -> IO.printf ch " : %s" (type_str ctx "" id));
		if v.v3_value <> A3VNone then IO.printf ch " = %s" (value_str ctx v.v3_value);
	| A3FClass c ->
		let c = iget ctx.as3_classes (no_nz c) in
		IO.printf ch "%s = %s" (type_str ctx "CLASS " c.cl3_name) (type_str ctx "class " f.f3_name);
	| A3FMethod m ->
		if m.m3_final then IO.printf ch "final ";
		if m.m3_override then IO.printf ch "override ";
		let k = "function " ^ (match m.m3_kind with
			| MK3Normal -> ""
			| MK3Getter -> "get "
			| MK3Setter -> "set "
		) in
		IO.printf ch "%s%s" (type_str ctx k f.f3_name) (method_str ctx (no_nz m.m3_type));
	);
	if f.f3_slot <> 0 then IO.printf ch " = [SLOT:%d]" f.f3_slot;
	IO.printf ch ";\n"

let dump_class ctx ch idx c =
	let st = if parse_statics then ctx.as3_statics.(idx) else { st3_slot = -1; st3_fields = [||] } in
	if not c.cl3_sealed then IO.printf ch "dynamic ";
	if c.cl3_final then IO.printf ch "final ";
	(match c.cl3_rights with
	| None -> ()
	| Some r -> IO.printf ch "%s " (base_right_str ctx r));
	let kind = (if c.cl3_interface then "interface " else "class ") in
	IO.printf ch "%s " (type_str ctx kind c.cl3_name);
	(match c.cl3_super with
	| None -> ()
	| Some s -> IO.printf ch "extends %s " (type_str ctx "" s));
	(match Array.to_list c.cl3_implements with
	| [] -> ()
	| l ->
		IO.printf ch "implements %s " (String.concat ", " (List.map (fun i -> type_str ctx "" i) l)));
	IO.printf ch "{\n";
	Array.iter (dump_field ctx ch false) c.cl3_fields;
	Array.iter (dump_field ctx ch true) st.st3_fields;
	IO.printf ch "} [SLOT:%d] [STATIC:%d]\n\n" c.cl3_slot st.st3_slot

let dump_inits ctx ch idx i =
	IO.printf ch "init [SLOT:%d] {\n" i.in3_slot;
	Array.iter (dump_field ctx ch false) i.in3_fields;
	IO.printf ch "}\n"

let dump_ident ctx ch idx _ =
	IO.printf ch "I%d = %s\n" idx (ident_str ctx (index ctx.as3_idents (idx + 1)))

let dump_base_right ctx ch idx _ =
	IO.printf ch "B%d = %s\n" idx (base_right_str ctx (index ctx.as3_base_rights (idx + 1)))

let dump_rights ctx ch idx _ =
	IO.printf ch "R%d = %s\n" idx (rights_str ctx (index ctx.as3_rights (idx + 1)))

let dump_type ctx ch idx _ =
	IO.printf ch "T%d = %s\n" idx (type_str ctx "" (index ctx.as3_types (idx + 1)))

let dump_method_type ctx ch idx _ =
	IO.printf ch "M%d = %s\n" idx (method_str ctx (index ctx.as3_method_types (idx + 1)))

let dump_metadata ctx ch idx _ =
	IO.printf ch "D%d = %s\n" idx (metadata_str ctx (index ctx.as3_metadatas (idx + 1)))

let dump ch ctx =
	(match ctx.as3_id with
	| None -> IO.printf ch "\n---------------- AS3 -------------------------\n\n";
	| Some (id,f) -> IO.printf ch "\n---------------- AS3 %s [%d] -----------------\n\n" f id);
(*	Array.iteri (dump_ident ctx ch) ctx.as3_idents;
	Array.iteri (dump_base_right ctx ch) ctx.as3_base_rights;
	Array.iteri (dump_rights ctx ch) ctx.as3_rights;
	Array.iteri (dump_type ctx ch) ctx.as3_types;
	Array.iteri (dump_method_type ctx ch) ctx.as3_method_types;
	Array.iteri (dump_metadata ctx ch) ctx.as3_metadatas; *)
	Array.iteri (dump_class ctx ch) ctx.as3_classes;
	Array.iteri (dump_inits ctx ch) ctx.as3_inits;
	IO.printf ch "(%d/%d bytes)\n\n" (String.length ctx.as3_unknown) (String.length ctx.as3_original_data)
